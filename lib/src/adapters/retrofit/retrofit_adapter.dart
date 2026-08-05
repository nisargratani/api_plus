import 'package:dio/dio.dart' as dio;
import '../../config/cache_config.dart';
import '../../config/logger_config.dart';
import '../../config/retry_config.dart';
import '../../core/api_request.dart';
import '../../core/api_response.dart';
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
    if (_client != null) return _client!;

    _client = dio.Dio(dio.BaseOptions(
      baseUrl: _baseUrl,
      headers: _defaultHeaders,
    ));

    _client!.interceptors.add(
      _RetrofitBridgeInterceptor(_interceptors),
    );

    return _client!;
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

  _RetrofitBridgeInterceptor(this._apiInterceptors);

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
      ApiRequest apiRequest = _dioOptionsToApiRequest(options);

      for (final interceptor in _apiInterceptors) {
        final result = await interceptor.onRequest(apiRequest);
        if (result is ApiResponse) {
          // Short-circuit: return cached/mocked response
          handler.resolve(dio.Response<dynamic>(
            data: result.data,
            statusCode: result.statusCode,
            statusMessage: result.statusMessage,
            requestOptions: options,
            headers: dio.Headers.fromMap(
              result.headers.map((k, v) => MapEntry(k, v)),
            ),
          ));
          return;
        } else if (result is ApiRequest) {
          apiRequest = result;
        }
      }

      // Apply any modifications from interceptors back to Dio options
      options.headers.addAll(apiRequest.headers);
      if (apiRequest.extra.isNotEmpty) {
        options.extra.addAll(apiRequest.extra);
      }

      handler.next(options);
    } catch (e) {
      handler.reject(
        dio.DioException(
          requestOptions: options,
          error: e,
          type: dio.DioExceptionType.unknown,
        ),
      );
    }
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
      final headers = <String, List<String>>{};
      response.headers.map.forEach((key, value) {
        headers[key] = value;
      });

      ApiResponse<dynamic> apiResponse = ApiResponse<dynamic>(
        data: response.data,
        statusCode: response.statusCode ?? 200,
        headers: headers,
        statusMessage: response.statusMessage,
        isRedirect: response.isRedirect,
        request: _dioOptionsToApiRequest(response.requestOptions),
      );

      for (final interceptor in _apiInterceptors) {
        apiResponse = await interceptor.onResponse(apiResponse);
      }

      // Convert back to Dio response
      handler.resolve(dio.Response<dynamic>(
        data: apiResponse.data,
        statusCode: apiResponse.statusCode,
        statusMessage: apiResponse.statusMessage,
        requestOptions: response.requestOptions,
        headers: dio.Headers.fromMap(
          apiResponse.headers.map((k, v) => MapEntry(k, v)),
        ),
      ));
    } catch (e) {
      handler.reject(
        dio.DioException(
          requestOptions: response.requestOptions,
          error: e,
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

      // Create an invoker that retries via Dio
      Future<ApiResponse<dynamic>> invoker(ApiRequest request) async {
        final retryOptions = dio.RequestOptions(
          path: request.path,
          method: request.method.value,
          headers: request.headers,
          queryParameters: request.queryParameters,
          data: request.body,
          baseUrl: err.requestOptions.baseUrl,
          extra: request.extra,
        );

        final retryResponse = await dio.Dio(dio.BaseOptions(
          baseUrl: err.requestOptions.baseUrl,
        )).fetch<dynamic>(retryOptions);

        final headers = <String, List<String>>{};
        retryResponse.headers.map.forEach((key, value) {
          headers[key] = value;
        });

        return ApiResponse<dynamic>(
          data: retryResponse.data,
          statusCode: retryResponse.statusCode ?? 200,
          headers: headers,
          statusMessage: retryResponse.statusMessage,
          request: request,
        );
      }

      for (final interceptor in _apiInterceptors) {
        final result = await interceptor.onError(apiException, invoker);
        if (result is ApiResponse) {
          // Recovered — convert to Dio response
          handler.resolve(dio.Response<dynamic>(
            data: result.data,
            statusCode: result.statusCode,
            statusMessage: result.statusMessage,
            requestOptions: err.requestOptions,
          ));
          return;
        } else if (result is ApiException) {
          apiException = result;
        }
      }

      handler.reject(err);
    } catch (e) {
      handler.reject(
        dio.DioException(
          requestOptions: err.requestOptions,
          error: e,
          type: dio.DioExceptionType.unknown,
        ),
      );
    }
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
    );
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
