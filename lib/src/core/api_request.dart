import 'package:meta/meta.dart';
import '../models/http_method.dart';

/// Represents a unified API request to be handled by any underlying adapter.
@immutable
class ApiRequest {
  /// The path or full URL for the request.
  final String path;

  /// The HTTP method to use.
  final HttpMethod method;

  /// The request headers.
  final Map<String, String> headers;

  /// The query parameters.
  final Map<String, dynamic> queryParameters;

  /// The body payload, if any.
  final dynamic body;

  /// Optional connection timeout.
  final Duration? connectTimeout;

  /// Optional receive timeout.
  final Duration? receiveTimeout;

  /// Optional send timeout.
  final Duration? sendTimeout;

  /// Extra context data for interceptors (e.g., retry count).
  final Map<String, dynamic> extra;

  /// Creates a new [ApiRequest].
  const ApiRequest({
    required this.path,
    this.method = HttpMethod.get,
    this.headers = const {},
    this.queryParameters = const {},
    this.body,
    this.connectTimeout,
    this.receiveTimeout,
    this.sendTimeout,
    this.extra = const {},
  });

  /// Creates a copy of this request with the given fields replaced with the new values.
  ApiRequest copyWith({
    String? path,
    HttpMethod? method,
    Map<String, String>? headers,
    Map<String, dynamic>? queryParameters,
    dynamic body,
    Duration? connectTimeout,
    Duration? receiveTimeout,
    Duration? sendTimeout,
    Map<String, dynamic>? extra,
  }) {
    return ApiRequest(
      path: path ?? this.path,
      method: method ?? this.method,
      headers: headers ?? this.headers,
      queryParameters: queryParameters ?? this.queryParameters,
      body: body ?? this.body,
      connectTimeout: connectTimeout ?? this.connectTimeout,
      receiveTimeout: receiveTimeout ?? this.receiveTimeout,
      sendTimeout: sendTimeout ?? this.sendTimeout,
      extra: extra ?? this.extra,
    );
  }
}
