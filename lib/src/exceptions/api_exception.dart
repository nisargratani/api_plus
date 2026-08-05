import 'package:meta/meta.dart';
import '../core/api_request.dart';
import '../core/api_response.dart';

/// Base class for all exceptions thrown by the `api_plus` package.
///
/// All exceptions in this package extend [ApiException], providing a
/// consistent interface for error handling. Each exception carries:
/// - A human-readable [message]
/// - An optional reference to the original [request]
/// - An optional [response] if one was received
/// - The original [error] object that caused this exception
/// - The [stackTrace] from the original error
///
/// {@tool snippet}
/// ```dart
/// try {
///   final response = await adapter.request(request);
/// } on ServerException catch (e) {
///   print('Server error: ${e.message}');
///   print('Status: ${e.response?.statusCode}');
/// } on NetworkException catch (e) {
///   print('Network error: ${e.message}');
/// } on ApiException catch (e) {
///   print('API error: ${e.message}');
/// }
/// ```
/// {@end-tool}
@immutable
abstract class ApiException implements Exception {
  /// A human-readable error message describing what went wrong.
  final String message;

  /// The original request that caused this exception, if available.
  final ApiRequest? request;

  /// The response received from the server, if available.
  ///
  /// This is typically populated for [ServerException] and its subclasses.
  final ApiResponse<dynamic>? response;

  /// The original exception or error object that caused this exception.
  final Object? error;

  /// The stack trace associated with the original error.
  final StackTrace? stackTrace;

  /// Creates a new [ApiException].
  const ApiException({
    required this.message,
    this.request,
    this.response,
    this.error,
    this.stackTrace,
  });

  @override
  String toString() {
    final buffer = StringBuffer('$runtimeType: $message');
    if (error != null) buffer.write('\nCaused by: $error');
    if (response != null) {
      buffer.write('\nStatus code: ${response!.statusCode}');
    }
    return buffer.toString();
  }
}

// ---------------------------------------------------------------------------
// Network Exceptions
// ---------------------------------------------------------------------------

/// Thrown when a network connection fails.
///
/// This includes DNS resolution failures, connection timeouts,
/// socket errors, and other transport-level failures.
class NetworkException extends ApiException {
  /// Creates a [NetworkException].
  const NetworkException({
    required super.message,
    super.request,
    super.error,
    super.stackTrace,
  });
}

/// Thrown when a request times out.
///
/// This covers connection timeouts, send timeouts, and receive timeouts.
class TimeoutException extends NetworkException {
  /// The type of timeout that occurred.
  final TimeoutType timeoutType;

  /// Creates a [TimeoutException].
  const TimeoutException({
    required super.message,
    required this.timeoutType,
    super.request,
    super.error,
    super.stackTrace,
  });
}

/// Describes the type of timeout that occurred.
enum TimeoutType {
  /// The connection to the server timed out.
  connection,

  /// Sending the request body timed out.
  send,

  /// Receiving the response timed out.
  receive,
}

/// Thrown when a request is cancelled by the caller.
class CancellationException extends ApiException {
  /// Creates a [CancellationException].
  const CancellationException({
    required super.message,
    super.request,
    super.error,
    super.stackTrace,
  });
}

// ---------------------------------------------------------------------------
// Server Exceptions
// ---------------------------------------------------------------------------

/// Thrown when the server returns an error response.
///
/// Use [ServerException.fromResponse] to automatically create the appropriate
/// subclass based on the HTTP status code.
///
/// {@tool snippet}
/// ```dart
/// final exception = ServerException.fromResponse(
///   message: 'Not found',
///   request: request,
///   response: response,
/// );
/// // Returns NotFoundException for 404, UnauthorizedException for 401, etc.
/// ```
/// {@end-tool}
class ServerException extends ApiException {
  /// Creates a [ServerException].
  const ServerException({
    required super.message,
    required super.request,
    required super.response,
    super.error,
    super.stackTrace,
  });

  /// Creates a specific [ServerException] subclass based on the response
  /// HTTP status code.
  ///
  /// Maps common status codes to their respective exception types:
  /// - 400 → [BadRequestException]
  /// - 401 → [UnauthorizedException]
  /// - 403 → [ForbiddenException]
  /// - 404 → [NotFoundException]
  /// - 405 → [MethodNotAllowedException]
  /// - 408 → [RequestTimeoutException]
  /// - 409 → [ConflictException]
  /// - 413 → [RequestEntityTooLargeException]
  /// - 422 → [UnprocessableEntityException]
  /// - 429 → [TooManyRequestsException]
  /// - 500 → [InternalServerException]
  /// - 502 → [BadGatewayException]
  /// - 503 → [ServiceUnavailableException]
  /// - 504 → [GatewayTimeoutException]
  ///
  /// Any other status code returns a generic [ServerException].
  factory ServerException.fromResponse({
    required String message,
    required ApiRequest request,
    required ApiResponse<dynamic> response,
    Object? error,
    StackTrace? stackTrace,
  }) {
    switch (response.statusCode) {
      case 400:
        return BadRequestException(
          message: message,
          request: request,
          response: response,
          error: error,
          stackTrace: stackTrace,
        );
      case 401:
        return UnauthorizedException(
          message: message,
          request: request,
          response: response,
          error: error,
          stackTrace: stackTrace,
        );
      case 403:
        return ForbiddenException(
          message: message,
          request: request,
          response: response,
          error: error,
          stackTrace: stackTrace,
        );
      case 404:
        return NotFoundException(
          message: message,
          request: request,
          response: response,
          error: error,
          stackTrace: stackTrace,
        );
      case 405:
        return MethodNotAllowedException(
          message: message,
          request: request,
          response: response,
          error: error,
          stackTrace: stackTrace,
        );
      case 408:
        return RequestTimeoutException(
          message: message,
          request: request,
          response: response,
          error: error,
          stackTrace: stackTrace,
        );
      case 409:
        return ConflictException(
          message: message,
          request: request,
          response: response,
          error: error,
          stackTrace: stackTrace,
        );
      case 413:
        return RequestEntityTooLargeException(
          message: message,
          request: request,
          response: response,
          error: error,
          stackTrace: stackTrace,
        );
      case 422:
        return UnprocessableEntityException(
          message: message,
          request: request,
          response: response,
          error: error,
          stackTrace: stackTrace,
        );
      case 429:
        return TooManyRequestsException(
          message: message,
          request: request,
          response: response,
          error: error,
          stackTrace: stackTrace,
        );
      case 500:
        return InternalServerException(
          message: message,
          request: request,
          response: response,
          error: error,
          stackTrace: stackTrace,
        );
      case 502:
        return BadGatewayException(
          message: message,
          request: request,
          response: response,
          error: error,
          stackTrace: stackTrace,
        );
      case 503:
        return ServiceUnavailableException(
          message: message,
          request: request,
          response: response,
          error: error,
          stackTrace: stackTrace,
        );
      case 504:
        return GatewayTimeoutException(
          message: message,
          request: request,
          response: response,
          error: error,
          stackTrace: stackTrace,
        );
      default:
        return ServerException(
          message: message,
          request: request,
          response: response,
          error: error,
          stackTrace: stackTrace,
        );
    }
  }
}

/// Thrown for HTTP 400 Bad Request.
///
/// Indicates the server cannot process the request due to a client error
/// (e.g., malformed syntax, invalid request parameters).
class BadRequestException extends ServerException {
  /// Creates a [BadRequestException].
  const BadRequestException({
    required super.message,
    required super.request,
    required super.response,
    super.error,
    super.stackTrace,
  });
}

/// Thrown for HTTP 401 Unauthorized.
///
/// Indicates that the request requires authentication, or the provided
/// credentials are invalid.
class UnauthorizedException extends ServerException {
  /// Creates an [UnauthorizedException].
  const UnauthorizedException({
    required super.message,
    required super.request,
    required super.response,
    super.error,
    super.stackTrace,
  });
}

/// Thrown for HTTP 403 Forbidden.
///
/// Indicates the server understood the request but refuses to authorize it.
class ForbiddenException extends ServerException {
  /// Creates a [ForbiddenException].
  const ForbiddenException({
    required super.message,
    required super.request,
    required super.response,
    super.error,
    super.stackTrace,
  });
}

/// Thrown for HTTP 404 Not Found.
///
/// Indicates the requested resource could not be found on the server.
class NotFoundException extends ServerException {
  /// Creates a [NotFoundException].
  const NotFoundException({
    required super.message,
    required super.request,
    required super.response,
    super.error,
    super.stackTrace,
  });
}

/// Thrown for HTTP 405 Method Not Allowed.
///
/// Indicates the HTTP method used is not supported for the requested resource.
class MethodNotAllowedException extends ServerException {
  /// Creates a [MethodNotAllowedException].
  const MethodNotAllowedException({
    required super.message,
    required super.request,
    required super.response,
    super.error,
    super.stackTrace,
  });
}

/// Thrown for HTTP 408 Request Timeout.
///
/// Indicates the server timed out waiting for the request.
class RequestTimeoutException extends ServerException {
  /// Creates a [RequestTimeoutException].
  const RequestTimeoutException({
    required super.message,
    required super.request,
    required super.response,
    super.error,
    super.stackTrace,
  });
}

/// Thrown for HTTP 409 Conflict.
///
/// Indicates a conflict with the current state of the resource
/// (e.g., concurrent modification).
class ConflictException extends ServerException {
  /// Creates a [ConflictException].
  const ConflictException({
    required super.message,
    required super.request,
    required super.response,
    super.error,
    super.stackTrace,
  });
}

/// Thrown for HTTP 413 Request Entity Too Large.
///
/// Indicates the request payload exceeds the server's size limit.
class RequestEntityTooLargeException extends ServerException {
  /// Creates a [RequestEntityTooLargeException].
  const RequestEntityTooLargeException({
    required super.message,
    required super.request,
    required super.response,
    super.error,
    super.stackTrace,
  });
}

/// Thrown for HTTP 422 Unprocessable Entity.
///
/// Indicates the server understands the content type and syntax, but
/// cannot process the contained instructions (e.g., validation errors).
class UnprocessableEntityException extends ServerException {
  /// Creates an [UnprocessableEntityException].
  const UnprocessableEntityException({
    required super.message,
    required super.request,
    required super.response,
    super.error,
    super.stackTrace,
  });
}

/// Thrown for HTTP 429 Too Many Requests.
///
/// Indicates the user has sent too many requests in a given time period
/// (rate limiting).
class TooManyRequestsException extends ServerException {
  /// Creates a [TooManyRequestsException].
  const TooManyRequestsException({
    required super.message,
    required super.request,
    required super.response,
    super.error,
    super.stackTrace,
  });
}

/// Thrown for HTTP 500 Internal Server Error.
///
/// Indicates an unexpected condition on the server that prevented it
/// from fulfilling the request.
class InternalServerException extends ServerException {
  /// Creates an [InternalServerException].
  const InternalServerException({
    required super.message,
    required super.request,
    required super.response,
    super.error,
    super.stackTrace,
  });
}

/// Thrown for HTTP 502 Bad Gateway.
///
/// Indicates the server received an invalid response from an upstream server.
class BadGatewayException extends ServerException {
  /// Creates a [BadGatewayException].
  const BadGatewayException({
    required super.message,
    required super.request,
    required super.response,
    super.error,
    super.stackTrace,
  });
}

/// Thrown for HTTP 503 Service Unavailable.
///
/// Indicates the server is temporarily unable to handle the request
/// (e.g., maintenance or overload).
class ServiceUnavailableException extends ServerException {
  /// Creates a [ServiceUnavailableException].
  const ServiceUnavailableException({
    required super.message,
    required super.request,
    required super.response,
    super.error,
    super.stackTrace,
  });
}

/// Thrown for HTTP 504 Gateway Timeout.
///
/// Indicates the server did not receive a timely response from an
/// upstream server.
class GatewayTimeoutException extends ServerException {
  /// Creates a [GatewayTimeoutException].
  const GatewayTimeoutException({
    required super.message,
    required super.request,
    required super.response,
    super.error,
    super.stackTrace,
  });
}

// ---------------------------------------------------------------------------
// Data/Processing Exceptions
// ---------------------------------------------------------------------------

/// Thrown when serialization or deserialization of request/response bodies fails.
///
/// This can occur when:
/// - JSON parsing fails
/// - Type casting fails
/// - A custom serializer throws an error
class SerializationException extends ApiException {
  /// Creates a [SerializationException].
  const SerializationException({
    required super.message,
    super.request,
    super.response,
    super.error,
    super.stackTrace,
  });
}

/// Thrown when retry limits are exceeded.
///
/// Contains information about the number of attempts made and the
/// total elapsed time.
class RetryLimitExceededException extends ApiException {
  /// The number of retry attempts that were made.
  final int attemptsMade;

  /// The total elapsed duration across all retry attempts.
  final Duration? totalElapsed;

  /// Creates a [RetryLimitExceededException].
  const RetryLimitExceededException({
    required super.message,
    this.attemptsMade = 0,
    this.totalElapsed,
    super.request,
    super.error,
    super.stackTrace,
  });
}

/// Thrown when a configuration error occurs in the setup of `api_plus`.
///
/// This typically indicates programmer error, such as missing required
/// configuration or incompatible settings.
class ConfigurationException extends ApiException {
  /// Creates a [ConfigurationException].
  const ConfigurationException({
    required super.message,
    super.error,
    super.stackTrace,
  });
}

/// Thrown when an error occurs in the caching layer.
///
/// This can occur during read, write, or eviction operations on
/// the cache store.
class CacheException extends ApiException {
  /// Creates a [CacheException].
  const CacheException({
    required super.message,
    super.request,
    super.response,
    super.error,
    super.stackTrace,
  });
}
