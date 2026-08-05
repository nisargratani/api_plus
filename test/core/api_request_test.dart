import 'package:api_plus/api_plus.dart';
import 'package:test/test.dart';

void main() {
  group('ApiRequest', () {
    test('creates with required path only', () {
      const request = ApiRequest(path: '/users');
      expect(request.path, '/users');
      expect(request.method, HttpMethod.get);
      expect(request.headers, isEmpty);
      expect(request.queryParameters, isEmpty);
      expect(request.body, isNull);
      expect(request.connectTimeout, isNull);
      expect(request.receiveTimeout, isNull);
      expect(request.sendTimeout, isNull);
      expect(request.extra, isEmpty);
    });

    test('creates with all parameters', () {
      const request = ApiRequest(
        path: '/posts',
        method: HttpMethod.post,
        headers: {'Content-Type': 'application/json'},
        queryParameters: {'page': '1'},
        body: 'test body',
        connectTimeout: Duration(seconds: 5),
        receiveTimeout: Duration(seconds: 10),
        sendTimeout: Duration(seconds: 3),
        extra: {'key': 'value'},
      );

      expect(request.path, '/posts');
      expect(request.method, HttpMethod.post);
      expect(request.headers, {'Content-Type': 'application/json'});
      expect(request.queryParameters, {'page': '1'});
      expect(request.body, 'test body');
      expect(request.connectTimeout, const Duration(seconds: 5));
      expect(request.receiveTimeout, const Duration(seconds: 10));
      expect(request.sendTimeout, const Duration(seconds: 3));
      expect(request.extra, {'key': 'value'});
    });

    group('copyWith', () {
      const original = ApiRequest(
        path: '/users',
        method: HttpMethod.get,
        headers: {'Accept': 'application/json'},
      );

      test('creates copy with changed path', () {
        final copy = original.copyWith(path: '/posts');
        expect(copy.path, '/posts');
        expect(copy.method, HttpMethod.get);
        expect(copy.headers, {'Accept': 'application/json'});
      });

      test('creates copy with changed method', () {
        final copy = original.copyWith(method: HttpMethod.post);
        expect(copy.path, '/users');
        expect(copy.method, HttpMethod.post);
      });

      test('creates copy with changed headers', () {
        final copy = original.copyWith(headers: {'X-Custom': 'value'});
        expect(copy.headers, {'X-Custom': 'value'});
      });

      test('creates copy with no changes returns equivalent object', () {
        final copy = original.copyWith();
        expect(copy, original);
      });
    });

    group('equality', () {
      test('equal requests are equal', () {
        const a = ApiRequest(path: '/users', method: HttpMethod.get);
        const b = ApiRequest(path: '/users', method: HttpMethod.get);
        expect(a, b);
        expect(a.hashCode, b.hashCode);
      });

      test('different paths are not equal', () {
        const a = ApiRequest(path: '/users');
        const b = ApiRequest(path: '/posts');
        expect(a, isNot(b));
      });

      test('different methods are not equal', () {
        const a = ApiRequest(path: '/users', method: HttpMethod.get);
        const b = ApiRequest(path: '/users', method: HttpMethod.post);
        expect(a, isNot(b));
      });

      test('different headers are not equal', () {
        const a = ApiRequest(
          path: '/users',
          headers: {'A': '1'},
        );
        const b = ApiRequest(
          path: '/users',
          headers: {'B': '2'},
        );
        expect(a, isNot(b));
      });

      test('identical returns true', () {
        const a = ApiRequest(path: '/users');
        expect(a == a, isTrue);
      });

      test('different type returns false', () {
        const a = ApiRequest(path: '/users');
        // ignore: unrelated_type_equality_checks
        expect(a == 'not a request', isFalse);
      });
    });

    test('toString returns method and path', () {
      const request = ApiRequest(path: '/users', method: HttpMethod.post);
      expect(request.toString(), 'ApiRequest(POST /users)');
    });
  });
}
