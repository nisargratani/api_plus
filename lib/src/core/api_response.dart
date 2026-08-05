import 'package:meta/meta.dart';
import 'api_request.dart';

/// Represents a unified response from any API client.
///
/// Wraps the response data, status code, headers, and metadata from
/// any underlying HTTP client into a single, client-agnostic type.
///
/// The generic type [T] represents the type of the response [data].
/// When no specific type is needed, use `ApiResponse<dynamic>`.
///
/// {@tool snippet}
/// ```dart
/// final response = ApiResponse<Map<String, dynamic>>(
///   data: {'id': 1, 'name': 'John'},
///   statusCode: 200,
///   statusMessage: 'OK',
/// );
///
/// if (response.isSuccessful) {
///   print(response.data);
/// }
/// ```
/// {@end-tool}
@immutable
class ApiResponse<T> {
  /// The payload of the response.
  ///
  /// The type depends on the response content and how the adapter
  /// parses the body. Typically a [Map], [List], or [String].
  final T? data;

  /// The HTTP status code of the response.
  final int statusCode;

  /// The HTTP headers returned by the server.
  ///
  /// Header names are lowercase. Values are lists to support
  /// multi-value headers.
  final Map<String, List<String>> headers;

  /// The status message if provided by the server (e.g., "OK", "Not Found").
  final String? statusMessage;

  /// Whether the request resulted in a redirect.
  final bool isRedirect;

  /// The original request that produced this response.
  ///
  /// May be `null` if the response was constructed without a request
  /// reference (e.g., from cache).
  final ApiRequest? request;

  /// Creates a new [ApiResponse].
  ///
  /// The [statusCode] is required. All other fields have sensible defaults.
  const ApiResponse({
    this.data,
    required this.statusCode,
    this.headers = const {},
    this.statusMessage,
    this.isRedirect = false,
    this.request,
  });

  /// Returns `true` if the [statusCode] is between 200 and 299 inclusive.
  bool get isSuccessful => statusCode >= 200 && statusCode < 300;

  /// Creates a copy of this response with the given fields replaced.
  ///
  /// Any field not provided will retain its current value.
  ApiResponse<T> copyWith({
    T? data,
    int? statusCode,
    Map<String, List<String>>? headers,
    String? statusMessage,
    bool? isRedirect,
    ApiRequest? request,
  }) {
    return ApiResponse<T>(
      data: data ?? this.data,
      statusCode: statusCode ?? this.statusCode,
      headers: headers ?? this.headers,
      statusMessage: statusMessage ?? this.statusMessage,
      isRedirect: isRedirect ?? this.isRedirect,
      request: request ?? this.request,
    );
  }

  @override
  String toString() => 'ApiResponse(statusCode: $statusCode, '
      'statusMessage: $statusMessage, '
      'isSuccessful: $isSuccessful)';
}
