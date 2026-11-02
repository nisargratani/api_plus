## 0.0.4

A bug-fix release based on an external QA report (issues API_PLUS-01 to
API_PLUS-19, plus the report's other observations). The changes make the code
do what the README and API docs already describe; no public API is removed,
renamed, or changed (two small additions are listed under "New"). Most apps
need no code changes; see "Behavior changes" below. Note that `^0.0.3` does not allow
`0.0.4`; update your constraint to `^0.0.4`.

### Bug fixes

- **Logger: tokens in camelCase were logged in plain text** (API_PLUS-01).
  `maskedKeys` are now compared after normalisation (lower-cased, without
  `_`, `-` and whitespace), so `access_token` also masks `accessToken`,
  `access-token` and `ACCESS_TOKEN`. `id_token` was added to the defaults.
- **`Retry-After` could exceed `maxDelay` and `maxElapsedDuration`**
  (API_PLUS-02). A `Retry-After: 3600` made a request wait an hour per retry.
  Now no wait exceeds `maxDelay` or ends after `maxElapsedDuration`: the
  request is not retried and the 429/503 is returned immediately.
- **`DioAdapter`: typed requests to empty (204) responses threw**
  (API_PLUS-03). An empty body is now `null`, as with `HttpAdapter`, so
  `request<Map<String, dynamic>>` works for a `DELETE` that returns 204.
- **`DioAdapter`/`RetrofitAdapter`: malformed JSON and invalid URLs were
  retryable `NetworkException`s** (API_PLUS-04). A malformed body is now a
  `SerializationException` and an invalid URL a `ConfigurationException`;
  neither is retried, and no request is sent for an invalid URL.
- **Interceptor errors during a retry were wrapped and retried**
  (API_PLUS-05). Non-`ApiException` errors (e.g. a `StateError`) thrown by an
  interceptor while a request is retried are now propagated unchanged and
  not retried, as documented (also with `RetrofitAdapter`).
- **`RetrofitAdapter` rethrew the first attempt's error** (API_PLUS-06).
  After retries, the `DioException` now carries the last attempt's status
  and body.
- **`RetrofitAdapter` skipped `onResponse` for error statuses**
  (API_PLUS-07). Interceptors now see every response, as with the other
  adapters.
- **`HttpAdapter.close()` aborted in-flight requests** (API_PLUS-08).
  `close()` now lets them finish and closes the client afterwards;
  `close(force: true)` aborts them.
- **Cache entries could be shared by different URLs** (API_PLUS-09). The
  default key used `Map.toString()`, so `{q: 'a', r: 'b'}` and
  `{q: 'a, r: b'}` collided and the second request got the first one's
  data.
- **`no-cache` responses were served without revalidation** when
  `enableStaleWhileRevalidate` was on (API_PLUS-10). They (and
  `must-revalidate` responses) are now revalidated before use. A `304`
  without its own `Cache-Control`/`Expires` now keeps the stored response's
  rules instead of renewing the entry for `defaultTtl`.
- **The `Expires` header was ignored** (API_PLUS-11). Responses with an
  expired `Expires` (e.g. `Thu, 01 Jan 1970 00:00:00 GMT`) were cached for
  `defaultTtl` (7 days). `Expires` now sets the lifetime when there is no
  `max-age`; invalid values such as `0` or `-1` mean "already expired".
  `max-age` still wins. `CacheEntry.isExpired` is now true at `expiresAt`, so
  zero-lifetime entries are always expired.
- **With cache + retry, a network error served stale data instead of
  retrying** (API_PLUS-12). The stale entry is now served only after the
  retry interceptor gives up; offline fallback still works.
- **Query parameters were never masked in logs** (API_PLUS-13). `api_key`,
  `access_token`, etc. in `queryParameters` or in a query string in the path
  are now masked in every format and in the curl command.
- **A failing `CacheStore` failed every request** (API_PLUS-14). A store
  read error is now treated as a miss and a write error is skipped; the
  request goes to the network.
- **A long-lived `ApiCancelToken` kept every request made with it in
  memory** (API_PLUS-15), including request bodies, until it was cancelled.
  Completed requests are now released. `HttpAdapter` also no longer keeps
  the last request alive through its idle connection.
- **`CacheKeyGenerator` did not produce the cache interceptor's keys**
  (API_PLUS-16). The interceptor now uses it, so one entry can be
  invalidated with `store.delete(CacheKeyGenerator.generate(...))`.
- **`CacheMetrics` counted a `304` revalidation twice** (API_PLUS-17), as a
  miss and a hit. A revalidation now counts once: a hit on 304, a miss on new
  content. Retry attempts and background refreshes are not counted again.
- **`HttpDateParser` accepted impossible dates** (API_PLUS-18) such as
  `31 Feb` or `25:61:61`, rolling them over. They now return `null`.
- **`HttpAdapter` sent a malformed absolute URL to the base URL**
  (API_PLUS-19), e.g. `http://[::1/users` became
  `<base>/http://%5B::1/users`. It now throws `ConfigurationException`
  without sending anything.

### Other fixes

These were noted in the same QA report:

- **Logger with retries:** the first attempt's error was never logged and the
  last one was logged twice. Each attempt's error is now logged once, in
  order (`RetryInterceptor` lets the logger see the first error before it
  retries).
- **Curl commands** used the relative path, so they could not be pasted;
  they now use the full URL. With `LogFormat.json`, the curl command was a
  separate non-JSON line; it is now the `curl` field of the request record.
- **Cached responses** reported the request that filled the cache (old
  headers, extras, and cancel token) as `response.request`; they now report
  the current request. Stale-while-revalidate responses no longer expose the
  internal `_apiPlusRevalidate` extra.
- **`InterceptorPipeline`** was documented for custom adapters but not
  exported; it is now part of the public API.
- **`ApiRequest.copyWith` / `ApiResponse.copyWith` could not clear nullable
  fields.** `copyWith` is unchanged (`null` keeps the value); the new
  `copyWithout` removes fields, e.g. `request.copyWithout(body: true)`.
- **Docs:** `RetryLimitExceededException` and `CacheException` are now
  documented as not thrown by api_plus (they were described as "thrown
  when…"), and the 0.0.3 entry below no longer claims that 5xx/429
  responses are served from stale cache (only network failures are).

### New

- `InterceptorPipeline` is exported, for custom `ApiAdapter`s.
- `ApiRequest.copyWithout` and `ApiResponse.copyWithout`.

### Behavior changes

- **Built-in interceptor order** is now retry → cache → logger → custom in
  `ApiBuilder` and `RetrofitAdapter` (was cache → retry → logger → custom),
  so retries run before the stale-cache fallback. If you build interceptor
  lists yourself, put `RetryInterceptor` before `CacheInterceptor`.
- **`DioAdapter`/`RetrofitAdapter`:** malformed JSON responses throw
  `SerializationException` and invalid URLs `ConfigurationException`
  (previously retryable `NetworkException`s). `ApiResponse.data` is `null`
  for an empty body (was `''`); Retrofit callers still receive what Dio
  returns.
- **`RetrofitAdapter`** rejects with the last attempt's `DioException` after
  retries, and runs `onResponse` interceptors for error statuses.
- **`close()`:** `HttpAdapter.close()` waits for in-flight requests (use
  `close(force: true)` to abort them). On `HttpAdapter` and `DioAdapter`,
  requests and retries started after `close()` fail with a
  `ConfigurationException` (not retried) instead of a retried
  `NetworkException`.
- **Retry-After:** requests are no longer retried when `Retry-After` asks
  for more than `maxDelay`, or for a wait that would end after
  `maxElapsedDuration`.
- **Caching:** `Expires` is honored; `no-cache` and `must-revalidate`
  entries are never served by stale-while-revalidate; a 304 without
  freshness headers keeps the stored rules.
- **Cache keys changed format.** Default keys now come from
  `CacheKeyGenerator.generate` (sorted JSON query parameters, `null` values
  ignored). Entries a persistent custom store wrote with 0.0.3 are missed
  once and fetched again. `CacheConfig.keyBuilder` is unchanged.
- **Logging masks more:** normalised key matching (camelCase, kebab-case,
  upper case), `id_token` in the defaults, and query parameters.
- **Logging output:** curl commands use the full URL; with `LogFormat.json`
  the curl command is a `curl` field instead of a separate line; with
  retries, each attempt's error is logged exactly once.
- **Cached responses** report the current request as `response.request`.
- **`CacheMetrics`:** revalidations, retry attempts and background
  refreshes are each counted once, so `totalRequests` matches the number of
  requests.

### Tests

- `test/qa_0_0_4_test.dart`: one regression test per issue (named after its
  ID), plus tests for the other fixes, against a real local server. The
  cancel-token test checks with forced garbage collection that completed
  requests are released.

## 0.0.3

This release fixes several bugs that affected real applications and adds
request cancellation. Most apps need no code changes; see "Behavior changes"
below. Note that `^0.0.2` does not allow `0.0.3`; update your constraint to
`^0.0.3`.

### Bug fixes

- **Typed requests work.** `request<Map<String, dynamic>>` (and any `T` other
  than `dynamic`) threw a `TypeError` on every adapter, after sending extra
  retry requests. Responses are now converted to `ApiResponse<T>`; data of
  the wrong type throws a `SerializationException` with a clear message.
- **`HttpAdapter`: HTTP error statuses reach `onError`.** Non-2xx responses
  skipped the error interceptors, so 5xx/429 responses were never retried.
  (The stale-cache fallback applies to network failures only.)
- **`DioAdapter`/`RetrofitAdapter`: ETag revalidation works.** A `304 Not
  Modified` was thrown as a `ServerException` instead of serving the cached
  data.
- **Builder timeouts are applied.** `withConnectTimeout`, `withReceiveTimeout`,
  and `withSendTimeout` were stored but ignored. `HttpAdapter` also ignored
  the per-request timeouts of `ApiRequest`.
- **Stale-while-revalidate is implemented.** `enableStaleWhileRevalidate` was
  accepted but had no effect.
- **Retries run in a single loop.** Retries used to nest recursively, which
  logged the final error once per attempt and over-counted
  `RetryMetrics.successfulRetries`.
- **Retrofit retries.** Retries created a new `Dio` per attempt that was never
  closed, dropped timeouts and response settings, and stopped after the
  first failed retry. They now reuse the adapter's client.
- **Retrofit request changes.** Changes interceptors make to the path,
  method, query, body, timeouts, or removed headers now reach the request.
- **`HttpAdapter` URLs.** Absolute URLs in `ApiRequest.path` are supported,
  and query strings in the path are merged with `queryParameters` instead of
  being dropped.
- **`HttpAdapter` bodies.** JSON bodies are sent as `application/json`; they
  were previously sent as `text/plain` unless a `Content-Type` was given. Map
  bodies with `application/x-www-form-urlencoded` are sent as form fields. A
  body that cannot be JSON-encoded throws `SerializationException`, and is no
  longer retried as a `NetworkException`.
- **`HttpAdapter` responses** respect the response charset and no longer fail
  on invalid UTF-8.
- **Logger masking.** `maskedKeys` now masks body fields (at any depth,
  including JSON strings) and response headers, as documented. Before, only
  request headers were masked, and passwords in bodies were logged in
  plain text. Keys are matched case-insensitively on both sides.
- The default `LoggerConfig.maskedKeys` also mask `proxy-authorization`,
  `cookie`, `set-cookie`, `x-api-key`, `api_key`, `access_token`,
  `refresh_token`, and `client_secret`.
- **The logger never fails a request.** Bodies that are not JSON-encodable
  used to throw in JSON and curl output.
- The logger printed error durations as `0:00:00.123000ms`, and
  `requestFilter` did not apply to errors.
- `RetryConfig.calculateDelay` overflowed to `0` for large attempt numbers,
  and allowed negative custom delays.
- `ApiRequest.hashCode` differed for equal requests with headers.
- `CacheInterceptor` threw on very large `max-age` values, cached `no-cache`
  responses without revalidation, did not renew entries after a `304`, and
  did not count a miss when revalidating.
- `CacheConfig.keyBuilder` now receives the query string, so requests that
  differ only by query parameters no longer share a cache entry.
- `DioAdapter` omits `null` query parameters, like `HttpAdapter`.
- `MemoryCacheStore` threw for `maxEntries <= 0`.
- `CacheKeyGenerator.generate` threw for query values that are not
  JSON-encodable.

### New

- **Request cancellation:** `ApiCancelToken` and `ApiRequest.cancelToken`.
  Cancelling aborts in-flight requests on every adapter, interrupts pending
  retry delays, and throws `CancellationException`, which is never retried.
  One token can cancel many requests. With `RetrofitAdapter`, Dio's
  `CancelToken` now also interrupts api_plus retry delays.
- `HttpAdapter` and `DioAdapter` accept `connectTimeout`, `receiveTimeout`,
  and `sendTimeout`.
- **Accurate `HttpAdapter` timeouts:** connect, send, and receive timeouts
  now apply to the matching phase of the request, like Dio. The receive
  timeout is an idle timeout between response chunks. Requests are aborted
  when a timeout fires.
- `MemoryCacheStore.evictionCount`, and `CacheMetrics.evictions` now counts
  `MemoryCacheStore` LRU evictions.
- `onResponse` interceptors now see error responses on every adapter (they
  already did with `HttpAdapter`).

### Behavior changes

- The minimum SDK is now Dart 3.4. `http ^1.6.0` already required it, so the
  previous `>=3.1.0` constraint could not be satisfied on older SDKs.
- Non-`ApiException` errors thrown by interceptors are propagated unchanged.
  They are no longer wrapped in `NetworkException` and retried.
- `HttpAdapter` returns non-JSON content types (e.g. `text/plain`) as
  `String` instead of attempting to JSON-decode them, matching Dio.
- `RetryConfig.onRetry` is called before the delay, as documented.
- `ServerException` messages are the same on every adapter:
  `Server returned <status>: <reason>`.

### Documentation and tooling

- README rewritten: pipeline semantics, typed responses, timeouts, cache keys
  and user-specific data, platform setup (macOS entitlements, Android
  permission), limitations, and migration notes.
- Adapter integration tests against a real local server, plus regression
  tests for the fixes above.
- CI tests on the real minimum SDK (3.4.0), checks the lowest dependency
  versions, and runs on `develop`.
- Removed unused dev dependencies (`mocktail`, `fake_async`).

## 0.0.2

- Fix log truncation for long console messages by chunking output
- Update dependencies (`dio`, `http`)
- Update dev dependencies (`lints`, `test`, `mocktail`, `fake_async`)

## 0.0.1

- Initial release
- **Retry System**: Configurable retry with exponential, linear, and fixed backoff strategies, random jitter, Retry-After header support, custom retry strategies, connectivity-aware retries, and retry metrics
- **Logging Framework**: Pretty, compact, and JSON log formats with colored console output, curl command generation, execution time tracking, sensitive data masking, custom log printers, and request/response filtering
- **HTTP Cache**: Memory cache with LRU eviction, Cache-Control/ETag/Last-Modified support, stale-while-revalidate, offline mode fallback, configurable TTL, custom cache stores, and cache metrics
- **Adapter Architecture**: Shared interceptor pipeline across http, dio, and retrofit clients
- **Error Handling**: 14+ typed exceptions covering all common HTTP status codes (400–504), network errors, timeouts, cancellations, serialization failures, and configuration errors
- **Builder Pattern**: Fluent API for configuring any networking client
- **Extensibility Interfaces**: `ApiAdapter`, `ApiInterceptor`, `CacheStore`, `RetryStrategy`, `ConnectivityChecker`, `LogPrinter`
- **Platform Support**: Dart VM, Flutter (Android, iOS, Web, Desktop), Server-side Dart
