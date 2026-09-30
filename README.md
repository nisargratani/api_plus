# api_plus

[![Dart CI](https://github.com/nisargratani/api_plus/actions/workflows/dart.yml/badge.svg)](https://github.com/nisargratani/api_plus/actions/workflows/dart.yml)
[![pub package](https://img.shields.io/pub/v/api_plus.svg)](https://pub.dev/packages/api_plus)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)

An adapter-based Dart networking package. Retry, HTTP caching, and logging are
implemented once as interceptors, and work the same over **Dio**, **http**,
and **Retrofit** clients.

## Features

| Feature | Description |
|---------|-------------|
| **Retry** | Exponential/linear/fixed backoff, jitter, `Retry-After`, custom strategies, connectivity-aware retries, metrics |
| **Logging** | Pretty/compact/JSON formats, colors, curl commands, execution time, masking of sensitive headers and body fields, custom printers |
| **HTTP cache** | In-memory LRU store, `Cache-Control`/`ETag`/`Last-Modified`, stale-while-revalidate, offline fallback, metrics |
| **Adapters** | `HttpAdapter`, `DioAdapter`, and a `RetrofitAdapter` bridge share one interceptor pipeline |
| **Typed errors** | An exception type for each common HTTP status (400–504), plus network, timeout, cancellation, and serialization errors |
| **Builder** | Fluent `ApiBuilder` for configuring a client |

## Installation

```yaml
dependencies:
  api_plus: ^0.0.3
```

Requires Dart 3.4+ (Flutter 3.22+). Pure Dart — no platform channels.

## Quick start

```dart
import 'package:api_plus/api_plus.dart';

Future<void> main() async {
  final api = ApiBuilder('https://jsonplaceholder.typicode.com')
      .clientType(ApiClientType.dio) // or ApiClientType.http (default)
      .addHeader('Accept', 'application/json')
      .withRetry(const RetryConfig(maxRetries: 3))
      .withCache(CacheConfig(
        store: MemoryCacheStore(maxEntries: 100),
        defaultTtl: const Duration(minutes: 5),
      ))
      .withLogger(const LoggerConfig(level: LogLevel.info))
      .withReceiveTimeout(const Duration(seconds: 15))
      .build();

  try {
    final response = await api.request<Map<String, dynamic>>(
      const ApiRequest(path: '/posts/1'),
    );
    print('Title: ${response.data!['title']}');
  } on NotFoundException catch (e) {
    print('Not found: ${e.message}');
  } on NetworkException catch (e) {
    print('Network error: ${e.message}');
  } on ApiException catch (e) {
    print('API error: ${e.message}');
  } finally {
    api.close();
  }
}
```

In Flutter, create the adapter once (for example in a repository or in
`initState`) and call `close()` when you no longer need it (for example in
`dispose`).

## Making requests

```dart
// Query parameters are merged with any query string in the path.
// null values are omitted; lists produce repeated keys.
await api.request<List<dynamic>>(const ApiRequest(
  path: '/posts',
  queryParameters: {'userId': 1, 'tag': ['a', 'b']},
));

// Map/List bodies are sent as JSON.
await api.request<Map<String, dynamic>>(const ApiRequest(
  path: '/posts',
  method: HttpMethod.post,
  body: {'title': 'Hello', 'userId': 1},
));

// Absolute URLs bypass the base URL.
await api.request<dynamic>(const ApiRequest(path: 'https://other.example.com/x'));
```

**Typed responses.** `request<T>` checks that the decoded body is a `T`; if it
is not, it throws a `SerializationException`. Decoded JSON is made of
`Map<String, dynamic>` and `List<dynamic>`, so ask for those and convert:

```dart
final response = await api.request<List<dynamic>>(const ApiRequest(path: '/users'));
final users = response.data!
    .cast<Map<String, dynamic>>()
    .map(User.fromJson)
    .toList();
```

Requesting `List<Map<String, dynamic>>` directly throws, because the decoded
list is a `List<dynamic>`. Non-JSON responses (e.g. `text/plain`) are returned
as `String`.

**Timeouts.** Set defaults with `withConnectTimeout`, `withSendTimeout`, and
`withReceiveTimeout` (or the adapter constructors); `ApiRequest.connectTimeout`,
`sendTimeout`, and `receiveTimeout` override them per request. Both adapters
apply them the same way:

| Timeout | Limits | `TimeoutException.timeoutType` |
|---------|--------|--------------------------------|
| connect | opening the connection | `TimeoutType.connection` |
| send | uploading the request body | `TimeoutType.send` |
| receive | waiting for the response, and each gap between chunks of the body | `TimeoutType.receive` |

`null` or `Duration.zero` means no timeout. The receive timeout is an idle
timeout, so a large download that keeps receiving data does not time out.
A timeout aborts the request and throws `TimeoutException` (a
`NetworkException`, so it is retried by default). Browsers don't expose the
connect and upload phases, so on the web only the receive timeout applies.

### Cancellation

Pass an `ApiCancelToken` and call `cancel()` to abort requests. This covers
requests in flight, pending retry delays, and requests that haven't started
yet. Cancelled requests throw `CancellationException` and are never retried.
One token can be shared by many requests, which makes it easy to tie them to
a screen's lifetime:

```dart
class _FeedScreenState extends State<FeedScreen> {
  final _cancelToken = ApiCancelToken();

  Future<void> _load() async {
    try {
      final response = await api.request<List<dynamic>>(
        ApiRequest(path: '/feed', cancelToken: _cancelToken),
      );
      if (!mounted) return;
      // ...
    } on CancellationException {
      // The screen was closed; nothing to do.
    }
  }

  @override
  void dispose() {
    _cancelToken.cancel('FeedScreen disposed');
    super.dispose();
  }
}
```

A cancelled token stays cancelled; create a new one for new requests. With
`RetrofitAdapter`, use Dio's `CancelToken` (Retrofit's `@CancelRequest()`) as
usual; it also stops api_plus retry delays.

## How the pipeline works

Every adapter runs the same steps:

1. `onRequest` for each interceptor, in list order. An interceptor may return
   an `ApiResponse` to short-circuit (this is how cache hits work).
2. The network call.
3. `onResponse` for each interceptor, for **every** status code.
4. A non-2xx status becomes the matching `ServerException` subclass and goes
   through `onError` for each interceptor, in list order. So do transport
   failures (`NetworkException`, `TimeoutException`). An interceptor may
   return an `ApiResponse` to recover.

`ApiBuilder` installs interceptors in the order cache → retry → logger →
your interceptors (`addInterceptor`). Retries are re-sent through the whole
pipeline, so the logger and cache see every attempt.

Errors thrown by your own interceptors that are not `ApiException`s (for
example a `StateError` from a bug) are propagated unchanged and are not
retried.

### Custom interceptors

Extend `ApiInterceptor` and override only what you need:

```dart
class AuthInterceptor extends ApiInterceptor {
  AuthInterceptor(this.readToken);

  final String? Function() readToken;

  @override
  Future<dynamic> onRequest(ApiRequest request) async {
    final token = readToken();
    if (token == null) return request;
    return request.copyWith(
      headers: {...request.headers, 'Authorization': 'Bearer $token'},
    );
  }
}

final api = ApiBuilder(baseUrl).addInterceptor(AuthInterceptor(() => token)).build();
```

## Retry

```dart
const retryConfig = RetryConfig(
  maxRetries: 3,                       // 1 original attempt + up to 3 retries
  backoffStrategy: RetryBackoffStrategy.exponential,
  baseDelay: Duration(seconds: 1),
  maxDelay: Duration(seconds: 30),
  maxElapsedDuration: Duration(minutes: 1),
  addJitter: true,                     // ±20%
  respectRetryAfter: true,
  retryableStatusCodes: {408, 429, 500, 502, 503, 504},
  retryableMethods: {HttpMethod.get, HttpMethod.head, HttpMethod.put},
  onRetry: _logRetry,                  // called before each delay
);
```

By default only idempotent methods (GET, HEAD, OPTIONS, PUT, DELETE) are
retried, for the status codes above and for network errors and timeouts.

- `shouldRetryException` replaces the status-code and network-error checks.
- A `customStrategy` (`RetryStrategy`) replaces `maxRetries`, the method and
  elapsed-time checks, and the backoff calculation. Its `shouldRetry` must
  eventually return `false`.
- A `connectivityChecker` stops retrying while the device is offline.

## Caching

```dart
final cacheConfig = CacheConfig(
  store: MemoryCacheStore(maxEntries: 200),
  defaultTtl: const Duration(minutes: 10), // when there is no max-age
  staleTtl: const Duration(hours: 1),      // stale/offline fallback window
  enableStaleWhileRevalidate: true,
);
```

- Only successful responses to `cacheableMethods` (GET by default) are stored.
- `Cache-Control: max-age` sets the lifetime, `no-store` prevents storing, and
  `no-cache` stores the response but revalidates it before every use.
- Expired entries are revalidated with `If-None-Match` / `If-Modified-Since`;
  a `304 Not Modified` returns the cached data (status 200) and renews the entry.
- With `enableStaleWhileRevalidate`, an expired entry younger than `staleTtl`
  is returned immediately and refreshed in the background.
- If the network fails (`NetworkException`), an entry younger than `staleTtl`
  is served instead of the error.
- `forceCache` serves any cached entry regardless of age; `bypassCache` skips
  cache lookups.

**Cache keys** are built from the method, path, and query parameters, not
headers. If responses depend on the user (e.g. `Authorization`), clear the
store on logout (`await store.clear()`) or include the user in a custom
`keyBuilder`, which receives the method and the path with its sorted query
string:

```dart
CacheConfig(
  store: store,
  keyBuilder: (method, url) => '$currentUserId:$method:$url',
);
```

`MemoryCacheStore` keeps response objects in memory as-is. Don't mutate
`response.data` if the response may be cached. Implement `CacheStore` for
persistent caching (SQLite, Hive, files, ...).

## Logging

```dart
const loggerConfig = LoggerConfig(
  level: LogLevel.info,           // requests/responses at info, errors at error
  format: LogFormat.pretty,       // or .compact, .json
  colors: true,
  printCurl: true,
  maskedKeys: {'authorization', 'password', 'token', 'secret', 'set-cookie'},
  // printer: MyLogPrinter(),     // default: print()
  // requestFilter: (r) => r.path != '/health',
  // filterStatusCodes: {500, 503},
);
```

`maskedKeys` are matched case-insensitively against request and response
header names and against keys at any depth of map/JSON bodies, in every
format including the curl command. Values that cannot be JSON-encoded are
logged with `toString()` and never fail the request.

Pretty-printing and masking large bodies costs CPU on the calling isolate.
In production, prefer `LogLevel.error`, or set `printRequestBody` /
`printResponseBody` to `false`.

Sample output (`LogFormat.pretty`, colors off):

```
┌── Request ──────────────────────────────────────────────────
│ GET /users/1
├─ Headers:
│   Accept: application/json
│   Authorization: ***
└────────────────────────────────────────────────────────────
curl -X GET -H "Accept: application/json" -H "Authorization: ***" "/users/1"
┌── Response ─────────────────────────────────────────────────
│ Status: 200 OK
│ Duration: 142ms
├─ Body:
│   {
│     "id": 1,
│     "name": "John Doe"
│   }
└────────────────────────────────────────────────────────────
```

## Error handling

```dart
try {
  await api.request<Map<String, dynamic>>(const ApiRequest(path: '/users/1'));
} on UnauthorizedException {
  // 401
} on NotFoundException {
  // 404
} on TooManyRequestsException catch (e) {
  // 429
  print('Retry after: ${e.response?.headers['retry-after']}');
} on ServerException catch (e) {
  // any other non-2xx status
  print('Status: ${e.response?.statusCode}, body: ${e.response?.data}');
} on TimeoutException catch (e) {
  print('Timeout type: ${e.timeoutType}');
} on CancellationException {
  // cancelled with an ApiCancelToken
} on NetworkException {
  // DNS, socket, TLS, connection errors
} on SerializationException {
  // body could not be encoded, or response data is not the requested type
} on ApiException {
  // anything else from api_plus
}
```

`TimeoutException` has the same name as `dart:async`'s. If a file imports
both, hide one: `import 'dart:async' hide TimeoutException;`.

## Using with Retrofit

```dart
final adapter = RetrofitAdapter(
  baseUrl: 'https://api.example.com',
  retryConfig: const RetryConfig(maxRetries: 3),
  loggerConfig: const LoggerConfig(level: LogLevel.info),
  cacheConfig: CacheConfig(store: MemoryCacheStore()),
);

// Pass the pre-configured Dio to your Retrofit-generated class.
final apiClient = MyRetrofitClient(adapter.client);

// Later:
adapter.close();
```

Retrofit code keeps receiving Dio types (`Response`, `DioException`); the
api_plus interceptors run inside Dio's interceptor chain.

## Metrics

Metrics live on the interceptor instance. Create the interceptor yourself to
keep a reference:

```dart
final retry = RetryInterceptor(config: const RetryConfig(enableMetrics: true));
final cache = CacheInterceptor(
  config: CacheConfig(store: MemoryCacheStore(), enableMetrics: true),
);
final api = ApiBuilder(baseUrl).addInterceptor(cache).addInterceptor(retry).build();

print(retry.metrics);  // RetryMetrics(total: 3, success: 1, failed: 0, ...)
print(cache.metrics.hitRate);
```

Interceptors created by `withRetry`/`withCache` can be found with
`api.interceptors.whereType<RetryInterceptor>().first`.

## Extensibility

| Interface | Purpose |
|-----------|---------|
| `ApiAdapter` | Support another HTTP client |
| `ApiInterceptor` | Custom request/response/error handling |
| `CacheStore` | Custom cache backend |
| `RetryStrategy` | Custom retry decisions and delays |
| `ConnectivityChecker` | Skip retries while offline (e.g. with `connectivity_plus`) |
| `LogPrinter` | Custom log destination |

## Platform support

Works on every Dart platform: Android, iOS, web, macOS, Windows, Linux, and
server-side Dart. `HttpAdapter` uses `package:http` (browser `fetch`/XHR on the
web), and `DioAdapter` uses Dio's platform adapters.

Flutter apps still need network access at the OS level:

- **macOS:** add `com.apple.security.network.client` = `true` to
  `macos/Runner/DebugProfile.entitlements` and `Release.entitlements`.
  Without it every request fails with a `NetworkException`.
- **Android:** release builds need
  `<uses-permission android:name="android.permission.INTERNET"/>` in
  `android/app/src/main/AndroidManifest.xml`. Plain `http://` URLs also need a
  cleartext-traffic exception.
- **Web:** the server must send CORS headers.

## Limitations

- `HttpAdapter` returns non-JSON bodies as a `String` (binary bodies are
  decoded leniently); for file downloads use a Dio client with
  `ResponseType.bytes`.
- `CacheMetrics.evictions` is recorded automatically for `MemoryCacheStore`
  only; custom stores call `metrics.recordEviction()` themselves.

## Upgrading from 0.0.2

For `0.0.x` versions, a caret constraint only allows patch-identical
releases (`^0.0.2` means `>=0.0.2 <0.0.3`), so update your constraint to
`^0.0.3`.

0.0.3 fixes several behaviors; most apps need no code changes. See the
[CHANGELOG](CHANGELOG.md) for the full list. In particular:

- The minimum SDK is Dart 3.4 (this was already required by `http ^1.6.0`).
- `request<Map<String, dynamic>>` and other typed calls now work; before,
  they threw a `TypeError`.
- With `HttpAdapter`, non-2xx responses now go through `onError`, so they are
  retried and can be served from stale cache.
- `HttpAdapter` returns non-JSON content types (e.g. `text/plain`) as a
  `String` instead of attempting to JSON-decode them.
- Non-`ApiException` errors thrown by your interceptors are no longer wrapped
  in `NetworkException` (and are no longer retried).
- `RetryConfig.onRetry` is called before the retry delay, as documented.

## Contributing

Contributions are welcome! See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

MIT — see [LICENSE](LICENSE).
