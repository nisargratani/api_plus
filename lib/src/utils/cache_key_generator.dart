import 'dart:convert';

/// Generates deterministic cache keys from request parameters.
///
/// Used by the cache interceptor to create consistent keys for
/// storing and retrieving cached responses.
class CacheKeyGenerator {
  CacheKeyGenerator._();

  /// Generates a cache key from the HTTP [method], [url], and
  /// optional [queryParameters].
  ///
  /// The key is a deterministic hash-like string that uniquely
  /// identifies the request.
  ///
  /// Example:
  /// ```dart
  /// final key = CacheKeyGenerator.generate('GET', '/users', {'page': '1'});
  /// ```
  static String generate(
    String method,
    String url, [
    Map<String, dynamic>? queryParameters,
  ]) {
    final buffer = StringBuffer('$method:$url');
    if (queryParameters != null && queryParameters.isNotEmpty) {
      final sorted = Map.fromEntries(
        queryParameters.entries.toList()
          ..sort((a, b) => a.key.compareTo(b.key)),
      );
      buffer.write(
        ':${jsonEncode(sorted, toEncodable: (value) => value.toString())}',
      );
    }
    return buffer.toString();
  }
}
