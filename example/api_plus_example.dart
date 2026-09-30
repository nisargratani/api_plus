// ignore_for_file: avoid_print
import 'package:api_plus/api_plus.dart';

/// Complete example demonstrating the core api_plus features:
/// retry, caching, logging, and error handling with the Dio adapter.
void main() async {
  // ─── Build the API client ─────────────────────────────────────────
  final api = ApiBuilder('https://jsonplaceholder.typicode.com')
      .clientType(ApiClientType.dio)
      .addHeader('Accept', 'application/json')
      .withLogger(const LoggerConfig(
        level: LogLevel.verbose,
        format: LogFormat.pretty,
        colors: true,
        printCurl: true,
        printExecutionTime: true,
        maskedKeys: {'authorization', 'api_key'},
      ))
      .withRetry(const RetryConfig(
        maxRetries: 3,
        backoffStrategy: RetryBackoffStrategy.exponential,
        baseDelay: Duration(seconds: 1),
        addJitter: true,
        enableMetrics: true,
      ))
      .withCache(CacheConfig(
        store: MemoryCacheStore(maxEntries: 50),
        defaultTtl: const Duration(minutes: 5),
        enableMetrics: true,
      ))
      .build();

  // ─── GET Request ──────────────────────────────────────────────────
  print('=== GET /posts/1 (First request — from network) ===\n');
  try {
    final response = await api.request<Map<String, dynamic>>(
      const ApiRequest(
        path: '/posts/1',
        method: HttpMethod.get,
      ),
    );
    print('Status: ${response.statusCode}');
    print('Title: ${response.data!['title']}');
  } on ApiException catch (e) {
    print('Failed: ${e.message}');
  }

  // ─── Cached GET Request ───────────────────────────────────────────
  print('\n=== GET /posts/1 (Second request — from cache) ===\n');
  try {
    final response = await api.request<Map<String, dynamic>>(
      const ApiRequest(
        path: '/posts/1',
        method: HttpMethod.get,
      ),
    );
    print('Status: ${response.statusCode}');
    print('Title: ${response.data!['title']}');
  } on ApiException catch (e) {
    print('Failed: ${e.message}');
  }

  // ─── POST Request ─────────────────────────────────────────────────
  print('\n=== POST /posts (Create) ===\n');
  try {
    final response = await api.request<Map<String, dynamic>>(
      const ApiRequest(
        path: '/posts',
        method: HttpMethod.post,
        headers: {'Content-Type': 'application/json'},
        body: {
          'title': 'Hello api_plus',
          'body': 'Enterprise-grade networking!',
          'userId': 1,
        },
      ),
    );
    print('Created with status: ${response.statusCode}');
    print('Response: ${response.data}');
  } on ApiException catch (e) {
    print('Failed: ${e.message}');
  }

  // ─── Error Handling Demo ──────────────────────────────────────────
  print('\n=== GET /posts/999999 (Not Found) ===\n');
  try {
    await api.request<Map<String, dynamic>>(
      const ApiRequest(path: '/posts/999999'),
    );
  } on NotFoundException catch (e) {
    print('404 Not Found: ${e.message}');
  } on ServerException catch (e) {
    print('Server error ${e.response?.statusCode}: ${e.message}');
  } on NetworkException catch (e) {
    print('Network error: ${e.message}');
  } on ApiException catch (e) {
    print('API error: ${e.message}');
  }

  // ─── Cleanup ──────────────────────────────────────────────────────
  api.close();
}
