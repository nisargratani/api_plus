import 'package:meta/meta.dart';
import '../interfaces/cache_store.dart';
import '../models/http_method.dart';

/// Configuration for the cache interceptor.
///
/// Controls what is cached, how long entries are valid, and
/// provides hooks for encryption and custom key generation.
///
/// {@tool snippet}
/// ```dart
/// final config = CacheConfig(
///   store: MemoryCacheStore(maxEntries: 100),
///   defaultTtl: const Duration(minutes: 5),
///   enableStaleWhileRevalidate: true,
/// );
/// ```
/// {@end-tool}
@immutable
class CacheConfig {
  /// The store used to persist cache entries.
  final CacheStore store;

  /// Default time-to-live for cache entries.
  ///
  /// Used when the response does not contain `Cache-Control: max-age`
  /// or similar directives.
  final Duration defaultTtl;

  /// Maximum age for stale entries to be served during network failures.
  ///
  /// When a network request fails and a stale cache entry exists
  /// that is younger than [staleTtl], the stale entry is served.
  final Duration staleTtl;

  /// When `true`, always serves from cache if available, ignoring
  /// expiration and `Cache-Control` directives.
  final bool forceCache;

  /// When `true`, bypasses cache entirely and forces a network request.
  final bool bypassCache;

  /// Custom function for generating cache keys.
  ///
  /// Receives the HTTP method and full URL. When `null`, a default
  /// key based on method, path, and query parameters is used.
  final String Function(String method, String url)? keyBuilder;

  /// HTTP methods that are eligible for caching.
  ///
  /// Defaults to GET only. Add other methods if your API supports
  /// cacheable responses for them.
  final Set<HttpMethod> cacheableMethods;

  /// When `true`, enables the stale-while-revalidate pattern.
  ///
  /// Stale entries are served immediately while a background request
  /// refreshes the cache. The refreshed response is stored for
  /// subsequent requests.
  final bool enableStaleWhileRevalidate;

  /// Whether to collect cache metrics.
  ///
  /// When `true`, the cache interceptor tracks hit/miss rates,
  /// evictions, and other statistics accessible via
  /// `CacheInterceptor.metrics`.
  final bool enableMetrics;

  /// Creates a [CacheConfig].
  const CacheConfig({
    required this.store,
    this.defaultTtl = const Duration(days: 7),
    this.staleTtl = const Duration(days: 30),
    this.forceCache = false,
    this.bypassCache = false,
    this.keyBuilder,
    this.cacheableMethods = const {HttpMethod.get},
    this.enableStaleWhileRevalidate = false,
    this.enableMetrics = false,
  });
}
