import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/modules/roads/road_module.dart';
import 'package:kazumi/services/player/episode_identity.dart';
import 'package:kazumi/utils/async_session.dart';

void main() {
  EpisodeIdentity episode(String title, String url) =>
      EpisodeIdentity(title: title, pageUrl: url);

  test('unique normalized ordinary label matches the reordered episode', () {
    final candidates = [
      episode('EP 02', '/new/2'),
      episode('第０１話', '/new/1'),
    ];
    expect(
      matchingEpisodeIdentity(episode('Episode 001', '/old/1'), candidates),
      1,
    );
  });

  test('a unique same-source page wins even when labels are ambiguous', () {
    final candidates = [
      episode('第1集', '/other/1'),
      episode('SP 1', '/same/1'),
    ];
    expect(
      matchingEpisodeIdentity(episode('EP 1', '/same/1'), candidates),
      1,
    );
  });

  test('duplicate page identity requires manual selection', () {
    expect(
      matchingEpisodeIdentity(episode('EP1', '/same/1'), [
        episode('EP1', '/same/1'),
        episode('SP1', '/same/1'),
      ]),
      isNull,
    );
  });

  test('duplicate normal ordinals cannot transfer old progress', () {
    final owner = AsyncSessionOwner();
    expect(
      resolveEpisodeTransfer(
        current: episode('EP01', '/old/1'),
        candidates: [
          episode('第1集', '/new/1a'),
          episode('Episode 1', '/new/1b'),
        ],
        position: const Duration(seconds: 350),
        duration: const Duration(minutes: 24),
        session: owner.begin(),
        acrossSources: true,
      ),
      isNull,
    );
  });

  test('missing identity does not borrow the old array index or offset', () {
    final owner = AsyncSessionOwner();
    expect(
      resolveEpisodeTransfer(
        current: episode('EP2', '/old/2'),
        candidates: [
          episode('EP1', '/new/1'),
          episode('EP3', '/new/3'),
        ],
        position: const Duration(seconds: 350),
        duration: const Duration(minutes: 24),
        session: owner.begin(),
        acrossSources: true,
      ),
      isNull,
    );
  });

  test('cross-source matching cannot use even an identical page URL', () {
    final current = episode('SP1', 'https://shared.test/episode/1');
    final candidates = [
      episode('EP1', 'https://shared.test/episode/1'),
    ];
    expect(matchingEpisodeIdentity(current, candidates), 0);
    expect(
      matchingEpisodeIdentity(current, candidates, acrossSources: true),
      isNull,
    );
  });

  test('specials and non-equivalent labels cannot be ordinary episodes', () {
    for (final label in [
      '预告1',
      '第1集预告',
      'SP1',
      'OVA 1',
      'PV 1',
      'Trailer 1',
      '1.5',
      'EP1 前篇',
      'Season 2 EP1',
      'OVA · 第1集',
      '第0集',
    ]) {
      expect(ordinaryEpisodeOrdinal(label), isNull, reason: label);
      expect(
        matchingEpisodeIdentity(
          episode(label, '/old/1'),
          [episode('EP1', '/new/1')],
          acrossSources: true,
        ),
        isNull,
        reason: label,
      );
    }
  });

  test('a late source response cannot resume after a newer selection',
      () async {
    final owner = AsyncSessionOwner();
    final firstSession = owner.begin();
    final response = Completer<List<EpisodeIdentity>>();
    final firstSelection =
        response.future.then((candidates) => resolveEpisodeTransfer(
              current: episode('EP2', '/old/2'),
              candidates: candidates,
              position: const Duration(seconds: 350),
              duration: const Duration(minutes: 24),
              session: firstSession,
              acrossSources: true,
            ));

    // Another source request or a manual selection replaces the pending owner.
    final currentSession = owner.begin();
    response.complete([episode('第2集', '/new/2')]);
    expect(await firstSelection, isNull);
    expect(
      resolveEpisodeTransfer(
        current: episode('EP2', '/old/2'),
        candidates: [episode('第2集', '/current/2')],
        position: const Duration(seconds: 350),
        duration: const Duration(minutes: 24),
        session: currentSession,
        acrossSources: true,
      ),
      (episodeIndex: 0, offset: 350),
    );
  });

  test('cancellation and disposal reject pending progress transfer', () {
    final owner = AsyncSessionOwner();
    final cancelled = owner.begin();
    owner.cancel();
    final disposed = owner.begin();
    owner.close();
    for (final session in [cancelled, disposed]) {
      expect(
        resolveEpisodeTransfer(
          current: episode('EP1', '/old/1'),
          candidates: [episode('EP1', '/new/1')],
          position: const Duration(seconds: 350),
          duration: const Duration(minutes: 24),
          session: session,
        ),
        isNull,
      );
    }
  });

  test('road identity uses normalized URLs and valid paired chapter fields',
      () {
    final road = Road(
      name: 'other road',
      data: ['http://example.test/ep/1/', '', '/ep/3'],
      identifier: ['第1集', 'EP2'],
    );
    const baseUrl = 'https://example.test';
    final candidates = episodeIdentitiesForRoad(road, baseUrl: baseUrl);
    expect(candidates, hasLength(2));
    expect(candidates.first.pageUrl, 'https://example.test/ep/1');
    expect(
      matchingEpisodeIdentity(
        episode('renamed title', 'https://example.test/ep/1'),
        candidates,
      ),
      0,
    );
    expect(episodeIdentityForRoad(road, 0, baseUrl: baseUrl), isNull);
    expect(episodeIdentityForRoad(road, 2, baseUrl: baseUrl), isNull);
    expect(episodeIdentityForRoad(road, 3, baseUrl: baseUrl), isNull);
    expect(
      matchingEpisodeIdentity(
        episode('EP2', '/old/2'),
        candidates,
        acrossSources: true,
      ),
      isNull,
    );
  });

  test('transfer uses bounded actual time and requires a known duration', () {
    expect(
      episodeTransferOffset(
        position: const Duration(seconds: 350, milliseconds: 900),
        duration: const Duration(minutes: 24),
      ),
      350,
    );
    expect(
      episodeTransferOffset(
        position: const Duration(minutes: 30),
        duration: const Duration(minutes: 24),
      ),
      1440,
    );
    expect(
      episodeTransferOffset(
        position: const Duration(seconds: -1),
        duration: const Duration(minutes: 24),
      ),
      0,
    );
    expect(
      episodeTransferOffset(
        position: const Duration(seconds: 350),
        duration: Duration.zero,
      ),
      0,
    );
  });
}
