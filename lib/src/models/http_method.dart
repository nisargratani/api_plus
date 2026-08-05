/// Represents the HTTP methods supported by the API clients.
///
/// Each method has a [value] property containing the uppercase string
/// representation as used in HTTP protocol (e.g., `'GET'`, `'POST'`).
///
/// {@tool snippet}
/// ```dart
/// const method = HttpMethod.get;
/// print(method.value); // 'GET'
/// print(method.isIdempotent); // true
/// ```
/// {@end-tool}
enum HttpMethod {
  /// HTTP GET method — retrieves a resource.
  get('GET'),

  /// HTTP POST method — creates a resource.
  post('POST'),

  /// HTTP PUT method — replaces a resource.
  put('PUT'),

  /// HTTP DELETE method — deletes a resource.
  delete('DELETE'),

  /// HTTP PATCH method — partially updates a resource.
  patch('PATCH'),

  /// HTTP HEAD method — retrieves headers only.
  head('HEAD'),

  /// HTTP OPTIONS method — describes communication options.
  options('OPTIONS');

  /// The uppercase string representation of this HTTP method.
  final String value;

  const HttpMethod(this.value);

  /// Returns `true` if this method is idempotent.
  ///
  /// Idempotent methods can be safely retried without side effects.
  /// GET, HEAD, PUT, DELETE, and OPTIONS are idempotent.
  bool get isIdempotent => this != post && this != patch;

  @override
  String toString() => value;
}
