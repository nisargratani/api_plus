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
  skipped the error interceptors, so 5xx/429 responses were never retried and
  never served from stale cache.
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
