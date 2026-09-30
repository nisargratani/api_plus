import '../adapters/dio/dio_adapter.dart';
import '../adapters/http/http_adapter.dart';
import '../config/cache_config.dart';
import '../config/logger_config.dart';
import '../config/retry_config.dart';
import '../core/api_request.dart';
import '../interfaces/api_adapter.dart';
import '../interfaces/api_interceptor.dart';
import '../interceptors/cache_interceptor.dart';
import '../interceptors/logger_interceptor.dart';
import '../interceptors/retry_interceptor.dart';

/// Defines the underlying HTTP client type for the [ApiBuilder].
enum ApiClientType {
  /// Uses the `http` package as the underlying client.
  http,

  /// Uses the `dio` package as the underlying client.
  dio,
}

/// A fluent builder for creating and configuring an [ApiAdapter].
///
/// Provides a clean, chainable API for configuring the networking
/// client with retry, caching, logging, and custom interceptors.
///
/// {@tool snippet}
/// ```dart
/// final api = ApiBuilder('https://api.example.com')
///     .clientType(ApiClientType.dio)
///     .addHeader('Accept', 'application/json')
///     .addHeader('Authorization', 'Bearer $token')
///     .withRetry(const RetryConfig(
///       maxRetries: 3,
///       backoffStrategy: RetryBackoffStrategy.exponential,
///     ))
///     .withCache(CacheConfig(
///       store: MemoryCacheStore(maxEntries: 100),
///       defaultTtl: const Duration(minutes: 5),
///     ))
///     .withLogger(const LoggerConfig(
///       level: LogLevel.verbose,
///       format: LogFormat.pretty,
///     ))
///     .build();
/// ```
/// {@end-tool}
class ApiBuilder {
  final String _baseUrl;
  ApiClientType _clientType = ApiClientType.http;
  final Map<String, String> _defaultHeaders = {};
  final List<ApiInterceptor> _customInterceptors = [];

  RetryConfig? _retryConfig;
  CacheConfig? _cacheConfig;
  LoggerConfig? _loggerConfig;

  Duration? _connectTimeout;
  Duration? _receiveTimeout;
  Duration? _sendTimeout;

  /// Starts building an [ApiAdapter] with the given [baseUrl].
  ///
  /// The [baseUrl] is the base URL that all relative request paths
  /// are resolved against.
  ApiBuilder(this._baseUrl);

  /// Sets the underlying HTTP client type.
  ///
  /// Defaults to [ApiClientType.http].
  ApiBuilder clientType(ApiClientType type) {
    _clientType = type;
    return this;
  }

  /// Adds a default header to all requests.
  ///
  /// Headers set here are merged with request-level headers,
  /// with request-level headers taking precedence.
  ApiBuilder addHeader(String key, String value) {
    _defaultHeaders[key] = value;
    return this;
  }

  /// Sets multiple default headers at once.
  ///
  /// Merges with any previously set headers.
  ApiBuilder withHeaders(Map<String, String> headers) {
    _defaultHeaders.addAll(headers);
    return this;
  }

  /// Configures retry behavior.
  ///
  /// See [RetryConfig] for available options.
  ApiBuilder withRetry(RetryConfig config) {
    _retryConfig = config;
    return this;
  }

  /// Configures caching behavior.
  ///
  /// See [CacheConfig] for available options.
  ApiBuilder withCache(CacheConfig config) {
    _cacheConfig = config;
    return this;
  }

  /// Configures logging behavior.
  ///
  /// See [LoggerConfig] for available options.
  ApiBuilder withLogger(LoggerConfig config) {
    _loggerConfig = config;
    return this;
  }

  /// Sets the default connection timeout of the built adapter.
  ///
  /// [ApiRequest.connectTimeout] overrides it for a single request.
  ApiBuilder withConnectTimeout(Duration timeout) {
    _connectTimeout = timeout;
    return this;
  }

  /// Sets the default receive timeout of the built adapter.
  ///
  /// [ApiRequest.receiveTimeout] overrides it for a single request.
  ApiBuilder withReceiveTimeout(Duration timeout) {
    _receiveTimeout = timeout;
    return this;
  }

  /// Sets the default send timeout of the built adapter.
  ///
  /// [ApiRequest.sendTimeout] overrides it for a single request.
  ApiBuilder withSendTimeout(Duration timeout) {
    _sendTimeout = timeout;
    return this;
  }

  /// Adds a custom interceptor to the pipeline.
  ///
  /// Custom interceptors are executed after the built-in interceptors
  /// (cache, retry, logger).
  ApiBuilder addInterceptor(ApiInterceptor interceptor) {
    _customInterceptors.add(interceptor);
    return this;
  }

  /// Builds the configured [ApiAdapter].
  ///
  /// The interceptor execution order is:
  /// 1. Cache (short-circuits if hit)
  /// 2. Retry (handles retrying on failure)
  /// 3. Logger (logs requests/responses)
  /// 4. Custom interceptors (in order added)
  ApiAdapter build() {
    final interceptors = <ApiInterceptor>[];

    if (_cacheConfig != null) {
      interceptors.add(CacheInterceptor(config: _cacheConfig!));
    }

    if (_retryConfig != null) {
      interceptors.add(RetryInterceptor(config: _retryConfig!));
    }

    if (_loggerConfig != null) {
      interceptors.add(LoggerInterceptor(config: _loggerConfig!));
    }

    interceptors.addAll(_customInterceptors);

    final headers = Map<String, String>.from(_defaultHeaders);

    switch (_clientType) {
      case ApiClientType.http:
        return HttpAdapter(
          baseUrl: _baseUrl,
          defaultHeaders: headers,
          interceptors: interceptors,
          connectTimeout: _connectTimeout,
          receiveTimeout: _receiveTimeout,
          sendTimeout: _sendTimeout,
        );
      case ApiClientType.dio:
        return DioAdapter(
          baseUrl: _baseUrl,
          defaultHeaders: headers,
          interceptors: interceptors,
          connectTimeout: _connectTimeout,
          receiveTimeout: _receiveTimeout,
          sendTimeout: _sendTimeout,
        );
    }
  }

  /// The configured connection timeout, if any.
  Duration? get connectTimeout => _connectTimeout;

  /// The configured receive timeout, if any.
  Duration? get receiveTimeout => _receiveTimeout;

  /// The configured send timeout, if any.
  Duration? get sendTimeout => _sendTimeout;
}
