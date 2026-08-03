import 'dart:math' as math;
import '../exceptions/api_exception.dart';
import '../models/http_method.dart';

/// Defines the strategy for delay backoff between retries.
enum RetryBackoffStrategy {
  /// Wait a fixed amount of time between retries.
  fixed,
  /// Increase the wait time linearly (e.g., 1s, 2s, 3s).
  linear,
  /// Increase the wait time exponentially (e.g., 1s, 2s, 4s, 8s).
  exponential,
}

/// Configuration for the Retry interceptor.
class RetryConfig {
  /// Maximum number of retries.
  final int maxRetries;

  /// Base delay between retries.
  final Duration baseDelay;

  /// Maximum delay allowed.
  final Duration maxDelay;

  /// Maximum total duration allowed for all retries.
  final Duration? maxElapsedDuration;

  /// The backoff strategy to use.
  final RetryBackoffStrategy backoffStrategy;

  /// Whether to add random jitter to the delay to prevent thundering herd.
  final bool addJitter;

  /// HTTP methods that should be retried (idempotent methods).
  final Set<HttpMethod> retryableMethods;

  /// HTTP status codes that should trigger a retry (e.g., 500, 502, 503, 504).
  final Set<int> retryableStatusCodes;

  /// Evaluates whether a specific [ApiException] should be retried.
  final bool Function(ApiException)? shouldRetryException;

  /// Callback when a retry occurs.
  final void Function(int retryCount, Duration delay)? onRetry;

  /// Whether to respect the `Retry-After` header.
  final bool respectRetryAfter;

  /// Creates a [RetryConfig].
  const RetryConfig({
    this.maxRetries = 3,
    this.baseDelay = const Duration(seconds: 1),
    this.maxDelay = const Duration(seconds: 30),
    this.maxElapsedDuration,
    this.backoffStrategy = RetryBackoffStrategy.exponential,
    this.addJitter = true,
    this.retryableMethods = const {
      HttpMethod.get,
      HttpMethod.head,
      HttpMethod.options,
      HttpMethod.put,
      HttpMethod.delete,
    },
    this.retryableStatusCodes = const {408, 429, 500, 502, 503, 504},
    this.shouldRetryException,
    this.onRetry,
    this.respectRetryAfter = true,
  });

  /// Calculates the delay for a given retry attempt (1-indexed).
  Duration calculateDelay(int attempt) {
    if (attempt <= 0) return Duration.zero;

    double delayInMilliseconds = baseDelay.inMilliseconds.toDouble();

    switch (backoffStrategy) {
      case RetryBackoffStrategy.fixed:
        break;
      case RetryBackoffStrategy.linear:
        delayInMilliseconds *= attempt;
        break;
      case RetryBackoffStrategy.exponential:
        delayInMilliseconds *= math.pow(2, attempt - 1);
        break;
    }

    if (addJitter) {
      final random = math.Random();
      // Add a random jitter of +/- 20%
      final jitter = (random.nextDouble() * 0.4) - 0.2;
      delayInMilliseconds = delayInMilliseconds * (1 + jitter);
    }

    Duration delay = Duration(milliseconds: delayInMilliseconds.round());
    if (delay > maxDelay) {
      delay = maxDelay;
    }
    
    return delay;
  }
}
