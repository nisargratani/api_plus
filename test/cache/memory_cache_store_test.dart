import 'package:api_plus/api_plus.dart';
import 'package:test/test.dart';

void main() {
  group('MemoryCacheStore', () {
    late MemoryCacheStore store;

    setUp(() {
      store = MemoryCacheStore(maxEntries: 3);
    });

    test('initially empty', () async {
      expect(await store.size, 0);
      expect(await store.get('key'), isNull);
    });

    test('put and get entry', () async {
      final entry = CacheEntry(
        response: const ApiResponse<String>(
          data: 'test',
          statusCode: 200,
        ),
        cachedAt: DateTime.now(),
      );

      await store.put('key1', entry);
      final result = await store.get('key1');

      expect(result, isNotNull);
      expect(result!.response.data, 'test');
      expect(await store.size, 1);
    });

    test('containsKey returns true for existing key', () async {
      final entry = CacheEntry(
        response: const ApiResponse<void>(statusCode: 200),
        cachedAt: DateTime.now(),
      );

      await store.put('key1', entry);
      expect(await store.containsKey('key1'), isTrue);
      expect(await store.containsKey('key2'), isFalse);
    });

    test('delete removes entry', () async {
      final entry = CacheEntry(
        response: const ApiResponse<void>(statusCode: 200),
        cachedAt: DateTime.now(),
      );

      await store.put('key1', entry);
      expect(await store.size, 1);

      await store.delete('key1');
      expect(await store.size, 0);
      expect(await store.get('key1'), isNull);
    });

    test('delete non-existent key does nothing', () async {
      await store.delete('nonexistent');
      expect(await store.size, 0);
    });

    test('clear removes all entries', () async {
      final entry = CacheEntry(
        response: const ApiResponse<void>(statusCode: 200),
        cachedAt: DateTime.now(),
      );

      await store.put('key1', entry);
      await store.put('key2', entry);
      await store.put('key3', entry);
      expect(await store.size, 3);

      await store.clear();
      expect(await store.size, 0);
    });

    test('evicts oldest entry when exceeding maxEntries', () async {
      final entry1 = CacheEntry(
        response: const ApiResponse<String>(data: 'first', statusCode: 200),
        cachedAt: DateTime.now(),
      );
      final entry2 = CacheEntry(
        response: const ApiResponse<String>(data: 'second', statusCode: 200),
        cachedAt: DateTime.now(),
      );
      final entry3 = CacheEntry(
        response: const ApiResponse<String>(data: 'third', statusCode: 200),
        cachedAt: DateTime.now(),
      );
      final entry4 = CacheEntry(
        response: const ApiResponse<String>(data: 'fourth', statusCode: 200),
        cachedAt: DateTime.now(),
      );

      await store.put('key1', entry1);
      await store.put('key2', entry2);
      await store.put('key3', entry3);
      expect(await store.size, 3);

      // Adding a 4th should evict key1 (oldest)
      await store.put('key4', entry4);
      expect(await store.size, 3);
      expect(await store.get('key1'), isNull);
      expect(await store.get('key2'), isNotNull);
      expect(await store.get('key3'), isNotNull);
      expect(await store.get('key4'), isNotNull);
    });

    test('get moves entry to most recently used', () async {
      final entry1 = CacheEntry(
        response: const ApiResponse<String>(data: 'first', statusCode: 200),
        cachedAt: DateTime.now(),
      );
      final entry2 = CacheEntry(
        response: const ApiResponse<String>(data: 'second', statusCode: 200),
        cachedAt: DateTime.now(),
      );
      final entry3 = CacheEntry(
        response: const ApiResponse<String>(data: 'third', statusCode: 200),
        cachedAt: DateTime.now(),
      );

      await store.put('key1', entry1);
      await store.put('key2', entry2);
      await store.put('key3', entry3);

      // Access key1 to make it most recently used
      await store.get('key1');

      // Add key4 — should evict key2 (now the oldest)
      final entry4 = CacheEntry(
        response: const ApiResponse<String>(data: 'fourth', statusCode: 200),
        cachedAt: DateTime.now(),
      );
      await store.put('key4', entry4);

      expect(await store.get('key1'), isNotNull); // Still present
      expect(await store.get('key2'), isNull); // Evicted
      expect(await store.get('key3'), isNotNull);
      expect(await store.get('key4'), isNotNull);
    });

    test('put replaces existing entry', () async {
      final entry1 = CacheEntry(
        response: const ApiResponse<String>(data: 'original', statusCode: 200),
        cachedAt: DateTime.now(),
      );
      final entry2 = CacheEntry(
        response: const ApiResponse<String>(data: 'updated', statusCode: 200),
        cachedAt: DateTime.now(),
      );

      await store.put('key1', entry1);
      await store.put('key1', entry2);

      expect(await store.size, 1);
      final result = await store.get('key1');
      expect(result!.response.data, 'updated');
    });
  });

  group('CacheEntry', () {
    test('isExpired returns false when expiresAt is null', () {
      final entry = CacheEntry(
        response: const ApiResponse<void>(statusCode: 200),
        cachedAt: DateTime.now(),
      );
      expect(entry.isExpired, isFalse);
    });

    test('isExpired returns false when not yet expired', () {
      final entry = CacheEntry(
        response: const ApiResponse<void>(statusCode: 200),
        cachedAt: DateTime.now(),
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      );
      expect(entry.isExpired, isFalse);
    });

    test('isExpired returns true when past expiresAt', () {
      final entry = CacheEntry(
        response: const ApiResponse<void>(statusCode: 200),
        cachedAt: DateTime.now().subtract(const Duration(hours: 2)),
        expiresAt: DateTime.now().subtract(const Duration(hours: 1)),
      );
      expect(entry.isExpired, isTrue);
    });

    test('age returns duration since cachedAt', () {
      final cachedAt = DateTime.now().subtract(const Duration(minutes: 5));
      final entry = CacheEntry(
        response: const ApiResponse<void>(statusCode: 200),
        cachedAt: cachedAt,
      );
      expect(entry.age.inMinutes, greaterThanOrEqualTo(4));
      expect(entry.age.inMinutes, lessThanOrEqualTo(6));
    });

    test('stores eTag and lastModified', () {
      final entry = CacheEntry(
        response: const ApiResponse<void>(statusCode: 200),
        cachedAt: DateTime.now(),
        eTag: '"abc123"',
        lastModified: 'Wed, 21 Oct 2015 07:28:00 GMT',
      );
      expect(entry.eTag, '"abc123"');
      expect(entry.lastModified, 'Wed, 21 Oct 2015 07:28:00 GMT');
    });
  });
}
