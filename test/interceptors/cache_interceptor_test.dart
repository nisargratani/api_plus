import 'package:api_plus/api_plus.dart';
import 'package:test/test.dart';

void main() {
  group('CacheInterceptor', () {
    late MemoryCacheStore store;
    late CacheInterceptor interceptor;

    setUp(() {
      store = MemoryCacheStore(maxEntries: 50);
      interceptor = CacheInterceptor(
        config: CacheConfig(
          store: store,
          defaultTtl: const Duration(minutes: 5),
        ),
      );
    });

    group('onRequest', () {
      test('passes through non-GET requests', () async {
        const request = ApiRequest(path: '/users', method: HttpMethod.post);
        final result = await interceptor.onRequest(request);
        expect(result, isA<ApiRequest>());
      });

      test('passes through when bypassCache is true', () async {
        interceptor = CacheInterceptor(
          config: CacheConfig(store: store, bypassCache: true),
        );
        const request = ApiRequest(path: '/users');
        final result = await interceptor.onRequest(request);
        expect(result, isA<ApiRequest>());
      });

      test('returns cached response when available and fresh', () async {
        const cachedResponse = ApiResponse<String>(
          data: 'cached',
          statusCode: 200,
        );

        await store.put(
          'GET:/users',
          CacheEntry(
            response: cachedResponse,
            cachedAt: DateTime.now(),
            expiresAt: DateTime.now().add(const Duration(hours: 1)),
          ),
        );

        const request = ApiRequest(path: '/users');
        final result = await interceptor.onRequest(request);

        expect(result, isA<ApiResponse<dynamic>>());
        expect((result as ApiResponse<dynamic>).data, 'cached');
      });

      test('adds conditional headers for expired entries', () async {
        await store.put(
          'GET:/users',
          CacheEntry(
            response: const ApiResponse<String>(
              data: 'stale',
              statusCode: 200,
            ),
            cachedAt: DateTime.now().subtract(const Duration(hours: 2)),
            expiresAt: DateTime.now().subtract(const Duration(hours: 1)),
            eTag: '"abc123"',
            lastModified: 'Wed, 21 Oct 2015 07:28:00 GMT',
          ),
        );

        const request = ApiRequest(path: '/users');
        final result = await interceptor.onRequest(request);

        expect(result, isA<ApiRequest>());
        final modifiedRequest = result as ApiRequest;
        expect(modifiedRequest.headers['If-None-Match'], '"abc123"');
        expect(modifiedRequest.headers['If-Modified-Since'],
            'Wed, 21 Oct 2015 07:28:00 GMT');
      });

      test('returns cached response with forceCache even if expired', () async {
        interceptor = CacheInterceptor(
          config: CacheConfig(store: store, forceCache: true),
        );

        await store.put(
          'GET:/users',
          CacheEntry(
            response: const ApiResponse<String>(
              data: 'stale',
              statusCode: 200,
            ),
            cachedAt: DateTime.now().subtract(const Duration(hours: 2)),
            expiresAt: DateTime.now().subtract(const Duration(hours: 1)),
          ),
        );

        const request = ApiRequest(path: '/users');
        final result = await interceptor.onRequest(request);

        expect(result, isA<ApiResponse<dynamic>>());
        expect((result as ApiResponse<dynamic>).data, 'stale');
      });
    });

    group('onResponse', () {
      test('caches successful GET responses', () async {
        const request = ApiRequest(path: '/users');
        const response = ApiResponse<String>(
          data: 'users data',
          statusCode: 200,
          request: request,
        );

        await interceptor.onResponse(response);

        final cached = await store.get('GET:/users');
        expect(cached, isNotNull);
        expect(cached!.response.data, 'users data');
      });

      test('does not cache non-GET responses', () async {
        const request = ApiRequest(path: '/users', method: HttpMethod.post);
        const response = ApiResponse<String>(
          data: 'created',
          statusCode: 201,
          request: request,
        );

        await interceptor.onResponse(response);

        expect(await store.size, 0);
      });

      test('does not cache responses with no-store', () async {
        const request = ApiRequest(path: '/users');
        const response = ApiResponse<String>(
          data: 'private',
          statusCode: 200,
          headers: {
            'cache-control': ['no-store'],
          },
          request: request,
        );

        await interceptor.onResponse(response);

        expect(await store.size, 0);
      });

      test('respects max-age from Cache-Control', () async {
        const request = ApiRequest(path: '/users');
        const response = ApiResponse<String>(
          data: 'data',
          statusCode: 200,
          headers: {
            'cache-control': ['max-age=60'],
          },
          request: request,
        );

        await interceptor.onResponse(response);

        final cached = await store.get('GET:/users');
        expect(cached, isNotNull);
        // Should expire in roughly 60 seconds
        final expiresIn = cached!.expiresAt!.difference(DateTime.now());
        expect(expiresIn.inSeconds, closeTo(60, 2));
      });

      test('stores ETag and Last-Modified', () async {
        const request = ApiRequest(path: '/users');
        const response = ApiResponse<String>(
          data: 'data',
          statusCode: 200,
          headers: {
            'etag': ['"abc123"'],
            'last-modified': ['Wed, 21 Oct 2015 07:28:00 GMT'],
          },
          request: request,
        );

        await interceptor.onResponse(response);

        final cached = await store.get('GET:/users');
        expect(cached!.eTag, '"abc123"');
        expect(cached.lastModified, 'Wed, 21 Oct 2015 07:28:00 GMT');
      });

      test('handles 304 Not Modified by returning cached response', () async {
        // Pre-populate cache
        await store.put(
          'GET:/users',
          CacheEntry(
            response: const ApiResponse<String>(
              data: 'original',
              statusCode: 200,
            ),
            cachedAt: DateTime.now(),
          ),
        );

        const request = ApiRequest(path: '/users');
        const response = ApiResponse<void>(
          statusCode: 304,
          request: request,
        );

        final result = await interceptor.onResponse(response);
        expect(result.data, 'original');
      });

      test('does not cache error responses', () async {
        const request = ApiRequest(path: '/users');
        const response = ApiResponse<String>(
          data: 'error',
          statusCode: 500,
          request: request,
        );

        await interceptor.onResponse(response);

        expect(await store.size, 0);
      });
    });

    group('onError', () {
      test('serves stale cache during network failure', () async {
        await store.put(
          'GET:/users',
          CacheEntry(
            response: const ApiResponse<String>(
              data: 'cached',
              statusCode: 200,
            ),
            cachedAt: DateTime.now().subtract(const Duration(hours: 1)),
          ),
        );

        const request = ApiRequest(path: '/users');
        const error =
            NetworkException(message: 'No internet', request: request);

        final result = await interceptor.onError(error, (_) async {
          throw StateError('unreachable');
        });

        expect(result, isA<ApiResponse<dynamic>>());
        expect((result as ApiResponse<dynamic>).data, 'cached');
      });

      test('does not serve stale cache for non-GET', () async {
        await store.put(
          'POST:/users',
          CacheEntry(
            response: const ApiResponse<String>(
              data: 'cached',
              statusCode: 200,
            ),
            cachedAt: DateTime.now(),
          ),
        );

        const request = ApiRequest(path: '/users', method: HttpMethod.post);
        const error =
            NetworkException(message: 'No internet', request: request);

        final result = await interceptor.onError(error, (_) async {
          throw StateError('unreachable');
        });

        expect(result, isA<ApiException>());
      });

      test('does not serve expired stale cache', () async {
        interceptor = CacheInterceptor(
          config: CacheConfig(
            store: store,
            staleTtl: const Duration(hours: 1),
          ),
        );

        await store.put(
          'GET:/users',
          CacheEntry(
            response: const ApiResponse<String>(
              data: 'very old',
              statusCode: 200,
            ),
            cachedAt: DateTime.now().subtract(const Duration(hours: 2)),
          ),
        );

        const request = ApiRequest(path: '/users');
        const error =
            NetworkException(message: 'No internet', request: request);

        final result = await interceptor.onError(error, (_) async {
          throw StateError('unreachable');
        });

        expect(result, isA<ApiException>());
      });

      test('passes through non-NetworkException errors', () async {
        const request = ApiRequest(path: '/users');
        const error = ServerException(
          message: 'Server error',
          request: request,
          response: ApiResponse<void>(statusCode: 500, request: request),
        );

        final result = await interceptor.onError(error, (_) async {
          throw StateError('unreachable');
        });

        expect(result, isA<ApiException>());
      });
    });

    group('metrics', () {
      test('tracks hits when enabled', () async {
        interceptor = CacheInterceptor(
          config: CacheConfig(
            store: store,
            enableMetrics: true,
          ),
        );

        await store.put(
          'GET:/users',
          CacheEntry(
            response: const ApiResponse<String>(
              data: 'cached',
              statusCode: 200,
            ),
            cachedAt: DateTime.now(),
            expiresAt: DateTime.now().add(const Duration(hours: 1)),
          ),
        );

        await interceptor.onRequest(const ApiRequest(path: '/users'));

        expect(interceptor.metrics.hits, 1);
      });

      test('tracks misses when enabled', () async {
        interceptor = CacheInterceptor(
          config: CacheConfig(
            store: store,
            enableMetrics: true,
          ),
        );

        await interceptor.onRequest(const ApiRequest(path: '/not-cached'));

        expect(interceptor.metrics.misses, 1);
      });
    });

    group('custom key builder', () {
      test('uses custom key builder', () async {
        interceptor = CacheInterceptor(
          config: CacheConfig(
            store: store,
            keyBuilder: (method, url) => 'custom:$url',
          ),
        );

        const request = ApiRequest(path: '/users');
        const response = ApiResponse<String>(
          data: 'data',
          statusCode: 200,
          request: request,
        );

        await interceptor.onResponse(response);

        final cached = await store.get('custom:/users');
        expect(cached, isNotNull);
      });
    });
  });
}
