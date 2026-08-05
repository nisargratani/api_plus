/// Extensions on [Map] for common header and data manipulation.
///
/// Provides case-insensitive lookup and merging utilities commonly
/// needed when working with HTTP headers.
extension MapExtensions<V> on Map<String, V> {
  /// Returns the value for the given [key], matching case-insensitively.
  ///
  /// Returns `null` if no matching key is found.
  ///
  /// Example:
  /// ```dart
  /// final headers = {'Content-Type': 'application/json'};
  /// headers.getIgnoreCase('content-type'); // 'application/json'
  /// ```
  V? getIgnoreCase(String key) {
    final lowerKey = key.toLowerCase();
    for (final entry in entries) {
      if (entry.key.toLowerCase() == lowerKey) {
        return entry.value;
      }
    }
    return null;
  }

  /// Returns `true` if the map contains the given [key],
  /// matching case-insensitively.
  bool containsKeyIgnoreCase(String key) {
    final lowerKey = key.toLowerCase();
    return keys.any((k) => k.toLowerCase() == lowerKey);
  }
}
