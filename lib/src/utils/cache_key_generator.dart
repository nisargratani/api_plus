import 'dart:convert';

/// Generates deterministic cache keys from request parameters.
///
/// `CacheInterceptor` stores entries under these keys (unless
/// `CacheConfig.keyBuilder` is set), so an app can invalidate one entry
/// after a mutation:
///
/// ```dart
/// await store.delete(
///   CacheKeyGenerator.generate('GET', '/posts', {'userId': 1}),
/// );
/// ```
///
/// Pass the same `path` and `queryParameters` as in the `ApiRequest`.
class CacheKeyGenerator {
  CacheKeyGenerator._();

  /// Generates a cache key from the HTTP [method], [url], and
  /// optional [queryParameters].
  ///
  /// Query parameters are sorted by name and JSON-encoded, so requests
  /// with different parameters never share a key. `null` values are
  /// ignored, because the adapters omit them from the URL. Values that are
  /// not JSON-encodable are encoded with `toString()`.
  ///
  /// Example:
  /// ```dart
  /// final key = CacheKeyGenerator.generate('GET', '/users', {'page': '1'});
  /// // GET:/users:{"page":"1"}
  /// ```
  static String generate(
    String method,
    String url, [
    Map<String, dynamic>? queryParameters,
  ]) {
    final buffer = StringBuffer('$method:$url');
    if (queryParameters != null && queryParameters.isNotEmpty) {
      final sorted = Map.fromEntries(
        queryParameters.entries.where((e) => e.value != null).toList()
          ..sort((a, b) => a.key.compareTo(b.key)),
      );
      if (sorted.isNotEmpty) {
        buffer.write(
          ':${jsonEncode(sorted, toEncodable: (value) => value.toString())}',
        );
      }
    }
    return buffer.toString();
  }
}
