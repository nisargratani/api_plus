import 'package:api_plus/api_plus.dart';
import 'package:test/test.dart';

void main() {
  group('HttpDateParser', () {
    group('IMF-fixdate format', () {
      test('parses standard format', () {
        final date = HttpDateParser.parse('Sun, 06 Nov 1994 08:49:37 GMT');
        expect(date, isNotNull);
        expect(date!.year, 1994);
        expect(date.month, 11);
        expect(date.day, 6);
        expect(date.hour, 8);
        expect(date.minute, 49);
        expect(date.second, 37);
        expect(date.isUtc, isTrue);
      });

      test('parses another date', () {
        final date = HttpDateParser.parse('Wed, 21 Oct 2015 07:28:00 GMT');
        expect(date, isNotNull);
        expect(date!.year, 2015);
        expect(date.month, 10);
        expect(date.day, 21);
      });
    });

    group('RFC 850 format', () {
      test('parses standard format', () {
        final date = HttpDateParser.parse('Sunday, 06-Nov-94 08:49:37 GMT');
        expect(date, isNotNull);
        expect(date!.year, 1994);
        expect(date.month, 11);
        expect(date.day, 6);
      });

      test('handles year < 70 as 2000s', () {
        final date = HttpDateParser.parse('Monday, 01-Jan-25 00:00:00 GMT');
        expect(date, isNotNull);
        expect(date!.year, 2025);
      });

      test('handles year >= 70 as 1900s', () {
        final date = HttpDateParser.parse('Tuesday, 01-Jan-80 00:00:00 GMT');
        expect(date, isNotNull);
        expect(date!.year, 1980);
      });
    });

    group('asctime format', () {
      test('parses standard format', () {
        final date = HttpDateParser.parse('Sun Nov  6 08:49:37 1994');
        expect(date, isNotNull);
        expect(date!.year, 1994);
        expect(date.month, 11);
        expect(date.day, 6);
      });

      test('parses double-digit day', () {
        final date = HttpDateParser.parse('Wed Oct 21 07:28:00 2015');
        expect(date, isNotNull);
        expect(date!.day, 21);
      });
    });

    group('edge cases', () {
      test('returns null for invalid input', () {
        expect(HttpDateParser.parse('not a date'), isNull);
      });

      test('returns null for empty string', () {
        expect(HttpDateParser.parse(''), isNull);
      });

      test('handles whitespace', () {
        final date = HttpDateParser.parse('  Sun, 06 Nov 1994 08:49:37 GMT  ');
        expect(date, isNotNull);
      });

      test('returns null for partial date', () {
        expect(HttpDateParser.parse('Sun, 06 Nov'), isNull);
      });

      test('returns null for invalid month', () {
        expect(HttpDateParser.parse('Sun, 06 Xyz 1994 08:49:37 GMT'), isNull);
      });
    });
  });

  group('CacheKeyGenerator', () {
    test('generates key from method and url', () {
      final key = CacheKeyGenerator.generate('GET', '/users');
      expect(key, 'GET:/users');
    });

    test('includes query parameters in key', () {
      final key = CacheKeyGenerator.generate(
        'GET',
        '/users',
        {'page': '1', 'limit': '10'},
      );
      expect(key, contains('GET:/users:'));
      expect(key, contains('"limit":"10"'));
      expect(key, contains('"page":"1"'));
    });

    test('sorts query parameters for consistency', () {
      final key1 = CacheKeyGenerator.generate(
        'GET',
        '/users',
        {'b': '2', 'a': '1'},
      );
      final key2 = CacheKeyGenerator.generate(
        'GET',
        '/users',
        {'a': '1', 'b': '2'},
      );
      expect(key1, key2);
    });

    test('handles empty query parameters', () {
      final key = CacheKeyGenerator.generate('GET', '/users', {});
      expect(key, 'GET:/users');
    });

    test('handles null query parameters', () {
      final key = CacheKeyGenerator.generate('GET', '/users');
      expect(key, 'GET:/users');
    });
  });

  group('MapExtensions', () {
    test('getIgnoreCase finds value', () {
      final map = {'Content-Type': 'application/json'};
      expect(map.getIgnoreCase('content-type'), 'application/json');
      expect(map.getIgnoreCase('Content-Type'), 'application/json');
      expect(map.getIgnoreCase('CONTENT-TYPE'), 'application/json');
    });

    test('getIgnoreCase returns null for missing key', () {
      final map = {'Content-Type': 'application/json'};
      expect(map.getIgnoreCase('accept'), isNull);
    });

    test('containsKeyIgnoreCase returns true', () {
      final map = {'Authorization': 'Bearer token'};
      expect(map.containsKeyIgnoreCase('authorization'), isTrue);
      expect(map.containsKeyIgnoreCase('AUTHORIZATION'), isTrue);
    });

    test('containsKeyIgnoreCase returns false', () {
      final map = {'Authorization': 'Bearer token'};
      expect(map.containsKeyIgnoreCase('accept'), isFalse);
    });
  });
}
