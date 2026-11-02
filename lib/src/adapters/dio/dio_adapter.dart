import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart' as dio;

import '../../core/api_request.dart';
import '../../core/api_response.dart';
import '../../core/internal_keys.dart';
import '../../core/request_url.dart';
import '../../exceptions/api_exception.dart';
import '../../interfaces/api_adapter.dart';
import '../../interfaces/api_interceptor.dart';
import '../adapter_mixin.dart';

/// An adapter that wraps the `dio` package HTTP client.
///
/// Translates unified [ApiRequest] and [ApiResponse] types to and from
/// Dio's native request/response types, while running all requests
/// through the shared [InterceptorPipeline].
///
/// {@tool snippet}
/// ```dart
/// final adapter = DioAdapter(
///   baseUrl: 'https://api.example.com',
///   defaultHeaders: {'Accept': 'application/json'},
///   interceptors: [retryInterceptor, loggerInterceptor],
/// );
///
/// final response = await adapter.request<Map<String, dynamic>>(
///   const ApiRequest(path: '/users/1'),
/// );
/// ```
/// {@end-tool}
class DioAdapter extends ApiAdapter with InterceptorPipeline {
  final dio.Dio _client;

  /// Whether [close] was called; no new network calls are started.
  bool _closed = false;

  @override
  final String baseUrl;

  @override
  final Map<String, String> defaultHeaders;

  @override
  final List<ApiInterceptor> interceptors;

  /// Creates a new [DioAdapter].
  ///
  /// If no [client] is provided, a new [dio.Dio] instance is created
  /// with the given [baseUrl]. The client (provided or not) is closed
  /// by [close].
  ///
  /// [connectTimeout], [receiveTimeout], and [sendTimeout] become the
  /// client's defaults; per-request values on [ApiRequest] override them.
  DioAdapter({
    required this.baseUrl,
    dio.Dio? client,
    this.defaultHeaders = const {},
    this.interceptors = const [],
    Duration? connectTimeout,
    Duration? receiveTimeout,
    Duration? sendTimeout,
  }) : _client = client ?? dio.Dio(dio.BaseOptions(baseUrl: baseUrl)) {
    final options = _client.options;
    if (options.baseUrl.isEmpty) options.baseUrl = baseUrl;
    if (connectTimeout != null) options.connectTimeout = connectTimeout;
    if (receiveTimeout != null) options.receiveTimeout = receiveTimeout;
    if (sendTimeout != null) options.sendTimeout = sendTimeout;
  }

  /// Provides access to the underlying [dio.Dio] client.
  ///
  /// Useful for passing to Retrofit-generated client classes.
  dio.Dio get client => _client;

  @override
  Future<ApiResponse<T>> request<T>(ApiRequest request) {
    return runPipeline<T>(request, _send);
  }

  Future<ApiResponse<dynamic>> _send(ApiRequest request) async {
    if (_closed) {
      throw const ConfigurationException(message: 'DioAdapter is closed');
    }
    _validateUrl(request.path);

    final cancelToken = request.cancelToken;
    dio.CancelToken? dioCancelToken;
    void Function()? removeCancelListener;
    if (cancelToken != null) {
      final token = dioCancelToken = dio.CancelToken();
      // Removed when the request finishes, so a long-lived token does not
      // keep completed requests (and their bodies) reachable.
      removeCancelListener = cancelToken.addCancelListener(() {
        if (!token.isCancelled) token.cancel(cancelToken.reason);
      });
    }
    try {
      final dioResponse = await _client.request<dynamic>(
        request.path,
        data: request.body,
        queryParameters: _withoutNulls(request.queryParameters),
        options: dio.Options(
          method: request.method.value,
          headers: request.headers,
          connectTimeout: request.connectTimeout,
          sendTimeout: request.sendTimeout,
          receiveTimeout: request.receiveTimeout,
        ),
        cancelToken: dioCancelToken,
      );
      return _toApiResponse(dioResponse, request);
    } on dio.DioException catch (e, stackTrace) {
      // Error statuses are returned (not thrown) so that the pipeline runs
      // onResponse interceptors for them, exactly like the other adapters.
      final response = e.response;
      if (e.type == dio.DioExceptionType.badResponse && response != null) {
        return _toApiResponse(response, request);
      }
      throw _mapDioException(e, request, stackTrace);
    } on ApiException {
      rethrow;
    } catch (e, stackTrace) {
      throw NetworkException(
        message: 'Unexpected error occurred.',
        request: request,
        error: e,
        stackTrace: stackTrace,
      );
    } finally {
      removeCancelListener?.call();
    }
  }

  /// Throws a [ConfigurationException] if Dio could not build a valid URL
  /// from [path] and the client's base URL. Checked before sending, so an
  /// invalid URL is not reported as a (retryable) network error.
  void _validateUrl(String path) {
    try {
      if (looksLikeAbsoluteUrl(path)) parseAbsoluteUrl(path);
      // The same URL resolution Dio applies when it sends the request.
      dio.RequestOptions(path: path, baseUrl: _client.options.baseUrl).uri;
    } on FormatException catch (e, stackTrace) {
      throw ConfigurationException(
        message: 'Invalid request URL: ${e.message}',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Null query parameters are omitted, as in the other adapters.
  static Map<String, dynamic>? _withoutNulls(Map<String, dynamic> params) {
    if (params.isEmpty) return null;
    if (!params.values.contains(null)) return params;
    return {
      for (final entry in params.entries)
        if (entry.value != null) entry.key: entry.value,
    };
  }

  /// An empty body is `null`, as with `HttpAdapter` (Dio yields `''`).
  static ApiResponse<dynamic> _toApiResponse(
    dio.Response<dynamic> response,
    ApiRequest request,
  ) {
    final data = response.data;
    return ApiResponse<dynamic>(
      data: data is String && data.isEmpty ? null : data,
      statusCode: response.statusCode ?? 200,
      headers: Map<String, List<String>>.of(response.headers.map),
      statusMessage: response.statusMessage,
      isRedirect: response.isRedirect,
      request: request,
    );
  }

  /// Closes the adapter and its Dio client.
  ///
  /// With `force: false` (the default), requests that are in flight finish
  /// normally; with `force: true`, they are aborted. Either way, network
  /// calls started after [close] (new requests and retries) fail with a
  /// [ConfigurationException] without being retried.
  @override
  void close({bool force = false}) {
    _closed = true;
    _client.close(force: force);
  }

  ApiException _mapDioException(
    dio.DioException e,
    ApiRequest request,
    StackTrace stackTrace,
  ) {
    switch (e.type) {
      case dio.DioExceptionType.connectionTimeout:
        return TimeoutException(
          message: e.message ?? 'Connection timeout',
          timeoutType: TimeoutType.connection,
          request: request,
          error: e,
          stackTrace: stackTrace,
        );
      case dio.DioExceptionType.sendTimeout:
        return TimeoutException(
          message: e.message ?? 'Send timeout',
          timeoutType: TimeoutType.send,
          request: request,
          error: e,
          stackTrace: stackTrace,
        );
      case dio.DioExceptionType.receiveTimeout:
        return TimeoutException(
          message: e.message ?? 'Receive timeout',
          timeoutType: TimeoutType.receive,
          request: request,
          error: e,
          stackTrace: stackTrace,
        );
      case dio.DioExceptionType.connectionError:
        return NetworkException(
          message: e.message ?? 'Connection error',
          request: request,
          error: e,
          stackTrace: stackTrace,
        );
      case dio.DioExceptionType.badResponse:
        final respHeaders = <String, List<String>>{};
        e.response?.headers.map.forEach((key, value) {
          respHeaders[key] = value;
        });

        final data = e.response?.data;
        final apiResp = ApiResponse<dynamic>(
          data: data is String && data.isEmpty ? null : data,
          statusCode: e.response?.statusCode ?? 500,
          headers: respHeaders,
          statusMessage: e.response?.statusMessage,
          request: request,
        );

        return ServerException.fromResponse(
          message: e.message ?? 'Server error',
          request: request,
          response: apiResp,
          error: e,
          stackTrace: stackTrace,
        );
      case dio.DioExceptionType.cancel:
        if (request.cancelToken?.isCancelled ?? false) {
          return cancellationFor(request, error: e, stackTrace: stackTrace);
        }
        return CancellationException(
          message: 'Request cancelled',
          request: request,
          error: e,
          stackTrace: stackTrace,
        );
      case dio.DioExceptionType.badCertificate:
        return NetworkException(
          message: e.message ?? 'Bad certificate',
          request: request,
          error: e,
          stackTrace: stackTrace,
        );
      case dio.DioExceptionType.unknown:
      case dio.DioExceptionType.transformTimeout:
        if (e.error is JsonUnsupportedObjectError) {
          return SerializationException(
            message: 'Request body could not be encoded as JSON: ${e.error}',
            request: request,
            error: e,
            stackTrace: stackTrace,
          );
        }
        // The URL is validated before sending, so a FormatException here
        // comes from decoding the response body (e.g. malformed JSON).
        if (e.error is FormatException) {
          final response = e.response;
          return SerializationException(
            message: 'Response body could not be decoded: ${e.error}',
            request: request,
            response:
                response == null ? null : _toApiResponse(response, request),
            error: e,
            stackTrace: stackTrace,
          );
        }
        return NetworkException(
          message: e.message ?? 'Unknown network error',
          request: request,
          error: e,
          stackTrace: stackTrace,
        );
    }
  }
}
