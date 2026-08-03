import '../config/cache_config.dart';
import '../core/api_request.dart';
import '../core/api_response.dart';
import '../exceptions/api_exception.dart';
import '../interfaces/api_interceptor.dart';
import '../interfaces/cache_store.dart';
import '../models/http_method.dart';

/// An interceptor that implements HTTP caching logic.
class CacheInterceptor implements ApiInterceptor {
  final CacheConfig config;

  /// Creates a [CacheInterceptor] with the given [config].
  CacheInterceptor({required this.config});

  String _buildKey(ApiRequest request) {
    if (config.keyBuilder != null) {
      return config.keyBuilder!(request.method.value, request.path);
    }
    return '${request.method.value}_${request.path}_${request.queryParameters}';
  }

  @override
  Future<dynamic> onRequest(ApiRequest request) async {
    if (config.bypassCache || request.method != HttpMethod.get) {
      return request;
    }

    final key = _buildKey(request);
    final entry = await config.store.get(key);

    if (entry != null) {
      if (config.forceCache || !entry.isExpired) {
        // Return cached response immediately
        return entry.response;
      } else {
        // Entry is expired, add conditional headers for validation if possible
        Map<String, String> extraHeaders = {};
        if (entry.eTag != null) {
          extraHeaders['If-None-Match'] = entry.eTag!;
        }
        if (entry.lastModified != null) {
          extraHeaders['If-Modified-Since'] = entry.lastModified!;
        }

        if (extraHeaders.isNotEmpty) {
          final newHeaders = Map<String, String>.from(request.headers)..addAll(extraHeaders);
          return request.copyWith(headers: newHeaders);
        }
      }
    }

    return request;
  }

  @override
  Future<ApiResponse<dynamic>> onResponse(ApiResponse<dynamic> response) async {
    // Only cache GET responses, and check Cache-Control headers
    final request = response.request;
    
    if (request == null || request.method != HttpMethod.get) {
      return response;
    }

    if (response.statusCode == 304) {
      // Not Modified, return the cached response
      final key = _buildKey(request);
      final entry = await config.store.get(key);
      if (entry != null) {
        return entry.response;
      }
      return response;
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final cacheControl = response.headers['cache-control']?.first.toLowerCase() ?? '';
      if (cacheControl.contains('no-store')) {
        return response;
      }

      Duration ttl = config.defaultTtl;
      final maxAgeMatch = RegExp(r'max-age=(\d+)').firstMatch(cacheControl);
      if (maxAgeMatch != null) {
        ttl = Duration(seconds: int.parse(maxAgeMatch.group(1)!));
      }

      final key = _buildKey(request);
      
      final eTag = response.headers['etag']?.first;
      final lastModified = response.headers['last-modified']?.first;
      
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
    // If offline and request failed, try to serve stale cache
    if (error is NetworkException && error.request?.method == HttpMethod.get) {
      final key = _buildKey(error.request!);
      final entry = await config.store.get(key);
      
      if (entry != null) {
        final staleAge = DateTime.now().difference(entry.cachedAt);
        if (staleAge <= config.staleTtl) {
          // Serve stale cache
          return entry.response;
        }
      }
    }
    return error;
  }
}
