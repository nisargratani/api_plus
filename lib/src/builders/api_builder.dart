import '../adapters/dio/dio_adapter.dart';
import '../adapters/http/http_adapter.dart';
import '../config/cache_config.dart';
import '../config/logger_config.dart';
import '../config/retry_config.dart';
import '../interfaces/api_adapter.dart';
import '../interfaces/api_interceptor.dart';
import '../interceptors/cache_interceptor.dart';
import '../interceptors/logger_interceptor.dart';
import '../interceptors/retry_interceptor.dart';

/// Defines the underlying client type for the ApiBuilder.
enum ApiClientType {
  /// Uses the `http` package.
  http,
  /// Uses the `dio` package.
  dio,
}

/// A fluent builder for creating and configuring an [ApiAdapter].
class ApiBuilder {
  final String _baseUrl;
  ApiClientType _clientType = ApiClientType.http;
  final Map<String, String> _defaultHeaders = {};
  final List<ApiInterceptor> _customInterceptors = [];
  
  RetryConfig? _retryConfig;
  CacheConfig? _cacheConfig;
  LoggerConfig? _loggerConfig;

  /// Starts building an [ApiAdapter] with the given [baseUrl].
  ApiBuilder(this._baseUrl);

  /// Sets the underlying HTTP client type.
  ApiBuilder clientType(ApiClientType type) {
    _clientType = type;
    return this;
  }

  /// Adds a default header to all requests.
  ApiBuilder addHeader(String key, String value) {
    _defaultHeaders[key] = value;
    return this;
  }

  /// Configures retry behavior.
  ApiBuilder withRetry(RetryConfig config) {
    _retryConfig = config;
    return this;
  }

  /// Configures caching behavior.
  ApiBuilder withCache(CacheConfig config) {
    _cacheConfig = config;
    return this;
  }

  /// Configures logging behavior.
  ApiBuilder withLogger(LoggerConfig config) {
    _loggerConfig = config;
    return this;
  }

  /// Adds a custom interceptor.
  ApiBuilder addInterceptor(ApiInterceptor interceptor) {
    _customInterceptors.add(interceptor);
    return this;
  }

  /// Builds the configured [ApiAdapter].
  ApiAdapter build() {
    final interceptors = <ApiInterceptor>[];

    // Order matters: 
    // 1. Cache (short-circuits network if hit)
    // 2. Retry (handles retrying network if failed)
    // 3. Logger (logs the network requests/responses)
    // 4. Custom Interceptors

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

    switch (_clientType) {
      case ApiClientType.http:
        return HttpAdapter(
          baseUrl: _baseUrl,
          defaultHeaders: _defaultHeaders,
          interceptors: interceptors,
        );
      case ApiClientType.dio:
        return DioAdapter(
          baseUrl: _baseUrl,
          defaultHeaders: _defaultHeaders,
          interceptors: interceptors,
        );
    }
  }
}
