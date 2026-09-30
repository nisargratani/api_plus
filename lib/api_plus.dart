/// An enterprise-grade, adapter-based Dart networking package with robust
/// retry, caching, and logging systems supporting Dio, Http, and Retrofit.
///
/// ## Quick Start
///
/// ```dart
/// import 'package:api_plus/api_plus.dart';
///
/// final api = ApiBuilder('https://api.example.com')
///     .clientType(ApiClientType.dio)
///     .withRetry(const RetryConfig(maxRetries: 3))
///     .withLogger(const LoggerConfig(level: LogLevel.verbose))
///     .withCache(CacheConfig(store: MemoryCacheStore()))
///     .build();
///
/// final response = await api.request<Map<String, dynamic>>(
///   const ApiRequest(path: '/users/1'),
/// );
/// ```
///
/// ## Architecture
///
/// The package follows an adapter-based architecture where the core
/// logic (retry, caching, logging) is shared across all HTTP clients:
///
/// - Use [ApiBuilder] for a fluent configuration experience
/// - Use [DioAdapter], [HttpAdapter], or [RetrofitAdapter] directly
/// - Implement [ApiAdapter] for custom HTTP clients
/// - Implement [CacheStore] for custom cache backends
library;

// Core
export 'src/core/api_cancel_token.dart';
export 'src/core/api_request.dart';
export 'src/core/api_response.dart';

// Exceptions
export 'src/exceptions/api_exception.dart';

// Interfaces
export 'src/interfaces/api_adapter.dart';
export 'src/interfaces/api_interceptor.dart';
export 'src/interfaces/cache_store.dart';
export 'src/interfaces/connectivity_checker.dart';
export 'src/interfaces/log_printer.dart';
export 'src/interfaces/retry_strategy.dart';

// Configuration
export 'src/config/cache_config.dart';
export 'src/config/logger_config.dart';
export 'src/config/retry_config.dart';

// Models
export 'src/models/cache_metrics.dart';
export 'src/models/http_method.dart';
export 'src/models/retry_metrics.dart';

// Builders
export 'src/builders/api_builder.dart';

// Adapters
export 'src/adapters/dio/dio_adapter.dart';
export 'src/adapters/http/http_adapter.dart';
export 'src/adapters/retrofit/retrofit_adapter.dart';

// Interceptors
export 'src/interceptors/cache_interceptor.dart';
export 'src/interceptors/logger_interceptor.dart';
export 'src/interceptors/retry_interceptor.dart';

// Cache Stores
export 'src/cache/memory_cache_store.dart';

// Extensions
export 'src/extensions/map_extensions.dart';

// Utilities
export 'src/utils/cache_key_generator.dart';
export 'src/utils/http_date_parser.dart';
