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
