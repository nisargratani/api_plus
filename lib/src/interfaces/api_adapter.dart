import '../core/api_request.dart';
import '../core/api_response.dart';
import 'api_interceptor.dart';

/// Defines the contract for an API adapter (e.g., Http, Dio).
///
/// An adapter wraps an underlying HTTP client and provides a unified
/// interface for making network requests. All adapters share the same
/// [ApiInterceptor] pipeline, ensuring consistent behavior regardless
/// of the underlying client.
///
/// {@tool snippet}
/// ```dart
/// // Use any adapter implementation interchangeably
/// final ApiAdapter adapter = DioAdapter(baseUrl: 'https://api.example.com');
/// final response = await adapter.request<Map<String, dynamic>>(
///   const ApiRequest(path: '/users/1'),
/// );
/// ```
/// {@end-tool}
abstract class ApiAdapter {
  /// The base URL used by this adapter.
  ///
  /// All relative request paths are resolved against this URL.
  String get baseUrl;

  /// Default headers applied to every request.
  ///
  /// Request-level headers take precedence over these defaults.
  Map<String, String> get defaultHeaders;

  /// The list of interceptors applied to requests and responses.
  ///
  /// Interceptors are executed in order for requests and responses,
  /// and in reverse order for errors.
  List<ApiInterceptor> get interceptors;

  /// Executes the given [request] and returns an [ApiResponse].
  ///
  /// The type parameter [T] specifies the expected type of the
  /// response data.
  ///
  /// Throws [ApiException] or its subclasses on failure:
  /// - [NetworkException] for connection failures
  /// - [ServerException] for HTTP error status codes
  /// - [SerializationException] for parsing failures
  Future<ApiResponse<T>> request<T>(ApiRequest request);

  /// Closes the adapter and releases any resources.
  ///
  /// If [force] is `true`, active connections are terminated immediately.
  /// Otherwise, the adapter waits for pending requests to complete.
  void close({bool force = false});
}
