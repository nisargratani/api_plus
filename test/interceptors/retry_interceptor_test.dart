import 'package:api_plus/api_plus.dart';
import 'package:test/test.dart';

void main() {
  group('RetryInterceptor', () {
    test('initializes retry state on first request', () async {
      final interceptor = RetryInterceptor();
      const request = ApiRequest(path: '/test');

      final result = await interceptor.onRequest(request);
      expect(result, isA<ApiRequest>());
      final modifiedRequest = result as ApiRequest;
      expect(modifiedRequest.extra['_retryCount'], 0);
      expect(modifiedRequest.extra['_firstAttemptTime'], isNotNull);
    });

    test('preserves existing retry state', () async {
      final interceptor = RetryInterceptor();
      const request = ApiRequest(
        path: '/test',
        extra: {'_retryCount': 2, '_firstAttemptTime': 1000},
      );

      final result = await interceptor.onRequest(request);
      expect(result, isA<ApiRequest>());
      final modifiedRequest = result as ApiRequest;
      expect(modifiedRequest.extra['_retryCount'], 2);
    });

    test('onResponse passes through', () async {
      final interceptor = RetryInterceptor();
      const response = ApiResponse<String>(
        data: 'test',
        statusCode: 200,
      );

      final result = await interceptor.onResponse(response);
      expect(result.data, 'test');
      expect(result.statusCode, 200);
    });

    test('does not retry when request is null', () async {
      final interceptor = RetryInterceptor();
      const error = NetworkException(message: 'No connection');

      final result = await interceptor.onError(error, (_) async {
        throw StateError('Should not be called');
      });

      expect(result, isA<ApiException>());
    });

    test('does not retry non-retryable methods', () async {
      final interceptor = RetryInterceptor(
        config: const RetryConfig(
          retryableMethods: {HttpMethod.get},
        ),
      );
      const request = ApiRequest(
        path: '/test',
        method: HttpMethod.post,
        extra: {'_retryCount': 0, '_firstAttemptTime': 0},
      );
      const error = NetworkException(message: 'Error', request: request);

      final result = await interceptor.onError(error, (_) async {
        throw StateError('Should not be called');
      });

      expect(result, isA<ApiException>());
    });

    test('does not retry when maxRetries exceeded', () async {
      final interceptor = RetryInterceptor(
        config: const RetryConfig(maxRetries: 2),
      );
      const request = ApiRequest(
        path: '/test',
        extra: {'_retryCount': 2, '_firstAttemptTime': 0},
      );
      const error = NetworkException(message: 'Error', request: request);

      final result = await interceptor.onError(error, (_) async {
        throw StateError('Should not be called');
      });

      expect(result, isA<ApiException>());
    });

    test('retries on retryable NetworkException', () async {
      final interceptor = RetryInterceptor(
        config: const RetryConfig(
          maxRetries: 3,
          baseDelay: Duration.zero,
          addJitter: false,
        ),
      );
      final request = ApiRequest(
        path: '/test',
        extra: {
          '_retryCount': 0,
          '_firstAttemptTime': DateTime.now().millisecondsSinceEpoch,
        },
      );
      final error = NetworkException(message: 'Error', request: request);

      final result = await interceptor.onError(error, (req) async {
        return const ApiResponse<String>(
          data: 'recovered',
          statusCode: 200,
        );
      });

      expect(result, isA<ApiResponse<dynamic>>());
      expect((result as ApiResponse<dynamic>).data, 'recovered');
    });

    test('retries on retryable status code', () async {
      final interceptor = RetryInterceptor(
        config: const RetryConfig(
          maxRetries: 3,
          baseDelay: Duration.zero,
          addJitter: false,
        ),
      );
      final request = ApiRequest(
        path: '/test',
        extra: {
          '_retryCount': 0,
          '_firstAttemptTime': DateTime.now().millisecondsSinceEpoch,
        },
      );
      final error = ServerException(
        message: 'Server error',
        request: request,
        response: ApiResponse<void>(statusCode: 503, request: request),
      );

      final result = await interceptor.onError(error, (req) async {
        return const ApiResponse<String>(data: 'ok', statusCode: 200);
      });

      expect(result, isA<ApiResponse<dynamic>>());
    });

    test('does not retry on non-retryable status code', () async {
      final interceptor = RetryInterceptor(
        config: const RetryConfig(
          maxRetries: 3,
          retryableStatusCodes: {500},
        ),
      );
      final request = ApiRequest(
        path: '/test',
        extra: {
          '_retryCount': 0,
          '_firstAttemptTime': DateTime.now().millisecondsSinceEpoch,
        },
      );
      final error = ServerException(
        message: 'Not found',
        request: request,
        response: ApiResponse<void>(statusCode: 404, request: request),
      );

      final result = await interceptor.onError(error, (_) async {
        throw StateError('Should not be called');
      });

      expect(result, isA<ApiException>());
    });

    test('calls onRetry callback', () async {
      int calledWith = 0;
      final interceptor = RetryInterceptor(
        config: RetryConfig(
          maxRetries: 3,
          baseDelay: Duration.zero,
          addJitter: false,
          onRetry: (count, delay) {
            calledWith = count;
          },
        ),
      );
      final request = ApiRequest(
        path: '/test',
        extra: {
          '_retryCount': 0,
          '_firstAttemptTime': DateTime.now().millisecondsSinceEpoch,
        },
      );
      final error = NetworkException(message: 'Error', request: request);

      await interceptor.onError(error, (req) async {
        return const ApiResponse<void>(statusCode: 200);
      });

      expect(calledWith, 1);
    });

    test('uses custom shouldRetryException', () async {
      final interceptor = RetryInterceptor(
        config: RetryConfig(
          maxRetries: 3,
          baseDelay: Duration.zero,
          addJitter: false,
          shouldRetryException: (e) => e.message == 'retry me',
        ),
      );
      final request = ApiRequest(
        path: '/test',
        extra: {
          '_retryCount': 0,
          '_firstAttemptTime': DateTime.now().millisecondsSinceEpoch,
        },
      );

      // Should retry
      final retryError =
          NetworkException(message: 'retry me', request: request);
      final result1 = await interceptor.onError(retryError, (req) async {
        return const ApiResponse<void>(statusCode: 200);
      });
      expect(result1, isA<ApiResponse<dynamic>>());

      // Should NOT retry
      final noRetryError =
          NetworkException(message: 'do not retry', request: request);
      final result2 = await interceptor.onError(noRetryError, (_) async {
        throw StateError('Should not be called');
      });
      expect(result2, isA<ApiException>());
    });

    test('tracks metrics when enabled', () async {
      final interceptor = RetryInterceptor(
        config: const RetryConfig(
          maxRetries: 3,
          baseDelay: Duration.zero,
          addJitter: false,
          enableMetrics: true,
        ),
      );
      final request = ApiRequest(
        path: '/test',
        extra: {
          '_retryCount': 0,
          '_firstAttemptTime': DateTime.now().millisecondsSinceEpoch,
        },
      );
      final error = NetworkException(message: 'Error', request: request);

      await interceptor.onError(error, (req) async {
        return const ApiResponse<void>(statusCode: 200);
      });

      expect(interceptor.metrics.totalRetries, 1);
      expect(interceptor.metrics.successfulRetries, 1);
    });

    test('handles invoker throwing ApiException', () async {
      final interceptor = RetryInterceptor(
        config: const RetryConfig(
          maxRetries: 3,
          baseDelay: Duration.zero,
          addJitter: false,
        ),
      );
      final request = ApiRequest(
        path: '/test',
        extra: {
          '_retryCount': 0,
          '_firstAttemptTime': DateTime.now().millisecondsSinceEpoch,
        },
      );
      final error = NetworkException(message: 'Error', request: request);

      final result = await interceptor.onError(error, (req) async {
        throw const NetworkException(message: 'Still failing');
      });

      expect(result, isA<NetworkException>());
    });

    test('handles invoker throwing unexpected error', () async {
      final interceptor = RetryInterceptor(
        config: const RetryConfig(
          maxRetries: 3,
          baseDelay: Duration.zero,
          addJitter: false,
        ),
      );
      final request = ApiRequest(
        path: '/test',
        extra: {
          '_retryCount': 0,
          '_firstAttemptTime': DateTime.now().millisecondsSinceEpoch,
        },
      );
      final error = NetworkException(message: 'Error', request: request);

      final result = await interceptor.onError(error, (req) async {
        throw Exception('Unexpected');
      });

      expect(result, isA<NetworkException>());
    });
  });

  group('RetryMetrics', () {
    test('starts at zero', () {
      final metrics = RetryMetrics();
      expect(metrics.totalRetries, 0);
      expect(metrics.successfulRetries, 0);
      expect(metrics.failedRetries, 0);
      expect(metrics.totalDelayTime, Duration.zero);
      expect(metrics.successRate, 0.0);
    });

    test('records retries', () {
      final metrics = RetryMetrics();
      metrics.recordRetry(const Duration(seconds: 1));
      metrics.recordRetry(const Duration(seconds: 2));

      expect(metrics.totalRetries, 2);
      expect(metrics.totalDelayTime, const Duration(seconds: 3));
    });

    test('records success', () {
      final metrics = RetryMetrics();
      metrics.recordRetry(Duration.zero);
      metrics.recordSuccess();

      expect(metrics.successfulRetries, 1);
      expect(metrics.successRate, 100.0);
    });

    test('records failure', () {
      final metrics = RetryMetrics();
      metrics.recordRetry(Duration.zero);
      metrics.recordFailure();

      expect(metrics.failedRetries, 1);
      expect(metrics.successRate, 0.0);
    });

    test('calculates success rate correctly', () {
      final metrics = RetryMetrics();
      metrics.recordRetry(Duration.zero);
      metrics.recordSuccess();
      metrics.recordRetry(Duration.zero);
      metrics.recordFailure();

      expect(metrics.successRate, 50.0);
    });

    test('reset clears all counters', () {
      final metrics = RetryMetrics();
      metrics.recordRetry(const Duration(seconds: 1));
      metrics.recordSuccess();
      metrics.reset();

      expect(metrics.totalRetries, 0);
      expect(metrics.successfulRetries, 0);
      expect(metrics.totalDelayTime, Duration.zero);
    });

    test('toString returns meaningful info', () {
      final metrics = RetryMetrics();
      metrics.recordRetry(Duration.zero);
      metrics.recordSuccess();

      final str = metrics.toString();
      expect(str, contains('total: 1'));
      expect(str, contains('success: 1'));
    });
  });
}
