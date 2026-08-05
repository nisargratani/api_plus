import 'dart:async';
import '../config/retry_config.dart';
import '../core/api_request.dart';
import '../core/api_response.dart';
import '../exceptions/api_exception.dart';
import '../interfaces/api_interceptor.dart';
import '../models/retry_metrics.dart';
import '../utils/http_date_parser.dart';

/// An interceptor that retries failed requests based on a [RetryConfig].
///
/// Supports multiple backoff strategies, custom retry conditions,
/// connectivity-aware retries, Retry-After header support, and
/// retry metrics collection.
///
/// {@tool snippet}
/// ```dart
/// final retry = RetryInterceptor(
///   config: const RetryConfig(
///     maxRetries: 3,
///     backoffStrategy: RetryBackoffStrategy.exponential,
///     addJitter: true,
///   ),
/// );
/// ```
/// {@end-tool}
class RetryInterceptor implements ApiInterceptor {
  /// The retry configuration.
  final RetryConfig config;

  /// Retry metrics for monitoring.
  ///
  /// Only populated when [RetryConfig.enableMetrics] is `true`.
  final RetryMetrics metrics = RetryMetrics();

  /// Creates a [RetryInterceptor] with the given [config].
  RetryInterceptor({this.config = const RetryConfig()});

  @override
  Future<dynamic> onRequest(ApiRequest request) async {
    // Initialize retry state if not present
    if (!request.extra.containsKey('_retryCount')) {
      final newExtra = Map<String, dynamic>.from(request.extra);
      newExtra['_retryCount'] = 0;
      newExtra['_firstAttemptTime'] = DateTime.now().millisecondsSinceEpoch;
      return request.copyWith(extra: newExtra);
    }
    return request;
  }

  @override
  Future<ApiResponse<dynamic>> onResponse(
    ApiResponse<dynamic> response,
  ) async {
    return response;
  }

  @override
  Future<dynamic> onError(
    ApiException error,
    Future<ApiResponse<dynamic>> Function(ApiRequest) invoker,
  ) async {
    final request = error.request;
    if (request == null) {
      return error;
    }

    final int currentAttempt = request.extra['_retryCount'] as int? ?? 0;
    final int? firstAttemptMs = request.extra['_firstAttemptTime'] as int?;
    final DateTime? firstAttemptTime = firstAttemptMs != null
        ? DateTime.fromMillisecondsSinceEpoch(firstAttemptMs)
        : null;

    if (!_shouldRetry(error, currentAttempt, firstAttemptTime, request)) {
      if (config.enableMetrics && currentAttempt > 0) {
        metrics.recordFailure();
      }
      return error;
    }

    // Check connectivity before retrying
    if (config.connectivityChecker != null) {
      final isConnected = await config.connectivityChecker!.isConnected;
      if (!isConnected) {
        return error;
      }
    }

    // Calculate delay
    Duration delay = config.calculateDelay(currentAttempt + 1);

    // Check for Retry-After header
    if (config.respectRetryAfter && error.response != null) {
      final retryAfterValues = error.response!.headers['retry-after'];
      if (retryAfterValues != null && retryAfterValues.isNotEmpty) {
        final parsedDelay = _parseRetryAfter(retryAfterValues.first);
        if (parsedDelay != null && parsedDelay > delay) {
          delay = parsedDelay;
        }
      }
    }

    // Record metrics
    if (config.enableMetrics) {
      metrics.recordRetry(delay);
    }

    // Wait for the delay
    if (delay > Duration.zero) {
      await Future<void>.delayed(delay);
    }

    // Trigger onRetry callback
    config.onRetry?.call(currentAttempt + 1, delay);

    // Update request state
    final newExtra = Map<String, dynamic>.from(request.extra);
    newExtra['_retryCount'] = currentAttempt + 1;
    final newRequest = request.copyWith(extra: newExtra);

    // Retry the request via the invoker
    try {
      final response = await invoker(newRequest);
      if (config.enableMetrics) {
        metrics.recordSuccess();
      }
      return response;
    } on ApiException catch (e) {
      return e;
    } catch (e) {
      return NetworkException(
        message: 'Unexpected error during retry: $e',
        request: newRequest,
        error: e,
      );
    }
  }

  bool _shouldRetry(
    ApiException error,
    int attempt,
    DateTime? firstAttemptTime,
    ApiRequest request,
  ) {
    // Check custom strategy first
    if (config.customStrategy != null) {
      return config.customStrategy!.shouldRetry(error, attempt + 1, request);
    }

    if (attempt >= config.maxRetries) {
      return false;
    }

    // Check max elapsed duration
    if (config.maxElapsedDuration != null && firstAttemptTime != null) {
      final elapsed = DateTime.now().difference(firstAttemptTime);
      if (elapsed > config.maxElapsedDuration!) {
        return false;
      }
    }

    // Check if method is retryable
    if (!config.retryableMethods.contains(request.method)) {
      return false;
    }

    // Check custom exception evaluator
    if (config.shouldRetryException != null) {
      return config.shouldRetryException!(error);
    }

    // Check retryable status codes
    if (error is ServerException && error.response != null) {
      if (config.retryableStatusCodes.contains(error.response!.statusCode)) {
        return true;
      }
    }

    // Network exceptions are typically retryable
    if (error is NetworkException) {
      return true;
    }

    return false;
  }

  Duration? _parseRetryAfter(String retryAfter) {
    // Try parsing as seconds first
    final seconds = int.tryParse(retryAfter);
    if (seconds != null) {
      return Duration(seconds: seconds);
    }

    // Try parsing as HTTP-date
    final date = HttpDateParser.parse(retryAfter);
    if (date != null) {
      final diff = date.difference(DateTime.now());
      return diff.isNegative ? Duration.zero : diff;
    }

    return null;
  }
}
