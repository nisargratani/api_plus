import '../core/api_response.dart';

/// Represents a cached response entry.
class CacheEntry {
  /// The cached response.
  final ApiResponse<dynamic> response;

  /// When this entry was cached.
  final DateTime cachedAt;

  /// The expiration date of this entry, if any.
  final DateTime? expiresAt;

  /// ETag for conditional requests.
  final String? eTag;

  /// Last-Modified for conditional requests.
  final String? lastModified;

  /// Creates a [CacheEntry].
  const CacheEntry({
    required this.response,
    required this.cachedAt,
    this.expiresAt,
    this.eTag,
    this.lastModified,
  });

  /// Checks if the entry is expired based on [expiresAt].
  bool get isExpired {
    if (expiresAt == null) return false;
    return DateTime.now().isAfter(expiresAt!);
  }
}

/// Defines the contract for an HTTP cache storage system.
abstract class CacheStore {
  /// Retrieves a cached response by [key].
  Future<CacheEntry?> get(String key);

  /// Saves a cached [entry] by [key].
  Future<void> put(String key, CacheEntry entry);

  /// Deletes a cached entry by [key].
  Future<void> delete(String key);

  /// Clears all entries in the cache store.
  Future<void> clear();
}
