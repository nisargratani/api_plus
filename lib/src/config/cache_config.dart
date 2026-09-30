import 'package:meta/meta.dart';
import '../exceptions/api_exception.dart';
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

  /// Maximum age for stale entries to be served during network failures
  /// or by stale-while-revalidate.
  ///
  /// When a network request fails with a [NetworkException] and a cache
  /// entry exists that is younger than [staleTtl] (measured from when it
  /// was cached or last revalidated), that entry is served instead.
  final Duration staleTtl;

  /// When `true`, always serves from cache if available, ignoring
  /// expiration and `Cache-Control` directives.
  final bool forceCache;

  /// When `true`, bypasses cache entirely and forces a network request.
  final bool bypassCache;

  /// Custom function for generating cache keys.
  ///
  /// Receives the HTTP method and the request path including its query
  /// parameters (sorted by name), e.g. `/users?page=2`. When `null`, a
  /// default key based on method, path, and query parameters is used.
  ///
  /// Request headers are not part of the default key. If responses depend
  /// on the caller (e.g. the `Authorization` header), include that in your
  /// key or clear the store when the user changes.
  final String Function(String method, String url)? keyBuilder;

  /// HTTP methods that are eligible for caching.
  ///
  /// Defaults to GET only. Add other methods if your API supports
  /// cacheable responses for them.
  final Set<HttpMethod> cacheableMethods;

  /// When `true`, enables the stale-while-revalidate pattern.
  ///
  /// Expired entries younger than [staleTtl] are served immediately while
  /// the adapter refreshes them with a background request (using
  /// `If-None-Match`/`If-Modified-Since` when available). The refreshed
  /// response is stored for subsequent requests. A failed refresh leaves
  /// the stale entry in place.
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
