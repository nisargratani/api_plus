import 'package:api_plus/api_plus.dart';

void main() async {
  // Build the ApiAdapter using the fluent ApiBuilder.
  // We can seamlessly switch between Http and Dio using .clientType()
  final api = ApiBuilder('https://jsonplaceholder.typicode.com')
      .clientType(ApiClientType.dio) // Or ApiClientType.http
      .addHeader('Accept', 'application/json')
      .withLogger(const LoggerConfig(
        level: LogLevel.verbose,
        format: LogFormat.pretty,
        colors: true,
      ))
      .withRetry(const RetryConfig(
        maxRetries: 3,
        backoffStrategy: RetryBackoffStrategy.exponential,
        addJitter: true,
      ))
      .withCache(CacheConfig(
        store: MemoryCacheStore(maxEntries: 50),
        defaultTtl: const Duration(minutes: 5),
      ))
      .build();

  print('--- Executing first request (Network) ---');
  try {
    final response = await api.request(
      const ApiRequest(
        path: '/posts/1',
        method: HttpMethod.get,
      ),
    );
    print('Title: ${response.data['title']}');
  } on ApiException catch (e) {
    print('Failed: ${e.message}');
  }

  print('\n--- Executing second request (Should hit Cache) ---');
  try {
    final response2 = await api.request(
      const ApiRequest(
        path: '/posts/1',
        method: HttpMethod.get,
      ),
    );
    print('Title from cache: ${response2.data['title']}');
  } on ApiException catch (e) {
    print('Failed: ${e.message}');
  }

  api.close();
}
