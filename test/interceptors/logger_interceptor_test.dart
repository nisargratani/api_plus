import 'dart:convert';
import 'package:api_plus/api_plus.dart';
import 'package:test/test.dart';

void main() {
  group('LoggerInterceptor', () {
    late List<String> logOutput;
    late LoggerInterceptor interceptor;

    setUp(() {
      logOutput = [];
    });

    LoggerConfig configWith({
      LogLevel level = LogLevel.verbose,
      LogFormat format = LogFormat.pretty,
      bool colors = false,
      bool printCurl = false,
      bool printExecutionTime = false,
    }) {
      return LoggerConfig(
        level: level,
        format: format,
        colors: colors,
        printCurl: printCurl,
        printExecutionTime: printExecutionTime,
        printer: _TestLogPrinter(logOutput),
      );
    }

    group('onRequest', () {
      test('logs request in pretty format', () async {
        interceptor = LoggerInterceptor(
          config: configWith(format: LogFormat.pretty),
        );
        const request = ApiRequest(
          path: '/users',
          method: HttpMethod.get,
          headers: {'Accept': 'application/json'},
        );

        await interceptor.onRequest(request);

        final output = logOutput.join('\n');
        expect(output, contains('Request'));
        expect(output, contains('GET'));
        expect(output, contains('/users'));
      });

      test('logs request in compact format', () async {
        interceptor = LoggerInterceptor(
          config: configWith(format: LogFormat.compact),
        );
        const request = ApiRequest(path: '/users', method: HttpMethod.post);

        await interceptor.onRequest(request);

        expect(logOutput.first, contains('POST'));
        expect(logOutput.first, contains('/users'));
      });

      test('logs request in JSON format', () async {
        interceptor = LoggerInterceptor(
          config: configWith(format: LogFormat.json),
        );
        const request = ApiRequest(path: '/users', method: HttpMethod.get);

        await interceptor.onRequest(request);

        final jsonOutput = jsonDecode(logOutput.first) as Map<String, dynamic>;
        expect(jsonOutput['type'], 'request');
        expect(jsonOutput['method'], 'GET');
        expect(jsonOutput['url'], '/users');
      });

      test('does not log when level is none', () async {
        interceptor = LoggerInterceptor(
          config: configWith(level: LogLevel.none),
        );
        const request = ApiRequest(path: '/users');

        final result = await interceptor.onRequest(request);

        expect(logOutput, isEmpty);
        expect(result, isA<ApiRequest>());
      });

      test('masks sensitive headers', () async {
        interceptor = LoggerInterceptor(
          config: configWith(format: LogFormat.pretty),
        );
        const request = ApiRequest(
          path: '/users',
          headers: {
            'Authorization': 'Bearer secret_token',
            'Accept': 'application/json',
          },
        );

        await interceptor.onRequest(request);

        final output = logOutput.join('\n');
        expect(output, contains('***'));
        expect(output, isNot(contains('secret_token')));
        expect(output, contains('application/json'));
      });

      test('generates curl command', () async {
        interceptor = LoggerInterceptor(
          config: configWith(
            format: LogFormat.compact,
            printCurl: true,
            colors: false,
          ),
        );
        const request = ApiRequest(
          path: '/users',
          method: HttpMethod.post,
          headers: {'Content-Type': 'application/json'},
          body: '{"name":"test"}',
        );

        await interceptor.onRequest(request);

        final curlOutput = logOutput.firstWhere((l) => l.contains('curl'));
        expect(curlOutput, contains('curl -X POST'));
        expect(curlOutput, contains('-H "Content-Type: application/json"'));
      });

      test('respects request filter', () async {
        interceptor = LoggerInterceptor(
          config: LoggerConfig(
            level: LogLevel.verbose,
            printer: _TestLogPrinter(logOutput),
            requestFilter: (req) => req.path.startsWith('/api'),
          ),
        );

        await interceptor.onRequest(
          const ApiRequest(path: '/health'),
        );
        expect(logOutput, isEmpty);

        await interceptor.onRequest(
          const ApiRequest(path: '/api/users'),
        );
        expect(logOutput, isNotEmpty);
      });

      test('attaches request start time for execution time tracking', () async {
        interceptor = LoggerInterceptor(
          config: configWith(printExecutionTime: true),
        );
        const request = ApiRequest(path: '/test');

        final result = await interceptor.onRequest(request);
        final modifiedRequest = result as ApiRequest;
        expect(modifiedRequest.extra['_requestStartTime'], isNotNull);
      });
    });

    group('onResponse', () {
      test('logs response in pretty format', () async {
        interceptor = LoggerInterceptor(
          config: configWith(format: LogFormat.pretty),
        );
        const response = ApiResponse<String>(
          data: 'test',
          statusCode: 200,
          statusMessage: 'OK',
        );

        await interceptor.onResponse(response);

        final output = logOutput.join('\n');
        expect(output, contains('Response'));
        expect(output, contains('200'));
      });

      test('logs response in JSON format', () async {
        interceptor = LoggerInterceptor(
          config: configWith(format: LogFormat.json),
        );
        const response = ApiResponse<String>(
          data: 'test',
          statusCode: 200,
        );

        await interceptor.onResponse(response);

        final jsonOutput = jsonDecode(logOutput.first) as Map<String, dynamic>;
        expect(jsonOutput['type'], 'response');
        expect(jsonOutput['statusCode'], 200);
      });

      test('filters by status code', () async {
        interceptor = LoggerInterceptor(
          config: LoggerConfig(
            level: LogLevel.verbose,
            printer: _TestLogPrinter(logOutput),
            filterStatusCodes: const {500},
          ),
        );

        await interceptor.onResponse(
          const ApiResponse<void>(statusCode: 200),
        );
        expect(logOutput, isEmpty);

        await interceptor.onResponse(
          const ApiResponse<void>(statusCode: 500),
        );
        expect(logOutput, isNotEmpty);
      });
    });

    group('onError', () {
      test('logs error', () async {
        interceptor = LoggerInterceptor(
          config: configWith(format: LogFormat.pretty),
        );
        const error = NetworkException(message: 'Connection refused');

        final result = await interceptor.onError(error, (_) async {
          throw StateError('unreachable');
        });

        expect(logOutput.join('\n'), contains('Connection refused'));
        expect(result, isA<ApiException>());
      });

      test('logs error in JSON format', () async {
        interceptor = LoggerInterceptor(
          config: configWith(format: LogFormat.json),
        );
        const error = NetworkException(message: 'Timeout');

        await interceptor.onError(error, (_) async {
          throw StateError('unreachable');
        });

        final jsonOutput = jsonDecode(logOutput.first) as Map<String, dynamic>;
        expect(jsonOutput['type'], 'error');
        expect(jsonOutput['message'], 'Timeout');
      });

      test('does not log when level below error', () async {
        interceptor = LoggerInterceptor(
          config: configWith(level: LogLevel.none),
        );
        const error = NetworkException(message: 'Error');

        await interceptor.onError(error, (_) async {
          throw StateError('unreachable');
        });

        expect(logOutput, isEmpty);
      });
    });
  });

  group('CacheMetrics', () {
    test('starts at zero', () {
      final metrics = CacheMetrics();
      expect(metrics.hits, 0);
      expect(metrics.misses, 0);
      expect(metrics.evictions, 0);
      expect(metrics.staleHits, 0);
      expect(metrics.totalRequests, 0);
      expect(metrics.hitRate, 0.0);
    });

    test('records hits and misses', () {
      final metrics = CacheMetrics();
      metrics.recordHit();
      metrics.recordHit();
      metrics.recordMiss();

      expect(metrics.hits, 2);
      expect(metrics.misses, 1);
      expect(metrics.totalRequests, 3);
      expect(metrics.hitRate, closeTo(66.67, 0.1));
    });

    test('records evictions and stale hits', () {
      final metrics = CacheMetrics();
      metrics.recordEviction();
      metrics.recordStaleHit();

      expect(metrics.evictions, 1);
      expect(metrics.staleHits, 1);
    });

    test('reset clears all', () {
      final metrics = CacheMetrics();
      metrics.recordHit();
      metrics.recordMiss();
      metrics.recordEviction();
      metrics.recordStaleHit();
      metrics.reset();

      expect(metrics.hits, 0);
      expect(metrics.misses, 0);
      expect(metrics.evictions, 0);
      expect(metrics.staleHits, 0);
    });

    test('toString returns meaningful info', () {
      final metrics = CacheMetrics();
      metrics.recordHit();
      final str = metrics.toString();
      expect(str, contains('hits: 1'));
    });
  });
}

class _TestLogPrinter implements LogPrinter {
  final List<String> output;

  _TestLogPrinter(this.output);

  @override
  void log(String message) {
    output.add(message);
  }
}
