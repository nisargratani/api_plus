import 'dart:convert';
import '../config/logger_config.dart';
import '../core/api_request.dart';
import '../core/api_response.dart';
import '../core/internal_keys.dart';
import '../core/request_url.dart';
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
    var current = request;
    if (config.isEnabled(LogLevel.error)) {
      // Lets a RetryInterceptor placed before this one report the first
      // attempt's error before it retries, so every attempt's error is
      // logged once, in order.
      current = withErrorObserver(current, _logErrorOnce);
    }
    if (!config.isEnabled(LogLevel.info)) return current;

    // Check request filter
    if (config.requestFilter != null && !config.requestFilter!(current)) {
      return current;
    }

    // Attach start time for execution time tracking
    final newExtra = Map<String, dynamic>.from(current.extra);
    newExtra['_requestStartTime'] = DateTime.now().millisecondsSinceEpoch;
    final finalRequest = current.copyWith(extra: newExtra);

    switch (config.format) {
      case LogFormat.json:
        // The curl command is a field of the record, so every line of
        // JSON output is valid JSON.
        _logJsonRequest(finalRequest);
      case LogFormat.pretty:
        _logPrettyRequest(finalRequest);
        if (config.printCurl) _logCurlCommand(finalRequest);
      case LogFormat.compact:
        _logCompactRequest(finalRequest);
        if (config.printCurl) _logCurlCommand(finalRequest);
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
    _logErrorOnce(error);
    return error;
  }

  /// Errors this logger has already logged. With retries, the final error
  /// of the last attempt reaches [onError] twice (from the last attempt and
  /// from the retry loop); it is logged once.
  final Expando<bool> _loggedErrors = Expando<bool>('apiPlusLoggedError');

  void _logErrorOnce(ApiException error) {
    if (_loggedErrors[error] ?? false) return;
    _loggedErrors[error] = true;
    _logError(error);
  }

  void _logError(ApiException error) {
    if (!config.isEnabled(LogLevel.error)) return;
    if (config.requestFilter != null &&
        error.request != null &&
        !config.requestFilter!(error.request!)) {
      return;
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
          buffer.writeln('$color│ ${reset}Request: '
              '${error.request!.method.value} '
              '${_maskPathQuery(error.request!.path)}');
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
      config.maskedKeys.map(_normalizeKey).toSet();

  static final _keySeparators = RegExp(r'[\s_\-]');

  /// Lower-cases [key] and drops `_`, `-` and whitespace, so `accessToken`,
  /// `access-token` and `ACCESS_TOKEN` all match `access_token`.
  static String _normalizeKey(String key) =>
      key.toLowerCase().replaceAll(_keySeparators, '');

  bool _isMasked(Object? key) =>
      key is String && _maskedKeys.contains(_normalizeKey(key));

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

  /// The request path with its query parameters, with masked keys'
  /// values replaced (in [ApiRequest.queryParameters] and in a query string
  /// that is part of [ApiRequest.path]).
  String _describePath(ApiRequest request) {
    final path = _maskPathQuery(request.path);
    final parts = <String>[];
    request.queryParameters.forEach((key, value) {
      if (value == null) return;
      if (_isMasked(key)) {
        parts.add(_queryPart(key, config.maskString, encodeValue: false));
      } else if (value is Iterable) {
        for (final item in value) {
          parts.add(_queryPart(key, '$item'));
        }
      } else {
        parts.add(_queryPart(key, '$value'));
      }
    });
    if (parts.isEmpty) return path;
    final separator = path.contains('?') ? '&' : '?';
    return '$path$separator${parts.join('&')}';
  }

  /// Encodes one `key=value` pair like [Uri.queryParameters] does. The mask
  /// string is written as-is so it stays readable.
  static String _queryPart(
    String key,
    String value, {
    bool encodeValue = true,
  }) {
    final encodedKey = Uri.encodeQueryComponent(key);
    if (value.isEmpty) return encodedKey;
    return '$encodedKey='
        '${encodeValue ? Uri.encodeQueryComponent(value) : value}';
  }

  /// Masks the values of masked keys in a query string that is part of
  /// [path]. Other parts of the path are left exactly as they are.
  String _maskPathQuery(String path) {
    final queryStart = path.indexOf('?');
    if (queryStart < 0) return path;
    final fragmentStart = path.indexOf('#', queryStart);
    final queryEnd = fragmentStart < 0 ? path.length : fragmentStart;
    final query = path.substring(queryStart + 1, queryEnd);
    if (query.isEmpty) return path;

    var changed = false;
    final pairs = query.split('&').map((pair) {
      final equals = pair.indexOf('=');
      final rawKey = equals < 0 ? pair : pair.substring(0, equals);
      String key;
      try {
        key = Uri.decodeQueryComponent(rawKey);
      } catch (_) {
        key = rawKey;
      }
      if (!_isMasked(key)) return pair;
      changed = true;
      return '$rawKey=${config.maskString}';
    }).toList();
    if (!changed) return path;
    return '${path.substring(0, queryStart + 1)}${pairs.join('&')}'
        '${path.substring(queryEnd)}';
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
      if (config.printCurl) 'curl': _curlCommand(request),
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
    final color = config.colors ? '\x1B[36m' : ''; // Cyan
    final reset = config.colors ? '\x1B[0m' : '';
    _log('$color${_curlCommand(request)}$reset');
  }

  /// The curl command for [request], with masked values and the full URL
  /// (the adapter's base URL joined with the path).
  String _curlCommand(ApiRequest request) {
    final curl = StringBuffer('curl -X ${request.method.value}');

    _maskHeaders(request.headers).forEach((key, value) {
      curl.write(' -H "$key: $value"');
    });

    if (request.body != null) {
      final masked = _maskBody(request.body);
      final bodyStr = masked is String ? masked : _encode(masked);
      curl.write(" -d '${bodyStr.replaceAll("'", "'\\''")}'");
    }

    curl.write(' "${_describeUrl(request)}"');
    return curl.toString();
  }

  /// [_describePath] prefixed with the adapter's base URL, unless the path
  /// is already an absolute URL.
  String _describeUrl(ApiRequest request) {
    final path = _describePath(request);
    final base = request.extra[baseUrlExtraKey];
    if (base is! String || base.isEmpty || looksLikeAbsoluteUrl(path)) {
      return path;
    }
    final trimmedBase =
        base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    return path.startsWith('/') ? '$trimmedBase$path' : '$trimmedBase/$path';
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
