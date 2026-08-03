import 'dart:collection';
import '../interfaces/cache_store.dart';

/// A simple in-memory cache store with LRU eviction.
class MemoryCacheStore implements CacheStore {
  final int maxEntries;
  final LinkedHashMap<String, CacheEntry> _cache = LinkedHashMap();

  /// Creates a [MemoryCacheStore] with a maximum number of entries.
  MemoryCacheStore({this.maxEntries = 100});

  @override
  Future<CacheEntry?> get(String key) async {
    final entry = _cache[key];
    if (entry != null) {
      // LRU logic: move to end
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

    if (_cache.length > maxEntries) {
      // Remove oldest (first) entry
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
}
