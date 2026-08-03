import '../core/api_request.dart';
import '../core/api_response.dart';
import 'api_interceptor.dart';

/// Defines the contract for an API adapter (e.g. Http, Dio).
abstract class ApiAdapter {
  /// Base URL used by the adapter.
  String get baseUrl;

  /// Default headers to be applied to all requests.
  Map<String, String> get defaultHeaders;

  /// List of interceptors to be applied to requests and responses.
  List<ApiInterceptor> get interceptors;

  /// Executes the given [request] and returns an [ApiResponse].
  ///
  /// Throws [NetworkException] or its subclasses on failure.
  Future<ApiResponse<T>> request<T>(ApiRequest request);

  /// Closes the adapter and releases any resources.
  void close({bool force = false});
}
