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
    if (config.requestFilter != null &&
        error.request != null &&
        !config.requestFilter!(error.request!)) {
      return error;
    }

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
          buffer.writeln(
              '$color│ ${reset}Duration: ${executionTime.inMilliseconds}ms');
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

  late final Set<String> _maskedKeys =
      config.maskedKeys.map((k) => k.toLowerCase()).toSet();

  bool _isMasked(Object? key) =>
      key is String && _maskedKeys.contains(key.toLowerCase());

  Map<String, String> _maskHeaders(Map<String, String> headers) {
    return headers.map(
      (key, value) => MapEntry(key, _isMasked(key) ? config.maskString : value),
    );
  }

  Map<String, List<String>> _maskResponseHeaders(
    Map<String, List<String>> headers,
  ) {
    return headers.map(
      (key, value) =>
          MapEntry(key, _isMasked(key) ? [config.maskString] : value),
    );
  }

  /// Returns a copy of [data] in which the values of masked keys are
  /// replaced, recursing into maps and lists. JSON strings are decoded
  /// first so that their keys are masked too.
  dynamic _maskBody(dynamic data) {
    if (data is String) {
      final trimmed = data.trimLeft();
      if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
        try {
          return _maskBody(jsonDecode(data));
        } on FormatException {
          return data;
        }
      }
      return data;
    }
    if (data is Map) {
      return {
        for (final entry in data.entries)
          '${entry.key}':
              _isMasked(entry.key) ? config.maskString : _maskBody(entry.value),
      };
    }
    if (data is List && data is! List<int>) {
      return [for (final item in data) _maskBody(item)];
    }
    return data;
  }

  /// JSON-encodes [data], falling back to `toString()` for values that are
  /// not JSON-encodable, so logging never fails a request.
  static String _encode(Object? data, {bool indent = false}) {
    final encoder = indent
        ? const JsonEncoder.withIndent('  ', _toEncodable)
        : const JsonEncoder(_toEncodable);
    return encoder.convert(data);
  }

  static Object? _toEncodable(Object? value) => value.toString();

  static String _describePath(ApiRequest request) {
    if (request.queryParameters.isEmpty) return request.path;
    final params = <String, dynamic>{
      for (final entry in request.queryParameters.entries)
        if (entry.value != null)
          entry.key: entry.value is Iterable
              ? (entry.value as Iterable).map((e) => '$e').toList()
              : '${entry.value}',
    };
    if (params.isEmpty) return request.path;
    final separator = request.path.contains('?') ? '&' : '?';
    return '${request.path}$separator${Uri(queryParameters: params).query}';
  }

  // ─── JSON Formatting ─────────────────────────────────────────────

  void _logJsonRequest(ApiRequest request) {
    final logData = <String, dynamic>{
      'type': 'request',
      'method': request.method.value,
      'url': _describePath(request),
      if (config.printRequestHeaders) 'headers': _maskHeaders(request.headers),
      if (config.printRequestBody && request.body != null)
        'body': _maskBody(request.body),
    };
    _log(_encode(logData));
  }

  void _logJsonResponse(
    ApiResponse<dynamic> response,
    Duration? executionTime,
  ) {
    final logData = <String, dynamic>{
      'type': 'response',
      'statusCode': response.statusCode,
      if (config.printResponseHeaders)
        'headers': _maskResponseHeaders(response.headers),
      if (config.printResponseBody && response.data != null)
        'body': _maskBody(response.data),
      if (executionTime != null && config.printExecutionTime)
        'durationMs': executionTime.inMilliseconds,
    };
    _log(_encode(logData));
  }

  void _logJsonError(ApiException error, Duration? executionTime) {
    final logData = <String, dynamic>{
      'type': 'error',
      'message': error.message,
      'statusCode': error.response?.statusCode,
      'url': error.request == null ? null : _describePath(error.request!),
      if (executionTime != null && config.printExecutionTime)
        'durationMs': executionTime.inMilliseconds,
    };
    _log(_encode(logData));
  }

  // ─── Pretty Formatting ───────────────────────────────────────────

  void _logPrettyRequest(ApiRequest request) {
    final color = config.colors ? '\x1B[34m' : ''; // Blue
    final reset = config.colors ? '\x1B[0m' : '';

    final buffer = StringBuffer();
    buffer.writeln(
        '$color┌── Request ──────────────────────────────────────────────────$reset');
    buffer.writeln(
        '$color│ $reset${request.method.value} ${_describePath(request)}');

    if (config.printRequestHeaders && request.headers.isNotEmpty) {
      buffer.writeln('$color├─ Headers:$reset');
      _maskHeaders(request.headers).forEach((key, value) {
        buffer.writeln('$color│ $reset  $key: $value');
      });
    }

    if (config.printRequestBody && request.body != null) {
      buffer.writeln('$color├─ Body:$reset');
      final bodyLines = _tryFormatJson(_maskBody(request.body)).split('\n');
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
      _maskResponseHeaders(response.headers).forEach((key, value) {
        buffer.writeln('$color│ $reset  $key: ${value.join(', ')}');
      });
    }

    if (config.printResponseBody && response.data != null) {
      buffer.writeln('$color├─ Body:$reset');
      final bodyLines = _tryFormatJson(_maskBody(response.data)).split('\n');
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
    _log('→ ${request.method.value} ${_describePath(request)}');
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
      final masked = _maskBody(request.body);
      final bodyStr = masked is String ? masked : _encode(masked);
      curl.write(" -d '${bodyStr.replaceAll("'", "'\\''")}'");
    }

    curl.write(' "${_describePath(request)}"');

    final color = config.colors ? '\x1B[36m' : ''; // Cyan
    final reset = config.colors ? '\x1B[0m' : '';
    _log('$color$curl$reset');
  }

  String _tryFormatJson(dynamic data) {
    if (data is String) {
      try {
        return _encode(jsonDecode(data), indent: true);
      } on FormatException {
        return data;
      }
    }
    return _encode(data, indent: true);
  }
}
