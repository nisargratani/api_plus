// ignore_for_file: avoid_print
import 'package:api_plus/api_plus.dart';

/// Example using the `dio` package adapter with retry and logging.
void main() async {
  final api = ApiBuilder('https://jsonplaceholder.typicode.com')
      .clientType(ApiClientType.dio)
      .addHeader('Accept', 'application/json')
      .withRetry(const RetryConfig(
        maxRetries: 3,
        backoffStrategy: RetryBackoffStrategy.exponential,
        enableMetrics: true,
      ))
      .withLogger(const LoggerConfig(
        level: LogLevel.verbose,
        format: LogFormat.pretty,
        colors: true,
        printCurl: true,
      ))
      .build();

  try {
    // GET request
    final response = await api.request<Map<String, dynamic>>(
      const ApiRequest(path: '/posts/1'),
    );
    print('Post title: ${response.data}');

    // POST request with body
    final createResponse = await api.request<Map<String, dynamic>>(
      const ApiRequest(
        path: '/posts',
        method: HttpMethod.post,
        headers: {'Content-Type': 'application/json'},
        body: {
          'title': 'New Post',
          'body': 'Created with api_plus + Dio',
          'userId': 1,
        },
      ),
    );
    print('Created: ${createResponse.data}');

    // PUT request
    final updateResponse = await api.request<Map<String, dynamic>>(
      const ApiRequest(
        path: '/posts/1',
        method: HttpMethod.put,
        headers: {'Content-Type': 'application/json'},
        body: {
          'id': 1,
          'title': 'Updated Post',
          'body': 'Updated with api_plus + Dio',
          'userId': 1,
        },
      ),
    );
    print('Updated: ${updateResponse.data}');

    // DELETE request
    final deleteResponse = await api.request<Map<String, dynamic>>(
      const ApiRequest(
        path: '/posts/1',
        method: HttpMethod.delete,
      ),
    );
    print('Deleted: ${deleteResponse.statusCode}');
  } on ApiException catch (e) {
    print('Error: ${e.message}');
  }

  api.close();
}
