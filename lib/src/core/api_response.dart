import 'package:meta/meta.dart';
import 'api_request.dart';

/// Represents a unified response from any API client.
@immutable
class ApiResponse<T> {
  /// The payload of the response.
  final T? data;

  /// The HTTP status code.
  final int statusCode;

  /// The HTTP headers returned by the server.
  final Map<String, List<String>> headers;

  /// The status message if provided.
  final String? statusMessage;

  /// Whether the request was a redirect.
  final bool isRedirect;

  /// The original request that resulted in this response.
  final ApiRequest? request;

  /// Creates a new [ApiResponse].
  const ApiResponse({
    this.data,
    required this.statusCode,
    this.headers = const {},
    this.statusMessage,
    this.isRedirect = false,
    this.request,
  });

  /// Returns true if the status code is between 200 and 299 inclusive.
  bool get isSuccessful => statusCode >= 200 && statusCode < 300;
}
