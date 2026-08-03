import 'package:meta/meta.dart';

/// Defines the level of verbosity for the logger.
enum LogLevel {
  /// No logs.
  none,
  /// Errors only.
  error,
  /// Warnings and errors.
  warning,
  /// Informational messages.
  info,
  /// Detailed debugging logs.
  debug,
  /// All logs including trace.
  verbose,
}

/// Defines the style of the logs.
enum LogFormat {
  /// Simple, single-line logs.
  compact,
  /// Human-readable, multi-line logs with ASCII borders.
  pretty,
  /// Structured JSON logs, useful for external log aggregation.
  json,
}

/// Configuration for the API logger interceptor.
@immutable
class LoggerConfig {
  /// The verbosity level.
  final LogLevel level;

  /// The formatting style.
  final LogFormat format;

  /// Whether to print request headers.
  final bool printRequestHeaders;

  /// Whether to print the request body.
  final bool printRequestBody;

  /// Whether to print response headers.
  final bool printResponseHeaders;

  /// Whether to print the response body.
  final bool printResponseBody;

  /// Whether to include ANSI colors in console output.
  final bool colors;

  /// A set of keys (e.g. 'Authorization', 'password') whose values 
  /// should be masked in the logs to protect sensitive data.
  final Set<String> maskedKeys;

  /// Whether to print the equivalent curl command for the request.
  final bool printCurl;

  /// The string to use for masking sensitive data.
  final String maskString;
  
  /// Callback for custom logging output (e.g. file writing).
  /// If null, defaults to `print`.
  final void Function(String message)? output;

  /// Creates a [LoggerConfig].
  const LoggerConfig({
    this.level = LogLevel.debug,
    this.format = LogFormat.pretty,
    this.printRequestHeaders = true,
    this.printRequestBody = true,
    this.printResponseHeaders = true,
    this.printResponseBody = true,
    this.colors = true,
    this.maskedKeys = const {'authorization', 'password', 'token', 'secret'},
    this.printCurl = true,
    this.maskString = '***',
    this.output,
  });

  /// Helper to check if a log level is enabled.
  bool isEnabled(LogLevel targetLevel) {
    return level.index >= targetLevel.index && level != LogLevel.none;
  }
}
