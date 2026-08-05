/// Tracks metrics about retry behavior for monitoring and debugging.
///
/// Provides insight into how the retry system is performing, including
/// success rates, total attempts, and timing information.
///
/// {@tool snippet}
/// ```dart
/// final metrics = retryInterceptor.metrics;
/// print('Total retries: ${metrics.totalRetries}');
/// print('Success rate: ${metrics.successRate}%');
/// ```
/// {@end-tool}
class RetryMetrics {
  int _totalRetries = 0;
  int _successfulRetries = 0;
  int _failedRetries = 0;
  Duration _totalDelayTime = Duration.zero;

  /// Total number of retry attempts made.
  int get totalRetries => _totalRetries;

  /// Number of retry attempts that succeeded.
  int get successfulRetries => _successfulRetries;

  /// Number of retry attempts that failed (exhausted all retries).
  int get failedRetries => _failedRetries;

  /// Total time spent waiting between retries.
  Duration get totalDelayTime => _totalDelayTime;

  /// Success rate as a percentage (0.0 to 100.0).
  ///
  /// Returns 0.0 if no retries have been attempted.
  double get successRate {
    if (_totalRetries == 0) return 0.0;
    return (_successfulRetries / _totalRetries) * 100.0;
  }

  /// Records a retry attempt.
  ///
  /// Called internally by the retry interceptor.
  void recordRetry(Duration delay) {
    _totalRetries++;
    _totalDelayTime += delay;
  }

  /// Records that a retry sequence succeeded.
  ///
  /// Called internally by the retry interceptor.
  void recordSuccess() {
    _successfulRetries++;
  }

  /// Records that a retry sequence failed (all retries exhausted).
  ///
  /// Called internally by the retry interceptor.
  void recordFailure() {
    _failedRetries++;
  }

  /// Resets all metrics to zero.
  void reset() {
    _totalRetries = 0;
    _successfulRetries = 0;
    _failedRetries = 0;
    _totalDelayTime = Duration.zero;
  }

  @override
  String toString() => 'RetryMetrics(total: $_totalRetries, '
      'success: $_successfulRetries, '
      'failed: $_failedRetries, '
      'successRate: ${successRate.toStringAsFixed(1)}%)';
}
