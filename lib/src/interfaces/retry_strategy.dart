import '../core/api_request.dart';
import '../exceptions/api_exception.dart';

/// Interface for implementing custom retry strategies.
///
/// Use this to implement retry logic that goes beyond the built-in
/// backoff strategies (fixed, linear, exponential). For example,
/// you might implement circuit breaker patterns or adaptive retry
/// strategies based on error history.
///
/// {@tool snippet}
/// ```dart
/// class CircuitBreakerStrategy implements RetryStrategy {
///   int _failureCount = 0;
///   static const _threshold = 5;
///
///   @override
///   bool shouldRetry(ApiException error, int attempt, ApiRequest request) {
///     if (_failureCount >= _threshold) return false;
///     return attempt < 3;
///   }
///
///   @override
///   Duration getDelay(int attempt) {
///     return Duration(seconds: attempt * 2);
///   }
/// }
/// ```
/// {@end-tool}
abstract class RetryStrategy {
  /// Determines whether the request should be retried.
  ///
  /// Called after each failed attempt with the [error] that occurred,
  /// the current [attempt] number (1-indexed), and the original [request].
  bool shouldRetry(ApiException error, int attempt, ApiRequest request);

  /// Returns the delay to wait before the next retry [attempt].
  ///
  /// The [attempt] parameter is 1-indexed (first retry is attempt 1).
  Duration getDelay(int attempt);
}
