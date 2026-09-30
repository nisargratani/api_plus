import 'dart:async';
import '../config/retry_config.dart';
import '../core/api_cancel_token.dart';
import '../core/api_request.dart';
import '../core/api_response.dart';
import '../core/internal_keys.dart';
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

  /// Retries the failed request until it succeeds, retries are exhausted,
  /// or the error is not retryable.
  ///
  /// Each retry is sent through [invoker], i.e. through the adapter's
  /// complete interceptor pipeline, so other interceptors (logging, caching)
  /// observe every attempt. Returns the successful [ApiResponse], or the
  /// [ApiException] of the last attempt.
  @override
  Future<dynamic> onError(
    ApiException error,
    Future<ApiResponse<dynamic>> Function(ApiRequest) invoker,
  ) async {
    final request = error.request;
    if (request == null) {
      return error;
    }
    // This attempt was sent by a retry loop that is already running further
    // up the call stack; that loop decides whether to try again.
    if (request.extra[retryAttemptExtraKey] == true) {
      return error;
    }
    // Cancelled requests are never retried.
    final cancelToken = request.cancelToken;
    if (error is CancellationException || (cancelToken?.isCancelled ?? false)) {
      return error;
    }

    var attempt = request.extra['_retryCount'] as int? ?? 0;
    final int? firstAttemptMs = request.extra['_firstAttemptTime'] as int?;
    final DateTime? firstAttemptTime = firstAttemptMs != null
        ? DateTime.fromMillisecondsSinceEpoch(firstAttemptMs)
        : null;

    ApiException lastError = error;
    var retried = false;

    while (_shouldRetry(lastError, attempt, firstAttemptTime, request)) {
      // Check connectivity before retrying
      if (config.connectivityChecker != null &&
          !await config.connectivityChecker!.isConnected) {
        break;
      }

      final delay = _delayFor(lastError, attempt + 1);
      config.onRetry?.call(attempt + 1, delay);
      if (!await _wait(delay, cancelToken)) {
        // Cancelled while waiting: the retry never happened.
        return cancellationFor(request);
      }
      if (config.enableMetrics) {
        metrics.recordRetry(delay);
      }

      attempt++;
      retried = true;
      final newRequest = withExtras(request, {
        '_retryCount': attempt,
        retryAttemptExtraKey: true,
      });

      try {
        final response = await invoker(newRequest);
        if (config.enableMetrics) {
          metrics.recordSuccess();
        }
        return response;
      } on ApiException catch (e) {
        lastError = e;
        if (e is CancellationException) break;
      } catch (e, stackTrace) {
        lastError = NetworkException(
          message: 'Unexpected error during retry: $e',
          request: newRequest,
          error: e,
          stackTrace: stackTrace,
        );
      }
    }

    if (config.enableMetrics &&
        (retried || attempt > 0) &&
        lastError is! CancellationException) {
      metrics.recordFailure();
    }
    return lastError;
  }

  /// Waits for [delay]. Returns `false` if [cancelToken] is cancelled first.
  static Future<bool> _wait(Duration delay, ApiCancelToken? cancelToken) {
    if (cancelToken?.isCancelled ?? false) return Future.value(false);
    if (delay <= Duration.zero) return Future.value(true);
    final completer = Completer<bool>();
    final timer = Timer(delay, () {
      if (!completer.isCompleted) completer.complete(true);
    });
    cancelToken?.whenCancelled.then((_) {
      timer.cancel();
      if (!completer.isCompleted) completer.complete(false);
    });
    return completer.future;
  }

  Duration _delayFor(ApiException error, int attempt) {
    var delay = config.calculateDelay(attempt);
    final retryAfterValues = error.response?.headers['retry-after'];
    if (config.respectRetryAfter &&
        retryAfterValues != null &&
        retryAfterValues.isNotEmpty) {
      final parsedDelay = _parseRetryAfter(retryAfterValues.first);
      if (parsedDelay != null && parsedDelay > delay) {
        delay = parsedDelay;
      }
    }
    return delay;
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
    final seconds = int.tryParse(retryAfter.trim());
    if (seconds != null) {
      return seconds <= 0 ? Duration.zero : Duration(seconds: seconds);
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
