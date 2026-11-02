/// Keys that `api_plus` stores in [ApiRequest.extra] to coordinate
/// interceptors and adapters.
///
/// This file is intentionally not exported from the package.
library;

import '../exceptions/api_exception.dart';
import 'api_request.dart';
import 'api_response.dart';

/// Set on the request attached to a stale cached response that should be
/// refreshed in the background (stale-while-revalidate).
const String revalidateExtraKey = '_apiPlusRevalidate';

/// Set on the background request that refreshes a stale cache entry, so the
/// cache interceptor does not short-circuit it with the stale entry again.
const String revalidatingExtraKey = '_apiPlusRevalidating';

/// Set on requests re-sent by a `RetryInterceptor`, so that nested pipeline
/// runs do not start their own retry loop.
const String retryAttemptExtraKey = '_apiPlusRetryAttempt';

/// Set by the cache interceptor on a conditional request that revalidates an
/// expired entry, so the outcome (304 or new content) is counted once in
/// `CacheMetrics`.
const String cacheRevalidationExtraKey = '_apiPlusCacheRevalidation';

/// Set by the adapters to their base URL, so the logger can print a curl
/// command with the full URL.
const String baseUrlExtraKey = '_apiPlusBaseUrl';

/// A list of `void Function(ApiException)` callbacks (added by
/// `LoggerInterceptor.onRequest`) that a `RetryInterceptor` calls with the
/// first attempt's error before it retries. Interceptors placed after the
/// retry interceptor would otherwise never see that error: their `onError`
/// only runs once the retry loop has finished.
const String errorObserversExtraKey = '_apiPlusErrorObservers';

/// Returns [request] with [observer] added to its error observers.
ApiRequest withErrorObserver(
  ApiRequest request,
  void Function(ApiException error) observer,
) {
  final existing = request.extra[errorObserversExtraKey];
  final observers = existing is List<void Function(ApiException)>
      ? existing
      : const <void Function(ApiException)>[];
  if (observers.contains(observer)) return request;
  return withExtras(request, {
    errorObserversExtraKey: List<void Function(ApiException)>.unmodifiable(
      [...observers, observer],
    ),
  });
}

/// Calls the error observers of [error]'s request (see
/// [errorObserversExtraKey]).
void notifyErrorObservers(ApiException error) {
  final observers = error.request?.extra[errorObserversExtraKey];
  if (observers is! List<void Function(ApiException)>) return;
  for (final observer in observers) {
    observer(error);
  }
}

/// Responses whose `null` data stands for an empty body that the client
/// returned as `''` (Dio). Retrofit callers get `''` back.
final Expando<bool> _emptyBodies = Expando<bool>('apiPlusEmptyBody');

/// Marks [response] as having an empty body (see [isEmptyBody]).
void markEmptyBody(ApiResponse<dynamic> response) {
  _emptyBodies[response] = true;
}

/// Whether [response] was marked with [markEmptyBody].
bool isEmptyBody(ApiResponse<dynamic> response) =>
    _emptyBodies[response] ?? false;

/// A copy of [response] that reports [request] as the request that produced
/// it (e.g. a cached response served for a new request).
ApiResponse<T> withRequest<T>(ApiResponse<T> response, ApiRequest request) {
  final copy = response.copyWith(request: request);
  if (isEmptyBody(response)) markEmptyBody(copy);
  return copy;
}

/// Errors that a `RetryInterceptor` has finished with: it will not retry
/// them (again). See [markRetryFinished].
final Expando<bool> _retryFinished = Expando<bool>('apiPlusRetryFinished');

/// Marks [error] as final: the retry interceptor has stopped retrying
/// (retries exhausted, not retryable, offline, out of time, ...).
///
/// The cache interceptor only serves a stale entry for a failed retry
/// attempt once the error is final, so retries happen before the stale
/// fallback.
void markRetryFinished(ApiException error) {
  _retryFinished[error] = true;
}

/// Whether [error] was marked with [markRetryFinished].
bool isRetryFinished(ApiException error) => _retryFinished[error] ?? false;

/// Whether [request] was re-sent by a `RetryInterceptor`.
bool isRetryAttempt(ApiRequest? request) =>
    request?.extra[retryAttemptExtraKey] == true;

/// The [ServerException] subclass for a non-2xx [response] to [request],
/// with the message format shared by every adapter.
ServerException serverExceptionFor(
  ApiRequest request,
  ApiResponse<dynamic> response, {
  Object? error,
  StackTrace? stackTrace,
}) {
  final reason = response.statusMessage;
  return ServerException.fromResponse(
    message: 'Server returned ${response.statusCode}'
        '${reason != null ? ': $reason' : ''}',
    request: request,
    response: response,
    error: error,
    stackTrace: stackTrace,
  );
}

/// Returns a copy of [request] whose [ApiRequest.extra] does not contain
/// [key].
ApiRequest withoutExtra(ApiRequest request, String key) {
  if (!request.extra.containsKey(key)) return request;
  return request.copyWith(
    extra: Map<String, dynamic>.of(request.extra)..remove(key),
  );
}

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
    ..remove(cacheRevalidationExtraKey)
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
