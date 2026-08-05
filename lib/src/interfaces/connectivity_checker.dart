/// Interface for checking network connectivity.
///
/// Implement this interface to provide connectivity awareness to the
/// retry system. When connectivity is unavailable, retries can be
/// skipped to avoid unnecessary delays.
///
/// The package does not include a default implementation because
/// connectivity checking is platform-specific. Use a package like
/// `connectivity_plus` to implement this interface.
///
/// {@tool snippet}
/// ```dart
/// class AppConnectivityChecker implements ConnectivityChecker {
///   @override
///   Future<bool> get isConnected async {
///     // Use connectivity_plus or similar package
///     final result = await Connectivity().checkConnectivity();
///     return result != ConnectivityResult.none;
///   }
/// }
/// ```
/// {@end-tool}
abstract class ConnectivityChecker {
  /// Returns `true` if the device currently has network connectivity.
  ///
  /// This is called before each retry attempt. If it returns `false`,
  /// the retry is skipped and the error is propagated immediately.
  Future<bool> get isConnected;
}
