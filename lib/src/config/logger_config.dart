import 'package:meta/meta.dart';
import '../core/api_request.dart';
import '../interfaces/log_printer.dart';

/// Defines the level of verbosity for the logger.
///
/// Levels are ordered from least to most verbose:
/// [none] < [error] < [warning] < [info] < [debug] < [verbose]
enum LogLevel {
  /// No logs are emitted.
  none,

  /// Only errors are logged.
  error,

  /// Warnings and errors are logged.
  warning,

  /// Informational messages, warnings, and errors are logged.
  info,

  /// Detailed debugging information is logged.
  debug,

  /// All available information is logged, including trace data.
  verbose,
}

/// Defines the formatting style for log output.
enum LogFormat {
  /// Simple, single-line log entries.
  ///
  /// Example: `REQ: GET /users/1`
  compact,

  /// Human-readable, multi-line logs with ASCII box-drawing borders.
  ///
  /// Ideal for development and debugging.
  pretty,

  /// Structured JSON logs.
  ///
  /// Ideal for log aggregation services (e.g., Datadog, CloudWatch).
  json,
}

/// Configuration for the API logger interceptor.
///
/// Controls what information is logged, how it is formatted, and
/// where the output is directed.
///
/// {@tool snippet}
/// ```dart
/// const config = LoggerConfig(
///   level: LogLevel.verbose,
///   format: LogFormat.pretty,
///   colors: true,
///   printCurl: true,
///   maskedKeys: {'authorization', 'password', 'api_key'},
/// );
/// ```
/// {@end-tool}
@immutable
class LoggerConfig {
  /// The verbosity level for log output.
  ///
  /// Messages at or below this level are emitted. Messages above
  /// this level are suppressed.
  final LogLevel level;

  /// The formatting style for log messages.
  final LogFormat format;

  /// Whether to include request headers in the log output.
  final bool printRequestHeaders;

  /// Whether to include the request body in the log output.
  final bool printRequestBody;

  /// Whether to include response headers in the log output.
  final bool printResponseHeaders;

  /// Whether to include the response body in the log output.
  final bool printResponseBody;

  /// Whether to use ANSI color codes in console output.
  ///
  /// Set to `false` for environments that do not support ANSI codes
  /// (e.g., file logging, some CI systems).
  final bool colors;

  /// Keys whose values should be masked in log output.
  ///
  /// Matched case-insensitively against header names and body keys.
  /// Values for matching keys are replaced with [maskString].
  final Set<String> maskedKeys;

  /// Whether to include the equivalent curl command for each request.
  final bool printCurl;

  /// The string used to replace masked values.
  final String maskString;

  /// Whether to calculate and display request/response execution time.
  final bool printExecutionTime;

  /// Optional custom log printer for directing output.
  ///
  /// When `null`, logs are printed to the console via `print()`.
  /// Use this to direct logs to files, remote services, etc.
  final LogPrinter? printer;

  /// Optional filter for selective request logging.
  ///
  /// When provided, only requests for which this function returns
  /// `true` are logged. All other requests are silently passed through.
  final bool Function(ApiRequest)? requestFilter;

  /// Optional set of status codes to filter response logging.
  ///
  /// When provided, only responses with matching status codes are logged.
  /// When `null`, all responses are logged.
  final Set<int>? filterStatusCodes;

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
    this.printExecutionTime = true,
    this.printer,
    this.requestFilter,
    this.filterStatusCodes,
  });

  /// Returns `true` if the given [targetLevel] should be logged.
  ///
  /// A level is enabled if the config [level] is at or above
  /// [targetLevel] and is not [LogLevel.none].
  bool isEnabled(LogLevel targetLevel) {
    return level.index >= targetLevel.index && level != LogLevel.none;
  }
}
