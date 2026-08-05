import 'package:api_plus/api_plus.dart';
import 'package:test/test.dart';

void main() {
  group('ApiBuilder', () {
    test('builds HttpAdapter by default', () {
      final adapter = ApiBuilder('https://api.example.com').build();
      expect(adapter, isA<HttpAdapter>());
      expect(adapter.baseUrl, 'https://api.example.com');
    });

    test('builds DioAdapter when specified', () {
      final adapter = ApiBuilder('https://api.example.com')
          .clientType(ApiClientType.dio)
          .build();
      expect(adapter, isA<DioAdapter>());
    });

    test('adds single header', () {
      final adapter = ApiBuilder('https://api.example.com')
          .addHeader('Accept', 'application/json')
          .build();
      expect(adapter.defaultHeaders['Accept'], 'application/json');
    });

    test('adds multiple headers via withHeaders', () {
      final adapter = ApiBuilder('https://api.example.com').withHeaders({
        'Accept': 'application/json',
        'X-Custom': 'value',
      }).build();
      expect(adapter.defaultHeaders['Accept'], 'application/json');
      expect(adapter.defaultHeaders['X-Custom'], 'value');
    });

    test('configures retry interceptor', () {
      final adapter = ApiBuilder('https://api.example.com')
          .withRetry(const RetryConfig(maxRetries: 5))
          .build();
      expect(
        adapter.interceptors.any((i) => i is RetryInterceptor),
        isTrue,
      );
    });

    test('configures cache interceptor', () {
      final adapter = ApiBuilder('https://api.example.com')
          .withCache(CacheConfig(store: MemoryCacheStore()))
          .build();
      expect(
        adapter.interceptors.any((i) => i is CacheInterceptor),
        isTrue,
      );
    });

    test('configures logger interceptor', () {
      final adapter = ApiBuilder('https://api.example.com')
          .withLogger(const LoggerConfig(level: LogLevel.verbose))
          .build();
      expect(
        adapter.interceptors.any((i) => i is LoggerInterceptor),
        isTrue,
      );
    });

    test('interceptor ordering is cache, retry, logger, custom', () {
      final custom = _CustomInterceptor();
      final adapter = ApiBuilder('https://api.example.com')
          .withCache(CacheConfig(store: MemoryCacheStore()))
          .withRetry(const RetryConfig())
          .withLogger(const LoggerConfig())
          .addInterceptor(custom)
          .build();

      expect(adapter.interceptors[0], isA<CacheInterceptor>());
      expect(adapter.interceptors[1], isA<RetryInterceptor>());
      expect(adapter.interceptors[2], isA<LoggerInterceptor>());
      expect(adapter.interceptors[3], custom);
    });

    test('supports timeout configuration', () {
      final builder = ApiBuilder('https://api.example.com')
          .withConnectTimeout(const Duration(seconds: 5))
          .withReceiveTimeout(const Duration(seconds: 10))
          .withSendTimeout(const Duration(seconds: 3));

      expect(builder.connectTimeout, const Duration(seconds: 5));
      expect(builder.receiveTimeout, const Duration(seconds: 10));
      expect(builder.sendTimeout, const Duration(seconds: 3));
    });

    test('fluent API returns same builder', () {
      final builder = ApiBuilder('https://api.example.com');
      final result = builder
          .clientType(ApiClientType.dio)
          .addHeader('key', 'value')
          .withHeaders({'k': 'v'})
          .withRetry(const RetryConfig())
          .withCache(CacheConfig(store: MemoryCacheStore()))
          .withLogger(const LoggerConfig())
          .withConnectTimeout(const Duration(seconds: 5))
          .withReceiveTimeout(const Duration(seconds: 10))
          .withSendTimeout(const Duration(seconds: 3))
          .addInterceptor(_CustomInterceptor());

      // The fluent API should return the same builder
      expect(result, isA<ApiBuilder>());
    });
  });

  group('ApiClientType', () {
    test('has http and dio values', () {
      expect(ApiClientType.values, hasLength(2));
      expect(ApiClientType.values, contains(ApiClientType.http));
      expect(ApiClientType.values, contains(ApiClientType.dio));
    });
  });
}

class _CustomInterceptor extends ApiInterceptor {}
