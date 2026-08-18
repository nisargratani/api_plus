import 'dart:convert';
import '../config/logger_config.dart';
import '../core/api_request.dart';
import '../core/api_response.dart';
import '../exceptions/api_exception.dart';
import '../interfaces/api_interceptor.dart';

/// An interceptor that logs API requests, responses, and errors.
///
/// Supports multiple output formats (pretty, compact, JSON),
/// sensitive data masking, curl command generation, execution
/// time tracking, and custom log printers.
///
/// {@tool snippet}
/// ```dart
/// final logger = LoggerInterceptor(
///   config: const LoggerConfig(
///     level: LogLevel.verbose,
///     format: LogFormat.pretty,
///     colors: true,
///   ),
/// );
/// ```
/// {@end-tool}
class LoggerInterceptor implements ApiInterceptor {
  /// The logger configuration.
  final LoggerConfig config;

  /// Creates a [LoggerInterceptor] with the given [config].
  LoggerInterceptor({this.config = const LoggerConfig()});

  void _log(String message) {
    if (config.printer != null) {
      config.printer!.log(message);
    } else {
      // Split by newline and chunk to avoid truncation in consoles
      final lines = message.split('\n');
      for (final line in lines) {
        if (line.length > 800) {
          for (var i = 0; i < line.length; i += 800) {
            final end = (i + 800 < line.length) ? i + 800 : line.length;
            // ignore: avoid_print
            print(line.substring(i, end));
          }
        } else {
          // ignore: avoid_print
          print(line);
        }
      }
    }
  }

  @override
  Future<dynamic> onRequest(ApiRequest request) async {
    if (!config.isEnabled(LogLevel.info)) return request;

    // Check request filter
    if (config.requestFilter != null && !config.requestFilter!(request)) {
      return request;
    }

    // Attach start time for execution time tracking
    final newExtra = Map<String, dynamic>.from(request.extra);
    newExtra['_requestStartTime'] = DateTime.now().millisecondsSinceEpoch;
    final finalRequest = request.copyWith(extra: newExtra);

    switch (config.format) {
      case LogFormat.json:
        _logJsonRequest(finalRequest);
      case LogFormat.pretty:
        _logPrettyRequest(finalRequest);
      case LogFormat.compact:
        _logCompactRequest(finalRequest);
    }

    if (config.printCurl) {
      _logCurlCommand(finalRequest);
    }

    return finalRequest;
  }

  @override
  Future<ApiResponse<dynamic>> onResponse(
    ApiResponse<dynamic> response,
  ) async {
    if (!config.isEnabled(LogLevel.info)) return response;

    // Check status code filter
    if (config.filterStatusCodes != null &&
        !config.filterStatusCodes!.contains(response.statusCode)) {
      return response;
    }

    // Check request filter
    if (config.requestFilter != null &&
        response.request != null &&
        !config.requestFilter!(response.request!)) {
      return response;
    }

    final executionTime = _getExecutionTime(response.request);

    switch (config.format) {
      case LogFormat.json:
        _logJsonResponse(response, executionTime);
      case LogFormat.pretty:
        _logPrettyResponse(response, executionTime);
      case LogFormat.compact:
        _logCompactResponse(response, executionTime);
    }

    return response;
  }

  @override
  Future<dynamic> onError(
    ApiException error,
    Future<ApiResponse<dynamic>> Function(ApiRequest) invoker,
  ) async {
    if (!config.isEnabled(LogLevel.error)) return error;

    final executionTime = _getExecutionTime(error.request);

    switch (config.format) {
      case LogFormat.json:
        _logJsonError(error, executionTime);
      case LogFormat.pretty:
      case LogFormat.compact:
        final color = config.colors ? '\x1B[31m' : '';
        final reset = config.colors ? '\x1B[0m' : '';
        final buffer = StringBuffer();
        buffer.writeln(
            '$color┌── Error ────────────────────────────────────────────────────$reset');
        buffer.writeln('$color│ ${reset}ERROR: ${error.message}');
        if (error.request != null) {
          buffer.writeln(
              '$color│ ${reset}Request: ${error.request!.method.value} ${error.request!.path}');
        }
        if (error.response != null) {
          buffer
              .writeln('$color│ ${reset}Status: ${error.response!.statusCode}');
        }
        if (executionTime != null && config.printExecutionTime) {
          buffer.writeln('$color│ ${reset}Duration: ${executionTime}ms');
        }
        buffer.write(
            '$color└────────────────────────────────────────────────────────────$reset');
        _log(buffer.toString());
    }

    return error;
  }

  // ─── Utility Methods ─────────────────────────────────────────────

  Duration? _getExecutionTime(ApiRequest? request) {
    if (request == null || !config.printExecutionTime) return null;
    final startTime = request.extra['_requestStartTime'] as int?;
    if (startTime == null) return null;
    return Duration(
      milliseconds: DateTime.now().millisecondsSinceEpoch - startTime,
    );
  }

  String _maskValue(String key, String value) {
    if (config.maskedKeys.contains(key.toLowerCase())) {
      return config.maskString;
    }
    return value;
  }

  Map<String, String> _maskHeaders(Map<String, String> headers) {
    return headers.map((key, value) => MapEntry(key, _maskValue(key, value)));
  }

  // ─── JSON Formatting ─────────────────────────────────────────────

  void _logJsonRequest(ApiRequest request) {
    final logData = <String, dynamic>{
      'type': 'request',
      'method': request.method.value,
      'url': request.path,
      if (config.printRequestHeaders) 'headers': _maskHeaders(request.headers),
      if (config.printRequestBody && request.body != null) 'body': request.body,
    };
    _log(jsonEncode(logData));
  }

  void _logJsonResponse(
    ApiResponse<dynamic> response,
    Duration? executionTime,
  ) {
    final logData = <String, dynamic>{
      'type': 'response',
      'statusCode': response.statusCode,
      if (config.printResponseHeaders) 'headers': response.headers,
      if (config.printResponseBody && response.data != null)
        'body': response.data,
      if (executionTime != null && config.printExecutionTime)
        'durationMs': executionTime.inMilliseconds,
    };
    _log(jsonEncode(logData));
  }

  void _logJsonError(ApiException error, Duration? executionTime) {
    final logData = <String, dynamic>{
      'type': 'error',
      'message': error.message,
      'statusCode': error.response?.statusCode,
      'url': error.request?.path,
      if (executionTime != null && config.printExecutionTime)
        'durationMs': executionTime.inMilliseconds,
    };
    _log(jsonEncode(logData));
  }

  // ─── Pretty Formatting ───────────────────────────────────────────

  void _logPrettyRequest(ApiRequest request) {
    final color = config.colors ? '\x1B[34m' : ''; // Blue
    final reset = config.colors ? '\x1B[0m' : '';

    final buffer = StringBuffer();
    buffer.writeln(
        '$color┌── Request ──────────────────────────────────────────────────$reset');
    buffer.writeln('$color│ $reset${request.method.value} ${request.path}');

    if (config.printRequestHeaders && request.headers.isNotEmpty) {
      buffer.writeln('$color├─ Headers:$reset');
      _maskHeaders(request.headers).forEach((key, value) {
        buffer.writeln('$color│ $reset  $key: $value');
      });
    }

    if (config.printRequestBody && request.body != null) {
      buffer.writeln('$color├─ Body:$reset');
      final bodyLines = _tryFormatJson(request.body).split('\n');
      for (final line in bodyLines) {
        buffer.writeln('$color│ $reset  $line');
      }
    }
    buffer.write(
        '$color└────────────────────────────────────────────────────────────$reset');
    _log(buffer.toString());
  }

  void _logPrettyResponse(
    ApiResponse<dynamic> response,
    Duration? executionTime,
  ) {
    final isSuccess = response.statusCode >= 200 && response.statusCode < 300;
    final color = config.colors
        ? (isSuccess ? '\x1B[32m' : '\x1B[33m')
        : ''; // Green or Yellow
    final reset = config.colors ? '\x1B[0m' : '';

    final buffer = StringBuffer();
    buffer.writeln(
        '$color┌── Response ─────────────────────────────────────────────────$reset');
    buffer.writeln(
        '$color│ ${reset}Status: ${response.statusCode} ${response.statusMessage ?? ''}');

    if (executionTime != null && config.printExecutionTime) {
      buffer.writeln(
          '$color│ ${reset}Duration: ${executionTime.inMilliseconds}ms');
    }

    if (config.printResponseHeaders && response.headers.isNotEmpty) {
      buffer.writeln('$color├─ Headers:$reset');
      response.headers.forEach((key, value) {
        buffer.writeln('$color│ $reset  $key: ${value.join(', ')}');
      });
    }

    if (config.printResponseBody && response.data != null) {
      buffer.writeln('$color├─ Body:$reset');
      final bodyLines = _tryFormatJson(response.data).split('\n');
      for (final line in bodyLines) {
        buffer.writeln('$color│ $reset  $line');
      }
    }
    buffer.write(
        '$color└────────────────────────────────────────────────────────────$reset');
    _log(buffer.toString());
  }

  // ─── Compact Formatting ──────────────────────────────────────────

  void _logCompactRequest(ApiRequest request) {
    _log('→ ${request.method.value} ${request.path}');
  }

  void _logCompactResponse(
    ApiResponse<dynamic> response,
    Duration? executionTime,
  ) {
    final timeStr = (executionTime != null && config.printExecutionTime)
        ? ' (${executionTime.inMilliseconds}ms)'
        : '';
    _log('← [${response.statusCode}]$timeStr');
  }

  // ─── Curl Generation ─────────────────────────────────────────────

  void _logCurlCommand(ApiRequest request) {
    final curl = StringBuffer('curl -X ${request.method.value}');

    _maskHeaders(request.headers).forEach((key, value) {
      curl.write(' -H "$key: $value"');
    });

    if (request.body != null) {
      final bodyStr = request.body is String
          ? request.body as String
          : jsonEncode(request.body);
      curl.write(" -d '${bodyStr.replaceAll("'", "'\\''")}' ");
    }

    curl.write(' "${request.path}"');

    final color = config.colors ? '\x1B[36m' : ''; // Cyan
    final reset = config.colors ? '\x1B[0m' : '';
    _log('$color$curl$reset');
  }

  String _tryFormatJson(dynamic data) {
    try {
      final json = data is String ? jsonDecode(data) : data;
      return const JsonEncoder.withIndent('  ').convert(json);
    } catch (_) {
      return data.toString();
    }
  }
}
