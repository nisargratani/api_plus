import 'package:api_plus/api_plus.dart';
import 'package:test/test.dart';

void main() {
  group('HttpMethod', () {
    test('has correct string values', () {
      expect(HttpMethod.get.value, 'GET');
      expect(HttpMethod.post.value, 'POST');
      expect(HttpMethod.put.value, 'PUT');
      expect(HttpMethod.delete.value, 'DELETE');
      expect(HttpMethod.patch.value, 'PATCH');
      expect(HttpMethod.head.value, 'HEAD');
      expect(HttpMethod.options.value, 'OPTIONS');
    });

    test('toString returns value', () {
      expect(HttpMethod.get.toString(), 'GET');
      expect(HttpMethod.post.toString(), 'POST');
    });

    group('isIdempotent', () {
      test('GET is idempotent', () {
        expect(HttpMethod.get.isIdempotent, isTrue);
      });

      test('HEAD is idempotent', () {
        expect(HttpMethod.head.isIdempotent, isTrue);
      });

      test('PUT is idempotent', () {
        expect(HttpMethod.put.isIdempotent, isTrue);
      });

      test('DELETE is idempotent', () {
        expect(HttpMethod.delete.isIdempotent, isTrue);
      });

      test('OPTIONS is idempotent', () {
        expect(HttpMethod.options.isIdempotent, isTrue);
      });

      test('POST is NOT idempotent', () {
        expect(HttpMethod.post.isIdempotent, isFalse);
      });

      test('PATCH is NOT idempotent', () {
        expect(HttpMethod.patch.isIdempotent, isFalse);
      });
    });

    test('enum values list is complete', () {
      expect(HttpMethod.values, hasLength(7));
    });
  });
}
