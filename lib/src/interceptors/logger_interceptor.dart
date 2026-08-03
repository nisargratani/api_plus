import 'dart:convert';
import '../config/logger_config.dart';
import '../core/api_request.dart';
import '../core/api_response.dart';
import '../exceptions/api_exception.dart';
import '../interfaces/api_interceptor.dart';

/// An interceptor that logs API requests, responses, and errors.
class LoggerInterceptor implements ApiInterceptor {
  final LoggerConfig config;

  /// Creates a [LoggerInterceptor] with the given [config].
  LoggerInterceptor({this.config = const LoggerConfig()});

  void _log(String message) {
    if (config.output != null) {
      config.output!(message);
    } else {
      // ignore: avoid_print
      print(message);
    }
  }

  @override
  Future<dynamic> onRequest(ApiRequest request) async {
    if (!config.isEnabled(LogLevel.info)) return request;

    // Attach start time for execution time tracking
    final newExtra = Map<String, dynamic>.from(request.extra);
    newExtra['requestStartTime'] = DateTime.now().millisecondsSinceEpoch;
    final finalRequest = request.copyWith(extra: newExtra);

    if (config.format == LogFormat.json) {
      _logJsonRequest(finalRequest);
    } else if (config.format == LogFormat.pretty) {
      _logPrettyRequest(finalRequest);
    } else {
      _logCompactRequest(finalRequest);
    }

    if (config.printCurl) {
      _logCurlCommand(finalRequest);
    }

    return finalRequest;
  }

  @override
  Future<ApiResponse<dynamic>> onResponse(ApiResponse<dynamic> response) async {
    if (!config.isEnabled(LogLevel.info)) return response;

    // request is available via response.request
    // For simplicity, we just log the response.
    // For simplicity, we just log the response.
    
    if (config.format == LogFormat.json) {
      _logJsonResponse(response);
    } else if (config.format == LogFormat.pretty) {
      _logPrettyResponse(response);
    } else {
      _logCompactResponse(response);
    }

    return response;
  }

  @override
  Future<dynamic> onError(
    ApiException error,
    Future<ApiResponse<dynamic>> Function(ApiRequest) invoker,
  ) async {
    if (!config.isEnabled(LogLevel.error)) return error;

    if (config.format == LogFormat.json) {
      _logJsonError(error);
    } else {
      final color = config.colors ? '\x1B[31m' : '';
      final reset = config.colors ? '\x1B[0m' : '';
      _log('$color[ERROR] ${error.message}$reset');
      if (error.response != null) {
        _logPrettyResponse(error.response!);
      }
    }

    return error; // Let it propagate
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

  // --- Json Formatting ---

  void _logJsonRequest(ApiRequest request) {
    final logData = {
      'type': 'request',
      'method': request.method.value,
      'url': request.path,
      if (config.printRequestHeaders) 'headers': _maskHeaders(request.headers),
      if (config.printRequestBody) 'body': request.body,
    };
    _log(jsonEncode(logData));
  }

  void _logJsonResponse(ApiResponse<dynamic> response) {
    final logData = {
      'type': 'response',
      'statusCode': response.statusCode,
      if (config.printResponseHeaders) 'headers': response.headers,
      if (config.printResponseBody) 'body': response.data,
    };
    _log(jsonEncode(logData));
  }

  void _logJsonError(ApiException error) {
    final logData = {
      'type': 'error',
      'message': error.message,
      'statusCode': error.response?.statusCode,
      'url': error.request?.path,
    };
    _log(jsonEncode(logData));
  }

  // --- Pretty Formatting ---

  void _logPrettyRequest(ApiRequest request) {
    final color = config.colors ? '\x1B[34m' : ''; // Blue
    final reset = config.colors ? '\x1B[0m' : '';
    
    final buffer = StringBuffer();
    buffer.writeln('$color┌── Request ──────────────────────────────────────────────────$reset');
    buffer.writeln('$color│ $reset${request.method.value} ${request.path}');
    
    if (config.printRequestHeaders && request.headers.isNotEmpty) {
      buffer.writeln('$color├─ Headers:$reset');
      _maskHeaders(request.headers).forEach((key, value) {
        buffer.writeln('$color│ $reset  $key: $value');
      });
    }

    if (config.printRequestBody && request.body != null) {
      buffer.writeln('$color├─ Body:$reset');
      buffer.writeln('$color│ $reset  ${_tryFormatJson(request.body)}');
    }
    buffer.writeln('$color└────────────────────────────────────────────────────────────$reset');
    _log(buffer.toString());
  }

  void _logPrettyResponse(ApiResponse<dynamic> response) {
    final isSuccess = response.statusCode >= 200 && response.statusCode < 300;
    final color = config.colors ? (isSuccess ? '\x1B[32m' : '\x1B[33m') : ''; // Green or Yellow
    final reset = config.colors ? '\x1B[0m' : '';

    final buffer = StringBuffer();
    buffer.writeln('$color┌── Response ─────────────────────────────────────────────────$reset');
    buffer.writeln('$color│ ${reset}Status: ${response.statusCode} ${response.statusMessage ?? ''}');
    
    if (config.printResponseHeaders && response.headers.isNotEmpty) {
      buffer.writeln('$color├─ Headers:$reset');
      response.headers.forEach((key, value) {
        buffer.writeln('$color│ $reset  $key: ${value.join(', ')}');
      });
    }

    if (config.printResponseBody && response.data != null) {
      buffer.writeln('$color├─ Body:$reset');
      buffer.writeln('$color│ $reset  ${_tryFormatJson(response.data)}');
    }
    buffer.writeln('$color└────────────────────────────────────────────────────────────$reset');
    _log(buffer.toString());
  }

  // --- Compact Formatting ---

  void _logCompactRequest(ApiRequest request) {
    _log('REQ: ${request.method.value} ${request.path}');
  }

  void _logCompactResponse(ApiResponse<dynamic> response) {
    _log('RES: [${response.statusCode}]');
  }

  // --- Utilities ---

  void _logCurlCommand(ApiRequest request) {
    final curl = StringBuffer('curl -X ${request.method.value}');
    
    _maskHeaders(request.headers).forEach((key, value) {
      curl.write(' -H "$key: $value"');
    });

    if (request.body != null) {
      final bodyStr = request.body is String ? request.body : jsonEncode(request.body);
      curl.write(" -d '${bodyStr.replaceAll("'", "'\\''")}'");
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
