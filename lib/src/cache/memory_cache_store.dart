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
  final int maxEntries;

  final LinkedHashMap<String, CacheEntry> _cache =
      LinkedHashMap<String, CacheEntry>();

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
    while (_cache.length > maxEntries) {
      _cache.remove(_cache.keys.first);
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
