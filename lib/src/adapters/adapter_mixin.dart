import '../core/api_request.dart';
import '../core/api_response.dart';
import '../exceptions/api_exception.dart';
import '../interfaces/api_adapter.dart';

/// Mixin that provides the shared interceptor pipeline for all adapters.
///
/// This mixin eliminates code duplication by extracting the common
/// interceptor execution logic (onRequest, onResponse, onError) that
/// is identical across all adapter implementations.
///
/// {@tool snippet}
/// ```dart
/// class MyAdapter extends ApiAdapter with InterceptorPipeline {
///   // Only implement the raw network call
/// }
/// ```
/// {@end-tool}
mixin InterceptorPipeline on ApiAdapter {
  /// Runs the onRequest interceptor chain.
  ///
  /// Returns either an [ApiRequest] (to continue with the network call)
  /// or an [ApiResponse] (to short-circuit).
  Future<dynamic> runOnRequest(ApiRequest request) async {
    final mergedRequest = request.copyWith(
      headers: {...defaultHeaders, ...request.headers},
    );

    dynamic current = mergedRequest;
    for (final interceptor in interceptors) {
      final result = await interceptor.onRequest(
        current as ApiRequest,
      );
      if (result is ApiResponse) {
        return result;
      } else if (result is ApiRequest) {
        current = result;
      }
    }
    return current;
  }

  /// Runs the onResponse interceptor chain.
  ///
  /// Each interceptor can modify the response before passing it
  /// to the next.
  Future<ApiResponse<dynamic>> runOnResponse(
    ApiResponse<dynamic> response,
  ) async {
    ApiResponse<dynamic> current = response;
    for (final interceptor in interceptors) {
      current = await interceptor.onResponse(current);
    }
    return current;
  }

  /// Runs the onError interceptor chain.
  ///
  /// Interceptors can either:
  /// - Return an [ApiResponse] to recover from the error
  /// - Return or throw an [ApiException] to propagate the error
  /// - Use the [invoker] to retry the request
  Future<ApiResponse<T>> runOnError<T>(ApiException error) async {
    ApiException currentError = error;
    for (final interceptor in interceptors) {
      final result = await interceptor.onError(currentError, request);
      if (result is ApiResponse) {
        return result as ApiResponse<T>;
      } else if (result is ApiException) {
        currentError = result;
      }
    }
    throw currentError;
  }
}
