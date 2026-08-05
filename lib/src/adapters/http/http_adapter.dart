import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../core/api_request.dart';
import '../../core/api_response.dart';
import '../../exceptions/api_exception.dart';
import '../../interfaces/api_adapter.dart';
import '../../interfaces/api_interceptor.dart';
import '../adapter_mixin.dart';

/// An adapter that wraps the `http` package HTTP client.
///
/// Translates unified [ApiRequest] and [ApiResponse] types to and from
/// the `http` package's native request/response types, while running
/// all requests through the shared [InterceptorPipeline].
///
/// {@tool snippet}
/// ```dart
/// final adapter = HttpAdapter(
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
class HttpAdapter extends ApiAdapter with InterceptorPipeline {
  final http.Client _client;

  @override
  final String baseUrl;

  @override
  final Map<String, String> defaultHeaders;

  @override
  final List<ApiInterceptor> interceptors;

  /// Creates a new [HttpAdapter].
  ///
  /// If no [client] is provided, a new [http.Client] instance is created.
  HttpAdapter({
    required this.baseUrl,
    http.Client? client,
    this.defaultHeaders = const {},
    this.interceptors = const [],
  }) : _client = client ?? http.Client();

  @override
  Future<ApiResponse<T>> request<T>(ApiRequest request) async {
    // 1. Run onRequest interceptors
    final dynamic requestResult = await runOnRequest(request);
    if (requestResult is ApiResponse) {
      return requestResult as ApiResponse<T>;
    }
    final ApiRequest finalRequest = requestResult as ApiRequest;

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
            httpRequest.headers['content-type'] =
                'application/json; charset=utf-8';
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
          parsedData = responseBody;
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
    } on http.ClientException catch (e, stackTrace) {
      final apiException = NetworkException(
        message: e.message,
        request: finalRequest,
        error: e,
        stackTrace: stackTrace,
      );
      return runOnError<T>(apiException);
    } catch (e, stackTrace) {
      final apiException = NetworkException(
        message: 'Unexpected network error occurred.',
        request: finalRequest,
        error: e,
        stackTrace: stackTrace,
      );
      return runOnError<T>(apiException);
    }
  }

  Uri _buildUri(ApiRequest request) {
    final basePath = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    final reqPath =
        request.path.startsWith('/') ? request.path : '/${request.path}';

    final uri = Uri.parse('$basePath$reqPath');

    if (request.queryParameters.isNotEmpty) {
      final cleanParams = <String, dynamic>{};
      request.queryParameters.forEach((key, value) {
        if (value != null) {
          cleanParams[key] = value is Iterable
              ? value.map((e) => e.toString()).toList()
              : value.toString();
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
