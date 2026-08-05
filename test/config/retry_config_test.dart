import 'package:api_plus/api_plus.dart';
import 'package:test/test.dart';

void main() {
  group('RetryConfig', () {
    test('has sensible defaults', () {
      const config = RetryConfig();
      expect(config.maxRetries, 3);
      expect(config.baseDelay, const Duration(seconds: 1));
      expect(config.maxDelay, const Duration(seconds: 30));
      expect(config.backoffStrategy, RetryBackoffStrategy.exponential);
      expect(config.addJitter, isTrue);
      expect(config.respectRetryAfter, isTrue);
      expect(config.enableMetrics, isFalse);
      expect(config.customStrategy, isNull);
      expect(config.connectivityChecker, isNull);
      expect(config.retryableStatusCodes, {408, 429, 500, 502, 503, 504});
      expect(config.retryableMethods, contains(HttpMethod.get));
      expect(config.retryableMethods, isNot(contains(HttpMethod.post)));
    });

    group('calculateDelay', () {
      test('returns zero for attempt <= 0', () {
        const config = RetryConfig(addJitter: false);
        expect(config.calculateDelay(0), Duration.zero);
        expect(config.calculateDelay(-1), Duration.zero);
      });

      test('fixed strategy returns same delay', () {
        const config = RetryConfig(
          backoffStrategy: RetryBackoffStrategy.fixed,
          baseDelay: Duration(seconds: 2),
          addJitter: false,
        );
        expect(config.calculateDelay(1), const Duration(seconds: 2));
        expect(config.calculateDelay(2), const Duration(seconds: 2));
        expect(config.calculateDelay(3), const Duration(seconds: 2));
      });

      test('linear strategy scales linearly', () {
        const config = RetryConfig(
          backoffStrategy: RetryBackoffStrategy.linear,
          baseDelay: Duration(seconds: 1),
          addJitter: false,
        );
        expect(config.calculateDelay(1), const Duration(seconds: 1));
        expect(config.calculateDelay(2), const Duration(seconds: 2));
        expect(config.calculateDelay(3), const Duration(seconds: 3));
      });

      test('exponential strategy doubles each time', () {
        const config = RetryConfig(
          backoffStrategy: RetryBackoffStrategy.exponential,
          baseDelay: Duration(seconds: 1),
          addJitter: false,
        );
        expect(config.calculateDelay(1), const Duration(seconds: 1));
        expect(config.calculateDelay(2), const Duration(seconds: 2));
        expect(config.calculateDelay(3), const Duration(seconds: 4));
        expect(config.calculateDelay(4), const Duration(seconds: 8));
      });

      test('caps at maxDelay', () {
        const config = RetryConfig(
          backoffStrategy: RetryBackoffStrategy.exponential,
          baseDelay: Duration(seconds: 10),
          maxDelay: Duration(seconds: 15),
          addJitter: false,
        );
        expect(config.calculateDelay(1), const Duration(seconds: 10));
        expect(config.calculateDelay(2), const Duration(seconds: 15));
        expect(config.calculateDelay(3), const Duration(seconds: 15));
      });

      test('jitter modifies delay within range', () {
        const config = RetryConfig(
          backoffStrategy: RetryBackoffStrategy.fixed,
          baseDelay: Duration(milliseconds: 1000),
          addJitter: true,
        );
        // Run multiple times to test jitter variance
        final delays = <int>{};
        for (int i = 0; i < 20; i++) {
          final delay = config.calculateDelay(1);
          delays.add(delay.inMilliseconds);
          // Jitter is ±20%, so 800ms to 1200ms
          expect(delay.inMilliseconds, greaterThanOrEqualTo(800));
          expect(delay.inMilliseconds, lessThanOrEqualTo(1200));
        }
      });
    });
  });

  group('RetryBackoffStrategy', () {
    test('has all expected values', () {
      expect(RetryBackoffStrategy.values, hasLength(3));
      expect(RetryBackoffStrategy.values, contains(RetryBackoffStrategy.fixed));
      expect(
          RetryBackoffStrategy.values, contains(RetryBackoffStrategy.linear));
      expect(RetryBackoffStrategy.values,
          contains(RetryBackoffStrategy.exponential));
    });
  });
}
