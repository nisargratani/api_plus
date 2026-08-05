import 'package:api_plus/api_plus.dart';
import 'package:test/test.dart';

void main() {
  group('ApiResponse', () {
    test('creates with required statusCode', () {
      const response = ApiResponse<String>(statusCode: 200);
      expect(response.statusCode, 200);
      expect(response.data, isNull);
      expect(response.headers, isEmpty);
      expect(response.statusMessage, isNull);
      expect(response.isRedirect, isFalse);
      expect(response.request, isNull);
    });

    test('creates with all parameters', () {
      const request = ApiRequest(path: '/users');
      const response = ApiResponse<String>(
        data: 'hello',
        statusCode: 200,
        headers: {
          'content-type': ['application/json'],
        },
        statusMessage: 'OK',
        isRedirect: false,
        request: request,
      );

      expect(response.data, 'hello');
      expect(response.statusCode, 200);
      expect(response.headers['content-type'], ['application/json']);
      expect(response.statusMessage, 'OK');
      expect(response.isRedirect, isFalse);
      expect(response.request, request);
    });

    group('isSuccessful', () {
      test('returns true for 200', () {
        const response = ApiResponse<void>(statusCode: 200);
        expect(response.isSuccessful, isTrue);
      });

      test('returns true for 201', () {
        const response = ApiResponse<void>(statusCode: 201);
        expect(response.isSuccessful, isTrue);
      });

      test('returns true for 299', () {
        const response = ApiResponse<void>(statusCode: 299);
        expect(response.isSuccessful, isTrue);
      });

      test('returns false for 199', () {
        const response = ApiResponse<void>(statusCode: 199);
        expect(response.isSuccessful, isFalse);
      });

      test('returns false for 300', () {
        const response = ApiResponse<void>(statusCode: 300);
        expect(response.isSuccessful, isFalse);
      });

      test('returns false for 404', () {
        const response = ApiResponse<void>(statusCode: 404);
        expect(response.isSuccessful, isFalse);
      });

      test('returns false for 500', () {
        const response = ApiResponse<void>(statusCode: 500);
        expect(response.isSuccessful, isFalse);
      });
    });

    group('copyWith', () {
      const original = ApiResponse<String>(
        data: 'original',
        statusCode: 200,
        statusMessage: 'OK',
      );

      test('copies with new data', () {
        final copy = original.copyWith(data: 'modified');
        expect(copy.data, 'modified');
        expect(copy.statusCode, 200);
      });

      test('copies with new statusCode', () {
        final copy = original.copyWith(statusCode: 201);
        expect(copy.statusCode, 201);
        expect(copy.data, 'original');
      });

      test('copies with no changes returns equivalent values', () {
        final copy = original.copyWith();
        expect(copy.data, original.data);
        expect(copy.statusCode, original.statusCode);
        expect(copy.statusMessage, original.statusMessage);
      });
    });

    test('toString returns meaningful representation', () {
      const response = ApiResponse<void>(
        statusCode: 200,
        statusMessage: 'OK',
      );
      final str = response.toString();
      expect(str, contains('200'));
      expect(str, contains('OK'));
      expect(str, contains('true'));
    });
  });
}
