import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../core/api_request.dart';
import '../../core/api_response.dart';
import '../../exceptions/api_exception.dart';
import '../../interfaces/api_adapter.dart';
import '../../interfaces/api_interceptor.dart';


/// An adapter that wraps the `http` package client.
class HttpAdapter implements ApiAdapter {
  final http.Client _client;
  
  @override
  final String baseUrl;
  
  @override
  final Map<String, String> defaultHeaders;
  
  @override
  final List<ApiInterceptor> interceptors;

  /// Creates a new [HttpAdapter].
  HttpAdapter({
    required this.baseUrl,
    http.Client? client,
    this.defaultHeaders = const {},
    this.interceptors = const [],
  }) : _client = client ?? http.Client();

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
      final uri = _buildUri(finalRequest);
      final httpRequest = http.Request(finalRequest.method.value, uri);
      
      httpRequest.headers.addAll(finalRequest.headers);
      
      if (finalRequest.body != null) {
        if (finalRequest.body is String) {
          httpRequest.body = finalRequest.body as String;
        } else if (finalRequest.body is List<int>) {
          httpRequest.bodyBytes = finalRequest.body as List<int>;
        } else {
          httpRequest.body = jsonEncode(finalRequest.body);
          if (!httpRequest.headers.containsKey('content-type')) {
            httpRequest.headers['content-type'] = 'application/json; charset=utf-8';
          }
        }
      }

      final httpResponse = await _client.send(httpRequest);
      final responseBody = await httpResponse.stream.bytesToString();
      
      dynamic parsedData;
      if (responseBody.isNotEmpty) {
        try {
          parsedData = jsonDecode(responseBody);
        } catch (_) {
          parsedData = responseBody; // Fallback to raw string if not JSON
        }
      }

      ApiResponse<dynamic> response = ApiResponse<dynamic>(
        data: parsedData,
        statusCode: httpResponse.statusCode,
        headers: httpResponse.headers.map((k, v) => MapEntry(k, [v])),
        statusMessage: httpResponse.reasonPhrase,
        isRedirect: httpResponse.isRedirect,
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
    } catch (e, stackTrace) {
      ApiException apiException;
      if (e is http.ClientException) {
        apiException = NetworkException(
          message: e.message,
          request: finalRequest,
          error: e,
          stackTrace: stackTrace,
        );
      } else {
        apiException = NetworkException(
          message: 'Unexpected network error occurred.',
          request: finalRequest,
          error: e,
          stackTrace: stackTrace,
        );
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
    }
  }

  Uri _buildUri(ApiRequest request) {
    final basePath = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    final reqPath = request.path.startsWith('/') ? request.path : '/${request.path}';
    
    final uri = Uri.parse('$basePath$reqPath');
    
    if (request.queryParameters.isNotEmpty) {
      final Map<String, dynamic> cleanParams = {};
      request.queryParameters.forEach((key, value) {
        if (value != null) {
          cleanParams[key] = value is Iterable ? value.map((e) => e.toString()).toList() : value.toString();
        }
      });
      return uri.replace(queryParameters: cleanParams);
    }
    
    return uri;
  }

  @override
  void close({bool force = false}) {
    _client.close();
  }
}
