/// URL helpers shared by the adapters.
///
/// This file is intentionally not exported from the package.
library;

/// Matches a path that starts with a URL scheme followed by `//`
/// (`https://`, `http://`, ...), i.e. an absolute URL with an authority.
final RegExp _absoluteUrlPattern = RegExp(r'^[a-zA-Z][a-zA-Z0-9+.\-]*://');

/// Whether [path] is written as an absolute URL (`scheme://...`).
bool looksLikeAbsoluteUrl(String path) => _absoluteUrlPattern.hasMatch(path);

/// Parses [path] as an absolute URL.
///
/// Throws a [FormatException] if it cannot be parsed or has no host, so a
/// malformed absolute URL is never sent to the base URL as a relative path.
Uri parseAbsoluteUrl(String path) {
  final uri = Uri.parse(path);
  if (uri.host.isEmpty) {
    throw FormatException('The URL has no host', path);
  }
  return uri;
}
