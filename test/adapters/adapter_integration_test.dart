@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:api_plus/api_plus.dart';
import 'package:dio/dio.dart' show CancelToken, DioException, DioExceptionType;
import 'package:test/test.dart';

/// A base URL on which nothing is listening.
Future<String> _unreachableBaseUrl() async {
  final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = socket.port;
  await socket.close();
  return 'http://127.0.0.1:$port';
}

/// A tiny HTTP server with scripted routes and per-path hit counters.
class _TestServer {
  late HttpServer _server;
  final Map<String, int> hits = {};
  final List<HttpHeaders> requestHeaders = [];
  final List<String> requestBodies = [];

  /// Remaining failures for `/flaky` before it succeeds.
  int flakyFailures = 0;

  /// Version served by `/etag` and `/swr`.
  int version = 1;

  String get baseUrl => 'http://${_server.address.host}:${_server.port}';

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen(_handle);
  }

  Future<void> stop() => _server.close(force: true);

  Future<void> _handle(HttpRequest req) async {
    final path = req.uri.path;
    hits[path] = (hits[path] ?? 0) + 1;
    requestHeaders.add(req.headers);
    requestBodies.add(await utf8.decoder.bind(req).join());
    final res = req.response;

    void json(Object? body, {int status = 200}) {
      res.statusCode = status;
      res.headers.contentType = ContentType.json;
      res.write(jsonEncode(body));
    }

    switch (path) {
      case '/json':
        json({'id': 1, 'query': req.uri.queryParametersAll});
      case '/list':
        json([
          {'id': 1},
          {'id': 2},
        ]);
      case '/echo':
        json({
          'method': req.method,
          'contentType': req.headers.contentType?.mimeType,
          'body': requestBodies.last,
        });
      case '/text':
        res.headers.contentType = ContentType.text;
        res.write('123');
      case '/not-found':
        json({'error': 'missing'}, status: 404);
      case '/503':
        res.statusCode = 503;
      case '/flaky':
        if (flakyFailures > 0) {
          flakyFailures--;
          res.statusCode = 503;
        } else {
          json({'ok': true});
        }
      case '/slow':
        await Future<void>.delayed(const Duration(seconds: 2));
        res.write('late');
      case '/etag':
        final tag = '"v$version"';
        res.headers.set('etag', tag);
        res.headers.set('cache-control', 'max-age=0');
        if (req.headers.value('if-none-match') == tag) {
          res.statusCode = 304;
        } else {
          json({'version': version});
        }
      case '/swr':
        res.headers.set('cache-control', 'max-age=0');
        json({'version': version});
      case '/drip':
        // 8 chunks, 100ms apart: slow overall, but never idle for long.
        res.bufferOutput = false;
        res.headers.contentType = ContentType.text;
        for (var i = 0; i < 8; i++) {
          res.write('$i');
          await res.flush();
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
      case '/stall':
        // Headers arrive, then the body stalls.
        res.bufferOutput = false;
        res.headers.contentType = ContentType.text;
        res.write('start');
        await res.flush();
        await Future<void>.delayed(const Duration(seconds: 2));
      default:
        res.statusCode = 404;
    }
    await res.close();
  }
}

class _LinesPrinter implements LogPrinter {
  final List<String> lines = [];

  @override
  void log(String message) => lines.add(message);
}

class _ThrowingInterceptor extends ApiInterceptor {
  @override
  Future<ApiResponse<dynamic>> onResponse(ApiResponse<dynamic> response) {
    throw StateError('interceptor bug');
  }
}

const _fastRetry = RetryConfig(
  maxRetries: 2,
  baseDelay: Duration(milliseconds: 1),
  addJitter: false,
  enableMetrics: true,
);

void main() {
  late _TestServer server;

  setUp(() async {
    server = _TestServer();
    await server.start();
  });

  tearDown(() => server.stop());

  for (final type in ApiClientType.values) {
    group('${type.name} adapter', () {
      ApiBuilder builder() => ApiBuilder(server.baseUrl).clientType(type);

      test('returns typed Map and List data', () async {
        final api = builder().build();
        addTearDown(api.close);

        final map = await api.request<Map<String, dynamic>>(
          const ApiRequest(path: '/json'),
        );
        expect(map.statusCode, 200);
        expect(map.data!['id'], 1);

        final list = await api.request<List<dynamic>>(
          const ApiRequest(path: '/list'),
        );
        expect(list.data, hasLength(2));
      });

      test('mismatched data type throws SerializationException', () async {
        final api = builder().build();
        addTearDown(api.close);

        await expectLater(
          api.request<List<Map<String, dynamic>>>(
            const ApiRequest(path: '/list'),
          ),
          throwsA(isA<SerializationException>()),
        );
      });

      test('merges query parameters and supports absolute URLs', () async {
        final api = builder().build();
        addTearDown(api.close);

        final response = await api.request<Map<String, dynamic>>(
          ApiRequest(
            path: '${server.baseUrl}/json?a=1',
            queryParameters: const {'b': 2, 'skip': null},
          ),
        );
        expect(response.data!['query'], {
          'a': ['1'],
          'b': ['2'],
        });
      });

      test('sends Map bodies as JSON', () async {
        final api = builder().build();
        addTearDown(api.close);

        final response = await api.request<Map<String, dynamic>>(
          const ApiRequest(
            path: '/echo',
            method: HttpMethod.post,
            body: {'name': 'Zoë 🚀'},
          ),
        );
        expect(response.data!['contentType'], 'application/json');
        expect(
            jsonDecode(response.data!['body'] as String), {'name': 'Zoë 🚀'});
      });

      test('returns non-JSON bodies as String', () async {
        final api = builder().build();
        addTearDown(api.close);

        final response = await api.request<String>(
          const ApiRequest(path: '/text'),
        );
        expect(response.data, '123');
      });

      test('maps 404 to NotFoundException with the response', () async {
        final api = builder().build();
        addTearDown(api.close);

        final error = await api
            .request<dynamic>(const ApiRequest(path: '/not-found'))
            .then<Object?>((_) => null, onError: (Object e) => e);
        expect(error, isA<NotFoundException>());
        final notFound = error! as NotFoundException;
        expect(notFound.response!.statusCode, 404);
        expect(notFound.response!.data, {'error': 'missing'});
      });

      test('retries retryable status codes up to maxRetries', () async {
        final retry = RetryInterceptor(config: _fastRetry);
        final api = builder().addInterceptor(retry).build();
        addTearDown(api.close);

        await expectLater(
          api.request<dynamic>(const ApiRequest(path: '/503')),
          throwsA(isA<ServiceUnavailableException>()),
        );
        expect(server.hits['/503'], 3);
        expect(retry.metrics.totalRetries, 2);
        expect(retry.metrics.failedRetries, 1);
        expect(retry.metrics.successfulRetries, 0);
      });

      test('recovers when a retry succeeds', () async {
        server.flakyFailures = 1;
        final retry = RetryInterceptor(config: _fastRetry);
        final api = builder().addInterceptor(retry).build();
        addTearDown(api.close);

        final response = await api.request<Map<String, dynamic>>(
          const ApiRequest(path: '/flaky'),
        );
        expect(response.data, {'ok': true});
        expect(server.hits['/flaky'], 2);
        expect(retry.metrics.totalRetries, 1);
        expect(retry.metrics.successfulRetries, 1);
      });

      test('does not retry POST by default', () async {
        final api = builder().withRetry(_fastRetry).build();
        addTearDown(api.close);

        await expectLater(
          api.request<dynamic>(
            const ApiRequest(path: '/503', method: HttpMethod.post),
          ),
          throwsA(isA<ServiceUnavailableException>()),
        );
        expect(server.hits['/503'], 1);
      });

      test('logs each retry attempt once', () async {
        final printer = _LinesPrinter();
        final api = builder()
            .withRetry(_fastRetry)
            .withLogger(LoggerConfig(
              format: LogFormat.compact,
              printCurl: false,
              printer: printer,
            ))
            .build();
        addTearDown(api.close);

        await expectLater(
          api.request<dynamic>(const ApiRequest(path: '/503')),
          throwsA(isA<ServerException>()),
        );
        final requestLogs = printer.lines.where((l) => l.startsWith('→'));
        expect(requestLogs, hasLength(3));
      });

      test('applies builder timeouts', () async {
        final api = builder()
            .withReceiveTimeout(const Duration(milliseconds: 200))
            .build();
        addTearDown(() => api.close(force: true));

        await expectLater(
          api.request<dynamic>(const ApiRequest(path: '/slow')),
          throwsA(isA<TimeoutException>()),
        );
      });

      test('per-request timeout overrides the default', () async {
        final api = builder().build();
        addTearDown(() => api.close(force: true));

        await expectLater(
          api.request<dynamic>(
            const ApiRequest(
              path: '/slow',
              receiveTimeout: Duration(milliseconds: 200),
            ),
          ),
          throwsA(isA<TimeoutException>()),
        );
      });

      test('serves fresh cache entries without a network call', () async {
        final cache = CacheInterceptor(
          config: CacheConfig(store: MemoryCacheStore(), enableMetrics: true),
        );
        final api = builder().addInterceptor(cache).build();
        addTearDown(api.close);

        for (var i = 0; i < 3; i++) {
          final response = await api.request<Map<String, dynamic>>(
            const ApiRequest(path: '/json'),
          );
          expect(response.data!['id'], 1);
        }
        expect(server.hits['/json'], 1);
        expect(cache.metrics.hits, 2);
        expect(cache.metrics.misses, 1);
      });

      test('revalidates with ETag and serves cached data on 304', () async {
        final api =
            builder().withCache(CacheConfig(store: MemoryCacheStore())).build();
        addTearDown(api.close);

        final first = await api.request<Map<String, dynamic>>(
          const ApiRequest(path: '/etag'),
        );
        final second = await api.request<Map<String, dynamic>>(
          const ApiRequest(path: '/etag'),
        );
        expect(first.data, {'version': 1});
        expect(second.statusCode, 200);
        expect(second.data, {'version': 1});
        expect(server.hits['/etag'], 2);
        expect(
          server.requestHeaders.last.value('if-none-match'),
          '"v1"',
        );
      });

      test('stale-while-revalidate refreshes in the background', () async {
        final store = MemoryCacheStore();
        final api = builder()
            .withCache(CacheConfig(
              store: store,
              enableStaleWhileRevalidate: true,
            ))
            .build();
        addTearDown(api.close);

        await api.request<dynamic>(const ApiRequest(path: '/swr'));
        server.version = 2;

        final stale = await api.request<Map<String, dynamic>>(
          const ApiRequest(path: '/swr'),
        );
        expect(stale.data, {'version': 1});

        // Wait for the background refresh to land in the store.
        for (var i = 0; i < 100 && server.hits['/swr'] != 2; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        await Future<void>.delayed(const Duration(milliseconds: 50));
        final entry = await store.get('GET:/swr');
        expect(entry!.response.data, {'version': 2});
      });

      test('serves stale cache when the network is unreachable', () async {
        final store = MemoryCacheStore();
        await store.put(
          'GET:/offline',
          CacheEntry(
            response: const ApiResponse<dynamic>(
              data: {'cached': true},
              statusCode: 200,
            ),
            cachedAt: DateTime.now().subtract(const Duration(hours: 1)),
            expiresAt: DateTime.now().subtract(const Duration(minutes: 1)),
          ),
        );
        final api = ApiBuilder(await _unreachableBaseUrl())
            .clientType(type)
            .withCache(CacheConfig(store: store))
            .build();
        addTearDown(api.close);

        final response = await api.request<Map<String, dynamic>>(
          const ApiRequest(path: '/offline'),
        );
        expect(response.data, {'cached': true});
      });

      test('connection failure throws NetworkException', () async {
        final api =
            ApiBuilder(await _unreachableBaseUrl()).clientType(type).build();
        addTearDown(api.close);

        await expectLater(
          api.request<dynamic>(const ApiRequest(path: '/json')),
          throwsA(isA<NetworkException>()),
        );
      });

      test('handles concurrent requests independently', () async {
        final api = builder().withRetry(_fastRetry).build();
        addTearDown(api.close);

        final responses = await Future.wait([
          for (var i = 0; i < 25; i++)
            api.request<Map<String, dynamic>>(
              ApiRequest(path: '/json', queryParameters: {'i': i}),
            ),
        ]);
        for (var i = 0; i < 25; i++) {
          expect(responses[i].data!['query'], {
            'i': ['$i'],
          });
        }
      });

      test('non-ApiException interceptor errors propagate unchanged', () async {
        final api = builder()
            .withRetry(_fastRetry)
            .addInterceptor(_ThrowingInterceptor())
            .build();
        addTearDown(api.close);

        await expectLater(
          api.request<dynamic>(const ApiRequest(path: '/json')),
          throwsA(isA<StateError>()),
        );
        expect(server.hits['/json'], 1);
      });

      test('requests after close fail with an ApiException', () async {
        final api = builder().build();
        api.close();

        await expectLater(
          api.request<dynamic>(const ApiRequest(path: '/json')),
          throwsA(isA<ApiException>()),
        );
      });
    });
  }

  group('HttpAdapter', () {
    test('sends form-urlencoded Map bodies as fields', () async {
      final api = HttpAdapter(baseUrl: server.baseUrl);
      addTearDown(api.close);

      final response = await api.request<Map<String, dynamic>>(
        const ApiRequest(
          path: '/echo',
          method: HttpMethod.post,
          headers: {'content-type': 'application/x-www-form-urlencoded'},
          body: {'a': '1', 'b': 'x y'},
        ),
      );
      expect(
          response.data!['contentType'], 'application/x-www-form-urlencoded');
      expect(response.data!['body'], 'a=1&b=x+y');
    });

    test('non-encodable JSON body throws SerializationException', () async {
      final api = HttpAdapter(baseUrl: server.baseUrl);
      addTearDown(api.close);

      await expectLater(
        api.request<dynamic>(
          ApiRequest(
            path: '/echo',
            method: HttpMethod.post,
            body: {'when': DateTime(2020)},
          ),
        ),
        throwsA(isA<SerializationException>()),
      );
      expect(server.hits['/echo'], isNull);
    });
  });

  group('RetrofitAdapter', () {
    test('retries through the bridged Dio client', () async {
      final adapter = RetrofitAdapter(
        baseUrl: server.baseUrl,
        retryConfig: _fastRetry,
      );
      addTearDown(adapter.close);

      await expectLater(
        adapter.client.get<dynamic>('/503'),
        throwsA(isA<DioException>()),
      );
      expect(server.hits['/503'], 3);
    });

    test('recovers when a retry succeeds', () async {
      server.flakyFailures = 1;
      final adapter = RetrofitAdapter(
        baseUrl: server.baseUrl,
        retryConfig: _fastRetry,
      );
      addTearDown(adapter.close);

      final response = await adapter.client.get<dynamic>('/flaky');
      expect(response.data, {'ok': true});
      expect(server.hits['/flaky'], 2);
    });

    test('serves cache hits and 304 revalidations', () async {
      final adapter = RetrofitAdapter(
        baseUrl: server.baseUrl,
        cacheConfig: CacheConfig(store: MemoryCacheStore()),
      );
      addTearDown(adapter.close);

      await adapter.client.get<dynamic>('/json');
      final cached = await adapter.client.get<dynamic>('/json');
      expect((cached.data as Map)['id'], 1);
      expect(server.hits['/json'], 1);

      await adapter.client.get<dynamic>('/etag');
      final revalidated = await adapter.client.get<dynamic>('/etag');
      expect(revalidated.statusCode, 200);
      expect(revalidated.data, {'version': 1});
      expect(server.hits['/etag'], 2);
    });

    test('interceptor header changes reach the server', () async {
      final adapter = RetrofitAdapter(
        baseUrl: server.baseUrl,
        interceptors: [_HeaderInterceptor()],
      );
      addTearDown(adapter.close);

      await adapter.client.get<dynamic>('/json');
      expect(server.requestHeaders.last.value('x-api-plus'), 'yes');
    });
  });

  for (final type in ApiClientType.values) {
    group('${type.name} cancellation and timeouts', () {
      ApiBuilder builder() => ApiBuilder(server.baseUrl).clientType(type);

      Future<Object?> errorOf(Future<Object?> future) =>
          future.then<Object?>((_) => null, onError: (Object e) => e);

      test('cancelling aborts an in-flight request', () async {
        final api = builder().build();
        addTearDown(() => api.close(force: true));
        final token = ApiCancelToken();
        final stopwatch = Stopwatch()..start();

        final pending = errorOf(api.request<dynamic>(
          ApiRequest(path: '/slow', cancelToken: token),
        ));
        await Future<void>.delayed(const Duration(milliseconds: 100));
        token.cancel('user left');

        final error = await pending;
        expect(error, isA<CancellationException>());
        expect(
            (error! as CancellationException).message, contains('user left'));
        expect(stopwatch.elapsed, lessThan(const Duration(seconds: 1)));
      });

      test('an already-cancelled token never hits the network', () async {
        final api = builder().build();
        addTearDown(api.close);
        final token = ApiCancelToken()..cancel();

        await expectLater(
          api.request<dynamic>(ApiRequest(path: '/json', cancelToken: token)),
          throwsA(isA<CancellationException>()),
        );
        expect(server.hits['/json'], isNull);
      });

      test('cancelling stops a pending retry delay', () async {
        final retry = RetryInterceptor(
          config: const RetryConfig(
            maxRetries: 3,
            baseDelay: Duration(seconds: 5),
            addJitter: false,
            enableMetrics: true,
          ),
        );
        final api = builder().addInterceptor(retry).build();
        addTearDown(api.close);
        final token = ApiCancelToken();
        final stopwatch = Stopwatch()..start();

        final pending = errorOf(api.request<dynamic>(
          ApiRequest(path: '/503', cancelToken: token),
        ));
        await Future<void>.delayed(const Duration(milliseconds: 200));
        token.cancel();

        expect(await pending, isA<CancellationException>());
        expect(stopwatch.elapsed, lessThan(const Duration(seconds: 2)));
        expect(server.hits['/503'], 1);
        expect(retry.metrics.totalRetries, 0);
        expect(retry.metrics.failedRetries, 0);
      });

      test('one token cancels many concurrent requests', () async {
        final api = builder().build();
        addTearDown(() => api.close(force: true));
        final token = ApiCancelToken();

        final pending = [
          for (var i = 0; i < 5; i++)
            errorOf(api.request<dynamic>(ApiRequest(
              path: '/slow',
              queryParameters: {'i': i},
              cancelToken: token,
            ))),
        ];
        await Future<void>.delayed(const Duration(milliseconds: 100));
        token.cancel();

        expect(
          await Future.wait(pending),
          everyElement(isA<CancellationException>()),
        );
      });

      test('receive timeout limits idle gaps, not the total time', () async {
        final api = builder()
            .withReceiveTimeout(const Duration(milliseconds: 400))
            .build();
        addTearDown(() => api.close(force: true));

        // ~800ms in total, but never more than ~100ms without data.
        final response = await api.request<String>(
          const ApiRequest(path: '/drip'),
        );
        expect(response.data, '01234567');
      });

      test('a stalled body times out as a receive timeout', () async {
        final api = builder()
            .withReceiveTimeout(const Duration(milliseconds: 300))
            .build();
        addTearDown(() => api.close(force: true));

        final error = await errorOf(
          api.request<dynamic>(const ApiRequest(path: '/stall')),
        );
        expect(error, isA<TimeoutException>());
        expect((error! as TimeoutException).timeoutType, TimeoutType.receive);
      });
    });
  }

  group('HttpAdapter timeout phases', () {
    // Accepts connections but never reads from or writes to them.
    Future<String> silentServer() async {
      final socketServer =
          await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final held = <Socket>[];
      socketServer.listen(held.add);
      addTearDown(() async {
        for (final socket in held) {
          socket.destroy();
        }
        await socketServer.close();
      });
      return 'http://127.0.0.1:${socketServer.port}';
    }

    test('an upload the server does not read is a send timeout', () async {
      final api = HttpAdapter(
        baseUrl: await silentServer(),
        sendTimeout: const Duration(milliseconds: 300),
        receiveTimeout: const Duration(seconds: 30),
      );
      addTearDown(() => api.close(force: true));

      final error = await api
          .request<dynamic>(ApiRequest(
            path: '/upload',
            method: HttpMethod.post,
            body: Uint8List(64 * 1024 * 1024),
          ))
          .then<Object?>((_) => null, onError: (Object e) => e);
      expect(error, isA<TimeoutException>());
      expect((error! as TimeoutException).timeoutType, TimeoutType.send);
    });

    test('no response after the upload is a receive timeout', () async {
      final api = HttpAdapter(
        baseUrl: await silentServer(),
        connectTimeout: const Duration(seconds: 30),
        sendTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(milliseconds: 300),
      );
      addTearDown(() => api.close(force: true));

      final error = await api
          .request<dynamic>(const ApiRequest(path: '/x'))
          .then<Object?>((_) => null, onError: (Object e) => e);
      expect(error, isA<TimeoutException>());
      expect((error! as TimeoutException).timeoutType, TimeoutType.receive);
    });
  });

  group('RetrofitAdapter cancellation', () {
    test('a Dio CancelToken stops a pending retry', () async {
      final adapter = RetrofitAdapter(
        baseUrl: server.baseUrl,
        retryConfig: const RetryConfig(
          maxRetries: 3,
          baseDelay: Duration(seconds: 5),
          addJitter: false,
        ),
      );
      addTearDown(adapter.close);
      final token = CancelToken();
      final stopwatch = Stopwatch()..start();

      final pending = adapter.client
          .get<dynamic>('/503', cancelToken: token)
          .then<Object?>((_) => null, onError: (Object e) => e);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      token.cancel('bye');

      final error = await pending;
      expect(error, isA<DioException>());
      expect((error! as DioException).type, DioExceptionType.cancel);
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 2)));
      expect(server.hits['/503'], 1);
    });
  });
}

class _HeaderInterceptor extends ApiInterceptor {
  @override
  Future<dynamic> onRequest(ApiRequest request) async {
    return request.copyWith(headers: {...request.headers, 'x-api-plus': 'yes'});
  }
}
