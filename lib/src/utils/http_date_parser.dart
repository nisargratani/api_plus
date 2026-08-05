/// Utilities for parsing HTTP date formats as defined in RFC 7231.
///
/// Supports the three HTTP-date formats:
/// 1. IMF-fixdate (preferred): `Sun, 06 Nov 1994 08:49:37 GMT`
/// 2. RFC 850 (obsolete): `Sunday, 06-Nov-94 08:49:37 GMT`
/// 3. asctime: `Sun Nov  6 08:49:37 1994`
class HttpDateParser {
  HttpDateParser._();

  static const _months = <String, int>{
    'Jan': 1,
    'Feb': 2,
    'Mar': 3,
    'Apr': 4,
    'May': 5,
    'Jun': 6,
    'Jul': 7,
    'Aug': 8,
    'Sep': 9,
    'Oct': 10,
    'Nov': 11,
    'Dec': 12,
  };

  /// Parses an HTTP-date string into a [DateTime].
  ///
  /// Supports IMF-fixdate, RFC 850, and asctime formats.
  /// Returns `null` if the string cannot be parsed.
  ///
  /// Example:
  /// ```dart
  /// final date = HttpDateParser.parse('Sun, 06 Nov 1994 08:49:37 GMT');
  /// // Returns 1994-11-06T08:49:37Z
  /// ```
  static DateTime? parse(String value) {
    final trimmed = value.trim();

    // Try IMF-fixdate: Sun, 06 Nov 1994 08:49:37 GMT
    final imfMatch = RegExp(
      r'^\w{3}, (\d{2}) (\w{3}) (\d{4}) (\d{2}):(\d{2}):(\d{2}) GMT$',
    ).firstMatch(trimmed);
    if (imfMatch != null) {
      return _buildDate(
        day: int.parse(imfMatch.group(1)!),
        month: _months[imfMatch.group(2)!],
        year: int.parse(imfMatch.group(3)!),
        hour: int.parse(imfMatch.group(4)!),
        minute: int.parse(imfMatch.group(5)!),
        second: int.parse(imfMatch.group(6)!),
      );
    }

    // Try RFC 850: Sunday, 06-Nov-94 08:49:37 GMT
    final rfc850Match = RegExp(
      r'^\w+, (\d{2})-(\w{3})-(\d{2}) (\d{2}):(\d{2}):(\d{2}) GMT$',
    ).firstMatch(trimmed);
    if (rfc850Match != null) {
      var year = int.parse(rfc850Match.group(3)!);
      year += year < 70 ? 2000 : 1900;
      return _buildDate(
        day: int.parse(rfc850Match.group(1)!),
        month: _months[rfc850Match.group(2)!],
        year: year,
        hour: int.parse(rfc850Match.group(4)!),
        minute: int.parse(rfc850Match.group(5)!),
        second: int.parse(rfc850Match.group(6)!),
      );
    }

    // Try asctime: Sun Nov  6 08:49:37 1994
    final asctimeMatch = RegExp(
      r'^\w{3} (\w{3})\s+(\d{1,2}) (\d{2}):(\d{2}):(\d{2}) (\d{4})$',
    ).firstMatch(trimmed);
    if (asctimeMatch != null) {
      return _buildDate(
        day: int.parse(asctimeMatch.group(2)!),
        month: _months[asctimeMatch.group(1)!],
        year: int.parse(asctimeMatch.group(6)!),
        hour: int.parse(asctimeMatch.group(3)!),
        minute: int.parse(asctimeMatch.group(4)!),
        second: int.parse(asctimeMatch.group(5)!),
      );
    }

    return null;
  }

  static DateTime? _buildDate({
    required int day,
    int? month,
    required int year,
    required int hour,
    required int minute,
    required int second,
  }) {
    if (month == null) return null;
    try {
      return DateTime.utc(year, month, day, hour, minute, second);
    } catch (_) {
      return null;
    }
  }
}
