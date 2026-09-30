// ignore_for_file: avoid_print
import 'package:api_plus/api_plus.dart';

/// Example demonstrating comprehensive error handling with api_plus.
///
/// Shows how to handle every common API error type with typed exceptions.
void main() async {
  final api = ApiBuilder('https://jsonplaceholder.typicode.com')
      .clientType(ApiClientType.dio)
      .withLogger(const LoggerConfig(
        level: LogLevel.error,
        format: LogFormat.compact,
        colors: false,
        printCurl: false,
      ))
      .build();

  // ─── Typed Error Handling ─────────────────────────────────────────
  print('=== Comprehensive Error Handling ===\n');

  await _demonstrateErrorHandling(api, '/posts/1', 'Success case');
  await _demonstrateErrorHandling(api, '/posts/999999', 'Not found case');

  // ─── Cancellation ─────────────────────────────────────────────────
  print('\n=== Cancellation ===');
  final cancelToken = ApiCancelToken();
  final pending = api.request<Map<String, dynamic>>(
    ApiRequest(path: '/posts', cancelToken: cancelToken),
  );
  cancelToken.cancel('No longer needed');
  try {
    await pending;
  } on CancellationException catch (e) {
    print('  ❌ ${e.message}');
  }

  // ─── Error Types Reference ────────────────────────────────────────
  print('\n=== Error Types Hierarchy ===');
  print('''
  ApiException (base)
  ├── NetworkException
  │   └── TimeoutException (connection/send/receive)
  ├── CancellationException
  ├── ServerException
  │   ├── BadRequestException         (400)
  │   ├── UnauthorizedException       (401)
  │   ├── ForbiddenException          (403)
  │   ├── NotFoundException           (404)
  │   ├── MethodNotAllowedException   (405)
  │   ├── RequestTimeoutException     (408)
  │   ├── ConflictException           (409)
  │   ├── RequestEntityTooLargeException (413)
  │   ├── UnprocessableEntityException (422)
  │   ├── TooManyRequestsException    (429)
  │   ├── InternalServerException     (500)
  │   ├── BadGatewayException         (502)
  │   ├── ServiceUnavailableException (503)
  │   └── GatewayTimeoutException     (504)
  ├── SerializationException
  ├── RetryLimitExceededException
  ├── ConfigurationException
  └── CacheException
  ''');

  api.close();
}

Future<void> _demonstrateErrorHandling(
  ApiAdapter api,
  String path,
  String label,
) async {
  print('--- $label: GET $path ---');
  try {
    final response = await api.request<Map<String, dynamic>>(
      ApiRequest(path: path),
    );
    print('  ✅ Success: ${response.statusCode}');
  } on UnauthorizedException catch (e) {
    print('  🔒 Unauthorized (401): ${e.message}');
    print('     → Redirect to login screen');
  } on ForbiddenException catch (e) {
    print('  🚫 Forbidden (403): ${e.message}');
    print('     → Show permission denied');
  } on NotFoundException catch (e) {
    print('  🔍 Not Found (404): ${e.message}');
    print('     → Show not found screen');
  } on TooManyRequestsException catch (e) {
    print('  ⏳ Rate Limited (429): ${e.message}');
    print('     → Back off and retry later');
  } on TimeoutException catch (e) {
    print('  ⏱️ Timeout (${e.timeoutType}): ${e.message}');
    print('     → Show timeout message');
  } on CancellationException catch (e) {
    print('  ❌ Cancelled: ${e.message}');
    print('     → User cancelled the request');
  } on NetworkException catch (e) {
    print('  📡 Network Error: ${e.message}');
    print('     → Show offline/connectivity message');
  } on ServerException catch (e) {
    print('  🖥️ Server Error (${e.response?.statusCode}): ${e.message}');
    print('     → Show generic server error');
  } on SerializationException catch (e) {
    print('  📦 Parse Error: ${e.message}');
    print('     → Log and show generic error');
  } on ApiException catch (e) {
    print('  ⚠️ API Error: ${e.message}');
    print('     → Catch-all handler');
  }
}
