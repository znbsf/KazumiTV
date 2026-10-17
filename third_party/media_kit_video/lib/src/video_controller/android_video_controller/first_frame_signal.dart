import 'dart:async';

/// One output instance's first consumed frame. A resized/initialized texture
/// is deliberately not evidence. Tokens also reject a retired native output's
/// delayed notification if libmpv later reuses the same player handle.
class AndroidFirstFrameSignal {
  AndroidFirstFrameSignal({required this.token, required this.supported});

  final String token;
  final bool supported;
  final _completer = Completer<void>();
  bool _disposed = false;

  Future<void> get future => _completer.future;

  void notify(Object? outputToken) {
    if (!_disposed && supported && outputToken == token && !_completer.isCompleted) {
      _completer.complete();
    }
  }

  // Unconfirmed/unsupported/disposed outputs never become successful evidence.
  // Callers retain responsibility for bounded timeout/cancellation.
  void dispose() => _disposed = true;
}
