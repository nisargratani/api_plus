import 'package:api_plus/api_plus.dart';
import 'package:test/test.dart';

void main() {
  group('LoggerConfig', () {
    test('has sensible defaults', () {
      const config = LoggerConfig();
      expect(config.level, LogLevel.debug);
      expect(config.format, LogFormat.pretty);
      expect(config.printRequestHeaders, isTrue);
      expect(config.printRequestBody, isTrue);
      expect(config.printResponseHeaders, isTrue);
      expect(config.printResponseBody, isTrue);
      expect(config.colors, isTrue);
      expect(config.printCurl, isTrue);
      expect(config.printExecutionTime, isTrue);
      expect(config.maskString, '***');
      expect(config.printer, isNull);
      expect(config.requestFilter, isNull);
      expect(config.filterStatusCodes, isNull);
      expect(
          config.maskedKeys, {'authorization', 'password', 'token', 'secret'});
    });

    group('isEnabled', () {
      test('none disables all', () {
        const config = LoggerConfig(level: LogLevel.none);
        expect(config.isEnabled(LogLevel.error), isFalse);
        expect(config.isEnabled(LogLevel.warning), isFalse);
        expect(config.isEnabled(LogLevel.info), isFalse);
        expect(config.isEnabled(LogLevel.debug), isFalse);
        expect(config.isEnabled(LogLevel.verbose), isFalse);
      });

      test('error enables only error', () {
        const config = LoggerConfig(level: LogLevel.error);
        expect(config.isEnabled(LogLevel.error), isTrue);
        expect(config.isEnabled(LogLevel.warning), isFalse);
        expect(config.isEnabled(LogLevel.info), isFalse);
      });

      test('verbose enables all', () {
        const config = LoggerConfig(level: LogLevel.verbose);
        expect(config.isEnabled(LogLevel.error), isTrue);
        expect(config.isEnabled(LogLevel.warning), isTrue);
        expect(config.isEnabled(LogLevel.info), isTrue);
        expect(config.isEnabled(LogLevel.debug), isTrue);
        expect(config.isEnabled(LogLevel.verbose), isTrue);
      });

      test('info enables info, warning, and error', () {
        const config = LoggerConfig(level: LogLevel.info);
        expect(config.isEnabled(LogLevel.error), isTrue);
        expect(config.isEnabled(LogLevel.warning), isTrue);
        expect(config.isEnabled(LogLevel.info), isTrue);
        expect(config.isEnabled(LogLevel.debug), isFalse);
        expect(config.isEnabled(LogLevel.verbose), isFalse);
      });
    });
  });

  group('LogLevel', () {
    test('has correct ordering', () {
      expect(LogLevel.none.index, 0);
      expect(LogLevel.error.index, 1);
      expect(LogLevel.warning.index, 2);
      expect(LogLevel.info.index, 3);
      expect(LogLevel.debug.index, 4);
      expect(LogLevel.verbose.index, 5);
    });
  });

  group('LogFormat', () {
    test('has all expected values', () {
      expect(LogFormat.values, hasLength(3));
      expect(LogFormat.values, contains(LogFormat.compact));
      expect(LogFormat.values, contains(LogFormat.pretty));
      expect(LogFormat.values, contains(LogFormat.json));
    });
  });
}
