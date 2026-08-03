import 'dart:async';
import '../config/retry_config.dart';
import '../core/api_request.dart';
import '../core/api_response.dart';
import '../exceptions/api_exception.dart';
import '../interfaces/api_interceptor.dart';

/// An interceptor that retries failed requests based on a [RetryConfig].
class RetryInterceptor implements ApiInterceptor {
  final RetryConfig config;

  /// Creates a [RetryInterceptor] with the given [config].
  RetryInterceptor({this.config = const RetryConfig()});

  @override
  Future<dynamic> onRequest(ApiRequest request) async {
    // Initialize retry state if not present
    if (!request.extra.containsKey('retryCount')) {
      final newExtra = Map<String, dynamic>.from(request.extra);
      newExtra['retryCount'] = 0;
      newExtra['firstAttemptTime'] = DateTime.now();
      return request.copyWith(extra: newExtra);
    }
    return request;
  }

  @override
  Future<ApiResponse<dynamic>> onResponse(ApiResponse<dynamic> response) async {
    // Check if status code requires retry (e.g. 503) and wasn't thrown as exception yet
    // Typically adapters throw ServerException for bad status codes before onResponse interceptors,
    // but if it wasn't thrown, we don't intercept it here since onResponse doesn't have an invoker.
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

    final int currentAttempt = request.extra['retryCount'] as int? ?? 0;
    final DateTime? firstAttemptTime = request.extra['firstAttemptTime'] as DateTime?;

    if (!_shouldRetry(error, currentAttempt, firstAttemptTime)) {
      return error; // Let the error propagate
    }

    // Determine delay
    Duration delay = config.calculateDelay(currentAttempt + 1);

    // Check for Retry-After header
    if (config.respectRetryAfter && error.response != null) {
      final retryAfter = error.response!.headers['retry-after']?.first;
      if (retryAfter != null) {
        final parsedDelay = _parseRetryAfter(retryAfter);
        if (parsedDelay != null && parsedDelay > delay) {
          delay = parsedDelay;
        }
      }
    }

    // Wait for the delay
    if (delay > Duration.zero) {
      await Future<void>.delayed(delay);
    }

    // Trigger onRetry callback
    config.onRetry?.call(currentAttempt + 1, delay);

    // Update request state
    final newExtra = Map<String, dynamic>.from(request.extra);
    newExtra['retryCount'] = currentAttempt + 1;
    final newRequest = request.copyWith(extra: newExtra);

    // Retry the request via the invoker
    try {
      final response = await invoker(newRequest);
      return response; // Recovered
    } on ApiException catch (e) {
      // Re-evaluate in the next catch block by propagating
      return e; 
    } catch (e) {
      // Wrap unexpected errors
      return NetworkException(
        message: 'Unexpected error during retry: $e',
        request: newRequest,
        error: e,
      );
    }
  }

  bool _shouldRetry(ApiException error, int attempt, DateTime? firstAttemptTime) {
    if (attempt >= config.maxRetries) {
      return false;
    }

    if (config.maxElapsedDuration != null && firstAttemptTime != null) {
      final elapsed = DateTime.now().difference(firstAttemptTime);
      if (elapsed > config.maxElapsedDuration!) {
        return false;
      }
    }

    final request = error.request;
    if (request == null || !config.retryableMethods.contains(request.method)) {
      return false;
    }

    if (config.shouldRetryException != null) {
      return config.shouldRetryException!(error);
    }

    if (error is ServerException && error.response != null) {
      if (config.retryableStatusCodes.contains(error.response!.statusCode)) {
        return true;
      }
    }

    if (error is NetworkException) {
      // Network exceptions (timeouts, connection issues) are typically retryable
      return true;
    }

    return false;
  }

  Duration? _parseRetryAfter(String retryAfter) {
    // Retry-After can be a delay in seconds or an HTTP-date
    final seconds = int.tryParse(retryAfter);
    if (seconds != null) {
      return Duration(seconds: seconds);
    }
    try {
      final date = DateTime.parse(retryAfter); // HTTP-date parsing is complex, this is simplified
      final diff = date.difference(DateTime.now());
      if (diff.isNegative) return Duration.zero;
      return diff;
    } catch (_) {
      return null;
    }
  }
}
