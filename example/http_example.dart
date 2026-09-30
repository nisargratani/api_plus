// ignore_for_file: avoid_print
import 'package:api_plus/api_plus.dart';

/// Example using the `http` package adapter.
void main() async {
  final api = ApiBuilder('https://jsonplaceholder.typicode.com')
      .clientType(ApiClientType.http)
      .addHeader('Accept', 'application/json')
      .withLogger(const LoggerConfig(
        level: LogLevel.info,
        format: LogFormat.compact,
        colors: false,
      ))
      .build();

  try {
    final response = await api.request<Map<String, dynamic>>(
      const ApiRequest(path: '/users/1'),
    );
    print('User: ${response.data!['name']}');
  } on ApiException catch (e) {
    print('Error: ${e.message}');
  }

  api.close();
}
