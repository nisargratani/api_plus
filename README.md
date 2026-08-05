# api_plus

[![Dart CI](https://github.com/nisargratani/api_plus/actions/workflows/dart.yml/badge.svg)](https://github.com/nisargratani/api_plus/actions/workflows/dart.yml)
[![pub package](https://img.shields.io/pub/v/api_plus.svg)](https://pub.dev/packages/api_plus)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)

An enterprise-grade, adapter-based Dart networking package with robust **retry**, **caching**, and **logging** systems supporting **Dio**, **Http**, and **Retrofit**.

## ✨ Features

| Feature | Description |
|---------|-------------|
| 🔄 **Retry System** | Exponential/linear/fixed backoff, jitter, Retry-After header support, custom strategies, connectivity-aware retries, retry metrics |
| 📝 **Logging Framework** | Pretty/compact/JSON formats, colored console, curl generation, execution time tracking, sensitive data masking, custom printers |
| 💾 **HTTP Cache** | Memory cache, Cache-Control/ETag/Last-Modified support, stale-while-revalidate, LRU eviction, offline mode, cache metrics |
| 🔌 **Adapter-Based** | Shared core logic across http, dio, and retrofit — zero code duplication |
| 🛡️ **Error Handling** | 14+ typed exceptions for every common HTTP error (400–504), network errors, timeouts, cancellations |
| 🏗️ **Builder Pattern** | Fluent, chainable API for configuring any networking client |
| 🎯 **Strongly Typed** | Full generic support, immutable models, const constructors |
| 📊 **Metrics** | Built-in retry and cache performance tracking |

## 📦 Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  api_plus: ^0.0.1
```

Then run:

```bash
dart pub get
```

## 🚀 Quick Start

```dart
import 'package:api_plus/api_plus.dart';

void main() async {
  // Build with fluent API
  final api = ApiBuilder('https://jsonplaceholder.typicode.com')
      .clientType(ApiClientType.dio)
      .addHeader('Accept', 'application/json')
      .withRetry(const RetryConfig(
        maxRetries: 3,
        backoffStrategy: RetryBackoffStrategy.exponential,
        addJitter: true,
      ))
      .withCache(CacheConfig(
        store: MemoryCacheStore(maxEntries: 100),
        defaultTtl: const Duration(minutes: 5),
      ))
      .withLogger(const LoggerConfig(
        level: LogLevel.verbose,
        format: LogFormat.pretty,
      ))
      .build();

  try {
    final response = await api.request<Map<String, dynamic>>(
      const ApiRequest(path: '/posts/1'),
    );
    print('Title: ${response.data}');
  } on NotFoundException catch (e) {
    print('Not found: ${e.message}');
  } on NetworkException catch (e) {
    print('Network error: ${e.message}');
  } on ApiException catch (e) {
    print('API error: ${e.message}');
  }

  api.close();
}
```

## 🏛️ Architecture

```
┌──────────────────────────────────────────────┐
│                  ApiBuilder                  │
│         (Fluent configuration API)           │
└──────────────┬───────────────────────────────┘
               │ builds
┌──────────────▼───────────────────────────────┐
│               ApiAdapter                     │
│   ┌───────────┬───────────┬───────────┐      │
│   │ HttpAdapter│DioAdapter│RetrofitAdapter│   │
│   └───────────┴───────────┴───────────┘      │
└──────────────┬───────────────────────────────┘
               │ uses
┌──────────────▼───────────────────────────────┐
│          InterceptorPipeline                 │
│   ┌──────────┬──────────┬──────────┐         │
│   │  Cache   │  Retry   │  Logger  │         │
│   └──────────┴──────────┴──────────┘         │
└──────────────────────────────────────────────┘
```

**Key principle:** All retry, cache, and logging logic lives in the shared interceptor pipeline. Adapters only translate between their native client types and the unified `ApiRequest`/`ApiResponse` types.

## 🔄 Retry System

```dart
const retryConfig = RetryConfig(
  maxRetries: 3,
  backoffStrategy: RetryBackoffStrategy.exponential,
  baseDelay: Duration(seconds: 1),
  maxDelay: Duration(seconds: 30),
  addJitter: true,
  respectRetryAfter: true,
  retryableStatusCodes: {408, 429, 500, 502, 503, 504},
  retryableMethods: {HttpMethod.get, HttpMethod.head, HttpMethod.put},
  enableMetrics: true,
  onRetry: (attempt, delay) {
    print('Retry attempt $attempt after ${delay.inSeconds}s');
  },
);
```

### Custom Retry Strategy

```dart
class CircuitBreakerStrategy implements RetryStrategy {
  int _failures = 0;

  @override
  bool shouldRetry(ApiException error, int attempt, ApiRequest request) {
    if (_failures > 5) return false; // Circuit open
    return attempt <= 3;
  }

  @override
  Duration getDelay(int attempt) => Duration(seconds: attempt * 2);
}
```

## 📝 Logging

```dart
const loggerConfig = LoggerConfig(
  level: LogLevel.verbose,
  format: LogFormat.pretty,       // or .compact, .json
  colors: true,
  printCurl: true,
  printExecutionTime: true,
  maskedKeys: {'authorization', 'password', 'api_key'},
  // Custom printer for file logging
  // printer: FileLogPrinter(logFile),
);
```

### Sample Pretty Output

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

## 💾 Caching

```dart
final cacheConfig = CacheConfig(
  store: MemoryCacheStore(maxEntries: 200),
  defaultTtl: const Duration(minutes: 10),
  staleTtl: const Duration(hours: 1),
  enableStaleWhileRevalidate: true,
  enableMetrics: true,
);
```

### Custom Cache Store

Implement `CacheStore` for any backend (SQLite, Hive, SharedPreferences, file):

```dart
class SqliteCacheStore implements CacheStore {
  @override
  Future<CacheEntry?> get(String key) async { /* ... */ }

  @override
  Future<void> put(String key, CacheEntry entry) async { /* ... */ }

  @override
  Future<void> delete(String key) async { /* ... */ }

  @override
  Future<void> clear() async { /* ... */ }

  @override
  Future<bool> containsKey(String key) async { /* ... */ }

  @override
  Future<int> get size async { /* ... */ }
}
```

## 🛡️ Error Handling

The package provides typed exceptions for every common HTTP error:

```dart
try {
  final response = await api.request<Map<String, dynamic>>(
    const ApiRequest(path: '/users/1'),
  );
} on UnauthorizedException catch (e) {
  // 401 — redirect to login
} on ForbiddenException catch (e) {
  // 403 — show permission denied
} on NotFoundException catch (e) {
  // 404 — show not found
} on TooManyRequestsException catch (e) {
  // 429 — rate limited
} on TimeoutException catch (e) {
  // Connection/send/receive timeout
  print('Timeout type: ${e.timeoutType}');
} on NetworkException catch (e) {
  // DNS, socket, connection errors
} on ServerException catch (e) {
  // Any 5xx error
  print('Status: ${e.response?.statusCode}');
} on ApiException catch (e) {
  // Catch-all for any API error
}
```

## 🔌 Using with Retrofit

```dart
// 1. Create a RetrofitAdapter with api_plus features
final adapter = RetrofitAdapter(
  baseUrl: 'https://api.example.com',
  retryConfig: const RetryConfig(maxRetries: 3),
  loggerConfig: const LoggerConfig(level: LogLevel.verbose),
  cacheConfig: CacheConfig(store: MemoryCacheStore()),
);

// 2. Pass the client to your Retrofit-generated class
final apiClient = MyRetrofitClient(adapter.client);
```

## 📊 Metrics

```dart
// Retry metrics
final retryInterceptor = RetryInterceptor(
  config: const RetryConfig(enableMetrics: true),
);
print(retryInterceptor.metrics.successRate);  // 85.0%
print(retryInterceptor.metrics.totalRetries); // 12

// Cache metrics
final cacheInterceptor = CacheInterceptor(
  config: CacheConfig(store: store, enableMetrics: true),
);
print(cacheInterceptor.metrics.hitRate);   // 72.5%
print(cacheInterceptor.metrics.hits);      // 145
print(cacheInterceptor.metrics.misses);    // 55
```

## 🔧 Extensibility

| Interface | Purpose |
|-----------|---------|
| `ApiAdapter` | Add support for new HTTP clients |
| `ApiInterceptor` | Create custom interceptors |
| `CacheStore` | Implement custom cache backends |
| `RetryStrategy` | Define custom retry logic |
| `ConnectivityChecker` | Network-aware retries |
| `LogPrinter` | Custom log output destinations |

## 📋 Platform Support

| Platform | Supported |
|----------|-----------|
| Dart VM | ✅ |
| Flutter Android | ✅ |
| Flutter iOS | ✅ |
| Flutter Web | ✅ |
| Flutter Desktop | ✅ |
| Server-side Dart | ✅ |

## 🤝 Contributing

Contributions are welcome! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## 📄 License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.
