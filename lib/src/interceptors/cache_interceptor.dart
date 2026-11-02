import '../cache/memory_cache_store.dart';
import '../config/cache_config.dart';
import '../core/api_request.dart';
import '../core/api_response.dart';
import '../core/internal_keys.dart';
import '../exceptions/api_exception.dart';
import '../interfaces/api_interceptor.dart';
import '../interfaces/cache_store.dart';
import '../models/cache_metrics.dart';
import '../utils/cache_key_generator.dart';
import '../utils/http_date_parser.dart';

/// An interceptor that implements HTTP caching logic.
///
/// Supports Cache-Control, ETag, Last-Modified, stale-while-revalidate,
/// offline mode, and configurable cache metrics.
///
/// The caching flow:
/// 1. **onRequest**: Check cache for a valid entry. If found and fresh,
///    return it immediately. If stale, add conditional headers.
/// 2. **onResponse**: Cache successful responses, respecting
///    `Cache-Control` (`max-age`, `no-store`, `no-cache`) and `Expires`.
/// 3. **onError**: Serve stale cache entries during network failures.
///    When a `RetryInterceptor` runs before this interceptor (the order
///    `ApiBuilder` uses), the stale entry is served only after the retry
///    interceptor has given up.
///
/// Entries are stored under [CacheKeyGenerator.generate] keys (unless
/// [CacheConfig.keyBuilder] is set), so one entry can be invalidated with
/// `store.delete(CacheKeyGenerator.generate('GET', path, queryParameters))`.
///
/// The cache never fails a request: if the [CacheStore] throws, a failed
/// read is treated as a miss and a failed write is skipped.
///
/// A response served from the cache reports the current request as its
/// [ApiResponse.request], not the request that originally filled the cache.
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
    return CacheKeyGenerator.generate(
      request.method.value,
      request.path,
      request.queryParameters,
    );
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
    final entry = await _get(key);
    // Background refresh started by stale-while-revalidate: go to the network.
    final revalidating = request.extra[revalidatingExtraKey] == true;
    // Each request is counted once: background refreshes and retry attempts
    // are not counted again.
    final count =
        config.enableMetrics && !revalidating && !isRetryAttempt(request);

    if (entry != null && !revalidating) {
      if (config.forceCache || !entry.isExpired) {
        // Return cached response immediately
        if (count) metrics.recordHit();
        return withRequest<dynamic>(entry.response, request);
      }

      if (config.enableStaleWhileRevalidate &&
          entry.age <= config.staleTtl &&
          !_requiresValidation(entry.response)) {
        // Serve the stale entry now; the adapter refreshes it in the
        // background because of the revalidate marker.
        if (count) metrics.recordHit();
        return withRequest<dynamic>(
          entry.response,
          withExtras(request, {revalidateExtraKey: true}),
        );
      }
    }

    if (entry == null) {
      if (count) metrics.recordMiss();
      return request;
    }

    // Entry is expired — add conditional headers for revalidation
    final extraHeaders = <String, String>{
      if (entry.eTag != null) 'If-None-Match': entry.eTag!,
      if (entry.lastModified != null) 'If-Modified-Since': entry.lastModified!,
    };
    if (extraHeaders.isEmpty) {
      // Nothing to revalidate with: a plain refetch.
      if (count) metrics.recordMiss();
      return request;
    }
    // A revalidation is counted once its outcome is known: a hit on
    // `304 Not Modified`, a miss when the server sends new content.
    return request.copyWith(
      headers: {...request.headers, ...extraHeaders},
      extra: {...request.extra, cacheRevalidationExtraKey: true},
    );
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
      if (config.enableMetrics &&
          request.extra[cacheRevalidationExtraKey] == true &&
          request.extra[revalidatingExtraKey] != true) {
        // The revalidation returned new content.
        metrics.recordMiss();
      }

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
      // A failed retry attempt: the retry loop decides whether to try
      // again, so the stale entry is only served once it gives up.
      if (isRetryAttempt(request) && !isRetryFinished(error)) {
        return error;
      }
      final entry = await _get(_buildKey(request));
      if (entry != null && entry.age <= config.staleTtl) {
        if (config.enableMetrics) {
          metrics.recordStaleHit();
        }
        return withRequest<dynamic>(entry.response, request);
      }
    }
    return error;
  }

  /// Reads [key] from the store. A failing store is treated as a miss.
  Future<CacheEntry?> _get(String key) async {
    try {
      return await config.store.get(key);
    } catch (_) {
      // The cache is an optimisation: fall back to the network.
      return null;
    }
  }

  /// Stores [entry], recording evictions it causes in [metrics]. A failing
  /// store is ignored, so the response is still returned.
  Future<void> _put(String key, CacheEntry entry) async {
    final store = config.store;
    try {
      if (!config.enableMetrics || store is! MemoryCacheStore) {
        await store.put(key, entry);
        return;
      }
      // MemoryCacheStore evicts synchronously inside put(), so reading the
      // count right after the call attributes exactly this write's
      // evictions.
      final before = store.evictionCount;
      final done = store.put(key, entry);
      for (var i = before; i < store.evictionCount; i++) {
        metrics.recordEviction();
      }
      await done;
    } catch (_) {
      // The cache is an optimisation: skip the write, keep the response.
    }
  }

  /// Serves the cached entry for a `304 Not Modified` [response] and
  /// renews its freshness. Returns `null` if nothing is cached.
  Future<ApiResponse<dynamic>?> _handleNotModified(
    ApiRequest request,
    ApiResponse<dynamic> response,
  ) async {
    final key = _buildKey(request);
    final entry = await _get(key);
    if (entry == null) return null;

    // The 304's headers update the stored ones (RFC 9111 §4.3.4): a 304
    // without its own Cache-Control/Expires keeps the stored response's
    // freshness rules, so e.g. `no-cache` is revalidated again next time.
    final merged = ApiResponse<dynamic>(
      statusCode: entry.response.statusCode,
      headers: {...entry.response.headers, ...response.headers},
    );
    final ttl = _ttlFor(merged) ?? Duration.zero;
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
    // A background refresh was already counted when the stale entry was
    // served.
    if (config.enableMetrics && request.extra[revalidatingExtraKey] != true) {
      metrics.recordHit();
    }
    return withRequest<dynamic>(entry.response, request);
  }

  /// How long [response] may be served from cache, or `null` if it must
  /// not be stored (`Cache-Control: no-store`).
  ///
  /// `max-age` wins over `Expires`; [CacheConfig.defaultTtl] applies only
  /// when neither is present.
  Duration? _ttlFor(ApiResponse<dynamic> response) {
    final cacheControl = _getCacheControlHeader(response);
    if (_hasDirective(cacheControl, 'no-store')) return null;
    // `no-cache` responses may be stored but must be revalidated before use.
    if (_hasDirective(cacheControl, 'no-cache')) return Duration.zero;

    final maxAge = _maxAgePattern.firstMatch(cacheControl)?.group(1);
    if (maxAge != null) {
      final seconds = int.tryParse(maxAge);
      // Values too large for an int are effectively "forever".
      if (seconds == null || seconds > _maxTtlSeconds) {
        return const Duration(seconds: _maxTtlSeconds);
      }
      return Duration(seconds: seconds);
    }

    final expires = _getHeaderValue(response, 'expires');
    if (expires != null) return _ttlFromExpires(expires, response);
    return config.defaultTtl;
  }

  /// The freshness lifetime given by an `Expires` header (RFC 9111 §4.2.1):
  /// `Expires` minus `Date` (or now). Invalid dates such as `0` or `-1`,
  /// and dates in the past, mean "already expired".
  static Duration _ttlFromExpires(
    String value,
    ApiResponse<dynamic> response,
  ) {
    final expires = HttpDateParser.parse(value);
    if (expires == null) return Duration.zero;
    final date = _getHeaderValue(response, 'date');
    final base =
        (date == null ? null : HttpDateParser.parse(date)) ?? DateTime.now();
    final ttl = expires.difference(base);
    if (ttl <= Duration.zero) return Duration.zero;
    const max = Duration(seconds: _maxTtlSeconds);
    return ttl > max ? max : ttl;
  }

  /// Whether a stored [response] must be revalidated before it is used, so
  /// stale-while-revalidate may not serve it (`no-cache`, `must-revalidate`).
  static bool _requiresValidation(ApiResponse<dynamic> response) {
    final cacheControl = _getCacheControlHeader(response);
    return _hasDirective(cacheControl, 'no-cache') ||
        _hasDirective(cacheControl, 'must-revalidate');
  }

  /// Whether the (lower-cased) [cacheControl] value contains the directive
  /// [name], with or without an argument.
  static bool _hasDirective(String cacheControl, String name) {
    for (final directive in cacheControl.split(',')) {
      final separator = directive.indexOf('=');
      final directiveName =
          (separator < 0 ? directive : directive.substring(0, separator))
              .trim();
      if (directiveName == name) return true;
    }
    return false;
  }

  static final _maxAgePattern = RegExp(r'(?:^|[,\s])max-age\s*=\s*"?(\d+)');

  /// Ten years, the cap applied to very large `max-age` values.
  static const _maxTtlSeconds = 10 * 365 * 24 * 60 * 60;

  static String _getCacheControlHeader(ApiResponse<dynamic> response) {
    final values = response.headers['cache-control'];
    if (values == null || values.isEmpty) return '';
    return values.join(',').toLowerCase();
  }

  static String? _getHeaderValue(
    ApiResponse<dynamic> response,
    String name,
  ) {
    final values = response.headers[name];
    if (values == null || values.isEmpty) return null;
    return values.first;
  }
}
