// ignore_for_file: avoid_print
import 'package:api_plus/api_plus.dart';

/// Example demonstrating Retrofit integration with api_plus.
///
/// Retrofit generates code that uses Dio internally. The [RetrofitAdapter]
/// provides a pre-configured Dio client with all api_plus interceptors
/// (retry, cache, logging) bridged in.
///
/// Usage:
/// 1. Define your Retrofit interface as usual
/// 2. Create a [RetrofitAdapter] with desired config
/// 3. Pass `adapter.client` to your Retrofit-generated constructor
void main() async {
  // Create a RetrofitAdapter with full api_plus features
  final adapter = RetrofitAdapter(
    baseUrl: 'https://jsonplaceholder.typicode.com',
    defaultHeaders: {'Accept': 'application/json'},
    retryConfig: const RetryConfig(
      maxRetries: 3,
      backoffStrategy: RetryBackoffStrategy.exponential,
    ),
    loggerConfig: const LoggerConfig(
      level: LogLevel.verbose,
      format: LogFormat.pretty,
    ),
    cacheConfig: CacheConfig(
      store: MemoryCacheStore(maxEntries: 100),
      defaultTtl: const Duration(minutes: 5),
    ),
  );

  // The `adapter.client` is a pre-configured Dio instance.
  // Pass it to your Retrofit-generated class:
  //
  //   @RestApi(baseUrl: 'https://jsonplaceholder.typicode.com')
  //   abstract class PostsApi {
  //     factory PostsApi(Dio dio) = _PostsApi;
  //
  //     @GET('/posts/{id}')
  //     Future<Post> getPost(@Path() int id);
  //   }
  //
  //   final postsApi = PostsApi(adapter.client);
  //   final post = await postsApi.getPost(1);

  print('RetrofitAdapter created with:');
  print('  - Base URL: https://jsonplaceholder.typicode.com');
  print('  - Retry: 3 attempts, exponential backoff');
  print('  - Logger: verbose, pretty format');
  print('  - Cache: memory, 5 min TTL');
  print('');
  print('Dio client ready: ${adapter.client.options.baseUrl}');
  print('Pass adapter.client to your Retrofit-generated class.');

  // Any request made with the client runs the api_plus interceptors,
  // exactly as generated Retrofit code would.
  final response = await adapter.client.get<dynamic>('/posts/1');
  print('GET /posts/1 -> ${response.statusCode}');

  // The second request is served from the api_plus cache.
  final cached = await adapter.client.get<dynamic>('/posts/1');
  print('GET /posts/1 (cached) -> ${cached.statusCode}');

  adapter.close();
}
