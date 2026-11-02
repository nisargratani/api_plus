import 'dart:async';

import 'package:dio/dio.dart' as dio;

import '../../config/cache_config.dart';
import '../../config/logger_config.dart';
import '../../config/retry_config.dart';
import '../../core/api_cancel_token.dart';
import '../../core/api_request.dart';
import '../../core/api_response.dart';
import '../../core/internal_keys.dart';
import '../../core/request_url.dart';
import '../../exceptions/api_exception.dart';
import '../../interfaces/api_interceptor.dart';
import '../../interceptors/cache_interceptor.dart';
import '../../interceptors/logger_interceptor.dart';
import '../../interceptors/retry_interceptor.dart';
import '../../models/http_method.dart';

/// A utility to bridge `api_plus` configuration with `retrofit` clients.
///
/// Since Retrofit generates code that relies on Dio, this adapter provides
/// a pre-configured [dio.Dio] client that fully supports the `api_plus`
/// interceptor ecosystem (retry, cache, logging).
///
/// The bridge interceptor translates between Dio's native
/// request/response/error types and `api_plus`'s unified types,
/// ensuring all interceptors work seamlessly.
///
/// {@tool snippet}
/// ```dart
/// final adapter = RetrofitAdapter(
///   baseUrl: 'https://api.example.com',
///   retryConfig: const RetryConfig(maxRetries: 3),
///   loggerConfig: const LoggerConfig(level: LogLevel.verbose),
///   cacheConfig: CacheConfig(store: MemoryCacheStore()),
/// );
///
/// // Pass the client to your Retrofit-generated class
/// final apiClient = MyRetrofitClient(adapter.client);
/// ```
/// {@end-tool}
class RetrofitAdapter {
  final String _baseUrl;
  final Map<String, String> _defaultHeaders;
  final List<ApiInterceptor> _interceptors;
  dio.Dio? _client;

  /// Creates a [RetrofitAdapter] with the given configuration.
  ///
  /// Interceptors are built from the provided configs in the order:
  /// retry → cache → logger → custom interceptors, as with `ApiBuilder`.
  /// Retry comes first so that a failed request is retried before the
  /// cache serves a stale entry.
  RetrofitAdapter({
    required String baseUrl,
    Map<String, String> defaultHeaders = const {},
    List<ApiInterceptor> interceptors = const [],
    RetryConfig? retryConfig,
    LoggerConfig? loggerConfig,
    CacheConfig? cacheConfig,
  })  : _baseUrl = baseUrl,
        _defaultHeaders = defaultHeaders,
        _interceptors = _buildInterceptors(
          interceptors,
          retryConfig: retryConfig,
          loggerConfig: loggerConfig,
          cacheConfig: cacheConfig,
        );

  static List<ApiInterceptor> _buildInterceptors(
    List<ApiInterceptor> custom, {
    RetryConfig? retryConfig,
    LoggerConfig? loggerConfig,
    CacheConfig? cacheConfig,
  }) {
    final result = <ApiInterceptor>[];
    if (retryConfig != null) {
      result.add(RetryInterceptor(config: retryConfig));
    }
    if (cacheConfig != null) {
      result.add(CacheInterceptor(config: cacheConfig));
    }
    if (loggerConfig != null) {
      result.add(LoggerInterceptor(config: loggerConfig));
    }
    result.addAll(custom);
    return result;
  }

  /// Provides the pre-configured [dio.Dio] client.
  ///
  /// Pass this client to your Retrofit-generated class constructor.
  /// All `api_plus` interceptors (retry, cache, logger) are active
  /// on this client via an internal bridge interceptor.
  dio.Dio get client {
    final existing = _client;
    if (existing != null) return existing;

    final created = dio.Dio(dio.BaseOptions(
      baseUrl: _baseUrl,
      headers: _defaultHeaders,
    ));
    created.interceptors
        .add(_RetrofitBridgeInterceptor(_interceptors, created));
    return _client = created;
  }

  /// Closes the underlying Dio client.
  void close({bool force = false}) {
    _client?.close(force: force);
  }
}

/// Internal interceptor that bridges Dio's interceptor system with
/// the `api_plus` unified [ApiInterceptor] pipeline.
///
/// Converts Dio types to Api types, runs the interceptor chain,
/// then converts back to Dio types.
class _RetrofitBridgeInterceptor extends dio.Interceptor {
  final List<ApiInterceptor> _apiInterceptors;

  /// The client this interceptor is installed on. Retries and background
  /// cache refreshes are sent through it, so they run the full pipeline.
  final dio.Dio _client;

  _RetrofitBridgeInterceptor(this._apiInterceptors, this._client);

  @override
  void onRequest(
    dio.RequestOptions options,
    dio.RequestInterceptorHandler handler,
  ) {
    _runOnRequest(options, handler);
  }

  Future<void> _runOnRequest(
    dio.RequestOptions options,
    dio.RequestInterceptorHandler handler,
  ) async {
    try {
      final original = _dioOptionsToApiRequest(options);
      ApiRequest apiRequest = original;

      for (final interceptor in _apiInterceptors) {
        final result = await interceptor.onRequest(apiRequest);
        if (result is ApiResponse) {
          // Short-circuit: return cached/mocked response
          handler.resolve(_toDioResponse(result, options));
          _scheduleRevalidation(result.request, options);
          return;
        } else if (result is ApiRequest) {
          apiRequest = result;
        }
      }

      _applyToOptions(original, apiRequest, options);

      final invalidUrl = _validateUrl(options);
      if (invalidUrl != null) {
        // Reported like DioAdapter: through onError (so it is logged), as a
        // ConfigurationException that is not retried.
        handler.reject(
          dio.DioException(
            requestOptions: options,
            error: invalidUrl,
            stackTrace: invalidUrl.stackTrace,
            type: dio.DioExceptionType.unknown,
          ),
          true,
        );
        return;
      }
      handler.next(options);
    } catch (e, stackTrace) {
      handler.reject(_interceptorFailure(options, e, stackTrace));
    }
  }

  /// Returns a [ConfigurationException] if Dio cannot build a valid URL for
  /// [options], so the error is not reported as a (retryable) network error.
  static ConfigurationException? _validateUrl(dio.RequestOptions options) {
    try {
      if (looksLikeAbsoluteUrl(options.path)) parseAbsoluteUrl(options.path);
      options.uri;
      return null;
    } on FormatException catch (e, stackTrace) {
      return ConfigurationException(
        message: 'Invalid request URL: ${e.message}',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Dio errors that wrap an error thrown by an api_plus interceptor (e.g.
  /// a `StateError` from a bug). Retries rethrow the original error, so it
  /// propagates unchanged instead of being retried as a network error.
  static final Expando<bool> _interceptorFailures =
      Expando<bool>('apiPlusInterceptorFailure');

  static dio.DioException _interceptorFailure(
    dio.RequestOptions options,
    Object error,
    StackTrace stackTrace,
  ) {
    final failure = dio.DioException(
      requestOptions: options,
      error: error,
      stackTrace: stackTrace,
      type: dio.DioExceptionType.unknown,
    );
    if (error is! ApiException) _interceptorFailures[failure] = true;
    return failure;
  }

  /// Writes the changes interceptors made to [modified] back into [options].
  void _applyToOptions(
    ApiRequest original,
    ApiRequest modified,
    dio.RequestOptions options,
  ) {
    if (modified.path != original.path) options.path = modified.path;
    if (modified.method != original.method) {
      options.method = modified.method.value;
    }
    if (!identical(modified.queryParameters, original.queryParameters)) {
      options.queryParameters =
          Map<String, dynamic>.of(modified.queryParameters);
    }
    if (!identical(modified.body, original.body)) options.data = modified.body;

    // Only touch changed headers so non-string header values survive.
    options.headers.removeWhere((key, _) => !modified.headers.containsKey(key));
    modified.headers.forEach((key, value) {
      if (original.headers[key] != value) options.headers[key] = value;
    });

    if (modified.connectTimeout != original.connectTimeout) {
      options.connectTimeout = modified.connectTimeout;
    }
    if (modified.sendTimeout != original.sendTimeout) {
      options.sendTimeout = modified.sendTimeout;
    }
    if (modified.receiveTimeout != original.receiveTimeout) {
      options.receiveTimeout = modified.receiveTimeout;
    }
    options.extra.addAll(modified.extra);
  }

  void _scheduleRevalidation(
    ApiRequest? servedFor,
    dio.RequestOptions options,
  ) {
    final refresh = revalidationRequestFor(servedFor);
    if (refresh == null) return;
    // The stale response was already delivered; a failed refresh just
    // leaves the stale entry cached (interceptors still see the error).
    unawaited(
      _client
          .fetch<dynamic>(_toRequestOptions(refresh, options))
          .then<void>((_) {}, onError: (_) {}),
    );
  }

  @override
  void onResponse(
    dio.Response<dynamic> response,
    dio.ResponseInterceptorHandler handler,
  ) {
    _runOnResponse(response, handler);
  }

  Future<void> _runOnResponse(
    dio.Response<dynamic> response,
    dio.ResponseInterceptorHandler handler,
  ) async {
    try {
      final apiResponse = await _runResponseChain(
        _toApiResponse(
          response,
          _dioOptionsToApiRequest(response.requestOptions),
        ),
      );
      handler.resolve(_toDioResponse(apiResponse, response.requestOptions));
    } catch (e, stackTrace) {
      handler.reject(
        _interceptorFailure(response.requestOptions, e, stackTrace),
      );
    }
  }

  /// Runs the api_plus `onResponse` chain on [response].
  Future<ApiResponse<dynamic>> _runResponseChain(
    ApiResponse<dynamic> response,
  ) async {
    var current = response;
    for (final interceptor in _apiInterceptors) {
      current = await interceptor.onResponse(current);
    }
    return current;
  }

  @override
  void onError(
    dio.DioException err,
    dio.ErrorInterceptorHandler handler,
  ) {
    _runOnError(err, handler);
  }

  Future<void> _runOnError(
    dio.DioException err,
    dio.ErrorInterceptorHandler handler,
  ) async {
    try {
      final apiRequest = _dioOptionsToApiRequest(err.requestOptions);
      ApiException apiException;

      final rawResponse = err.response;
      if (err.type == dio.DioExceptionType.badResponse && rawResponse != null) {
        // Like the other adapters, error statuses go through onResponse
        // first, then (unless an interceptor turned them into a success)
        // through onError as a ServerException.
        final converted = _toApiResponse(rawResponse, apiRequest);
        try {
          final response = await _runResponseChain(converted);
          if (response.isSuccessful) {
            handler.resolve(_toDioResponse(response, err.requestOptions));
            return;
          }
          apiException = serverExceptionFor(
            apiRequest,
            response,
            // Keep Dio's own error unless an interceptor changed the
            // response, so Retrofit callers see what interceptors see.
            error: identical(response, converted)
                ? err
                : dio.DioException.badResponse(
                    statusCode: response.statusCode,
                    requestOptions: err.requestOptions,
                    response: _toDioResponse(response, err.requestOptions),
                  ),
            stackTrace: err.stackTrace,
          );
        } on ApiException catch (e) {
          // As in the other adapters, an ApiException thrown by onResponse
          // goes through onError.
          apiException = e;
        }
      } else {
        apiException = _mapDioError(err, apiRequest);
      }

      // Re-sends a request through this client's full pipeline. Failures
      // are thrown as ApiException so interceptors (e.g. retry) handle them.
      Future<ApiResponse<dynamic>> invoker(ApiRequest request) async {
        try {
          final retryResponse = await _client.fetch<dynamic>(
            _toRequestOptions(request, err.requestOptions),
          );
          return _toApiResponse(retryResponse, request);
        } on dio.DioException catch (e) {
          final cause = e.error;
          if (cause != null && (_interceptorFailures[e] ?? false)) {
            // An interceptor bug, not a network error: propagate it as is.
            Error.throwWithStackTrace(cause, e.stackTrace);
          }
          // The error the attempt's own pipeline ended with (as the other
          // adapters do), so interceptors see one error object per attempt.
          throw _pipelineErrors[e] ?? _mapDioError(e, request);
        }
      }

      for (final interceptor in _apiInterceptors) {
        final result = await interceptor.onError(apiException, invoker);
        if (result is ApiResponse) {
          // Recovered — convert to Dio response
          handler.resolve(_toDioResponse(result, err.requestOptions));
          return;
        } else if (result is ApiException) {
          apiException = result;
        }
      }

      if (apiException is CancellationException &&
          err.type != dio.DioExceptionType.cancel) {
        final cancelError = apiException.error;
        handler.reject(
          cancelError is dio.DioException &&
                  cancelError.type == dio.DioExceptionType.cancel
              ? cancelError
              : dio.DioException.requestCancelled(
                  requestOptions: err.requestOptions,
                  reason: err.requestOptions.cancelToken?.cancelError?.error,
                ),
        );
        return;
      }
      final dioError = _toDioError(apiException, err);
      _pipelineErrors[dioError] = apiException;
      handler.reject(dioError);
    } catch (e, stackTrace) {
      handler.reject(_interceptorFailure(err.requestOptions, e, stackTrace));
    }
  }

  /// The api_plus error each rejected Dio error stands for.
  static final Expando<ApiException> _pipelineErrors =
      Expando<ApiException>('apiPlusPipelineError');

  /// The Dio error to reject with for the final [error] of the pipeline:
  /// the last attempt's [dio.DioException] (not the first one's), or one
  /// built from the error's response, falling back to [original].
  static dio.DioException _toDioError(
    ApiException error,
    dio.DioException original,
  ) {
    final cause = error.error;
    if (cause is dio.DioException) return cause;
    final response = error.response;
    if (response != null) {
      return dio.DioException.badResponse(
        statusCode: response.statusCode,
        requestOptions: original.requestOptions,
        response: _toDioResponse(response, original.requestOptions),
      );
    }
    return original;
  }

  /// Builds options for re-sending [request], keeping the Dio-specific
  /// settings (response type, validateStatus, ...) of [template].
  dio.RequestOptions _toRequestOptions(
    ApiRequest request,
    dio.RequestOptions template,
  ) {
    return template.copyWith(
      path: request.path,
      method: request.method.value,
      headers: Map<String, dynamic>.of(request.headers),
      queryParameters: Map<String, dynamic>.of(request.queryParameters),
      data: request.body,
      extra: Map<String, dynamic>.of(request.extra),
      connectTimeout: request.connectTimeout,
      sendTimeout: request.sendTimeout,
      receiveTimeout: request.receiveTimeout,
    );
  }

  /// Converts a Dio response for api_plus interceptors. An empty body is
  /// `null`, as with the other adapters.
  static ApiResponse<dynamic> _toApiResponse(
    dio.Response<dynamic> response,
    ApiRequest request,
  ) {
    final data = response.data;
    final empty = data is String && data.isEmpty;
    final converted = ApiResponse<dynamic>(
      data: empty ? null : data,
      statusCode: response.statusCode ?? 200,
      headers: Map<String, List<String>>.of(response.headers.map),
      statusMessage: response.statusMessage,
      isRedirect: response.isRedirect,
      request: request,
    );
    if (empty) markEmptyBody(converted);
    return converted;
  }

  /// Converts back for Dio and Retrofit code, which keep receiving exactly
  /// what Dio returned for an empty body (`''`).
  static dio.Response<dynamic> _toDioResponse(
    ApiResponse<dynamic> response,
    dio.RequestOptions options,
  ) {
    final data = response.data;
    return dio.Response<dynamic>(
      data: data == null && isEmptyBody(response) ? '' : data,
      statusCode: response.statusCode,
      statusMessage: response.statusMessage,
      requestOptions: options,
      isRedirect: response.isRedirect,
      headers: dio.Headers.fromMap(
        response.headers.map((k, v) => MapEntry(k, List<String>.of(v))),
      ),
    );
  }

  ApiRequest _dioOptionsToApiRequest(dio.RequestOptions options) {
    final headers = <String, String>{};
    options.headers.forEach((key, value) {
      headers[key] = value.toString();
    });

    return ApiRequest(
      path: options.path,
      method: _parseHttpMethod(options.method),
      headers: headers,
      queryParameters: options.queryParameters,
      body: options.data,
      connectTimeout: options.connectTimeout,
      receiveTimeout: options.receiveTimeout,
      sendTimeout: options.sendTimeout,
      extra: {...options.extra, baseUrlExtraKey: options.baseUrl},
      cancelToken: _linkCancelToken(options.cancelToken),
    );
  }

  /// The [ApiCancelToken] mirroring each Dio token, so a long-lived Dio
  /// token gets one listener rather than one per request.
  static final Expando<ApiCancelToken> _linkedTokens =
      Expando<ApiCancelToken>('apiPlusLinkedCancelToken');

  /// Mirrors a Dio [token] as an [ApiCancelToken], so api_plus interceptors
  /// (e.g. a pending retry delay) react to Retrofit's `@CancelRequest`.
  static ApiCancelToken? _linkCancelToken(dio.CancelToken? token) {
    if (token == null) return null;
    final existing = _linkedTokens[token];
    if (existing != null) return existing;
    final apiToken = _linkedTokens[token] = ApiCancelToken();
    if (token.isCancelled) {
      apiToken.cancel(token.cancelError?.error);
    } else {
      unawaited(token.whenCancel.then((e) => apiToken.cancel(e.error)));
    }
    return apiToken;
  }

  HttpMethod _parseHttpMethod(String method) {
    switch (method.toUpperCase()) {
      case 'GET':
        return HttpMethod.get;
      case 'POST':
        return HttpMethod.post;
      case 'PUT':
        return HttpMethod.put;
      case 'DELETE':
        return HttpMethod.delete;
      case 'PATCH':
        return HttpMethod.patch;
      case 'HEAD':
        return HttpMethod.head;
      case 'OPTIONS':
        return HttpMethod.options;
      default:
        return HttpMethod.get;
    }
  }

  ApiException _mapDioError(dio.DioException e, ApiRequest request) {
    switch (e.type) {
      case dio.DioExceptionType.connectionTimeout:
        return TimeoutException(
          message: e.message ?? 'Connection timeout',
          timeoutType: TimeoutType.connection,
          request: request,
          error: e,
        );
      case dio.DioExceptionType.sendTimeout:
        return TimeoutException(
          message: e.message ?? 'Send timeout',
          timeoutType: TimeoutType.send,
          request: request,
          error: e,
        );
      case dio.DioExceptionType.receiveTimeout:
        return TimeoutException(
          message: e.message ?? 'Receive timeout',
          timeoutType: TimeoutType.receive,
          request: request,
          error: e,
        );
      case dio.DioExceptionType.badResponse:
        final response = e.response;
        if (response != null) {
          return serverExceptionFor(
            request,
            _toApiResponse(response, request),
            error: e,
          );
        }
        return ServerException.fromResponse(
          message: e.message ?? 'Server error',
          request: request,
          response: ApiResponse<dynamic>(statusCode: 500, request: request),
          error: e,
        );
      case dio.DioExceptionType.cancel:
        return CancellationException(
          message: 'Request cancelled',
          request: request,
          error: e,
        );
      case dio.DioExceptionType.unknown:
      case dio.DioExceptionType.transformTimeout:
        final cause = e.error;
        // Thrown by an api_plus interceptor or by URL validation.
        if (cause is ApiException) return cause;
        // URLs are validated before sending, so a FormatException comes
        // from decoding the response body (e.g. malformed JSON).
        if (cause is FormatException) {
          final response = e.response;
          return SerializationException(
            message: 'Response body could not be decoded: $cause',
            request: request,
            response:
                response == null ? null : _toApiResponse(response, request),
            error: e,
          );
        }
        return NetworkException(
          message: e.message ?? 'Network error',
          request: request,
          error: e,
        );
      case dio.DioExceptionType.connectionError:
      case dio.DioExceptionType.badCertificate:
        return NetworkException(
          message: e.message ?? 'Network error',
          request: request,
          error: e,
        );
    }
  }
}
