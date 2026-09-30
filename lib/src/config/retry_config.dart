import 'dart:math' as math;
import '../exceptions/api_exception.dart';
import '../interfaces/connectivity_checker.dart';
import '../interfaces/retry_strategy.dart';
import '../models/http_method.dart';

/// Defines the strategy for delay backoff between retry attempts.
///
/// Each strategy determines how the delay grows with subsequent attempts:
/// - [fixed]: Same delay every time
/// - [linear]: Delay grows proportionally (1×, 2×, 3×, ...)
/// - [exponential]: Delay doubles each time (1×, 2×, 4×, 8×, ...)
enum RetryBackoffStrategy {
  /// Wait a fixed amount of time between retries.
  ///
  /// Example with 1s base delay: 1s, 1s, 1s, 1s
  fixed,

  /// Increase the wait time linearly.
  ///
  /// Example with 1s base delay: 1s, 2s, 3s, 4s
  linear,

  /// Increase the wait time exponentially.
  ///
  /// Example with 1s base delay: 1s, 2s, 4s, 8s
  exponential,
}

/// Configuration for the retry interceptor.
///
/// Controls how and when failed requests are retried, including
/// backoff strategy, retry conditions, and timeout limits.
///
/// {@tool snippet}
/// ```dart
/// const config = RetryConfig(
///   maxRetries: 3,
///   backoffStrategy: RetryBackoffStrategy.exponential,
///   baseDelay: Duration(seconds: 1),
///   addJitter: true,
///   retryableStatusCodes: {408, 429, 500, 502, 503, 504},
/// );
/// ```
/// {@end-tool}
class RetryConfig {
  /// Maximum number of retry attempts.
  ///
  /// A value of 3 means the request will be attempted up to 4 times
  /// total (1 original + 3 retries).
  final int maxRetries;

  /// Base delay between retries.
  ///
  /// The actual delay depends on the [backoffStrategy] and [addJitter].
  final Duration baseDelay;

  /// Maximum delay allowed between any two retry attempts.
  ///
  /// Caps the calculated delay to prevent extremely long waits.
  final Duration maxDelay;

  /// Maximum total duration allowed for all retry attempts.
  ///
  /// If the total elapsed time since the first attempt exceeds this
  /// duration, no more retries are attempted. Set to `null` for no limit.
  final Duration? maxElapsedDuration;

  /// The backoff strategy to use for calculating delays.
  final RetryBackoffStrategy backoffStrategy;

  /// Whether to add random jitter to the delay.
  ///
  /// Jitter helps prevent the "thundering herd" problem when many
  /// clients retry simultaneously. Adds ±20% randomization.
  final bool addJitter;

  /// HTTP methods that are eligible for retry.
  ///
  /// Defaults to idempotent methods: GET, HEAD, OPTIONS, PUT, DELETE.
  /// POST and PATCH are excluded by default as they may not be safe
  /// to retry.
  final Set<HttpMethod> retryableMethods;

  /// HTTP status codes that should trigger a retry.
  ///
  /// Defaults to: 408 (Timeout), 429 (Too Many Requests),
  /// 500 (Internal Server Error), 502 (Bad Gateway),
  /// 503 (Service Unavailable), 504 (Gateway Timeout).
  final Set<int> retryableStatusCodes;

  /// Custom evaluator for whether a specific [ApiException] should be retried.
  ///
  /// Takes precedence over [retryableStatusCodes] when provided.
  /// Return `true` to retry, `false` to skip.
  final bool Function(ApiException)? shouldRetryException;

  /// Callback invoked each time a retry attempt begins.
  ///
  /// Receives the retry `retryCount` (1-indexed) and the `delay`
  /// that will be waited before the attempt. Called before waiting.
  final void Function(int retryCount, Duration delay)? onRetry;

  /// Whether to respect the `Retry-After` header in the response.
  ///
  /// When `true`, the delay from the Retry-After header takes precedence
  /// over the calculated backoff delay if it is larger.
  final bool respectRetryAfter;

  /// Optional custom retry strategy.
  ///
  /// When provided, overrides [backoffStrategy], [maxRetries], and
  /// [shouldRetryException] with custom logic.
  final RetryStrategy? customStrategy;

  /// Optional connectivity checker for network-aware retries.
  ///
  /// When provided, the retry interceptor checks connectivity before
  /// each retry attempt. If the device is offline, the retry is skipped.
  final ConnectivityChecker? connectivityChecker;

  /// Whether to collect retry metrics.
  ///
  /// When `true`, the retry interceptor tracks success/failure counts,
  /// total delay time, and other statistics accessible via
  /// `RetryInterceptor.metrics`.
  final bool enableMetrics;

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
    this.customStrategy,
    this.connectivityChecker,
    this.enableMetrics = false,
  });

  /// Calculates the delay for a given retry [attempt] (1-indexed).
  ///
  /// Returns [Duration.zero] for invalid attempt numbers.
  /// Applies the backoff strategy, optional jitter, and caps at [maxDelay].
  Duration calculateDelay(int attempt) {
    if (attempt <= 0) return Duration.zero;

    // Delegate to custom strategy if provided
    if (customStrategy != null) {
      final delay = customStrategy!.getDelay(attempt);
      if (delay.isNegative) return Duration.zero;
      return delay > maxDelay ? maxDelay : delay;
    }

    double delayMs = baseDelay.inMilliseconds.toDouble();

    switch (backoffStrategy) {
      case RetryBackoffStrategy.fixed:
        break;
      case RetryBackoffStrategy.linear:
        delayMs *= attempt;
      case RetryBackoffStrategy.exponential:
        delayMs *= math.pow(2.0, attempt - 1);
    }

    if (addJitter) {
      final random = math.Random();
      // Add random jitter of ±20%
      final jitter = (random.nextDouble() * 0.4) - 0.2;
      delayMs = delayMs * (1 + jitter);
    }

    // Cap before converting: large attempts overflow to infinity.
    final maxMs = maxDelay.inMilliseconds.toDouble();
    if (delayMs.isNaN || delayMs > maxMs) delayMs = maxMs;
    if (delayMs < 0) delayMs = 0;
    final delay = Duration(milliseconds: delayMs.round());

    return delay;
  }
}
