import 'package:meta/meta.dart';
import '../models/http_method.dart';
import 'api_cancel_token.dart';

/// Represents a unified API request to be handled by any underlying adapter.
///
/// This is the core request type used throughout the `api_plus` package.
/// It provides a client-agnostic representation of an HTTP request that
/// can be processed by any adapter (http, dio, retrofit).
///
/// {@tool snippet}
/// ```dart
/// const request = ApiRequest(
///   path: '/users/1',
///   method: HttpMethod.get,
///   headers: {'Accept': 'application/json'},
/// );
/// ```
/// {@end-tool}
@immutable
class ApiRequest {
  /// The path or full URL for the request.
  ///
  /// Can be a relative path (e.g., `/users/1`) which will be appended to
  /// the adapter's base URL, or a full URL.
  final String path;

  /// The HTTP method to use for this request.
  ///
  /// Defaults to [HttpMethod.get].
  final HttpMethod method;

  /// The request headers.
  ///
  /// These are merged with the adapter's default headers, with request-level
  /// headers taking precedence.
  final Map<String, String> headers;

  /// The query parameters to append to the URL.
  ///
  /// They are merged with any query string already present in [path].
  /// `null` values are omitted; [Iterable] values produce repeated keys.
  final Map<String, dynamic> queryParameters;

  /// The body payload, if any.
  ///
  /// Can be a [String], [Map], [List], or [List<int>] depending on the
  /// content type. The adapter handles serialization.
  final dynamic body;

  /// Optional connection timeout for this specific request.
  ///
  /// Overrides the adapter's default timeout if set.
  final Duration? connectTimeout;

  /// Optional receive timeout for this specific request.
  ///
  /// Overrides the adapter's default timeout if set.
  final Duration? receiveTimeout;

  /// Optional send timeout for this specific request.
  ///
  /// Overrides the adapter's default timeout if set.
  final Duration? sendTimeout;

  /// Extra context data for interceptors.
  ///
  /// Used internally by interceptors to pass state (e.g., retry count,
  /// request start time). Can also be used by custom interceptors.
  final Map<String, dynamic> extra;

  /// Optional token for cancelling this request.
  ///
  /// When the token is cancelled, the request is aborted (including any
  /// pending retry delay) and throws a `CancellationException`. The token
  /// is not part of [==] or [hashCode].
  final ApiCancelToken? cancelToken;

  /// Creates a new [ApiRequest].
  ///
  /// The [path] is required. All other parameters have sensible defaults.
  ///
  /// Example:
  /// ```dart
  /// const request = ApiRequest(
  ///   path: '/posts',
  ///   method: HttpMethod.post,
  ///   body: {'title': 'Hello', 'body': 'World'},
  /// );
  /// ```
  const ApiRequest({
    required this.path,
    this.method = HttpMethod.get,
    this.headers = const {},
    this.queryParameters = const {},
    this.body,
    this.connectTimeout,
    this.receiveTimeout,
    this.sendTimeout,
    this.extra = const {},
    this.cancelToken,
  });

  /// Creates a copy of this request with the given fields replaced.
  ///
  /// Any field not provided will retain its current value.
  ApiRequest copyWith({
    String? path,
    HttpMethod? method,
    Map<String, String>? headers,
    Map<String, dynamic>? queryParameters,
    dynamic body,
    Duration? connectTimeout,
    Duration? receiveTimeout,
    Duration? sendTimeout,
    Map<String, dynamic>? extra,
    ApiCancelToken? cancelToken,
  }) {
    return ApiRequest(
      path: path ?? this.path,
      method: method ?? this.method,
      headers: headers ?? this.headers,
      queryParameters: queryParameters ?? this.queryParameters,
      body: body ?? this.body,
      connectTimeout: connectTimeout ?? this.connectTimeout,
      receiveTimeout: receiveTimeout ?? this.receiveTimeout,
      sendTimeout: sendTimeout ?? this.sendTimeout,
      extra: extra ?? this.extra,
      cancelToken: cancelToken ?? this.cancelToken,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! ApiRequest) return false;
    return path == other.path &&
        method == other.method &&
        _mapsEqual(headers, other.headers) &&
        _mapsEqual(queryParameters, other.queryParameters) &&
        body == other.body &&
        connectTimeout == other.connectTimeout &&
        receiveTimeout == other.receiveTimeout &&
        sendTimeout == other.sendTimeout;
  }

  @override
  int get hashCode => Object.hash(
        path,
        method,
        // Order-independent, consistent with the map comparison in ==.
        Object.hashAllUnordered(
          headers.entries.map((e) => Object.hash(e.key, e.value)),
        ),
        body,
        connectTimeout,
        receiveTimeout,
        sendTimeout,
      );

  @override
  String toString() => 'ApiRequest(${method.value} $path)';

  static bool _mapsEqual<K, V>(Map<K, V> a, Map<K, V> b) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key) || a[key] != b[key]) return false;
    }
    return true;
  }
}
