/// Ownership of asynchronous work for one native video output.
class AndroidOutputLifetime {
  AndroidOutputLifetime({required this.playerDisposed});
  final bool Function() playerDisposed;
  bool _closed = false;
  bool get active => !_closed && !playerDisposed();
  void close() => _closed = true;

  Future<void> run(Future<void> Function() operation) async {
    if (!active) return;
    try {
      await operation();
    } catch (error) {
      // NativePlayer serializes commands. A command accepted before disposal
      // can reach its lock after disposal. Only that precise retired error is
      // cancellation; active errors and unrelated failures remain observable.
      if (!active &&
          error is AssertionError &&
          error.message == '[Player] has been disposed') return;
      rethrow;
    }
  }
}
