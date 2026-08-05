import 'package:api_plus/api_plus.dart';
import 'package:test/test.dart';

void main() {
  group('CacheConfig', () {
    test('has sensible defaults', () {
      final config = CacheConfig(store: MemoryCacheStore());
      expect(config.defaultTtl, const Duration(days: 7));
      expect(config.staleTtl, const Duration(days: 30));
      expect(config.forceCache, isFalse);
      expect(config.bypassCache, isFalse);
      expect(config.keyBuilder, isNull);
      expect(config.cacheableMethods, {HttpMethod.get});
      expect(config.enableStaleWhileRevalidate, isFalse);
      expect(config.enableMetrics, isFalse);
    });

    test('accepts custom ttl values', () {
      final config = CacheConfig(
        store: MemoryCacheStore(),
        defaultTtl: const Duration(minutes: 5),
        staleTtl: const Duration(hours: 1),
      );
      expect(config.defaultTtl, const Duration(minutes: 5));
      expect(config.staleTtl, const Duration(hours: 1));
    });

    test('accepts custom cache key builder', () {
      final config = CacheConfig(
        store: MemoryCacheStore(),
        keyBuilder: (method, url) => '$method-$url',
      );
      expect(config.keyBuilder, isNotNull);
      expect(config.keyBuilder!('GET', '/users'), 'GET-/users');
    });

    test('accepts multiple cacheable methods', () {
      final config = CacheConfig(
        store: MemoryCacheStore(),
        cacheableMethods: const {HttpMethod.get, HttpMethod.head},
      );
      expect(config.cacheableMethods, contains(HttpMethod.get));
      expect(config.cacheableMethods, contains(HttpMethod.head));
      expect(config.cacheableMethods, isNot(contains(HttpMethod.post)));
    });
  });
}
