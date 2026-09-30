/// Keys that `api_plus` stores in [ApiRequest.extra] to coordinate
/// interceptors and adapters.
///
/// This file is intentionally not exported from the package.
library;

import '../exceptions/api_exception.dart';
import 'api_request.dart';

/// Set on the request attached to a stale cached response that should be
/// refreshed in the background (stale-while-revalidate).
const String revalidateExtraKey = '_apiPlusRevalidate';

/// Set on the background request that refreshes a stale cache entry, so the
/// cache interceptor does not short-circuit it with the stale entry again.
const String revalidatingExtraKey = '_apiPlusRevalidating';

/// Set on requests re-sent by a `RetryInterceptor`, so that nested pipeline
/// runs do not start their own retry loop.
const String retryAttemptExtraKey = '_apiPlusRetryAttempt';

/// Returns a copy of [request] whose [ApiRequest.extra] contains [values].
ApiRequest withExtras(ApiRequest request, Map<String, dynamic> values) {
  return request.copyWith(extra: {...request.extra, ...values});
}

/// Returns the request to send in the background to refresh a stale cache
/// entry, or `null` if [request] does not ask for revalidation.
ApiRequest? revalidationRequestFor(ApiRequest? request) {
  if (request == null || request.extra[revalidateExtraKey] != true) {
    return null;
  }
  final extra = Map<String, dynamic>.from(request.extra)
    ..remove(revalidateExtraKey)
    ..remove(retryAttemptExtraKey)
    ..remove('_retryCount')
    ..remove('_firstAttemptTime')
    ..[revalidatingExtraKey] = true;
  // Built explicitly (not with copyWith) so the caller's cancel token is
  // dropped: cancelling the original request must not stop the refresh.
  return ApiRequest(
    path: request.path,
    method: request.method,
    headers: request.headers,
    queryParameters: request.queryParameters,
    body: request.body,
    connectTimeout: request.connectTimeout,
    receiveTimeout: request.receiveTimeout,
    sendTimeout: request.sendTimeout,
    extra: extra,
  );
}

/// The exception thrown for [request] after its cancel token was cancelled.
CancellationException cancellationFor(
  ApiRequest request, {
  Object? error,
  StackTrace? stackTrace,
}) {
  final reason = request.cancelToken?.reason;
  return CancellationException(
    message:
        reason == null ? 'Request cancelled' : 'Request cancelled: $reason',
    request: request,
    error: error ?? reason,
    stackTrace: stackTrace,
  );
}
