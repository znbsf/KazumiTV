import 'dart:async';

/// Owns asynchronous offline writes independently from the download queue.
/// Retiring a task invalidates network replies immediately and drains only an
/// already-started write before its directory can be deleted or reused.
class DownloadDanmakuCache {
  final _jobs = <String, _CacheJob>{};

  void start(
    String key, {
    required Future<bool> Function() hasCache,
    required Future<Object?> Function() fetch,
    required Future<void> Function(Object) write,
    required bool Function() isCurrent,
    required void Function(Object, StackTrace) onError,
  }) {
    if (_jobs.containsKey(key)) return;
    final job = _CacheJob();
    _jobs[key] = job;
    bool current() => identical(_jobs[key], job) && isCurrent();
    unawaited(() async {
      try {
        if (await hasCache() || !current()) return;
        final data = await fetch();
        if (data == null || !current()) return;
        // Assign before invoking write: retirement must see the in-flight work.
        final done = Completer<void>();
        job.writing = done.future;
        try {
          await write(data);
        } finally {
          done.complete();
        }
      } catch (error, stack) {
        onError(error, stack);
      }
    }());
  }

  Future<void> retire(String key) async {
    final job = _jobs[key];
    // Repeated delete/cancel calls must all drain the same active write.
    _jobs[key] = _CacheJob()..writing = job?.writing;
    await job?.writing;
  }

  Future<void> reset(String key) async {
    await retire(key);
    _jobs.remove(key);
  }
}

class _CacheJob {
  Future<void>? writing;
}
