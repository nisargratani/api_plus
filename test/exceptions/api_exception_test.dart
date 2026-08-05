import 'package:api_plus/api_plus.dart';
import 'package:test/test.dart';

void main() {
  group('ApiException', () {
    test('toString shows message', () {
      const exception = NetworkException(message: 'Connection failed');
      expect(exception.toString(), contains('Connection failed'));
    });

    test('toString shows error when present', () {
      const exception = NetworkException(
        message: 'Connection failed',
        error: 'underlying error',
      );
      final str = exception.toString();
      expect(str, contains('Connection failed'));
      expect(str, contains('underlying error'));
    });

    test('toString shows status code when response present', () {
      const exception = ServerException(
        message: 'Server error',
        request: ApiRequest(path: '/test'),
        response: ApiResponse<void>(statusCode: 500),
      );
      expect(exception.toString(), contains('500'));
    });
  });

  group('NetworkException', () {
    test('creates with message', () {
      const e = NetworkException(message: 'No internet');
      expect(e.message, 'No internet');
      expect(e.request, isNull);
      expect(e.response, isNull);
    });

    test('is an ApiException', () {
      const e = NetworkException(message: 'No internet');
      expect(e, isA<ApiException>());
    });
  });

  group('TimeoutException', () {
    test('creates with timeout type', () {
      const e = TimeoutException(
        message: 'Connection timed out',
        timeoutType: TimeoutType.connection,
      );
      expect(e.message, 'Connection timed out');
      expect(e.timeoutType, TimeoutType.connection);
    });

    test('is a NetworkException', () {
      const e = TimeoutException(
        message: 'Timeout',
        timeoutType: TimeoutType.send,
      );
      expect(e, isA<NetworkException>());
      expect(e, isA<ApiException>());
    });
  });

  group('CancellationException', () {
    test('creates with message', () {
      const e = CancellationException(message: 'Cancelled');
      expect(e.message, 'Cancelled');
    });

    test('is an ApiException', () {
      const e = CancellationException(message: 'Cancelled');
      expect(e, isA<ApiException>());
    });
  });

  group('ServerException', () {
    test('creates with required fields', () {
      const e = ServerException(
        message: 'Server error',
        request: ApiRequest(path: '/test'),
        response: ApiResponse<void>(statusCode: 500),
      );
      expect(e.message, 'Server error');
      expect(e.response!.statusCode, 500);
    });

    group('fromResponse factory', () {
      ApiRequest request() => const ApiRequest(path: '/test');

      test('maps 400 to BadRequestException', () {
        final e = ServerException.fromResponse(
          message: 'Bad request',
          request: request(),
          response: ApiResponse<void>(statusCode: 400, request: request()),
        );
        expect(e, isA<BadRequestException>());
      });

      test('maps 401 to UnauthorizedException', () {
        final e = ServerException.fromResponse(
          message: 'Unauthorized',
          request: request(),
          response: ApiResponse<void>(statusCode: 401, request: request()),
        );
        expect(e, isA<UnauthorizedException>());
      });

      test('maps 403 to ForbiddenException', () {
        final e = ServerException.fromResponse(
          message: 'Forbidden',
          request: request(),
          response: ApiResponse<void>(statusCode: 403, request: request()),
        );
        expect(e, isA<ForbiddenException>());
      });

      test('maps 404 to NotFoundException', () {
        final e = ServerException.fromResponse(
          message: 'Not found',
          request: request(),
          response: ApiResponse<void>(statusCode: 404, request: request()),
        );
        expect(e, isA<NotFoundException>());
      });

      test('maps 405 to MethodNotAllowedException', () {
        final e = ServerException.fromResponse(
          message: 'Method not allowed',
          request: request(),
          response: ApiResponse<void>(statusCode: 405, request: request()),
        );
        expect(e, isA<MethodNotAllowedException>());
      });

      test('maps 408 to RequestTimeoutException', () {
        final e = ServerException.fromResponse(
          message: 'Timeout',
          request: request(),
          response: ApiResponse<void>(statusCode: 408, request: request()),
        );
        expect(e, isA<RequestTimeoutException>());
      });

      test('maps 409 to ConflictException', () {
        final e = ServerException.fromResponse(
          message: 'Conflict',
          request: request(),
          response: ApiResponse<void>(statusCode: 409, request: request()),
        );
        expect(e, isA<ConflictException>());
      });

      test('maps 413 to RequestEntityTooLargeException', () {
        final e = ServerException.fromResponse(
          message: 'Too large',
          request: request(),
          response: ApiResponse<void>(statusCode: 413, request: request()),
        );
        expect(e, isA<RequestEntityTooLargeException>());
      });

      test('maps 422 to UnprocessableEntityException', () {
        final e = ServerException.fromResponse(
          message: 'Unprocessable',
          request: request(),
          response: ApiResponse<void>(statusCode: 422, request: request()),
        );
        expect(e, isA<UnprocessableEntityException>());
      });

      test('maps 429 to TooManyRequestsException', () {
        final e = ServerException.fromResponse(
          message: 'Rate limited',
          request: request(),
          response: ApiResponse<void>(statusCode: 429, request: request()),
        );
        expect(e, isA<TooManyRequestsException>());
      });

      test('maps 500 to InternalServerException', () {
        final e = ServerException.fromResponse(
          message: 'Internal',
          request: request(),
          response: ApiResponse<void>(statusCode: 500, request: request()),
        );
        expect(e, isA<InternalServerException>());
      });

      test('maps 502 to BadGatewayException', () {
        final e = ServerException.fromResponse(
          message: 'Bad gateway',
          request: request(),
          response: ApiResponse<void>(statusCode: 502, request: request()),
        );
        expect(e, isA<BadGatewayException>());
      });

      test('maps 503 to ServiceUnavailableException', () {
        final e = ServerException.fromResponse(
          message: 'Service unavailable',
          request: request(),
          response: ApiResponse<void>(statusCode: 503, request: request()),
        );
        expect(e, isA<ServiceUnavailableException>());
      });

      test('maps 504 to GatewayTimeoutException', () {
        final e = ServerException.fromResponse(
          message: 'Gateway timeout',
          request: request(),
          response: ApiResponse<void>(statusCode: 504, request: request()),
        );
        expect(e, isA<GatewayTimeoutException>());
      });

      test('maps unknown status to generic ServerException', () {
        final e = ServerException.fromResponse(
          message: 'Unknown',
          request: request(),
          response: ApiResponse<void>(statusCode: 418, request: request()),
        );
        expect(e, isA<ServerException>());
        expect(e, isNot(isA<BadRequestException>()));
      });

      test('preserves error and stackTrace', () {
        final trace = StackTrace.current;
        final e = ServerException.fromResponse(
          message: 'Error',
          request: request(),
          response: ApiResponse<void>(statusCode: 500, request: request()),
          error: 'original error',
          stackTrace: trace,
        );
        expect(e.error, 'original error');
        expect(e.stackTrace, trace);
      });
    });
  });

  group('SerializationException', () {
    test('is an ApiException', () {
      const e = SerializationException(message: 'Parse failed');
      expect(e, isA<ApiException>());
      expect(e.message, 'Parse failed');
    });
  });

  group('RetryLimitExceededException', () {
    test('tracks attempts made', () {
      const e = RetryLimitExceededException(
        message: 'Max retries',
        attemptsMade: 3,
        totalElapsed: Duration(seconds: 10),
      );
      expect(e.attemptsMade, 3);
      expect(e.totalElapsed, const Duration(seconds: 10));
    });

    test('defaults to 0 attempts', () {
      const e = RetryLimitExceededException(message: 'Max retries');
      expect(e.attemptsMade, 0);
      expect(e.totalElapsed, isNull);
    });
  });

  group('ConfigurationException', () {
    test('is an ApiException', () {
      const e = ConfigurationException(message: 'Invalid config');
      expect(e, isA<ApiException>());
    });
  });

  group('CacheException', () {
    test('is an ApiException', () {
      const e = CacheException(message: 'Cache error');
      expect(e, isA<ApiException>());
    });
  });
}
