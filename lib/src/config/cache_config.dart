import 'package:meta/meta.dart';
import '../interfaces/cache_store.dart';

/// Configuration for the Cache interceptor.
@immutable
class CacheConfig {
  /// The store used to save and retrieve cache entries.
  final CacheStore store;

  /// Default time-to-live for cache entries if Cache-Control/max-age is absent.
  final Duration defaultTtl;

  /// Maximum amount of time to keep stale entries for offline mode / stale-while-revalidate.
  final Duration staleTtl;

  /// Whether to use cache aggressively even if internet is available, ignoring max-age.
  final bool forceCache;

  /// Whether to bypass cache completely (forces network request).
  final bool bypassCache;

  /// Generates a cache key for a given request.
  final String Function(String method, String url)? keyBuilder;

  /// Creates a [CacheConfig].
  const CacheConfig({
    required this.store,
    this.defaultTtl = const Duration(days: 7),
    this.staleTtl = const Duration(days: 30),
    this.forceCache = false,
    this.bypassCache = false,
    this.keyBuilder,
  });
}
