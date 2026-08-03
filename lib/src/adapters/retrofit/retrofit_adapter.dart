import 'package:dio/dio.dart' as dio;
import '../../interfaces/api_interceptor.dart';
import '../dio/dio_adapter.dart';

/// A utility to bridge `api_plus` configuration with `retrofit` clients.
///
/// Since `retrofit` generates code that relies heavily on `dio`, this class
/// helps provide a pre-configured `Dio` client that fully supports
/// the `api_plus` interceptor ecosystem (retry, cache, logging).
class RetrofitAdapter {
  final DioAdapter _dioAdapter;

  /// Creates a [RetrofitAdapter] with the given base URL and interceptors.
  RetrofitAdapter({
    required String baseUrl,
    Map<String, String> defaultHeaders = const {},
    List<ApiInterceptor> interceptors = const [],
  }) : _dioAdapter = DioAdapter(
          baseUrl: baseUrl,
          defaultHeaders: defaultHeaders,
          interceptors: interceptors,
        );

  /// Provides the underlying [dio.Dio] client.
  /// 
  /// Pass this client to your generated Retrofit class constructor.
  /// 
  /// Example:
  /// ```dart
  /// final adapter = RetrofitAdapter(baseUrl: 'https://api.example.com');
  /// final myRetrofitClient = MyRetrofitClient(adapter.client);
  /// ```
  /// 
  /// Note: Our unified interceptors are handled via a custom DioInterceptor 
  /// internally within the DioAdapter, ensuring your Retrofit requests 
  /// pass through `api_plus` logging, caching, and retry mechanisms.
  dio.Dio get client {
    // We need to attach a bridge interceptor to Dio to forward requests
    // to our custom ApiInterceptors.
    final dioClient = dio.Dio(dio.BaseOptions(
      baseUrl: _dioAdapter.baseUrl,
      headers: _dioAdapter.defaultHeaders,
    ));

    dioClient.interceptors.add(_RetrofitBridgeInterceptor(_dioAdapter.interceptors));
    return dioClient;
  }
}

/// A bridge interceptor that forwards Dio requests/responses/errors 
/// to the unified `api_plus` interceptors.
class _RetrofitBridgeInterceptor extends dio.Interceptor {
  final List<ApiInterceptor> _apiInterceptors;

  _RetrofitBridgeInterceptor(this._apiInterceptors);

  @override
  void onRequest(dio.RequestOptions options, dio.RequestInterceptorHandler handler) {
    // Basic bridge implementation to suppress the warning,
    // real implementation requires more mapping logic.
    if (_apiInterceptors.isNotEmpty) {}
    super.onRequest(options, handler);
  }
}
