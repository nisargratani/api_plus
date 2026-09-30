import 'dart:async';

import 'api_request.dart';

/// Cancels in-flight requests.
///
/// Pass the same token to any number of [ApiRequest]s; calling [cancel]
/// aborts all of them that are still running, including pending retry
/// delays, and makes them throw a `CancellationException`. Requests started
/// with an already-cancelled token fail immediately without a network call.
///
/// A token cannot be reset; create a new one for new requests.
///
/// {@tool snippet}
/// ```dart
/// class _ScreenState extends State<Screen> {
///   final _cancelToken = ApiCancelToken();
///
///   Future<void> _load() async {
///     final response = await api.request<Map<String, dynamic>>(
///       ApiRequest(path: '/feed', cancelToken: _cancelToken),
///     );
///     // ...
///   }
///
///   @override
///   void dispose() {
///     _cancelToken.cancel('Screen disposed');
///     super.dispose();
///   }
/// }
/// ```
/// {@end-tool}
class ApiCancelToken {
  final Completer<void> _completer = Completer<void>();
  Object? _reason;

  /// Creates a token that is not cancelled.
  ApiCancelToken();

  /// Whether [cancel] has been called.
  bool get isCancelled => _completer.isCompleted;

  /// The reason passed to [cancel], if any.
  Object? get reason => _reason;

  /// Completes when [cancel] is called. Never completes with an error.
  Future<void> get whenCancelled => _completer.future;

  /// Cancels every request using this token.
  ///
  /// Calling it again has no effect; the first [reason] is kept.
  void cancel([Object? reason]) {
    if (isCancelled) return;
    _reason = reason;
    _completer.complete();
  }
}
