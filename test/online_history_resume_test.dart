import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/modules/history/history_module.dart';
import 'package:kazumi/modules/roads/road_module.dart';
import 'package:kazumi/services/player/online_history_resume.dart';
import 'support/tv_focus_fixtures.dart' show focusItem;

void main() {
  History history(
          {String url = '/ep/2',
          int road = 0,
          int episode = 2,
          int milliseconds = 18000}) =>
      History(
          focusItem(1), episode, 'plugin', DateTime(2026), '/subject', 'EP2',
          episodePageUrl: url)
        ..progresses[episode] = Progress(episode, road, milliseconds);
  Road road(List<String> urls, {List<String>? titles}) => Road(
      name: 'road',
      data: urls,
      identifier: titles ?? List.generate(urls.length, (i) => 'EP${i + 1}'));
  OnlineHistoryResume? resolve(History? saved, List<Road> roads,
          {bool enabled = true, String src = '/subject'}) =>
      resolveOnlineHistoryResume(
          history: saved,
          roads: roads,
          baseUrl: 'https://example.test',
          currentSrc: src,
          playResume: enabled);

  test('unchanged online history resumes its native progress', () {
    expect(
        resolve(history(), [
          road(['/ep/1', '/ep/2'])
        ]),
        (episode: 2, road: 0, offset: 18));
  });
  test('reordered episodes resume the same page instead of the old index', () {
    expect(
        resolve(history(), [
          road(['/ep/2', '/ep/1'])
        ]),
        (episode: 1, road: 0, offset: 18));
  });
  test('reordered roads locate the same page across the current snapshot', () {
    expect(
        resolve(history(), [
          road(['/other']),
          road(['/ep/2'])
        ]),
        (episode: 1, road: 1, offset: 18));
  });
  test('missing known page cannot transfer its offset to a different episode',
      () {
    expect(
        resolve(history(), [
          road(['/other/1', '/other/2'])
        ]),
        isNull);
  });
  test('URL matching uses the existing source normalization', () {
    expect(
        resolve(history(url: 'http://example.test/ep/2/'), [
          road(['/ep/2'])
        ]),
        (episode: 1, road: 0, offset: 18));
  });
  test('duplicate pages prefer the previously used valid road', () {
    expect(
        resolve(history(road: 1), [
          road(['/ep/2']),
          road(['/ep/1', '/ep/2'])
        ]),
        (episode: 2, road: 1, offset: 18));
  });
  test('legacy history without page URL retains bounded index fallback', () {
    expect(
        resolve(history(url: ''), [
          road(['/ep/1', '/ep/2'])
        ]),
        (episode: 2, road: 0, offset: 18));
  });
  for (final invalid in [
    (road: -1, episode: 2),
    (road: 3, episode: 2),
    (road: 0, episode: 0),
    (road: 0, episode: 3)
  ]) {
    test('invalid legacy selection $invalid is ignored safely', () {
      expect(
          resolve(
              history(url: '', road: invalid.road, episode: invalid.episode), [
            road(['/ep/1', '/ep/2'])
          ]),
          isNull);
    });
  }
  test('a road without the matching display title is not playable', () {
    expect(
        resolve(history(), [
          road(['/ep/1', '/ep/2'], titles: ['EP1'])
        ]),
        isNull);
  });
  test('negative saved progress is clamped before native playback', () {
    expect(
        resolve(history(milliseconds: -1000), [
          road(['/ep/1', '/ep/2'])
        ]),
        (episode: 2, road: 0, offset: 0));
  });
  test('disabled resume keeps the episode identity but seeks to zero', () {
    expect(
        resolve(
            history(),
            [
              road(['/ep/2', '/ep/1'])
            ],
            enabled: false),
        (episode: 1, road: 0, offset: 0));
  });
  test('no history is a normal fresh playback', () {
    expect(
        resolve(null, [
          road(['/ep/1'])
        ]),
        isNull);
  });
  test('a newly selected series never receives another source resume offset',
      () {
    expect(
        resolve(
            history(),
            [
              road(['/ep/1', '/ep/2'])
            ],
            src: '/new-subject'),
        isNull);
  });
  test('legacy empty source metadata can still resume a known episode', () {
    final saved = history()..lastSrc = '';
    expect(
        resolve(saved, [
          road(['/ep/1', '/ep/2'])
        ]),
        (episode: 2, road: 0, offset: 18));
  });
  test('a stable page can recover after the old road index became invalid', () {
    expect(
        resolve(history(road: -1), [
          road(['/ep/2'])
        ]),
        (episode: 1, road: 0, offset: 18));
  });
}
