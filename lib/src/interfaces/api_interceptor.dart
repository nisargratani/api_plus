import '../core/api_request.dart';
import '../core/api_response.dart';
import '../exceptions/api_exception.dart';

/// Contract for intercepting API requests, responses, and errors.
abstract class ApiInterceptor {
  /// Called before the request is executed.
  /// 
  /// Return an [ApiRequest] to continue the chain with the original or modified request.
  /// Return an [ApiResponse] to short-circuit the network call (e.g. for caching).
  Future<dynamic> onRequest(ApiRequest request) async => request;

  /// Called when a response is successfully received.
  /// 
  /// Return the original or a modified [ApiResponse].
  Future<ApiResponse<dynamic>> onResponse(ApiResponse<dynamic> response) async => response;

  /// Called when an error occurs during the request execution.
  /// 
  /// Use the [invoker] to retry the request if desired.
  /// Return an [ApiResponse] to recover from the error.
  /// Return or throw an [ApiException] to let the error propagate.
  Future<dynamic> onError(
    ApiException error, 
    Future<ApiResponse<dynamic>> Function(ApiRequest) invoker,
  ) async => error;
}
