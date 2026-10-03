import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/modules/history/history_module.dart';
import 'package:kazumi/modules/roads/road_module.dart';
import 'package:kazumi/services/player/cross_source_resume.dart';
import 'support/tv_focus_fixtures.dart' show focusItem;

void main() {
  final work = focusItem(25);
  History watched(
          {String label = '第2集',
          String kind = HistoryEntryKind.online,
          String adapter = 'old'}) =>
      History(work, 2, adapter, DateTime(2026, 10, 1), '/old-work', label,
          entryKind: kind, episodePageUrl: '/old-2')
        ..progresses[2] = Progress(2, 0, 123456);
  final roads = [
    Road(
        name: '重排',
        data: ['/3', '/2', '/1'],
        identifier: ['第3话', 'EP02', '第1话'])
  ];
  List<CrossSourceResume> choices(History history, {List<Road>? target}) =>
      crossSourceResumeChoices(
          histories: [history],
          bangumiId: 25,
          pluginName: 'new',
          src: '/new-work',
          roads: target ?? roads,
          baseUrl: 'https://new.invalid');

  test(
      'explicit cross-source choice uses unique label and saved actual position',
      () {
    final matches = choices(watched());
    expect(matches, hasLength(1));
    expect(matches.single.episode, 2);
    expect(matches.single.offset, 123);
    expect(matches.single.episodePageUrl, 'https://new.invalid/2');
  });
  test('an ambiguous target cannot borrow the previous array index', () {
    expect(
        choices(watched(), target: [
          Road(name: '重复', data: ['/2a', '/2b'], identifier: ['第2集', 'EP02'])
        ]),
        isEmpty);
  });
  test('special labels and missing progress offer no transfer', () {
    expect(choices(watched(label: 'SP2')), isEmpty);
    expect(choices(watched()..progresses.clear()), isEmpty);
    expect(choices(watched()..progresses[2] = Progress(1, 0, 123)), isEmpty);
  });
  test('offline, unrelated and negative records cannot supply online progress',
      () {
    expect(choices(watched(kind: HistoryEntryKind.offline)), isEmpty);
    expect(choices(watched()..progresses[2] = Progress(2, 0, -1)), isEmpty);
    expect(
        crossSourceResumeChoices(
            histories: [watched()],
            bangumiId: 26,
            pluginName: 'new',
            src: '/new-work',
            roads: roads,
            baseUrl: 'https://new.invalid'),
        isEmpty);
  });
  test('same source remains owned by existing stable-URL history resolver', () {
    final history = watched(adapter: 'new')..lastSrc = '/new-work';
    expect(choices(history), isEmpty);
  });
  test('latest unusable history never falls back to older unrelated progress',
      () {
    final later = watched(label: 'OVA 2')
      ..lastWatchTime = DateTime(2026, 10, 2);
    expect(
        crossSourceResumeChoices(
            histories: [watched(), later],
            bangumiId: 25,
            pluginName: 'new',
            src: '/new-work',
            roads: roads,
            baseUrl: 'https://new.invalid'),
        isEmpty);
  });
  test('receiver rechecks work, source, membership and destination page', () {
    final transfer = choices(watched()).single;
    bool valid({int id = 25, String plugin = 'new', List<Road>? target}) =>
        transfer.matches(
            currentBangumiId: id,
            currentPlugin: plugin,
            currentSrc: '/new-work',
            roads: target ?? roads,
            baseUrl: 'https://new.invalid');
    expect(valid(), isTrue);
    expect(valid(id: 26), isFalse);
    expect(valid(plugin: 'other'), isFalse);
    expect(
        valid(target: [
          Road(
              name: 'changed',
              data: ['/2', '/different'],
              identifier: ['EP2', 'EP3'])
        ]),
        isFalse);
  });
}
