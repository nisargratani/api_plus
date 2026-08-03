import 'package:meta/meta.dart';
import '../core/api_request.dart';
import '../core/api_response.dart';

/// Base class for all exceptions thrown by the api_plus package.
@immutable
abstract class ApiException implements Exception {
  /// A human-readable error message.
  final String message;

  /// The original request that caused the exception, if available.
  final ApiRequest? request;

  /// The response received, if available.
  final ApiResponse<dynamic>? response;

  /// The original exception or error object, if any.
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
    final buffer = StringBuffer('ApiException: $message');
    if (error != null) buffer.write('\nCaused by: $error');
    if (response != null) buffer.write('\nStatus code: ${response!.statusCode}');
    return buffer.toString();
  }
}

/// Thrown when a network connection fails (e.g., timeout, DNS resolution).
class NetworkException extends ApiException {
  /// Creates a [NetworkException].
  const NetworkException({
    required super.message,
    super.request,
    super.error,
    super.stackTrace,
  });
}

/// Thrown when the server returns an error response (e.g., 400 or 500 status codes).
class ServerException extends ApiException {
  /// Creates a [ServerException].
  const ServerException({
    required super.message,
    required super.request,
    required super.response,
    super.error,
    super.stackTrace,
  });

  /// Factory constructor that returns a specific [ServerException] subclass 
  /// based on the HTTP status code of the response.
  factory ServerException.fromResponse({
    required String message,
    required ApiRequest request,
    required ApiResponse<dynamic> response,
    Object? error,
    StackTrace? stackTrace,
  }) {
    switch (response.statusCode) {
      case 400:
        return BadRequestException(message: message, request: request, response: response, error: error, stackTrace: stackTrace);
      case 401:
        return UnauthorizedException(message: message, request: request, response: response, error: error, stackTrace: stackTrace);
      case 403:
        return ForbiddenException(message: message, request: request, response: response, error: error, stackTrace: stackTrace);
      case 404:
        return NotFoundException(message: message, request: request, response: response, error: error, stackTrace: stackTrace);
      case 409:
        return ConflictException(message: message, request: request, response: response, error: error, stackTrace: stackTrace);
      case 500:
        return InternalServerException(message: message, request: request, response: response, error: error, stackTrace: stackTrace);
      default:
        return ServerException(message: message, request: request, response: response, error: error, stackTrace: stackTrace);
    }
  }
}

/// Thrown for HTTP 400 Bad Request.
class BadRequestException extends ServerException {
  const BadRequestException({required super.message, required super.request, required super.response, super.error, super.stackTrace});
}

/// Thrown for HTTP 401 Unauthorized.
class UnauthorizedException extends ServerException {
  const UnauthorizedException({required super.message, required super.request, required super.response, super.error, super.stackTrace});
}

/// Thrown for HTTP 403 Forbidden.
class ForbiddenException extends ServerException {
  const ForbiddenException({required super.message, required super.request, required super.response, super.error, super.stackTrace});
}

/// Thrown for HTTP 404 Not Found.
class NotFoundException extends ServerException {
  const NotFoundException({required super.message, required super.request, required super.response, super.error, super.stackTrace});
}

/// Thrown for HTTP 409 Conflict.
class ConflictException extends ServerException {
  const ConflictException({required super.message, required super.request, required super.response, super.error, super.stackTrace});
}

/// Thrown for HTTP 500 Internal Server Error.
class InternalServerException extends ServerException {
  const InternalServerException({required super.message, required super.request, required super.response, super.error, super.stackTrace});
}

/// Thrown when serialization or deserialization of request/response bodies fails.
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
class RetryLimitExceededException extends ApiException {
  /// Creates a [RetryLimitExceededException].
  const RetryLimitExceededException({
    required super.message,
    super.request,
    super.error,
    super.stackTrace,
  });
}

/// Thrown when a configuration error occurs in the setup of api_plus.
class ConfigurationException extends ApiException {
  /// Creates a [ConfigurationException].
  const ConfigurationException({
    required super.message,
    super.error,
    super.stackTrace,
  });
}

/// Thrown when an error occurs in the caching layer.
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
