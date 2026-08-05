import 'package:dio/dio.dart' as dio;
import '../../core/api_request.dart';
import '../../core/api_response.dart';
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

  @override
  final String baseUrl;

  @override
  final Map<String, String> defaultHeaders;

  @override
  final List<ApiInterceptor> interceptors;

  /// Creates a new [DioAdapter].
  ///
  /// If no [client] is provided, a new [dio.Dio] instance is created
  /// with the given [baseUrl].
  DioAdapter({
    required this.baseUrl,
    dio.Dio? client,
    this.defaultHeaders = const {},
    this.interceptors = const [],
  }) : _client = client ?? dio.Dio(dio.BaseOptions(baseUrl: baseUrl)) {
    if (client != null && client.options.baseUrl.isEmpty) {
      client.options.baseUrl = baseUrl;
    }
  }

  /// Provides access to the underlying [dio.Dio] client.
  ///
  /// Useful for passing to Retrofit-generated client classes.
  dio.Dio get client => _client;

  @override
  Future<ApiResponse<T>> request<T>(ApiRequest request) async {
    // 1. Run onRequest interceptors
    final dynamic requestResult = await runOnRequest(request);
    if (requestResult is ApiResponse) {
      return requestResult as ApiResponse<T>;
    }
    final ApiRequest finalRequest = requestResult as ApiRequest;

    try {
      final dioResponse = await _client.request<dynamic>(
        finalRequest.path,
        data: finalRequest.body,
        queryParameters: finalRequest.queryParameters.isNotEmpty
            ? finalRequest.queryParameters
            : null,
        options: dio.Options(
          method: finalRequest.method.value,
          headers: finalRequest.headers,
          sendTimeout: finalRequest.sendTimeout,
          receiveTimeout: finalRequest.receiveTimeout,
        ),
      );

      final headers = <String, List<String>>{};
      dioResponse.headers.map.forEach((key, value) {
        headers[key] = value;
      });

      ApiResponse<dynamic> response = ApiResponse<dynamic>(
        data: dioResponse.data,
        statusCode: dioResponse.statusCode ?? 200,
        headers: headers,
        statusMessage: dioResponse.statusMessage,
        isRedirect: dioResponse.isRedirect,
        request: finalRequest,
      );

      // 2. Run onResponse interceptors
      response = await runOnResponse(response);

      if (!response.isSuccessful) {
        throw ServerException.fromResponse(
          message: 'Server returned ${response.statusCode}: '
              '${response.statusMessage}',
          request: finalRequest,
          response: response,
        );
      }

      return response as ApiResponse<T>;
    } on ApiException {
      rethrow;
    } on dio.DioException catch (e, stackTrace) {
      final apiException = _mapDioException(e, finalRequest, stackTrace);
      return runOnError<T>(apiException);
    } catch (e, stackTrace) {
      final apiException = NetworkException(
        message: 'Unexpected error occurred.',
        request: finalRequest,
        error: e,
        stackTrace: stackTrace,
      );
      return runOnError<T>(apiException);
    }
  }

  @override
  void close({bool force = false}) {
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

        final apiResp = ApiResponse<dynamic>(
          data: e.response?.data,
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
        return NetworkException(
          message: e.message ?? 'Unknown network error',
          request: request,
          error: e,
          stackTrace: stackTrace,
        );
    }
  }
}
