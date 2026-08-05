import '../config/cache_config.dart';
import '../core/api_request.dart';
import '../core/api_response.dart';
import '../exceptions/api_exception.dart';
import '../interfaces/api_interceptor.dart';
import '../interfaces/cache_store.dart';
import '../models/cache_metrics.dart';

/// An interceptor that implements HTTP caching logic.
///
/// Supports Cache-Control, ETag, Last-Modified, stale-while-revalidate,
/// offline mode, and configurable cache metrics.
///
/// The caching flow:
/// 1. **onRequest**: Check cache for a valid entry. If found and fresh,
///    return it immediately. If stale, add conditional headers.
/// 2. **onResponse**: Cache successful responses, respecting
///    Cache-Control directives.
/// 3. **onError**: Serve stale cache entries during network failures.
///
/// {@tool snippet}
/// ```dart
/// final cache = CacheInterceptor(
///   config: CacheConfig(
///     store: MemoryCacheStore(maxEntries: 100),
///     defaultTtl: const Duration(minutes: 5),
///   ),
/// );
/// ```
/// {@end-tool}
class CacheInterceptor implements ApiInterceptor {
  /// The cache configuration.
  final CacheConfig config;

  /// Cache metrics for monitoring.
  ///
  /// Only populated when [CacheConfig.enableMetrics] is `true`.
  final CacheMetrics metrics = CacheMetrics();

  /// Creates a [CacheInterceptor] with the given [config].
  CacheInterceptor({required this.config});

  String _buildKey(ApiRequest request) {
    if (config.keyBuilder != null) {
      return config.keyBuilder!(request.method.value, request.path);
    }
    final buffer = StringBuffer('${request.method.value}:${request.path}');
    if (request.queryParameters.isNotEmpty) {
      final sorted = Map.fromEntries(
        request.queryParameters.entries.toList()
          ..sort((a, b) => a.key.compareTo(b.key)),
      );
      buffer.write(':$sorted');
    }
    return buffer.toString();
  }

  @override
  Future<dynamic> onRequest(ApiRequest request) async {
    if (config.bypassCache ||
        !config.cacheableMethods.contains(request.method)) {
      return request;
    }

    final key = _buildKey(request);
    final entry = await config.store.get(key);

    if (entry != null) {
      if (config.forceCache || !entry.isExpired) {
        // Return cached response immediately
        if (config.enableMetrics) {
          metrics.recordHit();
        }
        return entry.response;
      }

      // Entry is expired — add conditional headers for revalidation
      final extraHeaders = <String, String>{};
      if (entry.eTag != null) {
        extraHeaders['If-None-Match'] = entry.eTag!;
      }
      if (entry.lastModified != null) {
        extraHeaders['If-Modified-Since'] = entry.lastModified!;
      }

      if (extraHeaders.isNotEmpty) {
        final newHeaders = Map<String, String>.from(request.headers)
          ..addAll(extraHeaders);
        return request.copyWith(headers: newHeaders);
      }
    }

    if (config.enableMetrics) {
      metrics.recordMiss();
    }

    return request;
  }

  @override
  Future<ApiResponse<dynamic>> onResponse(
    ApiResponse<dynamic> response,
  ) async {
    final request = response.request;

    if (request == null || !config.cacheableMethods.contains(request.method)) {
      return response;
    }

    // Handle 304 Not Modified — return the cached response
    if (response.statusCode == 304) {
      final key = _buildKey(request);
      final entry = await config.store.get(key);
      if (entry != null) {
        if (config.enableMetrics) {
          metrics.recordHit();
        }
        return entry.response;
      }
      return response;
    }

    // Only cache successful responses
    if (response.statusCode >= 200 && response.statusCode < 300) {
      final cacheControl = _getCacheControlHeader(response);
      if (cacheControl.contains('no-store')) {
        return response;
      }

      Duration ttl = config.defaultTtl;
      final maxAgeMatch = RegExp(r'max-age=(\d+)').firstMatch(cacheControl);
      if (maxAgeMatch != null) {
        ttl = Duration(seconds: int.parse(maxAgeMatch.group(1)!));
      }

      final key = _buildKey(request);
      final eTag = _getHeaderValue(response, 'etag');
      final lastModified = _getHeaderValue(response, 'last-modified');

      final entry = CacheEntry(
        response: response,
        cachedAt: DateTime.now(),
        expiresAt: DateTime.now().add(ttl),
        eTag: eTag,
        lastModified: lastModified,
      );

      await config.store.put(key, entry);
    }

    return response;
  }

  @override
  Future<dynamic> onError(
    ApiException error,
    Future<ApiResponse<dynamic>> Function(ApiRequest) invoker,
  ) async {
    // Serve stale cache during network failures
    if (error is NetworkException &&
        error.request != null &&
        config.cacheableMethods.contains(error.request!.method)) {
      final key = _buildKey(error.request!);
      final entry = await config.store.get(key);

      if (entry != null) {
        final staleAge = DateTime.now().difference(entry.cachedAt);
        if (staleAge <= config.staleTtl) {
          if (config.enableMetrics) {
            metrics.recordStaleHit();
          }
          return entry.response;
        }
      }
    }
    return error;
  }

  String _getCacheControlHeader(ApiResponse<dynamic> response) {
    final values = response.headers['cache-control'];
    if (values == null || values.isEmpty) return '';
    return values.first.toLowerCase();
  }

  String? _getHeaderValue(ApiResponse<dynamic> response, String name) {
    final values = response.headers[name];
    if (values == null || values.isEmpty) return null;
    return values.first;
  }
}
