import '../cache/memory_cache_store.dart';
import '../interfaces/cache_store.dart';

/// Tracks cache performance metrics for monitoring and tuning.
///
/// Provides insight into cache hit/miss rates, eviction counts,
/// and overall cache utilization.
///
/// {@tool snippet}
/// ```dart
/// final metrics = cacheInterceptor.metrics;
/// print('Hit rate: ${metrics.hitRate}%');
/// print('Total requests: ${metrics.totalRequests}');
/// ```
/// {@end-tool}
class CacheMetrics {
  int _hits = 0;
  int _misses = 0;
  int _evictions = 0;
  int _staleHits = 0;

  /// Number of cache hits (requests served from cache).
  int get hits => _hits;

  /// Number of cache misses (requests that required a network call).
  int get misses => _misses;

  /// Number of cache evictions due to size limits or invalidation.
  ///
  /// Evictions by [MemoryCacheStore] (least-recently-used entries dropped
  /// because the store is full) are recorded automatically. For a custom
  /// [CacheStore], call [recordEviction] yourself.
  int get evictions => _evictions;

  /// Number of stale cache entries served during network failures.
  ///
  /// Entries served by stale-while-revalidate count as [hits].
  int get staleHits => _staleHits;

  /// Total number of requests processed by the cache interceptor.
  int get totalRequests => _hits + _misses;

  /// Cache hit rate as a percentage (0.0 to 100.0).
  ///
  /// Returns 0.0 if no requests have been processed.
  double get hitRate {
    if (totalRequests == 0) return 0.0;
    return (_hits / totalRequests) * 100.0;
  }

  /// Records a cache hit.
  void recordHit() => _hits++;

  /// Records a cache miss.
  void recordMiss() => _misses++;

  /// Records a cache eviction.
  void recordEviction() => _evictions++;

  /// Records a stale cache hit (served during offline/error).
  void recordStaleHit() => _staleHits++;

  /// Resets all metrics to zero.
  void reset() {
    _hits = 0;
    _misses = 0;
    _evictions = 0;
    _staleHits = 0;
  }

  @override
  String toString() => 'CacheMetrics(hits: $_hits, misses: $_misses, '
      'evictions: $_evictions, staleHits: $_staleHits, '
      'hitRate: ${hitRate.toStringAsFixed(1)}%)';
}
