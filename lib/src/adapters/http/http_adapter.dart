import 'dart:async' as async;
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../core/api_request.dart';
import '../../core/api_response.dart';
import '../../core/internal_keys.dart';
import '../../exceptions/api_exception.dart';
import '../../interfaces/api_adapter.dart';
import '../../interfaces/api_interceptor.dart';
import '../adapter_mixin.dart';

/// An adapter that wraps the `http` package HTTP client.
///
/// Translates unified [ApiRequest] and [ApiResponse] types to and from
/// the `http` package's native request/response types, while running
/// all requests through the shared [InterceptorPipeline].
///
/// Request bodies are encoded as follows:
/// - [String] and `List<int>` bodies are sent as-is.
/// - [Map] bodies are sent as form fields when the `Content-Type` header is
///   `application/x-www-form-urlencoded`.
/// - Any other body is JSON-encoded, and `Content-Type` defaults to
///   `application/json; charset=utf-8`.
///
/// Response bodies are decoded using the response charset (UTF-8 by default)
/// and parsed as JSON when the `Content-Type` is a JSON type or missing.
/// Other content types are returned as a [String].
///
/// Timeouts, which match `DioAdapter`:
/// - [connectTimeout] limits opening the connection.
/// - [sendTimeout] limits uploading the request body.
/// - [receiveTimeout] limits waiting for the response and each gap between
///   chunks of the response body.
///
/// When a timeout fires or the request's [ApiRequest.cancelToken] is
/// cancelled, the underlying request is aborted. In browsers, connecting and
/// uploading cannot be observed, so only [receiveTimeout] applies there.
///
/// {@tool snippet}
/// ```dart
/// final adapter = HttpAdapter(
///   baseUrl: 'https://api.example.com',
///   defaultHeaders: {'Accept': 'application/json'},
///   interceptors: [retryInterceptor, loggerInterceptor],
///   receiveTimeout: const Duration(seconds: 15),
/// );
///
/// final response = await adapter.request<Map<String, dynamic>>(
///   const ApiRequest(path: '/users/1'),
/// );
/// ```
/// {@end-tool}
class HttpAdapter extends ApiAdapter with InterceptorPipeline {
  final http.Client _client;

  @override
  final String baseUrl;

  @override
  final Map<String, String> defaultHeaders;

  @override
  final List<ApiInterceptor> interceptors;

  /// Default connection timeout, overridden by [ApiRequest.connectTimeout].
  ///
  /// `null` or [Duration.zero] means no timeout.
  final Duration? connectTimeout;

  /// Default receive timeout, overridden by [ApiRequest.receiveTimeout].
  ///
  /// `null` or [Duration.zero] means no timeout.
  final Duration? receiveTimeout;

  /// Default send timeout, overridden by [ApiRequest.sendTimeout].
  ///
  /// `null` or [Duration.zero] means no timeout.
  final Duration? sendTimeout;

  /// Creates a new [HttpAdapter].
  ///
  /// If no [client] is provided, a new [http.Client] instance is created.
  /// The client (provided or not) is closed by [close].
  HttpAdapter({
    required this.baseUrl,
    http.Client? client,
    this.defaultHeaders = const {},
    this.interceptors = const [],
    this.connectTimeout,
    this.receiveTimeout,
    this.sendTimeout,
  }) : _client = client ?? http.Client();

  @override
  Future<ApiResponse<T>> request<T>(ApiRequest request) {
    return runPipeline<T>(request, _send);
  }

  Future<ApiResponse<dynamic>> _send(ApiRequest request) async {
    final Uri uri;
    try {
      uri = _buildUri(request);
    } on FormatException catch (e, stackTrace) {
      throw ConfigurationException(
        message: 'Invalid request URL: ${e.message}',
        error: e,
        stackTrace: stackTrace,
      );
    }
    final headers = Map<String, String>.of(request.headers);
    final body = _encodeBody(request, headers);

    final connect = _effective(request.connectTimeout ?? connectTimeout);
    final send = _effective(request.sendTimeout ?? sendTimeout);
    final receive = _effective(request.receiveTimeout ?? receiveTimeout);

    // One watchdog enforces the timeout of the current phase and reacts to
    // cancellation. When it fires, it aborts the request and fails `failure`,
    // which is raced against every await below.
    final abort = async.Completer<void>();
    final failure = async.Completer<Never>();
    async.Timer? timer;
    ApiException? failedWith;
    var finished = false;

    void fail(ApiException error) {
      if (finished || failedWith != null) return;
      failedWith = error;
      timer?.cancel();
      failure.completeError(error);
      if (!abort.isCompleted) abort.complete();
    }

    void arm(Duration? timeout, TimeoutType type) {
      timer?.cancel();
      timer = timeout == null
          ? null
          : async.Timer(timeout, () {
              fail(TimeoutException(
                message: '${_phaseLabel(type)} timed out after '
                    '${timeout.inMilliseconds}ms.',
                timeoutType: type,
                request: request,
              ));
            });
    }

    final cancelToken = request.cancelToken;
    if (cancelToken != null) {
      async.unawaited(
        cancelToken.whenCancelled.then((_) => fail(cancellationFor(request))),
      );
    }

    final httpRequest = _PhasedRequest(
      request.method.value,
      uri,
      body,
      abortTrigger: abort.future,
      // The client listens to the body once the connection is open, and the
      // body stream is done once it has been handed to the connection.
      onConnected: () => arm(send, TimeoutType.send),
      onBodySent: () => arm(receive, TimeoutType.receive),
    )..headers.addAll(headers);

    arm(connect, TimeoutType.connection);
    try {
      final streamed = await Future.any<http.StreamedResponse>([
        _client.send(httpRequest),
        failure.future,
      ]);

      arm(receive, TimeoutType.receive);
      final bytes = BytesBuilder(copy: false);
      final bodyDone = async.Completer<void>();
      final subscription = streamed.stream.listen(
        (chunk) {
          bytes.add(chunk);
          arm(receive, TimeoutType.receive);
        },
        onError: bodyDone.completeError,
        onDone: bodyDone.complete,
        cancelOnError: true,
      );
      try {
        await Future.any<void>([bodyDone.future, failure.future]);
      } catch (_) {
        async.unawaited(subscription.cancel());
        rethrow;
      }

      final contentType = streamed.headers['content-type'];
      return ApiResponse<dynamic>(
        data: _decodeBody(bytes.takeBytes(), contentType),
        statusCode: streamed.statusCode,
        headers: streamed.headers.map((k, v) => MapEntry(k, [v])),
        statusMessage: streamed.reasonPhrase,
        isRedirect: streamed.isRedirect,
        request: request,
      );
    } on ApiException {
      rethrow;
    } catch (e, stackTrace) {
      // An aborted request may surface the client's own error first.
      final watchdogError = failedWith;
      if (watchdogError != null) throw watchdogError;
      if (e is http.ClientException) {
        throw NetworkException(
          message: e.message,
          request: request,
          error: e,
          stackTrace: stackTrace,
        );
      }
      throw NetworkException(
        message: 'Unexpected network error occurred.',
        request: request,
        error: e,
        stackTrace: stackTrace,
      );
    } finally {
      finished = true;
      timer?.cancel();
    }
  }

  static String _phaseLabel(TimeoutType type) {
    switch (type) {
      case TimeoutType.connection:
        return 'Connecting';
      case TimeoutType.send:
        return 'Sending the request';
      case TimeoutType.receive:
        return 'Receiving the response';
    }
  }

  static Duration? _effective(Duration? timeout) =>
      (timeout == null || timeout <= Duration.zero) ? null : timeout;

  /// Encodes the request body, setting a default `content-type` in
  /// [headers] where needed.
  Uint8List _encodeBody(ApiRequest request, Map<String, String> headers) {
    final body = request.body;
    if (body == null) return Uint8List(0);

    String? contentType() {
      for (final entry in headers.entries) {
        if (entry.key.toLowerCase() == 'content-type') return entry.value;
      }
      return null;
    }

    void defaultContentType(String value) {
      if (contentType() == null) headers['content-type'] = value;
    }

    if (body is String) {
      defaultContentType('text/plain; charset=utf-8');
      final encoding = _charsetEncoding(contentType());
      return Uint8List.fromList(encoding.encode(body));
    }
    if (body is List<int>) {
      return body is Uint8List ? body : Uint8List.fromList(body);
    }
    if (body is Map &&
        (contentType() ?? '')
            .toLowerCase()
            .startsWith('application/x-www-form-urlencoded')) {
      final fields = <String, String>{
        for (final entry in body.entries)
          if (entry.value != null) '${entry.key}': '${entry.value}',
      };
      return utf8.encode(Uri(queryParameters: fields).query);
    }

    final String encoded;
    try {
      encoded = jsonEncode(body);
    } on JsonUnsupportedObjectError catch (e, stackTrace) {
      throw SerializationException(
        message: 'Request body could not be encoded as JSON: $e',
        request: request,
        error: e,
        stackTrace: stackTrace,
      );
    }
    defaultContentType('application/json; charset=utf-8');
    return utf8.encode(encoded);
  }

  static Encoding _charsetEncoding(String? contentType) {
    final charset = contentType == null
        ? null
        : RegExp(r'charset="?([^";\s]+)', caseSensitive: false)
            .firstMatch(contentType)
            ?.group(1);
    return (charset == null ? null : Encoding.getByName(charset)) ?? utf8;
  }

  static dynamic _decodeBody(List<int> bytes, String? contentType) {
    if (bytes.isEmpty) return null;
    final encoding = _charsetEncoding(contentType);
    final text = encoding.name == utf8.name
        ? utf8.decode(bytes, allowMalformed: true)
        : encoding.decode(bytes);

    final isJson = contentType == null ||
        contentType.split(';').first.trim().toLowerCase().endsWith('json');
    if (!isJson) return text;
    try {
      return jsonDecode(text);
    } on FormatException {
      return text;
    }
  }

  Uri _buildUri(ApiRequest request) {
    final parsed = Uri.tryParse(request.path);
    final Uri uri;
    if (parsed != null && parsed.hasScheme) {
      uri = parsed;
    } else {
      final basePath = baseUrl.endsWith('/')
          ? baseUrl.substring(0, baseUrl.length - 1)
          : baseUrl;
      final reqPath =
          request.path.startsWith('/') ? request.path : '/${request.path}';
      uri = Uri.parse('$basePath$reqPath');
    }

    final params = <String, dynamic>{};
    request.queryParameters.forEach((key, value) {
      if (value != null) {
        params[key] = value is Iterable
            ? value.map((e) => e.toString()).toList()
            : value.toString();
      }
    });
    if (params.isEmpty) return uri;
    return uri.replace(
      queryParameters: {...uri.queryParametersAll, ...params},
    );
  }

  @override
  void close({bool force = false}) {
    _client.close();
  }
}

/// A request whose body stream reports when the client starts reading it
/// (the connection is open) and when it has been fully handed over.
final class _PhasedRequest extends http.BaseRequest with http.Abortable {
  _PhasedRequest(
    super.method,
    super.url,
    this._body, {
    required this.abortTrigger,
    required this.onConnected,
    required this.onBodySent,
  }) {
    contentLength = _body.length;
  }

  static const _chunkSize = 64 * 1024;

  final Uint8List _body;
  final void Function() onConnected;
  final void Function() onBodySent;

  @override
  final Future<void>? abortTrigger;

  @override
  http.ByteStream finalize() {
    super.finalize();
    late final async.StreamController<List<int>> controller;
    controller = async.StreamController<List<int>>(
      onListen: () {
        onConnected();
        // Chunks let the connection's back-pressure delay `done` until the
        // body has actually been written.
        for (var i = 0; i < _body.length; i += _chunkSize) {
          final end =
              i + _chunkSize < _body.length ? i + _chunkSize : _body.length;
          controller.add(Uint8List.sublistView(_body, i, end));
        }
        controller.close();
      },
    );
    async.unawaited(controller.done.then((_) => onBodySent()));
    return http.ByteStream(controller.stream);
  }
}
