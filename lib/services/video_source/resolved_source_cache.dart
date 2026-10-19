import 'video_source_service.dart';

/// Only an address that rendered a frame can be a short-lived fallback.
/// This is process-local: signed URLs and request headers never go to disk.
class ResolvedSourceCache {
  ResolvedSourceCache({
    this.ttl = const Duration(minutes: 5),
    this.capacity = 20,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now {
    if (capacity < 1 || ttl <= Duration.zero) {
      throw ArgumentError('Cache capacity and lifetime must be positive');
    }
  }

  static final shared = ResolvedSourceCache();
  final Duration ttl;
  final int capacity;
  final DateTime Function() _now;
  final _entries = <String, _Entry>{};

  Future<ResolvedSourceAttempt> resolve({
    required String key,
    required int offset,
    required Map<String, String> headers,
    required Future<VideoSource> Function() fresh,
    required bool Function() isCurrent,
  }) async {
    try {
      return ResolvedSourceAttempt(await fresh(), headers, fromCache: false);
    } on VideoSourceTimeoutException {
      final fallback = _take(key, offset, isCurrent);
      if (fallback != null) return fallback;
      rethrow;
    } on VideoSourceNotFoundException {
      final fallback = _take(key, offset, isCurrent);
      if (fallback != null) return fallback;
      rethrow;
    }
    // Cancellation and unexpected/programming errors never start playback.
  }

  ResolvedSourceAttempt? _take(
      String key, int offset, bool Function() isCurrent) {
    if (!isCurrent()) return null;
    final entry = _entries.remove(key);
    if (entry == null || !_valid(entry)) return null;
    // Consume before attempting playback: an expired/broken URL gets one try.
    return ResolvedSourceAttempt(
      VideoSource(
        url: entry.attempt.source.url,
        offset: offset,
        type: VideoSourceType.online,
        format: entry.attempt.source.format,
      ),
      entry.attempt.headers,
      fromCache: true,
    );
  }

  Future<void> rememberAfterFirstFrame({
    required String key,
    required ResolvedSourceAttempt attempt,
    required Future<void> firstFrame,
    required bool Function() isCurrent,
  }) async {
    // A fallback must not renew a signed address's lifetime or replenish it.
    if (attempt.fromCache) return;
    try {
      await firstFrame.timeout(const Duration(seconds: 20));
      if (!isCurrent()) return;
      final uri = Uri.tryParse(attempt.source.url);
      if (attempt.source.type != VideoSourceType.online ||
          uri == null ||
          !['http', 'https'].contains(uri.scheme) ||
          uri.host.isEmpty ||
          attempt.source.url.length > 16384) {
        return;
      }
      _entries.removeWhere((_, entry) => !_valid(entry));
      _entries.remove(key);
      _entries[key] = _Entry(attempt, _now());
      while (_entries.length > capacity) {
        _entries.remove(_entries.keys.first);
      }
    } catch (_) {
      // Failed/retired output is not a confirmed source; diagnostics cannot
      // turn that error into a new playback attempt.
    }
  }

  void invalidate(String key) => _entries.remove(key);

  bool _valid(_Entry entry) {
    final age = _now().difference(entry.createdAt);
    return age >= Duration.zero && age < ttl;
  }
}

class ResolvedSourceAttempt {
  ResolvedSourceAttempt(this.source, Map<String, String> headers,
      {required this.fromCache})
      : headers = Map.unmodifiable(headers);
  final VideoSource source;
  final Map<String, String> headers;
  final bool fromCache;
}

class _Entry {
  _Entry(this.attempt, this.createdAt);
  final ResolvedSourceAttempt attempt;
  final DateTime createdAt;
}
