import 'dart:async';

import 'package:dio/dio.dart';

const catalogueHedgeDelay = Duration(seconds: 4);

class HedgedResult<T> {
  const HedgedResult(this.value, {required this.fromBackup});

  final T value;
  final bool fromBackup;
}

/// Returns the first acceptable result, or null when neither attempt can win.
/// Attempts must keep side effects outside the race and honour their token.
Future<HedgedResult<T>?> hedgedRequest<T>({
  required Future<T> Function(CancelToken) primary,
  required Future<T> Function(CancelToken) backup,
  required bool Function(Object) canRetry,
  required bool Function(T) acceptBackup,
  Duration delay = catalogueHedgeDelay,
}) {
  final result = Completer<HedgedResult<T>?>();
  final primaryToken = CancelToken();
  final backupToken = CancelToken();
  Timer? timer;
  var primaryDone = false;
  var backupStarted = false;
  var backupDone = false;

  void finish(HedgedResult<T>? winner) {
    if (result.isCompleted) return;
    timer?.cancel();
    if (winner?.fromBackup != false) primaryToken.cancel('Hedge settled');
    if (winner?.fromBackup != true) backupToken.cancel('Hedge settled');
    result.complete(winner);
  }

  void failIfDone() {
    if (primaryDone && backupDone) finish(null);
  }

  Future<void> runBackup() async {
    try {
      final value = await backup(backupToken);
      if (result.isCompleted) return;
      backupDone = true;
      if (acceptBackup(value)) {
        finish(HedgedResult(value, fromBackup: true));
      } else {
        failIfDone();
      }
    } catch (_) {
      if (result.isCompleted) return;
      backupDone = true;
      failIfDone();
    }
  }

  void startBackup() {
    if (result.isCompleted || backupStarted) return;
    backupStarted = true;
    timer?.cancel();
    unawaited(runBackup());
  }

  Future<void> runPrimary() async {
    try {
      final value = await primary(primaryToken);
      if (!result.isCompleted) {
        finish(HedgedResult(value, fromBackup: false));
      }
    } catch (error) {
      if (result.isCompleted) return;
      primaryDone = true;
      if (!backupStarted) {
        if (!canRetry(error)) {
          finish(null);
          return;
        }
        startBackup();
      }
      failIfDone();
    }
  }

  timer = Timer(delay, startBackup);
  unawaited(runPrimary());
  return result.future;
}
