/// Interface for custom log output destinations.
///
/// Implement this interface to direct log messages to custom
/// destinations such as files, remote logging services, or
/// custom console formatters.
///
/// {@tool snippet}
/// ```dart
/// class FileLogPrinter implements LogPrinter {
///   final File _logFile;
///
///   FileLogPrinter(this._logFile);
///
///   @override
///   void log(String message) {
///     _logFile.writeAsStringSync('$message\n', mode: FileMode.append);
///   }
/// }
/// ```
/// {@end-tool}
abstract class LogPrinter {
  /// Outputs a log [message].
  ///
  /// Called by the logger interceptor for each log entry.
  /// Implementations should handle their own buffering and flushing.
  void log(String message);
}
