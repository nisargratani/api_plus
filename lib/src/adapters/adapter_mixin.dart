import 'dart:async';

import 'package:meta/meta.dart';

import '../core/api_request.dart';
import '../core/api_response.dart';
import '../core/internal_keys.dart';
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
  /// - Use the invoker (this adapter's [request]) to retry the request
  Future<ApiResponse<T>> runOnError<T>(ApiException error) async {
    ApiException currentError = error;
    for (final interceptor in interceptors) {
      final result = await interceptor.onError(currentError, request);
      if (result is ApiResponse) {
        return castResponse<T>(result, currentError.request);
      } else if (result is ApiException) {
        currentError = result;
      }
    }
    throw currentError;
  }

  /// Runs [request] through the complete interceptor pipeline, using [send]
  /// to perform the actual network call.
  ///
  /// [send] must return the raw response for **any** HTTP status code and
  /// throw an [ApiException] for transport-level failures. Non-2xx responses
  /// are passed through the onResponse chain and then converted into a
  /// [ServerException] that is passed through the onError chain, so that
  /// interceptors such as retry and cache see them.
  @protected
  Future<ApiResponse<T>> runPipeline<T>(
    ApiRequest request,
    Future<ApiResponse<dynamic>> Function(ApiRequest request) send,
  ) async {
    if (request.cancelToken?.isCancelled ?? false) {
      return runOnError<T>(cancellationFor(request));
    }
    final dynamic requestResult = await runOnRequest(request);
    if (requestResult is ApiResponse) {
      _scheduleRevalidation(requestResult.request);
      return castResponse<T>(requestResult, request);
    }
    final finalRequest = requestResult as ApiRequest;

    ApiResponse<dynamic> response;
    try {
      response = await runOnResponse(await send(finalRequest));
      if (!response.isSuccessful) {
        throw ServerException.fromResponse(
          message: 'Server returned ${response.statusCode}'
              '${response.statusMessage != null ? ': ${response.statusMessage}' : ''}',
          request: finalRequest,
          response: response,
        );
      }
    } on ApiException catch (e) {
      return runOnError<T>(e);
    }
    return castResponse<T>(response, finalRequest);
  }

  /// Converts [response] into an `ApiResponse<T>`.
  ///
  /// Throws a [SerializationException] if the response data is not
  /// of type [T].
  @protected
  ApiResponse<T> castResponse<T>(
    ApiResponse<dynamic> response,
    ApiRequest? request,
  ) {
    if (response is ApiResponse<T>) return response;
    final data = response.data;
    if (data is! T?) {
      throw SerializationException(
        message: 'Expected response data of type $T, '
            'but received ${data.runtimeType}.',
        request: response.request ?? request,
        response: response,
      );
    }
    return ApiResponse<T>(
      data: data,
      statusCode: response.statusCode,
      headers: response.headers,
      statusMessage: response.statusMessage,
      isRedirect: response.isRedirect,
      request: response.request ?? request,
    );
  }

  /// Refreshes a stale cache entry in the background when a cache
  /// interceptor served it with stale-while-revalidate enabled.
  void _scheduleRevalidation(ApiRequest? servedFor) {
    final refresh = revalidationRequestFor(servedFor);
    if (refresh == null) return;
    // The stale response has already been returned to the caller, so a
    // failed refresh is not an error for them: the stale entry simply stays
    // in the cache. Interceptors (e.g. the logger) still observe the failure.
    unawaited(request<dynamic>(refresh).then<void>((_) {}, onError: (_) {}));
  }
}
