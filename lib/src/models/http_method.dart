/// Represents the HTTP methods supported by the API clients.
enum HttpMethod {
  /// GET method
  get('GET'),

  /// POST method
  post('POST'),

  /// PUT method
  put('PUT'),

  /// DELETE method
  delete('DELETE'),

  /// PATCH method
  patch('PATCH'),

  /// HEAD method
  head('HEAD'),

  /// OPTIONS method
  options('OPTIONS');

  /// The string representation of the HTTP method.
  final String value;

  const HttpMethod(this.value);

  @override
  String toString() => value;
}
