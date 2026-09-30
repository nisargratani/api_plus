import 'dart:async';

import 'package:dio/dio.dart' as dio;

import '../../config/cache_config.dart';
import '../../config/logger_config.dart';
import '../../config/retry_config.dart';
import '../../core/api_cancel_token.dart';
import '../../core/api_request.dart';
import '../../core/api_response.dart';
import '../../core/internal_keys.dart';
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
  /// cache → retry → logger → custom interceptors.
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
    if (cacheConfig != null) {
      result.add(CacheInterceptor(config: cacheConfig));
    }
    if (retryConfig != null) {
      result.add(RetryInterceptor(config: retryConfig));
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
      handler.next(options);
    } catch (e, stackTrace) {
      handler.reject(
        dio.DioException(
          requestOptions: options,
          error: e,
          stackTrace: stackTrace,
          type: dio.DioExceptionType.unknown,
        ),
      );
    }
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
      ApiResponse<dynamic> apiResponse = _toApiResponse(
        response,
        _dioOptionsToApiRequest(response.requestOptions),
      );

      for (final interceptor in _apiInterceptors) {
        apiResponse = await interceptor.onResponse(apiResponse);
      }

      handler.resolve(_toDioResponse(apiResponse, response.requestOptions));
    } catch (e, stackTrace) {
      handler.reject(
        dio.DioException(
          requestOptions: response.requestOptions,
          error: e,
          stackTrace: stackTrace,
          type: dio.DioExceptionType.unknown,
        ),
      );
    }
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
      ApiException apiException = _mapDioError(err, apiRequest);

      // Re-sends a request through this client's full pipeline. Failures
      // are thrown as ApiException so interceptors (e.g. retry) handle them.
      Future<ApiResponse<dynamic>> invoker(ApiRequest request) async {
        try {
          final retryResponse = await _client.fetch<dynamic>(
            _toRequestOptions(request, err.requestOptions),
          );
          return _toApiResponse(retryResponse, request);
        } on dio.DioException catch (e) {
          throw _mapDioError(e, request);
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
      handler.reject(err);
    } catch (e, stackTrace) {
      handler.reject(
        dio.DioException(
          requestOptions: err.requestOptions,
          error: e,
          stackTrace: stackTrace,
          type: dio.DioExceptionType.unknown,
        ),
      );
    }
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

  static ApiResponse<dynamic> _toApiResponse(
    dio.Response<dynamic> response,
    ApiRequest request,
  ) {
    return ApiResponse<dynamic>(
      data: response.data,
      statusCode: response.statusCode ?? 200,
      headers: Map<String, List<String>>.of(response.headers.map),
      statusMessage: response.statusMessage,
      isRedirect: response.isRedirect,
      request: request,
    );
  }

  static dio.Response<dynamic> _toDioResponse(
    ApiResponse<dynamic> response,
    dio.RequestOptions options,
  ) {
    return dio.Response<dynamic>(
      data: response.data,
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
      extra: options.extra,
      cancelToken: _linkCancelToken(options.cancelToken),
    );
  }

  /// Mirrors a Dio [token] as an [ApiCancelToken], so api_plus interceptors
  /// (e.g. a pending retry delay) react to Retrofit's `@CancelRequest`.
  static ApiCancelToken? _linkCancelToken(dio.CancelToken? token) {
    if (token == null) return null;
    final apiToken = ApiCancelToken();
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
        final respHeaders = <String, List<String>>{};
        e.response?.headers.map.forEach((key, value) {
          respHeaders[key] = value;
        });
        return ServerException.fromResponse(
          message: e.message ?? 'Server error',
          request: request,
          response: ApiResponse<dynamic>(
            data: e.response?.data,
            statusCode: e.response?.statusCode ?? 500,
            headers: respHeaders,
            statusMessage: e.response?.statusMessage,
            request: request,
          ),
          error: e,
        );
      case dio.DioExceptionType.cancel:
        return CancellationException(
          message: 'Request cancelled',
          request: request,
          error: e,
        );
      case dio.DioExceptionType.connectionError:
      case dio.DioExceptionType.badCertificate:
      case dio.DioExceptionType.unknown:
      case dio.DioExceptionType.transformTimeout:
        return NetworkException(
          message: e.message ?? 'Network error',
          request: request,
          error: e,
        );
    }
  }
}
