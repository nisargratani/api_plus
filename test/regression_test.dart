import 'package:api_plus/api_plus.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

class _LinesPrinter implements LogPrinter {
  final List<String> lines = [];

  @override
  void log(String message) => lines.add(message);
}

void main() {
  group('RetryConfig.calculateDelay', () {
    test('caps very large attempts at maxDelay instead of overflowing', () {
      const config = RetryConfig(addJitter: false);
      expect(config.calculateDelay(64), config.maxDelay);
      expect(config.calculateDelay(2000), config.maxDelay);
    });

    test('clamps negative custom strategy delays to zero', () {
      final config = RetryConfig(customStrategy: _NegativeDelayStrategy());
      expect(config.calculateDelay(1), Duration.zero);
    });
  });

  group('ApiRequest', () {
    test('equal requests have equal hash codes', () {
      const a = ApiRequest(path: '/x', headers: {'a': '1', 'b': '2'});
      const b = ApiRequest(path: '/x', headers: {'b': '2', 'a': '1'});
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect({a, b}, hasLength(1));
    });
  });

  group('RetryInterceptor', () {
    test('retries in a loop until maxRetries is exhausted', () async {
      final interceptor = RetryInterceptor(
        config: const RetryConfig(
          maxRetries: 3,
          baseDelay: Duration.zero,
          addJitter: false,
          enableMetrics: true,
        ),
      );
      const request = ApiRequest(path: '/x');
      var calls = 0;

      final result = await interceptor.onError(
        const NetworkException(message: 'down', request: request),
        (req) async {
          calls++;
          throw NetworkException(message: 'still down', request: req);
        },
      );

      expect(result, isA<NetworkException>());
      expect(calls, 3);
      expect(interceptor.metrics.totalRetries, 3);
      expect(interceptor.metrics.failedRetries, 1);
      expect(interceptor.metrics.successfulRetries, 0);
    });

    test('invokes onRetry before waiting', () async {
      final events = <String>[];
      final interceptor = RetryInterceptor(
        config: RetryConfig(
          maxRetries: 1,
          baseDelay: const Duration(milliseconds: 20),
          addJitter: false,
          onRetry: (count, delay) => events.add('onRetry $count $delay'),
        ),
      );
      const request = ApiRequest(path: '/x');

      await interceptor.onError(
        const NetworkException(message: 'down', request: request),
        (req) async {
          events.add('invoke');
          return const ApiResponse<void>(statusCode: 200);
        },
      );

      expect(events, [
        'onRetry 1 ${const Duration(milliseconds: 20)}',
        'invoke',
      ]);
    });

    test('stops retrying when the connectivity checker reports offline',
        () async {
      final interceptor = RetryInterceptor(
        config: RetryConfig(
          baseDelay: Duration.zero,
          connectivityChecker: _Offline(),
        ),
      );
      const error = NetworkException(
        message: 'down',
        request: ApiRequest(path: '/x'),
      );

      final result = await interceptor.onError(error, (_) async {
        throw StateError('should not be called');
      });
      expect(result, same(error));
    });

    test('honours numeric Retry-After headers', () async {
      Duration? observed;
      final interceptor = RetryInterceptor(
        config: RetryConfig(
          maxRetries: 1,
          baseDelay: Duration.zero,
          addJitter: false,
          onRetry: (_, delay) => observed = delay,
        ),
      );
      const request = ApiRequest(path: '/x');
      const response = ApiResponse<void>(
        statusCode: 429,
        headers: {
          'retry-after': ['1'],
        },
      );

      await interceptor.onError(
        const TooManyRequestsException(
          message: 'slow down',
          request: request,
          response: response,
        ),
        (_) async => const ApiResponse<void>(statusCode: 200),
      );
      expect(observed, const Duration(seconds: 1));
    });
  });

  group('CacheInterceptor', () {
    test('stores no-cache responses as immediately stale', () async {
      final store = MemoryCacheStore();
      final interceptor = CacheInterceptor(config: CacheConfig(store: store));
      const request = ApiRequest(path: '/x');

      await interceptor.onResponse(const ApiResponse<String>(
        data: 'v',
        statusCode: 200,
        request: request,
        headers: {
          'cache-control': ['no-cache'],
        },
      ));

      final entry = await store.get('GET:/x');
      expect(entry, isNotNull);
      expect(entry!.isExpired, isTrue);
    });

    test('does not throw on max-age values larger than an int', () async {
      final store = MemoryCacheStore();
      final interceptor = CacheInterceptor(config: CacheConfig(store: store));

      await interceptor.onResponse(const ApiResponse<String>(
        data: 'v',
        statusCode: 200,
        request: ApiRequest(path: '/x'),
        headers: {
          'cache-control': ['public, max-age=99999999999999999999999'],
        },
      ));

      final entry = await store.get('GET:/x');
      expect(entry!.isExpired, isFalse);
    });

    test('passes the query string to keyBuilder', () async {
      final keys = <String>[];
      final interceptor = CacheInterceptor(
        config: CacheConfig(
          store: MemoryCacheStore(),
          keyBuilder: (method, url) {
            keys.add('$method $url');
            return '$method $url';
          },
        ),
      );

      await interceptor.onRequest(const ApiRequest(
        path: '/users',
        queryParameters: {'page': 2, 'filter': 'a b'},
      ));
      expect(keys.single, 'GET /users?filter=a+b&page=2');
    });

    test('records a miss when adding conditional headers', () async {
      final store = MemoryCacheStore();
      await store.put(
        'GET:/x',
        CacheEntry(
          response: const ApiResponse<String>(data: 'v', statusCode: 200),
          cachedAt: DateTime.now().subtract(const Duration(hours: 1)),
          expiresAt: DateTime.now().subtract(const Duration(minutes: 1)),
          eTag: '"1"',
        ),
      );
      final interceptor = CacheInterceptor(
        config: CacheConfig(store: store, enableMetrics: true),
      );

      await interceptor.onRequest(const ApiRequest(path: '/x'));
      expect(interceptor.metrics.misses, 1);
    });

    test('serves the cached entry for a 304 reported as an error', () async {
      final store = MemoryCacheStore();
      await store.put(
        'GET:/x',
        CacheEntry(
          response: const ApiResponse<String>(data: 'cached', statusCode: 200),
          cachedAt: DateTime.now().subtract(const Duration(hours: 1)),
          expiresAt: DateTime.now().subtract(const Duration(minutes: 1)),
          eTag: '"1"',
        ),
      );
      final interceptor = CacheInterceptor(config: CacheConfig(store: store));
      const request = ApiRequest(path: '/x');

      final result = await interceptor.onError(
        const ServerException(
          message: 'Not modified',
          request: request,
          response: ApiResponse<void>(statusCode: 304, request: request),
        ),
        (_) async => throw StateError('unused'),
      );

      expect((result as ApiResponse<dynamic>).data, 'cached');
      final renewed = await store.get('GET:/x');
      expect(renewed!.age, lessThan(const Duration(minutes: 1)));
    });

    test('stale-while-revalidate serves expired entries within staleTtl',
        () async {
      final store = MemoryCacheStore();
      await store.put(
        'GET:/x',
        CacheEntry(
          response: const ApiResponse<String>(data: 'stale', statusCode: 200),
          cachedAt: DateTime.now().subtract(const Duration(hours: 1)),
          expiresAt: DateTime.now().subtract(const Duration(minutes: 1)),
        ),
      );
      final interceptor = CacheInterceptor(
        config: CacheConfig(store: store, enableStaleWhileRevalidate: true),
      );

      final result = await interceptor.onRequest(const ApiRequest(path: '/x'));
      expect(result, isA<ApiResponse<dynamic>>());
      expect((result as ApiResponse<dynamic>).data, 'stale');
    });
  });

  group('LoggerInterceptor', () {
    late _LinesPrinter printer;

    LoggerInterceptor logger({
      LogFormat format = LogFormat.json,
      Set<String> maskedKeys = const {'password', 'Authorization'},
      bool Function(ApiRequest)? requestFilter,
    }) {
      printer = _LinesPrinter();
      return LoggerInterceptor(
        config: LoggerConfig(
          format: format,
          colors: false,
          maskedKeys: maskedKeys,
          printer: printer,
          requestFilter: requestFilter,
        ),
      );
    }

    test('masks nested body keys and mixed-case configured keys', () async {
      await logger().onRequest(const ApiRequest(
        path: '/login',
        method: HttpMethod.post,
        headers: {'authorization': 'Bearer secret'},
        body: {
          'user': {'name': 'a', 'Password': 'hunter2'},
          'items': [
            {'password': 'x'},
          ],
        },
      ));

      final output = printer.lines.join('\n');
      expect(output, isNot(contains('hunter2')));
      expect(output, isNot(contains('Bearer secret')));
      expect(output, isNot(contains('"x"')));
      expect(output, contains('"name":"a"'));
    });

    test('masks JSON string bodies and response headers', () async {
      final interceptor = logger(
        format: LogFormat.pretty,
        maskedKeys: {'password', 'set-cookie'},
      );
      await interceptor.onRequest(const ApiRequest(
        path: '/login',
        method: HttpMethod.post,
        body: '{"password":"hunter2"}',
      ));
      await interceptor.onResponse(const ApiResponse<String>(
        statusCode: 200,
        headers: {
          'set-cookie': ['session=abc'],
        },
      ));

      final output = printer.lines.join('\n');
      expect(output, isNot(contains('hunter2')));
      expect(output, isNot(contains('session=abc')));
    });

    test('does not fail on bodies that are not JSON-encodable', () async {
      for (final format in LogFormat.values) {
        final result = await logger(format: format).onRequest(ApiRequest(
          path: '/x',
          method: HttpMethod.post,
          body: {'when': DateTime.utc(2020)},
        ));
        expect(result, isA<ApiRequest>());
        expect(printer.lines.join(), contains('2020-01-01'));
      }
    });

    test('prints error duration in milliseconds', () async {
      final interceptor = logger(format: LogFormat.pretty);
      final request = await interceptor.onRequest(const ApiRequest(path: '/x'))
          as ApiRequest;
      await interceptor.onError(
        NetworkException(message: 'down', request: request),
        (_) async => throw StateError('unused'),
      );
      expect(printer.lines.last, matches(RegExp(r'Duration: \d+ms')));
    });

    test('applies requestFilter to errors', () async {
      final interceptor = logger(requestFilter: (r) => r.path != '/health');
      await interceptor.onError(
        const NetworkException(
          message: 'down',
          request: ApiRequest(path: '/health'),
        ),
        (_) async => throw StateError('unused'),
      );
      expect(printer.lines, isEmpty);
    });

    test('includes query parameters in logs and curl', () async {
      await logger(format: LogFormat.compact).onRequest(const ApiRequest(
        path: '/search',
        queryParameters: {'q': 'dart'},
      ));
      expect(printer.lines.first, '→ GET /search?q=dart');
      expect(printer.lines.last, contains('"/search?q=dart"'));
    });
  });

  group('MemoryCacheStore', () {
    test('maxEntries of 0 stores nothing and does not throw', () async {
      final store = MemoryCacheStore(maxEntries: 0);
      await store.put(
        'k',
        CacheEntry(
          response: const ApiResponse<void>(statusCode: 200),
          cachedAt: DateTime.now(),
        ),
      );
      expect(await store.size, 0);
    });
  });

  group('ApiCancelToken', () {
    test('cancel is idempotent and keeps the first reason', () async {
      final token = ApiCancelToken();
      expect(token.isCancelled, isFalse);

      token.cancel('first');
      token.cancel('second');

      expect(token.isCancelled, isTrue);
      expect(token.reason, 'first');
      await expectLater(token.whenCancelled, completes);
    });

    test('is carried by copyWith and ignored by equality', () {
      final token = ApiCancelToken();
      final request = ApiRequest(path: '/x', cancelToken: token);

      expect(request.copyWith(path: '/y').cancelToken, same(token));
      expect(request, const ApiRequest(path: '/x'));
      expect(request.hashCode, const ApiRequest(path: '/x').hashCode);
    });

    test('RetryInterceptor never retries a cancelled request', () async {
      final interceptor = RetryInterceptor(
        config: RetryConfig(
          baseDelay: Duration.zero,
          shouldRetryException: (_) => true,
        ),
      );
      final request = ApiRequest(
        path: '/x',
        cancelToken: ApiCancelToken()..cancel(),
      );

      final result = await interceptor.onError(
        NetworkException(message: 'down', request: request),
        (_) async => throw StateError('should not be called'),
      );
      expect(result, isA<NetworkException>());

      const cancelled = CancellationException(
        message: 'cancelled',
        request: ApiRequest(path: '/x'),
      );
      expect(
        await interceptor.onError(
          cancelled,
          (_) async => throw StateError('should not be called'),
        ),
        same(cancelled),
      );
    });

    test('stale-while-revalidate refresh does not inherit the token', () async {
      final store = MemoryCacheStore();
      await store.put(
        'GET:/x',
        CacheEntry(
          response: const ApiResponse<String>(data: 'stale', statusCode: 200),
          cachedAt: DateTime.now().subtract(const Duration(minutes: 5)),
          expiresAt: DateTime.now().subtract(const Duration(minutes: 1)),
        ),
      );
      final requests = <ApiRequest>[];
      final adapter = HttpAdapter(
        baseUrl: 'https://api.test',
        client: _RecordingClient(requests),
        interceptors: [
          CacheInterceptor(
            config: CacheConfig(store: store, enableStaleWhileRevalidate: true),
          ),
          _CaptureInterceptor(requests),
        ],
      );
      final token = ApiCancelToken();

      final response = await adapter.request<String>(
        ApiRequest(path: '/x', cancelToken: token),
      );
      token.cancel();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(response.data, 'stale');
      expect(requests, hasLength(1));
      expect(requests.single.cancelToken, isNull);
      expect((await store.get('GET:/x'))!.response.data, 'fresh');
    });
  });

  group('Cache eviction metrics', () {
    test('MemoryCacheStore LRU evictions are reported', () async {
      final store = MemoryCacheStore(maxEntries: 2);
      final interceptor = CacheInterceptor(
        config: CacheConfig(store: store, enableMetrics: true),
      );

      for (final path in ['/a', '/b', '/c', '/d']) {
        await interceptor.onResponse(ApiResponse<String>(
          data: path,
          statusCode: 200,
          request: ApiRequest(path: path),
        ));
      }

      expect(store.evictionCount, 2);
      expect(interceptor.metrics.evictions, 2);
      expect(await store.containsKey('GET:/a'), isFalse);
      expect(await store.containsKey('GET:/d'), isTrue);
    });

    test('evictions are not recorded when metrics are disabled', () async {
      final store = MemoryCacheStore(maxEntries: 1);
      final interceptor = CacheInterceptor(config: CacheConfig(store: store));

      for (final path in ['/a', '/b']) {
        await interceptor.onResponse(ApiResponse<String>(
          data: path,
          statusCode: 200,
          request: ApiRequest(path: path),
        ));
      }

      expect(store.evictionCount, 1);
      expect(interceptor.metrics.evictions, 0);
    });
  });

  group('CacheKeyGenerator', () {
    test('handles query values that are not JSON-encodable', () {
      final key = CacheKeyGenerator.generate('GET', '/x', {
        'since': DateTime.utc(2020),
      });
      expect(key, contains('2020-01-01'));
    });
  });
}

class _NegativeDelayStrategy implements RetryStrategy {
  @override
  Duration getDelay(int attempt) => const Duration(seconds: -1);

  @override
  bool shouldRetry(ApiException error, int attempt, ApiRequest request) =>
      false;
}

class _Offline implements ConnectivityChecker {
  @override
  Future<bool> get isConnected async => false;
}

/// Answers every request with a fresh JSON string body.
class _RecordingClient extends http.BaseClient {
  _RecordingClient(this.requests);

  final List<ApiRequest> requests;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    await request.finalize().toBytes();
    return http.StreamedResponse(
      Stream.value('"fresh"'.codeUnits),
      200,
      headers: {'content-type': 'application/json'},
    );
  }
}

/// Records the requests that reach the network.
class _CaptureInterceptor extends ApiInterceptor {
  _CaptureInterceptor(this.requests);

  final List<ApiRequest> requests;

  @override
  Future<dynamic> onRequest(ApiRequest request) async {
    requests.add(request);
    return request;
  }
}
