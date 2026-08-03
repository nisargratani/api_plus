import 'package:dio/dio.dart' as dio;
import '../../core/api_request.dart';
import '../../core/api_response.dart';
import '../../exceptions/api_exception.dart';
import '../../interfaces/api_adapter.dart';
import '../../interfaces/api_interceptor.dart';


/// An adapter that wraps the `dio` package client.
class DioAdapter implements ApiAdapter {
  final dio.Dio _client;
  
  @override
  final String baseUrl;
  
  @override
  final Map<String, String> defaultHeaders;
  
  @override
  final List<ApiInterceptor> interceptors;

  /// Creates a new [DioAdapter].
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

  @override
  Future<ApiResponse<T>> request<T>(ApiRequest request) async {
    ApiRequest finalRequest = request.copyWith(
      headers: {...defaultHeaders, ...request.headers},
    );

    // 1. Run onRequest interceptors
    for (final interceptor in interceptors) {
      final dynamic result = await interceptor.onRequest(finalRequest);
      if (result is ApiResponse) {
        return result as ApiResponse<T>;
      } else if (result is ApiRequest) {
        finalRequest = result;
      }
    }

    try {
      final dioResponse = await _client.request<dynamic>(
        finalRequest.path,
        data: finalRequest.body,
        queryParameters: finalRequest.queryParameters,
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
      for (final interceptor in interceptors) {
        response = await interceptor.onResponse(response);
      }

      if (!response.isSuccessful) {
        throw ServerException.fromResponse(
          message: 'Server returned ${response.statusCode}: ${response.statusMessage}',
          request: finalRequest,
          response: response,
        );
      }

      return response as ApiResponse<T>;
    } on ApiException {
      rethrow;
    } on dio.DioException catch (e, stackTrace) {
      ApiException apiException;
      
      switch (e.type) {
        case dio.DioExceptionType.connectionTimeout:
        case dio.DioExceptionType.sendTimeout:
        case dio.DioExceptionType.receiveTimeout:
        case dio.DioExceptionType.connectionError:
          apiException = NetworkException(
            message: e.message ?? 'Network connection error',
            request: finalRequest,
            error: e,
            stackTrace: stackTrace,
          );
          break;
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
          );
          
          apiException = ServerException.fromResponse(
            message: e.message ?? 'Server error',
            request: finalRequest,
            response: apiResp,
            error: e,
            stackTrace: stackTrace,
          );
          break;
        case dio.DioExceptionType.cancel:
          apiException = NetworkException(
            message: 'Request cancelled',
            request: finalRequest,
            error: e,
            stackTrace: stackTrace,
          );
          break;
        case dio.DioExceptionType.badCertificate:
        case dio.DioExceptionType.unknown:
        default:
          apiException = NetworkException(
            message: e.message ?? 'Unknown network error',
            request: finalRequest,
            error: e,
            stackTrace: stackTrace,
          );
          break;
      }

      // 3. Run onError interceptors
      for (final interceptor in interceptors) {
        final dynamic result = await interceptor.onError(apiException, this.request);
        if (result is ApiResponse) {
          return result as ApiResponse<T>;
        } else if (result is ApiException) {
          apiException = result;
        }
      }
      
      throw apiException;
    } catch (e, stackTrace) {
      ApiException apiException = NetworkException(
        message: 'Unexpected error occurred.',
        request: finalRequest,
        error: e,
        stackTrace: stackTrace,
      );

      for (final interceptor in interceptors) {
        final dynamic result = await interceptor.onError(apiException, this.request);
        if (result is ApiResponse) {
          return result as ApiResponse<T>;
        } else if (result is ApiException) {
          apiException = result;
        }
      }
      
      throw apiException;
    }
  }

  @override
  void close({bool force = false}) {
    _client.close(force: force);
  }
}
