// Regression tests for the issues fixed in 0.0.4 (external QA report,
// API_PLUS-01 … API_PLUS-19). Each test is named after its issue ID and runs
// against a real local server.
@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:developer' show reachabilityBarrier;
import 'dart:io';

import 'package:api_plus/api_plus.dart';
import 'package:dio/dio.dart' show DioException, DioExceptionType;
import 'package:test/test.dart';

typedef _Handler = FutureOr<void> Function(HttpRequest request, int hit);

/// A local HTTP server whose responses are scripted per test.
class _Server {
  _Server._(this._server);

  final HttpServer _server;

  /// Answers every request; by default echoes the path, query, and hit.
  _Handler handler = (req, hit) => _json(req.response, {
        'path': req.uri.path,
        'query': req.uri.queryParametersAll,
        'hit': hit,
      });

  /// Requests received per path.
  final Map<String, int> hits = {};

  /// Request headers received per path (latest first).
  final Map<String, List<HttpHeaders>> headers = {};

  static Future<_Server> start() async {
    final server = _Server._(
      await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
    );
    server._server.listen(server._handle);
    return server;
  }

  String get baseUrl => 'http://127.0.0.1:${_server.port}';

  int hitsFor(String path) => hits[path] ?? 0;

  int get totalHits => hits.values.fold(0, (a, b) => a + b);

  Future<void> close() => _server.close(force: true);

  Future<void> _handle(HttpRequest req) async {
    await req.drain<void>();
    final path = req.uri.path;
    final hit = hits[path] = hitsFor(path) + 1;
    (headers[path] ??= []).insert(0, req.headers);
    try {
      await handler(req, hit);
    } catch (_) {
      // The handler may have dropped the connection on purpose.
    }
    try {
      await req.response.close();
    } catch (_) {
      // Already closed or detached.
    }
  }
}

void _json(
  HttpResponse res,
  Object? body, {
  int status = 200,
  Map<String, String> headers = const {},
}) {
  res.statusCode = status;
  res.headers.contentType = ContentType.json;
  headers.forEach(res.headers.set);
  res.write(jsonEncode(body));
}

/// Fast, deterministic retries.
RetryConfig _fastRetry({
  Duration maxDelay = const Duration(seconds: 30),
  Duration? maxElapsedDuration,
  void Function(int, Duration)? onRetry,
}) =>
    RetryConfig(
      baseDelay: const Duration(milliseconds: 5),
      maxDelay: maxDelay,
      maxElapsedDuration: maxElapsedDuration,
      addJitter: false,
      enableMetrics: true,
      onRetry: onRetry,
    );

class _Lines implements LogPrinter {
  final List<String> lines = [];

  String get all => lines.join('\n');

  @override
  void log(String message) => lines.add(message);
}

/// Throws a [StateError] from its second `onRequest` call on.
class _ThrowsFromSecondCall extends ApiInterceptor {
  int calls = 0;

  @override
  Future<dynamic> onRequest(ApiRequest request) async {
    calls++;
    if (calls >= 2) throw StateError('token store corrupted');
    return request;
  }
}

/// Records what `onResponse` sees.
class _ResponseSpy extends ApiInterceptor {
  final statuses = <int>[];
  final data = <Object?>[];

  @override
  Future<ApiResponse<dynamic>> onResponse(ApiResponse<dynamic> r) async {
    statuses.add(r.statusCode);
    data.add(r.data);
    return r;
  }
}

/// A store whose reads and writes always fail.
class _BrokenStore implements CacheStore {
  @override
  Future<CacheEntry?> get(String key) async =>
      throw const FileSystemException('cache file corrupted');

  @override
  Future<void> put(String key, CacheEntry entry) async =>
      throw const FileSystemException('disk full');

  @override
  Future<void> delete(String key) async {}

  @override
  Future<void> clear() async {}

  @override
  Future<bool> containsKey(String key) async => false;

  @override
  Future<int> get size async => 0;
}

/// A custom adapter built on the public [InterceptorPipeline]: it answers
/// with the scripted [statuses], one per network call.
class _ScriptedAdapter extends ApiAdapter with InterceptorPipeline {
  _ScriptedAdapter(this.interceptors, this.statuses);

  @override
  final List<ApiInterceptor> interceptors;

  final List<int> statuses;

  int calls = 0;

  @override
  String get baseUrl => 'https://api.example.com';

  @override
  Map<String, String> get defaultHeaders =>
      const {'accept': 'application/json'};

  @override
  Future<ApiResponse<T>> request<T>(ApiRequest request) =>
      runPipeline<T>(request, _send);

  Future<ApiResponse<dynamic>> _send(ApiRequest request) async {
    calls++;
    return ApiResponse<dynamic>(
      data: {'call': calls},
      statusCode: statuses[calls - 1],
      headers: const {
        'cache-control': ['max-age=60'],
      },
      request: request,
    );
  }

  @override
  void close({bool force = false}) {}
}

ApiAdapter _adapter(
  ApiClientType type,
  String baseUrl, [
  List<ApiInterceptor> interceptors = const [],
]) {
  switch (type) {
    case ApiClientType.http:
      return HttpAdapter(baseUrl: baseUrl, interceptors: interceptors);
    case ApiClientType.dio:
      return DioAdapter(baseUrl: baseUrl, interceptors: interceptors);
  }
}

/// Runs full garbage collections on the VM, like `package:leak_tracker`'s
/// `forceGC`: allocates until the reachability barrier has advanced.
Future<void> _forceGC({int cycles = 3}) async {
  final target = reachabilityBarrier + cycles;
  final deadline = DateTime.now().add(const Duration(seconds: 30));
  final storage = <List<int>>[];
  while (reachabilityBarrier < target) {
    if (DateTime.now().isAfter(deadline)) {
      fail('garbage collection did not run');
    }
    await Future<void>.delayed(Duration.zero);
    storage.add(List<int>.generate(30000, (n) => n));
    if (storage.length > 100) storage.removeAt(0);
  }
}

/// Sends [request] with a fresh body and returns a weak reference to it.
Future<WeakReference<Object>> _sendAndForget(
  ApiAdapter api,
  ApiCancelToken token,
  HttpMethod method,
  String path,
) async {
  final body = <String, Object>{'blob': List<int>.filled(10000, 7)};
  final ref = WeakReference<Object>(body);
  await api.request<dynamic>(
    ApiRequest(path: path, method: method, body: body, cancelToken: token),
  );
  return ref;
}

void main() {
  late _Server server;

  setUp(() async => server = await _Server.start());
  tearDown(() => server.close());

  test(
      'API_PLUS-01: default maskedKeys also mask camelCase, kebab-case and '
      'upper-case spellings of token keys', () async {
    server.handler = (req, hit) => _json(req.response, {
          'id': 1,
          'accessToken': 'SECRET-ACCESS',
          'refreshToken': 'SECRET-REFRESH',
          'idToken': 'SECRET-ID',
          'nested': {'apiKey': 'SECRET-KEY', 'clientSecret': 'SECRET-CLIENT'},
        }, headers: {
          'refresh-token': 'SECRET-HEADER',
        });
    final lines = _Lines();
    final api = HttpAdapter(baseUrl: server.baseUrl, interceptors: [
      LoggerInterceptor(config: LoggerConfig(printer: lines, colors: false)),
    ]);
    addTearDown(api.close);

    await api.request<dynamic>(const ApiRequest(
      path: '/auth/login',
      method: HttpMethod.post,
      headers: {'Access-Token': 'SECRET-REQUEST-HEADER'},
      body: {'username': 'emily', 'ACCESS_TOKEN': 'SECRET-BODY'},
    ));

    for (final secret in [
      'SECRET-ACCESS',
      'SECRET-REFRESH',
      'SECRET-ID',
      'SECRET-KEY',
      'SECRET-CLIENT',
      'SECRET-REQUEST-HEADER',
      'SECRET-BODY',
      'SECRET-HEADER',
    ]) {
      expect(lines.all, isNot(contains(secret)), reason: '$secret was logged');
    }
    expect(lines.all, contains('"accessToken": "***"'));
    expect(lines.all, contains('emily'));
    expect(
      const LoggerConfig().maskedKeys,
      containsAll(<String>{'access_token', 'refresh_token', 'id_token'}),
    );

    // Custom keys are normalised the same way.
    final custom = _Lines();
    final masked = LoggerInterceptor(
      config: LoggerConfig(
        printer: custom,
        colors: false,
        maskedKeys: const {'session_id'},
      ),
    );
    await masked.onRequest(const ApiRequest(
      path: '/x',
      body: {'sessionId': 'S1', 'session-id': 'S2', 'other': 'visible'},
    ));
    expect(custom.all, isNot(contains('S1')));
    expect(custom.all, isNot(contains('S2')));
    expect(custom.all, contains('visible'));
  });

  test(
      'API_PLUS-02: a Retry-After longer than maxDelay or past '
      'maxElapsedDuration stops retrying instead of waiting', () async {
    server.handler = (req, hit) => hit == 1
        ? _json(req.response, {}, status: 429, headers: {'retry-after': '3'})
        : _json(req.response, {'ok': true});
    final delays = <Duration>[];
    final api = HttpAdapter(baseUrl: server.baseUrl, interceptors: [
      RetryInterceptor(
        config: _fastRetry(
          maxDelay: const Duration(milliseconds: 200),
          onRetry: (_, delay) => delays.add(delay),
        ),
      ),
    ]);
    addTearDown(api.close);

    final watch = Stopwatch()..start();
    final error = await api
        .request<dynamic>(const ApiRequest(path: '/limited'))
        .then<Object?>((_) => null, onError: (Object e) => e);
    watch.stop();
    expect(error, isA<TooManyRequestsException>());
    expect(
      (error as ApiException).response?.headers['retry-after'],
      ['3'],
      reason: 'the caller can still read the requested delay',
    );
    expect(delays, isEmpty, reason: 'no wait may exceed maxDelay');
    expect(server.hitsFor('/limited'), 1);
    expect(watch.elapsed, lessThan(const Duration(seconds: 1)));

    // Within maxDelay, but the wait would end after maxElapsedDuration.
    server.handler = (req, hit) => hit == 1
        ? _json(req.response, {}, status: 503, headers: {'retry-after': '2'})
        : _json(req.response, {'ok': true});
    final budget = HttpAdapter(baseUrl: server.baseUrl, interceptors: [
      RetryInterceptor(
        config: _fastRetry(
          maxElapsedDuration: const Duration(milliseconds: 500),
          onRetry: (_, delay) => delays.add(delay),
        ),
      ),
    ]);
    addTearDown(budget.close);
    watch
      ..reset()
      ..start();
    await expectLater(
      budget.request<dynamic>(const ApiRequest(path: '/busy')),
      throwsA(isA<ServiceUnavailableException>()),
    );
    expect(delays, isEmpty);
    expect(server.hitsFor('/busy'), 1);
    expect(watch.elapsed, lessThan(const Duration(seconds: 1)));

    // A Retry-After within both limits is still honoured.
    server.handler = (req, hit) => hit == 1
        ? _json(req.response, {}, status: 503, headers: {'retry-after': '0'})
        : _json(req.response, {'ok': true});
    final ok = await budget
        .request<Map<String, dynamic>>(const ApiRequest(path: '/soon'));
    expect(ok.data, {'ok': true});
  });

  test(
      'API_PLUS-03: DioAdapter returns null data for an empty body, like '
      'HttpAdapter; Retrofit callers still get what Dio returns', () async {
    server.handler = (req, hit) {
      req.response.statusCode = req.method == 'DELETE' ? 204 : 200;
    };
    for (final type in ApiClientType.values) {
      final api = _adapter(type, server.baseUrl);
      addTearDown(api.close);
      final deleted = await api.request<Map<String, dynamic>>(
        const ApiRequest(path: '/posts/1', method: HttpMethod.delete),
      );
      expect(deleted.statusCode, 204, reason: type.name);
      expect(deleted.data, isNull, reason: type.name);
      final empty = await api
          .request<Map<String, dynamic>>(const ApiRequest(path: '/empty'));
      expect(empty.data, isNull, reason: type.name);
    }

    final spy = _ResponseSpy();
    final retrofit = RetrofitAdapter(
      baseUrl: server.baseUrl,
      interceptors: [spy],
    );
    addTearDown(retrofit.close);
    final response = await retrofit.client.get<dynamic>('/empty');
    expect(spy.data, [null], reason: 'interceptors see null');
    expect(response.data, '', reason: 'Dio returns an empty string');

    // Also when the empty response is served from the cache.
    final cached = RetrofitAdapter(
      baseUrl: server.baseUrl,
      cacheConfig: CacheConfig(store: MemoryCacheStore()),
    );
    addTearDown(cached.close);
    await cached.client.get<dynamic>('/cached-empty');
    final hit = await cached.client.get<dynamic>('/cached-empty');
    expect(hit.data, '');
    expect(server.hitsFor('/cached-empty'), 1);
  });

  test(
      'API_PLUS-04: malformed JSON is a SerializationException and an '
      'invalid URL a ConfigurationException, neither retried (Dio and '
      'Retrofit)', () async {
    server.handler = (req, hit) {
      req.response.headers.contentType = ContentType.json;
      req.response.write('{"id": 1,,');
    };
    final retry = RetryInterceptor(config: _fastRetry());
    final api = DioAdapter(baseUrl: server.baseUrl, interceptors: [retry]);
    addTearDown(api.close);

    await expectLater(
      api.request<Map<String, dynamic>>(const ApiRequest(path: '/bad-json')),
      throwsA(isA<SerializationException>()),
    );
    expect(server.hitsFor('/bad-json'), 1);

    await expectLater(
      api.request<dynamic>(const ApiRequest(path: 'http://[::1')),
      throwsA(isA<ConfigurationException>()),
    );
    expect(retry.metrics.totalRetries, 0);

    final retrofit = RetrofitAdapter(
      baseUrl: server.baseUrl,
      retryConfig: _fastRetry(),
    );
    addTearDown(retrofit.close);
    await expectLater(
      retrofit.client.get<dynamic>('/bad-json-retrofit'),
      throwsA(isA<DioException>()
          .having((e) => e.error, 'error', isA<FormatException>())),
    );
    expect(server.hitsFor('/bad-json-retrofit'), 1);

    await expectLater(
      retrofit.client.get<dynamic>('http://[::1'),
      throwsA(isA<DioException>()
          .having((e) => e.error, 'error', isA<ConfigurationException>())),
    );
    expect(server.totalHits, 2, reason: 'no request for invalid URLs');

    // Transport failures are still retryable network errors.
    await server.close();
    await expectLater(
      api.request<dynamic>(const ApiRequest(path: '/gone')),
      throwsA(isA<NetworkException>()),
    );
    expect(retry.metrics.totalRetries, 3);
    server = await _Server.start();
  });

  test(
      'API_PLUS-05: non-ApiException errors thrown by interceptors during a '
      'retry propagate unchanged and are not retried', () async {
    server.handler = (req, hit) => _json(req.response, {}, status: 503);
    for (final type in ApiClientType.values) {
      final spy = _ThrowsFromSecondCall();
      final api = _adapter(type, server.baseUrl, [
        RetryInterceptor(config: _fastRetry()),
        spy,
      ]);
      addTearDown(api.close);
      await expectLater(
        api.request<dynamic>(const ApiRequest(path: '/x')),
        throwsA(isA<StateError>()),
        reason: type.name,
      );
      expect(spy.calls, 2, reason: type.name);
    }

    final spy = _ThrowsFromSecondCall();
    final retrofit = RetrofitAdapter(
      baseUrl: server.baseUrl,
      retryConfig: _fastRetry(),
      interceptors: [spy],
    );
    addTearDown(retrofit.close);
    await expectLater(
      retrofit.client.get<dynamic>('/retrofit'),
      throwsA(isA<DioException>()
          .having((e) => e.error, 'error', isA<StateError>())),
    );
    expect(spy.calls, 2);
  });

  test(
      "API_PLUS-06: RetrofitAdapter rejects with the last attempt's error "
      'after retries', () async {
    server.handler = (req, hit) => hit == 1
        ? _json(req.response, {'attempt': 'first'}, status: 503)
        : _json(req.response, {'attempt': 'last'}, status: 404);
    final adapter = RetrofitAdapter(
      baseUrl: server.baseUrl,
      retryConfig: _fastRetry(),
    );
    addTearDown(adapter.close);

    await expectLater(
      adapter.client.get<dynamic>('/r'),
      throwsA(isA<DioException>()
          .having((e) => e.type, 'type', DioExceptionType.badResponse)
          .having((e) => e.response?.statusCode, 'status', 404)
          .having((e) => e.response?.data, 'data', {'attempt': 'last'})),
    );
    expect(server.hitsFor('/r'), 2);
  });

  test(
      'API_PLUS-07: RetrofitAdapter runs onResponse for non-2xx responses, '
      'like the other adapters', () async {
    server.handler = (req, hit) => _json(req.response, {}, status: 404);
    final spies = <String, _ResponseSpy>{};
    for (final type in ApiClientType.values) {
      final spy = spies[type.name] = _ResponseSpy();
      final api = _adapter(type, server.baseUrl, [spy]);
      addTearDown(api.close);
      await expectLater(
        api.request<dynamic>(const ApiRequest(path: '/missing')),
        throwsA(isA<NotFoundException>()),
      );
    }
    final spy = spies['retrofit'] = _ResponseSpy();
    final adapter = RetrofitAdapter(
      baseUrl: server.baseUrl,
      interceptors: [spy],
    );
    addTearDown(adapter.close);
    await expectLater(
      adapter.client.get<dynamic>('/missing'),
      throwsA(isA<DioException>()
          .having((e) => e.response?.statusCode, 'status', 404)),
    );

    for (final entry in spies.entries) {
      expect(entry.value.statuses, [404], reason: entry.key);
    }
  });

  test(
      'API_PLUS-08: HttpAdapter.close() lets in-flight requests complete; '
      'later requests fail fast; close(force: true) aborts', () async {
    server.handler = (req, hit) async {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      _json(req.response, {'ok': true});
    };
    final retry = RetryInterceptor(config: _fastRetry());
    final api = HttpAdapter(baseUrl: server.baseUrl, interceptors: [retry]);

    final pending =
        api.request<Map<String, dynamic>>(const ApiRequest(path: '/slow'));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    api.close();
    expect((await pending).data, {'ok': true});

    await expectLater(
      api.request<dynamic>(const ApiRequest(path: '/after-close')),
      throwsA(isA<ConfigurationException>()),
    );
    expect(server.hitsFor('/after-close'), 0);
    expect(retry.metrics.totalRetries, 0);

    final forced = HttpAdapter(baseUrl: server.baseUrl);
    final aborted = forced.request<dynamic>(const ApiRequest(path: '/slow'));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    forced.close(force: true);
    await expectLater(aborted, throwsA(isA<NetworkException>()));
  });

  test('API_PLUS-09: different query parameters never share a cache entry',
      () async {
    final api = HttpAdapter(baseUrl: server.baseUrl, interceptors: [
      CacheInterceptor(config: CacheConfig(store: MemoryCacheStore())),
    ]);
    addTearDown(api.close);

    Future<Object?> query(Map<String, dynamic> params) async =>
        (await api.request<Map<String, dynamic>>(
                ApiRequest(path: '/search', queryParameters: params)))
            .data!['query'];

    expect(await query({'q': 'a', 'r': 'b'}), {
      'q': ['a'],
      'r': ['b'],
    });
    expect(await query({'q': 'a, r: b'}), {
      'q': ['a, r: b'],
    });
    expect(await query({'a': null}), <String, Object?>{});
    expect(await query({'a': 'null'}), {
      'a': ['null'],
    });
    expect(server.hitsFor('/search'), 4);

    // Equal URLs still share an entry.
    expect(await query({'r': 'b', 'q': 'a'}), {
      'q': ['a'],
      'r': ['b'],
    });
    expect(server.hitsFor('/search'), 4);
  });

  test(
      'API_PLUS-10: no-cache (and must-revalidate) responses are revalidated '
      'before use, even with stale-while-revalidate', () async {
    var balance = 100;
    server.handler = (req, hit) {
      final etag = '"$balance"';
      if (req.headers.value('if-none-match') == etag) {
        req.response.statusCode = 304;
        return;
      }
      _json(req.response, {
        'balance': balance
      }, headers: {
        'cache-control': req.uri.path == '/strict'
            ? 'max-age=0, must-revalidate'
            : 'no-cache',
        'etag': etag,
      });
    };
    final api = HttpAdapter(baseUrl: server.baseUrl, interceptors: [
      CacheInterceptor(
        config: CacheConfig(
          store: MemoryCacheStore(),
          enableStaleWhileRevalidate: true,
        ),
      ),
    ]);
    addTearDown(api.close);

    for (final path in ['/balance', '/strict']) {
      balance = 100;
      await api.request<dynamic>(ApiRequest(path: path));
      balance = 50;
      final changed =
          await api.request<Map<String, dynamic>>(ApiRequest(path: path));
      expect(changed.data, {'balance': 50}, reason: path);

      final unchanged =
          await api.request<Map<String, dynamic>>(ApiRequest(path: path));
      expect(unchanged.data, {'balance': 50}, reason: path);
      expect(unchanged.statusCode, 200);
      expect(server.headers[path]!.first.value('if-none-match'), '"50"');

      // The 304 (without Cache-Control) keeps the stored rules, so the
      // entry is revalidated again rather than served for defaultTtl.
      balance = 25;
      final afterNotModified =
          await api.request<Map<String, dynamic>>(ApiRequest(path: path));
      expect(afterNotModified.data, {'balance': 25}, reason: path);
      expect(server.hitsFor(path), 4, reason: path);
    }
  });

  test(
      'API_PLUS-11: Expires sets freshness when there is no max-age, and '
      'max-age still wins', () async {
    final now = DateTime.now().toUtc();
    String httpDate(DateTime d) => HttpDate.format(d);
    final responses = <String, Map<String, String>>{
      '/expired': {
        'expires': 'Thu, 01 Jan 1970 00:00:00 GMT',
        'pragma': 'no-cache',
      },
      '/invalid': {'expires': '0'},
      '/max-age-wins': {'cache-control': 'max-age=60', 'expires': '-1'},
      '/future': {
        'expires': httpDate(now.add(const Duration(hours: 1))),
        'date': httpDate(now),
      },
      '/no-headers': {},
    };
    server.handler = (req, hit) =>
        _json(req.response, {'v': hit}, headers: responses[req.uri.path]!);
    final api = HttpAdapter(baseUrl: server.baseUrl, interceptors: [
      CacheInterceptor(config: CacheConfig(store: MemoryCacheStore())),
    ]);
    addTearDown(api.close);

    for (var i = 0; i < 2; i++) {
      for (final path in responses.keys) {
        await api.request<dynamic>(ApiRequest(path: path));
      }
    }
    expect(server.hitsFor('/expired'), 2);
    expect(server.hitsFor('/invalid'), 2);
    expect(server.hitsFor('/max-age-wins'), 1);
    expect(server.hitsFor('/future'), 1);
    expect(server.hitsFor('/no-headers'), 1, reason: 'defaultTtl applies');

    // An entry expires at expiresAt (inclusive).
    final atNow = DateTime.now();
    expect(
      CacheEntry(
        response: const ApiResponse<void>(statusCode: 200),
        cachedAt: atNow,
        expiresAt: atNow,
      ).isExpired,
      isTrue,
    );
  });

  group(
      'API_PLUS-12: a transient network error is retried before the stale '
      'cache entry is served', () {
    void flakyFeed() {
      server.handler = (req, hit) async {
        if (hit == 2) {
          // Drop the connection once.
          final socket = await req.response.detachSocket(writeHeaders: false);
          socket.destroy();
          return;
        }
        _json(req.response, {'v': hit},
            headers: {'cache-control': 'max-age=0'});
      };
    }

    for (final type in ApiClientType.values) {
      test('ApiBuilder (${type.name})', () async {
        flakyFeed();
        final api = ApiBuilder(server.baseUrl)
            .clientType(type)
            .withCache(CacheConfig(store: MemoryCacheStore()))
            .withRetry(_fastRetry())
            .build();
        addTearDown(api.close);
        expect(api.interceptors[0], isA<RetryInterceptor>());
        expect(api.interceptors[1], isA<CacheInterceptor>());

        await api.request<dynamic>(const ApiRequest(path: '/feed'));
        final fresh = await api
            .request<Map<String, dynamic>>(const ApiRequest(path: '/feed'));
        expect(server.hitsFor('/feed'), 3);
        expect(fresh.data, {'v': 3});

        // Offline: served from cache once the retries are exhausted.
        await server.close();
        final offline = await api
            .request<Map<String, dynamic>>(const ApiRequest(path: '/feed'));
        expect(offline.data, {'v': 3});
        final retry = api.interceptors.whereType<RetryInterceptor>().single;
        expect(retry.metrics.totalRetries, 1 + 3);
        server = await _Server.start();
      });
    }

    test('RetrofitAdapter', () async {
      flakyFeed();
      final adapter = RetrofitAdapter(
        baseUrl: server.baseUrl,
        retryConfig: _fastRetry(),
        cacheConfig: CacheConfig(store: MemoryCacheStore()),
      );
      addTearDown(adapter.close);

      await adapter.client.get<dynamic>('/feed');
      final fresh = await adapter.client.get<dynamic>('/feed');
      expect(server.hitsFor('/feed'), 3);
      expect(fresh.data, {'v': 3});

      await server.close();
      final offline = await adapter.client.get<dynamic>('/feed');
      expect(offline.data, {'v': 3});
      server = await _Server.start();
    });

    test('without a RetryInterceptor the stale entry is served at once',
        () async {
      flakyFeed();
      final api = ApiBuilder(server.baseUrl)
          .withCache(CacheConfig(store: MemoryCacheStore()))
          .build();
      addTearDown(api.close);
      await api.request<dynamic>(const ApiRequest(path: '/feed'));
      final stale = await api
          .request<Map<String, dynamic>>(const ApiRequest(path: '/feed'));
      expect(stale.data, {'v': 1});
      expect(server.hitsFor('/feed'), 2);
    });
  });

  test('API_PLUS-13: maskedKeys also mask query parameters (URL and curl)',
      () async {
    final lines = _Lines();
    for (final format in LogFormat.values) {
      final api = HttpAdapter(baseUrl: server.baseUrl, interceptors: [
        LoggerInterceptor(
          config: LoggerConfig(printer: lines, colors: false, format: format),
        ),
      ]);
      addTearDown(api.close);
      await api.request<dynamic>(const ApiRequest(
        path: '/weather?units=metric&apiKey=PATH-SECRET',
        queryParameters: {
          'city': 'Pune',
          'api_key': 'KEY-SECRET',
          'accessToken': 'TOKEN-SECRET',
          'tags': ['a', 'b'],
        },
      ));
    }
    expect(lines.all, isNot(contains('SECRET')));
    expect(lines.all, contains('units=metric'));
    expect(lines.all, contains('city=Pune&api_key=***&accessToken=***'));
    expect(lines.all, contains('tags=a&tags=b'));
    final curl = lines.lines.firstWhere((l) => l.startsWith('curl '));
    expect(
      curl,
      endsWith('"${server.baseUrl}/weather?units=metric&apiKey=***'
          '&city=Pune&api_key=***&accessToken=***&tags=a&tags=b"'),
    );
  });

  test(
      'API_PLUS-14: a failing CacheStore does not break requests (falls back '
      'to the network)', () async {
    final api = HttpAdapter(baseUrl: server.baseUrl, interceptors: [
      CacheInterceptor(
        config: CacheConfig(
          store: _BrokenStore(),
          enableStaleWhileRevalidate: true,
          enableMetrics: true,
        ),
      ),
    ]);
    addTearDown(api.close);

    final first =
        await api.request<Map<String, dynamic>>(const ApiRequest(path: '/p'));
    final second =
        await api.request<Map<String, dynamic>>(const ApiRequest(path: '/p'));
    expect(first.statusCode, 200);
    expect(second.data!['hit'], 2);

    // A network error is reported as such, not as the store's error.
    await server.close();
    await expectLater(
      api.request<dynamic>(const ApiRequest(path: '/p')),
      throwsA(isA<NetworkException>()),
    );
    server = await _Server.start();
  });

  for (final type in ApiClientType.values) {
    test(
        'API_PLUS-15: a long-lived ApiCancelToken does not retain completed '
        'requests (${type.name})', () async {
      server.handler = (req, hit) => req.uri.path == '/flaky' && hit == 1
          ? _json(req.response, {}, status: 503)
          : _json(req.response, {'ok': true});
      final screenToken = ApiCancelToken();
      final api = _adapter(type, server.baseUrl, [
        RetryInterceptor(config: _fastRetry()),
      ]);
      addTearDown(api.close);

      final posted =
          await _sendAndForget(api, screenToken, HttpMethod.post, '/upload');
      // Retried once: also covers the listener of the retry delay.
      final retried =
          await _sendAndForget(api, screenToken, HttpMethod.put, '/flaky');
      expect(server.hitsFor('/flaky'), 2);

      await _forceGC();
      expect(posted.target, isNull, reason: 'POST body still reachable');
      expect(retried.target, isNull, reason: 'PUT body still reachable');

      // The token still works for requests in flight.
      server.handler = (req, hit) async {
        await Future<void>.delayed(const Duration(seconds: 2));
        _json(req.response, {});
      };
      final pending = api.request<dynamic>(
        ApiRequest(path: '/slow', cancelToken: screenToken),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      screenToken.cancel('disposed');
      await expectLater(pending, throwsA(isA<CancellationException>()));
    });
  }

  test(
      'API_PLUS-16: CacheKeyGenerator produces the key the cache interceptor '
      'uses, so one entry can be invalidated', () async {
    final store = MemoryCacheStore();
    final api = HttpAdapter(baseUrl: server.baseUrl, interceptors: [
      CacheInterceptor(config: CacheConfig(store: store)),
    ]);
    addTearDown(api.close);

    const query = {'userId': 1, 'page': 2, 'filter': null};
    await api.request<dynamic>(
      const ApiRequest(path: '/posts', queryParameters: query),
    );
    final key = CacheKeyGenerator.generate('GET', '/posts', query);
    expect(key, 'GET:/posts:{"page":2,"userId":1}');
    expect(await store.containsKey(key), isTrue);

    await store.delete(key);
    await api.request<dynamic>(
      const ApiRequest(path: '/posts', queryParameters: query),
    );
    expect(server.hitsFor('/posts'), 2);
  });

  test('API_PLUS-17: a 304 revalidation counts as one request in CacheMetrics',
      () async {
    var version = 1;
    server.handler = (req, hit) {
      if (req.headers.value('if-none-match') == '"v$version"') {
        req.response.statusCode = 304;
        return;
      }
      _json(req.response, {
        'v': version
      }, headers: {
        'cache-control': 'max-age=0',
        'etag': '"v$version"',
      });
    };
    final cache = CacheInterceptor(
      config: CacheConfig(store: MemoryCacheStore(), enableMetrics: true),
    );
    final api = HttpAdapter(baseUrl: server.baseUrl, interceptors: [cache]);
    addTearDown(api.close);

    await api.request<dynamic>(const ApiRequest(path: '/m'));
    await api.request<dynamic>(const ApiRequest(path: '/m'));
    expect(cache.metrics.totalRequests, 2, reason: '${cache.metrics}');
    expect(cache.metrics.hits, 1);
    expect(cache.metrics.misses, 1);

    version = 2; // the revalidation returns new content: a miss
    final changed =
        await api.request<Map<String, dynamic>>(const ApiRequest(path: '/m'));
    expect(changed.data, {'v': 2});
    expect(cache.metrics.totalRequests, 3);
    expect(cache.metrics.misses, 2);
  });

  test('API_PLUS-18: HttpDateParser rejects impossible dates', () {
    expect(HttpDateParser.parse('Sat, 31 Feb 2024 08:49:37 GMT'), isNull);
    expect(HttpDateParser.parse('Mon, 01 Jan 2024 25:61:61 GMT'), isNull);
    expect(HttpDateParser.parse('Mon, 01 Jan 2024 23:60:00 GMT'), isNull);
    expect(HttpDateParser.parse('Mon, 00 Jan 2024 08:00:00 GMT'), isNull);
    expect(HttpDateParser.parse('Sunday, 32-Nov-94 08:49:37 GMT'), isNull);
    expect(HttpDateParser.parse('Sun Nov 31 08:49:37 1994'), isNull);

    expect(
      HttpDateParser.parse('Thu, 29 Feb 2024 23:59:59 GMT'),
      DateTime.utc(2024, 2, 29, 23, 59, 59),
    );
    // A leap second is clamped to :59.
    expect(
      HttpDateParser.parse('Sat, 31 Dec 2016 23:59:60 GMT'),
      DateTime.utc(2016, 12, 31, 23, 59, 59),
    );
    expect(
      HttpDateParser.parse('Sunday, 06-Nov-94 08:49:37 GMT'),
      DateTime.utc(1994, 11, 6, 8, 49, 37),
    );
  });

  test(
      'API_PLUS-19: a malformed absolute URL throws ConfigurationException '
      'instead of being sent to the base URL', () async {
    for (final type in ApiClientType.values) {
      final api = _adapter(type, server.baseUrl, [
        RetryInterceptor(config: _fastRetry()),
      ]);
      addTearDown(api.close);
      for (final path in ['http://[::1/users', 'http:///users']) {
        await expectLater(
          api.request<dynamic>(ApiRequest(path: path)),
          throwsA(isA<ConfigurationException>()),
          reason: '${type.name} $path',
        );
      }
      // Valid absolute URLs still bypass the base URL.
      final absolute = await api.request<Map<String, dynamic>>(
        ApiRequest(path: '${server.baseUrl}/absolute'),
      );
      expect(absolute.data!['path'], '/absolute');
    }
    expect(server.totalHits, 2, reason: 'only the valid absolute URLs');
  });

  group('Other QA observations', () {
    for (final kind in ['http', 'dio', 'retrofit']) {
      test("with retry, each attempt's error is logged once, in order ($kind)",
          () async {
        const failing = [500, 502, 503, 504];
        server.handler = (req, hit) => req.uri.path == '/fail'
            ? _json(req.response, {}, status: failing[hit - 1])
            : _json(req.response, {}, status: hit == 1 ? 500 : 200);
        final lines = _Lines();
        final logger = LoggerConfig(
          printer: lines,
          level: LogLevel.error,
          format: LogFormat.json,
        );
        Future<void> Function(String path) get;
        if (kind == 'retrofit') {
          final adapter = RetrofitAdapter(
            baseUrl: server.baseUrl,
            retryConfig: _fastRetry(),
            loggerConfig: logger,
          );
          addTearDown(adapter.close);
          get = (path) => adapter.client.get<dynamic>(path);
        } else {
          final api = ApiBuilder(server.baseUrl)
              .clientType(
                  kind == 'http' ? ApiClientType.http : ApiClientType.dio)
              .withRetry(_fastRetry())
              .withLogger(logger)
              .build();
          addTearDown(api.close);
          get = (path) => api.request<dynamic>(ApiRequest(path: path));
        }

        await expectLater(get('/fail'), throwsA(anything));
        await get('/recover');

        final errors = lines.lines
            .map((l) => jsonDecode(l) as Map<String, dynamic>)
            .where((record) => record['type'] == 'error')
            .map((record) => record['statusCode'])
            .toList();
        expect(errors, [...failing, 500]);
      });
    }

    test('InterceptorPipeline is public, so custom adapters get the pipeline',
        () async {
      final cache = CacheInterceptor(
        config: CacheConfig(store: MemoryCacheStore()),
      );
      final adapter = _ScriptedAdapter(
        [RetryInterceptor(config: _fastRetry()), cache],
        [503, 200],
      );
      final first = await adapter
          .request<Map<String, dynamic>>(const ApiRequest(path: '/custom'));
      expect(first.data, {'call': 2}, reason: 'retried once');
      expect(first.request!.headers['accept'], 'application/json');
      final second = await adapter
          .request<Map<String, dynamic>>(const ApiRequest(path: '/custom'));
      expect(second.data, {'call': 2}, reason: 'served from the cache');
      expect(adapter.calls, 2);
    });

    test(
        'LogFormat.json lines are all valid JSON (curl is a field), and curl '
        'commands use the full URL', () async {
      for (final type in ApiClientType.values) {
        final json = _Lines();
        final pretty = _Lines();
        final api = _adapter(type, server.baseUrl, [
          LoggerInterceptor(
            config: LoggerConfig(printer: json, format: LogFormat.json),
          ),
          LoggerInterceptor(
            config: LoggerConfig(printer: pretty, colors: false),
          ),
        ]);
        addTearDown(api.close);
        await api.request<dynamic>(const ApiRequest(
          path: '/users/1',
          headers: {'Authorization': 'secret'},
        ));
        final curl = 'curl -X GET -H "Authorization: ***" '
            '"${server.baseUrl}/users/1"';

        final records =
            json.lines.map((l) => jsonDecode(l) as Map<String, dynamic>);
        expect(records.map((r) => r['type']), ['request', 'response']);
        expect(records.first['curl'], curl, reason: type.name);
        expect(pretty.lines[1], curl, reason: type.name);
      }
    });

    test(
        'a cached response reports the current request; stale-while-'
        'revalidate does not expose its internal marker', () async {
      server.handler = (req, hit) => _json(req.response, {
            'v': hit
          }, headers: {
            'cache-control':
                req.uri.path == '/swr' ? 'max-age=0' : 'max-age=60',
          });
      final api = HttpAdapter(baseUrl: server.baseUrl, interceptors: [
        CacheInterceptor(
          config: CacheConfig(
            store: MemoryCacheStore(),
            enableStaleWhileRevalidate: true,
          ),
        ),
      ]);
      addTearDown(api.close);

      await api.request<dynamic>(
        const ApiRequest(path: '/fresh', headers: {'x-trace': '1'}),
      );
      final token = ApiCancelToken();
      final hit = await api.request<Map<String, dynamic>>(ApiRequest(
        path: '/fresh',
        headers: const {'x-trace': '2'},
        cancelToken: token,
      ));
      expect(hit.data, {'v': 1});
      expect(hit.request!.headers['x-trace'], '2');
      expect(hit.request!.cancelToken, same(token));

      await api.request<dynamic>(const ApiRequest(path: '/swr'));
      final stale = await api
          .request<Map<String, dynamic>>(const ApiRequest(path: '/swr'));
      expect(stale.data, {'v': 1});
      expect(stale.request!.extra.keys, isNot(contains('_apiPlusRevalidate')));
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(server.hitsFor('/swr'), 2, reason: 'background refresh');
    });

    test('copyWithout clears nullable fields that copyWith cannot', () {
      final token = ApiCancelToken();
      final request = ApiRequest(
        path: '/x',
        method: HttpMethod.post,
        body: const {'a': 1},
        connectTimeout: const Duration(seconds: 1),
        receiveTimeout: const Duration(seconds: 2),
        cancelToken: token,
      );
      expect(request.copyWith(body: null).body, {'a': 1});
      final cleared = request.copyWithout(
        body: true,
        connectTimeout: true,
        cancelToken: true,
      );
      expect(cleared.body, isNull);
      expect(cleared.connectTimeout, isNull);
      expect(cleared.cancelToken, isNull);
      expect(cleared.receiveTimeout, const Duration(seconds: 2));
      expect(cleared.method, HttpMethod.post);
      expect(request.copyWithout(), request);

      const response = ApiResponse<String>(
        data: 'x',
        statusCode: 200,
        statusMessage: 'OK',
        request: ApiRequest(path: '/x'),
      );
      final empty = response.copyWithout(data: true, request: true);
      expect(empty.data, isNull);
      expect(empty.request, isNull);
      expect(empty.statusMessage, 'OK');
    });
  });
}
