import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/services/player/player_error_mapper.dart';
import 'package:kazumi/services/player/confirmed_playback_recovery.dart';

void main() {
  test('native callback can release owner without losing prior safe diagnostic',
      () {
    var current = true;
    final events = <Object>[];
    PlayerErrorMapper.dispatchCurrentError('Failed to recognize file format',
        isCurrent: () => current,
        record: (category) => events.add(category),
        handle: (category) {
          current = false;
          events.add('released');
        });
    expect(events, [PlaybackFailureCategory.parser, 'released']);
    PlayerErrorMapper.dispatchCurrentError('late failure',
        isCurrent: () => current, record: events.add, handle: events.add);
    expect(events.length, 2);
  });
  test('diagnostic callback receives enum only, never raw private native text',
      () {
    final categories = <PlaybackFailureCategory>[];
    PlayerErrorMapper.dispatchCurrentError(
        'failed https://private.invalid/token=secret',
        isCurrent: () => true,
        record: categories.add,
        handle: (_) {});
    expect(categories, [PlaybackFailureCategory.unknown]);
  });

  test('first-frame deadline distinguishes exit, error and real frame',
      () async {
    expect(
        await observeFirstFrame(
            firstFrame: Future.value(), cancelled: Completer<void>().future),
        FirstFrameOutcome.rendered);
    expect(
        await observeFirstFrame(
            firstFrame: Completer<void>().future, cancelled: Future.value()),
        FirstFrameOutcome.cancelled);
    expect(
        await observeFirstFrame(
            firstFrame: Future.error(StateError('output')),
            cancelled: Completer<void>().future),
        FirstFrameOutcome.failed);
    expect(
        await observeFirstFrame(
            firstFrame: Completer<void>().future,
            cancelled: Completer<void>().future,
            timeout: const Duration(milliseconds: 1)),
        FirstFrameOutcome.timedOut);
  });
  test('timeout, parser, network, open and release remain distinct', () {
    final cases = <Object, PlaybackFailureCategory>{
      TimeoutException('first frame'): PlaybackFailureCategory.operationTimeout,
      'Failed to recognize file format': PlaybackFailureCategory.parser,
      'HTTP error 403 Forbidden': PlaybackFailureCategory.network,
      'Failed to open': PlaybackFailureCategory.sourceOpen,
      AssertionError('[Player] has been disposed'):
          PlaybackFailureCategory.releasedSession,
      'No audio': PlaybackFailureCategory.unknown,
      'Could not open codec.': PlaybackFailureCategory.unknown,
      'Invalid data found when processing input':
          PlaybackFailureCategory.unknown,
    };
    for (final entry in cases.entries) {
      expect(PlayerErrorMapper.classify(entry.key), entry.value);
      expect(isDirectDecoderFailure(prefix: 'vd', text: entry.key.toString()),
          isFalse);
    }
  });
  test('only named direct hardware method failure authorizes confirmation', () {
    for (final codec in ['h264', 'hevc', 'vp9', 'av1']) {
      expect(
          isDirectDecoderFailure(
              prefix: 'vd',
              text:
                  'Attempting next decoding method after failure of ${codec}_mediacodec-mediacodec.'),
          isTrue);
    }
    for (final text in [
      'Software decoding fallback is disabled.',
      'Attempting next decoding method after failure of h264.',
      'Attempting next decoding method after failure of h264_mediacodec-mediacodec-copy.',
      'HTTP error 403 Forbidden',
      'codec error',
      'hardware decoding failed'
    ]) {
      expect(isDirectDecoderFailure(prefix: 'vd', text: text), isFalse);
    }
  });
}
