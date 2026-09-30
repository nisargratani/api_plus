import '../cache/memory_cache_store.dart';
import '../config/cache_config.dart';
import '../core/api_request.dart';
import '../core/api_response.dart';
import '../core/internal_keys.dart';
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
      return config.keyBuilder!(request.method.value, _pathWithQuery(request));
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

  /// The request path with its query parameters encoded (sorted by key),
  /// as passed to [CacheConfig.keyBuilder].
  static String _pathWithQuery(ApiRequest request) {
    final params = <String, dynamic>{};
    final keys = request.queryParameters.keys.toList()..sort();
    for (final key in keys) {
      final value = request.queryParameters[key];
      if (value == null) continue;
      params[key] = value is Iterable
          ? value.map((e) => e.toString()).toList()
          : value.toString();
    }
    if (params.isEmpty) return request.path;
    final separator = request.path.contains('?') ? '&' : '?';
    return '${request.path}$separator${Uri(queryParameters: params).query}';
  }

  bool _isCacheable(ApiRequest request) =>
      config.cacheableMethods.contains(request.method);

  @override
  Future<dynamic> onRequest(ApiRequest request) async {
    if (config.bypassCache || !_isCacheable(request)) {
      return request;
    }

    final key = _buildKey(request);
    final entry = await config.store.get(key);
    // Background refresh started by stale-while-revalidate: go to the network.
    final revalidating = request.extra[revalidatingExtraKey] == true;

    if (entry != null && !revalidating) {
      if (config.forceCache || !entry.isExpired) {
        // Return cached response immediately
        if (config.enableMetrics) {
          metrics.recordHit();
        }
        return entry.response;
      }

      if (config.enableStaleWhileRevalidate && entry.age <= config.staleTtl) {
        // Serve the stale entry now; the adapter refreshes it in the
        // background because of the revalidate marker.
        if (config.enableMetrics) {
          metrics.recordHit();
        }
        return entry.response.copyWith(
          request: withExtras(request, {revalidateExtraKey: true}),
        );
      }
    }

    if (config.enableMetrics && !revalidating) {
      metrics.recordMiss();
    }

    if (entry == null) return request;

    // Entry is expired — add conditional headers for revalidation
    final extraHeaders = <String, String>{
      if (entry.eTag != null) 'If-None-Match': entry.eTag!,
      if (entry.lastModified != null) 'If-Modified-Since': entry.lastModified!,
    };
    if (extraHeaders.isEmpty) return request;
    return request.copyWith(headers: {...request.headers, ...extraHeaders});
  }

  @override
  Future<ApiResponse<dynamic>> onResponse(
    ApiResponse<dynamic> response,
  ) async {
    final request = response.request;

    if (request == null || !_isCacheable(request)) {
      return response;
    }

    // Handle 304 Not Modified — return the cached response
    if (response.statusCode == 304) {
      return await _handleNotModified(request, response) ?? response;
    }

    // Only cache successful responses
    if (response.isSuccessful) {
      final ttl = _ttlFor(response);
      if (ttl == null) return response;

      final now = DateTime.now();
      await _put(
        _buildKey(request),
        CacheEntry(
          response: response,
          cachedAt: now,
          expiresAt: now.add(ttl),
          eTag: _getHeaderValue(response, 'etag'),
          lastModified: _getHeaderValue(response, 'last-modified'),
        ),
      );
    }

    return response;
  }

  @override
  Future<dynamic> onError(
    ApiException error,
    Future<ApiResponse<dynamic>> Function(ApiRequest) invoker,
  ) async {
    final request = error.request;
    if (request == null || !_isCacheable(request)) {
      return error;
    }

    // Clients that treat 304 as an error (e.g. Dio's default validateStatus)
    final response = error.response;
    if (error is ServerException &&
        response != null &&
        response.statusCode == 304) {
      return await _handleNotModified(request, response) ?? error;
    }

    // Serve stale cache during network failures
    if (error is NetworkException) {
      final entry = await config.store.get(_buildKey(request));
      if (entry != null && entry.age <= config.staleTtl) {
        if (config.enableMetrics) {
          metrics.recordStaleHit();
        }
        return entry.response;
      }
    }
    return error;
  }

  /// Stores [entry], recording evictions it causes in [metrics].
  Future<void> _put(String key, CacheEntry entry) {
    final store = config.store;
    if (!config.enableMetrics || store is! MemoryCacheStore) {
      return store.put(key, entry);
    }
    // MemoryCacheStore evicts synchronously inside put(), so reading the
    // count right after the call attributes exactly this write's evictions.
    final before = store.evictionCount;
    final done = store.put(key, entry);
    for (var i = before; i < store.evictionCount; i++) {
      metrics.recordEviction();
    }
    return done;
  }

  /// Serves the cached entry for a `304 Not Modified` [response] and
  /// renews its freshness. Returns `null` if nothing is cached.
  Future<ApiResponse<dynamic>?> _handleNotModified(
    ApiRequest request,
    ApiResponse<dynamic> response,
  ) async {
    final key = _buildKey(request);
    final entry = await config.store.get(key);
    if (entry == null) return null;

    final ttl = _ttlFor(response) ?? Duration.zero;
    final now = DateTime.now();
    await _put(
      key,
      CacheEntry(
        response: entry.response,
        cachedAt: now,
        expiresAt: now.add(ttl),
        eTag: _getHeaderValue(response, 'etag') ?? entry.eTag,
        lastModified:
            _getHeaderValue(response, 'last-modified') ?? entry.lastModified,
      ),
    );
    if (config.enableMetrics) {
      metrics.recordHit();
    }
    return entry.response;
  }

  /// How long [response] may be served from cache, or `null` if it must
  /// not be stored (`Cache-Control: no-store`).
  Duration? _ttlFor(ApiResponse<dynamic> response) {
    final cacheControl = _getCacheControlHeader(response);
    if (cacheControl.contains('no-store')) return null;
    // `no-cache` responses may be stored but must be revalidated before use.
    if (cacheControl.contains('no-cache')) return Duration.zero;

    final maxAge = _maxAgePattern.firstMatch(cacheControl)?.group(1);
    if (maxAge == null) return config.defaultTtl;
    final seconds = int.tryParse(maxAge);
    // Values too large for an int are effectively "forever".
    if (seconds == null || seconds > _maxTtlSeconds) {
      return const Duration(seconds: _maxTtlSeconds);
    }
    return Duration(seconds: seconds);
  }

  static final _maxAgePattern = RegExp(r'(?:^|[,\s])max-age\s*=\s*"?(\d+)');

  /// Ten years, the cap applied to very large `max-age` values.
  static const _maxTtlSeconds = 10 * 365 * 24 * 60 * 60;

  String _getCacheControlHeader(ApiResponse<dynamic> response) {
    final values = response.headers['cache-control'];
    if (values == null || values.isEmpty) return '';
    return values.join(',').toLowerCase();
  }

  String? _getHeaderValue(ApiResponse<dynamic> response, String name) {
    final values = response.headers[name];
    if (values == null || values.isEmpty) return null;
    return values.first;
  }
}
