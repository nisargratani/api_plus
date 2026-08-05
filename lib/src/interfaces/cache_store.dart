import '../core/api_response.dart';

/// Represents a cached response entry with metadata.
///
/// Contains the cached [response] along with timing information
/// and HTTP conditional request headers (ETag, Last-Modified) for
/// efficient cache revalidation.
class CacheEntry {
  /// The cached response.
  final ApiResponse<dynamic> response;

  /// When this entry was originally cached.
  final DateTime cachedAt;

  /// The expiration date of this entry, if any.
  ///
  /// If `null`, the entry does not expire unless explicitly evicted.
  final DateTime? expiresAt;

  /// The ETag header value for conditional requests.
  ///
  /// Used with `If-None-Match` headers to validate the cache entry
  /// without re-downloading the full response.
  final String? eTag;

  /// The Last-Modified header value for conditional requests.
  ///
  /// Used with `If-Modified-Since` headers to validate the cache entry.
  final String? lastModified;

  /// Creates a [CacheEntry].
  const CacheEntry({
    required this.response,
    required this.cachedAt,
    this.expiresAt,
    this.eTag,
    this.lastModified,
  });

  /// Returns `true` if this entry has expired based on [expiresAt].
  ///
  /// Returns `false` if [expiresAt] is `null` (entry never expires).
  bool get isExpired {
    if (expiresAt == null) return false;
    return DateTime.now().isAfter(expiresAt!);
  }

  /// Returns the age of this cache entry.
  Duration get age => DateTime.now().difference(cachedAt);
}

/// Defines the contract for an HTTP cache storage system.
///
/// Implementations can store cache entries in memory, on disk,
/// in SQLite, SharedPreferences, Hive, or any other storage backend.
///
/// {@tool snippet}
/// ```dart
/// class MyCustomStore implements CacheStore {
///   @override
///   Future<CacheEntry?> get(String key) async {
///     // Retrieve from custom storage
///   }
///
///   @override
///   Future<void> put(String key, CacheEntry entry) async {
///     // Store to custom storage
///   }
///
///   @override
///   Future<void> delete(String key) async {
///     // Delete from custom storage
///   }
///
///   @override
///   Future<void> clear() async {
///     // Clear all entries
///   }
///
///   @override
///   Future<bool> containsKey(String key) async {
///     // Check if key exists
///   }
///
///   @override
///   Future<int> get size async {
///     // Return number of entries
///   }
/// }
/// ```
/// {@end-tool}
abstract class CacheStore {
  /// Retrieves a cached response by [key].
  ///
  /// Returns `null` if no entry exists for the given key.
  Future<CacheEntry?> get(String key);

  /// Saves a cached [entry] associated with the given [key].
  ///
  /// If an entry with the same key already exists, it is replaced.
  Future<void> put(String key, CacheEntry entry);

  /// Deletes a cached entry by [key].
  ///
  /// Does nothing if no entry exists for the given key.
  Future<void> delete(String key);

  /// Clears all entries in the cache store.
  Future<void> clear();

  /// Returns `true` if the store contains an entry for the given [key].
  Future<bool> containsKey(String key);

  /// Returns the number of entries currently in the cache store.
  Future<int> get size;
}
