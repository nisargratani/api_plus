import 'dart:collection';
import '../interfaces/cache_store.dart';

/// An in-memory cache store with LRU (Least Recently Used) eviction.
///
/// Entries are evicted when the number of entries exceeds [maxEntries].
/// The least recently accessed entry is evicted first.
///
/// This is the default cache store and is suitable for most use cases.
/// For persistent caching, implement [CacheStore] with SQLite, Hive,
/// SharedPreferences, or file storage.
///
/// {@tool snippet}
/// ```dart
/// final store = MemoryCacheStore(maxEntries: 100);
/// ```
/// {@end-tool}
class MemoryCacheStore implements CacheStore {
  /// The maximum number of entries to store before evicting.
  ///
  /// A value of `0` or less disables storage (every entry is evicted
  /// immediately).
  final int maxEntries;

  final LinkedHashMap<String, CacheEntry> _cache =
      LinkedHashMap<String, CacheEntry>();

  int _evictionCount = 0;

  /// Total number of entries evicted because the store was full.
  ///
  /// `CacheInterceptor` reports these in `CacheMetrics.evictions`.
  int get evictionCount => _evictionCount;

  /// Creates a [MemoryCacheStore] with a maximum number of [maxEntries].
  MemoryCacheStore({this.maxEntries = 100});

  @override
  Future<CacheEntry?> get(String key) async {
    final entry = _cache[key];
    if (entry != null) {
      // LRU: move to end (most recently used)
      _cache.remove(key);
      _cache[key] = entry;
      return entry;
    }
    return null;
  }

  @override
  Future<void> put(String key, CacheEntry entry) async {
    if (_cache.containsKey(key)) {
      _cache.remove(key);
    }
    _cache[key] = entry;

    // Evict oldest entries if over capacity
    while (_cache.length > maxEntries && _cache.isNotEmpty) {
      _cache.remove(_cache.keys.first);
      _evictionCount++;
    }
  }

  @override
  Future<void> delete(String key) async {
    _cache.remove(key);
  }

  @override
  Future<void> clear() async {
    _cache.clear();
  }

  @override
  Future<bool> containsKey(String key) async {
    return _cache.containsKey(key);
  }

  @override
  Future<int> get size async => _cache.length;
}
