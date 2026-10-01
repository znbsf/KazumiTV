// Business/routing fixture only. The /video/ destination explicitly replaces
// native MPV decoding; it never pretends that a widget test played real media.
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/bean/widget/tv_app_shell.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/history/history_module.dart';
import 'package:kazumi/navigation.dart';
import 'package:kazumi/pages/collect/collect_controller.dart';
import 'package:kazumi/pages/collect/collect_page.dart';
import 'package:kazumi/pages/download/download_controller.dart';
import 'package:kazumi/pages/history/history_controller.dart';
import 'package:kazumi/pages/history/history_page.dart';
import 'package:kazumi/pages/info/info_controller.dart';
import 'package:kazumi/pages/info/info_page.dart';
import 'package:kazumi/pages/info/source_sheet.dart';
import 'package:kazumi/pages/search/search_controller.dart';
import 'package:kazumi/pages/search/search_page.dart';
import 'package:kazumi/pages/video/video_playback_args.dart';
import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/plugins/plugins_controller.dart';
import 'package:kazumi/repositories/collect_crud_repository.dart';
import 'package:kazumi/repositories/collect_repository.dart';
import 'package:kazumi/repositories/history_repository.dart';
import 'package:kazumi/repositories/search_history_repository.dart';
import 'package:kazumi/services/player/history_playback_service.dart';
import 'package:kazumi/services/player/online_history_resume.dart';
import 'package:kazumi/services/player/playback_history_recorder.dart';

class UnattendedFlowApp extends StatelessWidget {
  UnattendedFlowApp({
    super.key,
    required List<Plugin> sourcePlugins,
    required Zone persistenceZone,
    this.initialRoute = '/search/',
    this.sourceSubject,
  }) {
    collection =
        _RealIoCollectController(CollectCrudRepository(), persistenceZone);
    historyRepository = HistoryRepository();
    history = _RealIoHistoryController(historyRepository, persistenceZone);
    search = SearchPageController(
        CollectRepository(), _RealIoSearchHistoryRepository(persistenceZone));
    plugins = PluginsController()..pluginList.addAll(sourcePlugins);
    playback =
        HistoryPlaybackService(plugins, _UnusedOfflineDownloadBoundary());
    module = createModule(register: (container) {
      container.addInstance<CollectController>(collection);
      container.addInstance<ICollectCrudRepository>(CollectCrudRepository());
      container.addInstance<IHistoryRepository>(historyRepository);
      container.addInstance<PluginsController>(plugins);
      container.addInstance<HistoryPlaybackService>(playback);
      container.route('/search/',
          child: (_, __) => SearchPage(controller: search));
      container.route('/collection/',
          child: (_, __) => CollectPage(controller: collection));
      container.route('/history/',
          child: (_, __) => HistoryPage(controller: history));
      container.route('/info/', child: (_, state) {
        final subject = state.arguments as BangumiItem;
        openedSubjectIds.add(subject.id);
        return InfoPage(
          inputBangumiItem: subject,
          infoController: _infoControllers.putIfAbsent(
              subject.id, () => InfoController(collection)),
        );
      });
      container.route('/sources/', child: (_, __) {
        final controller = _sourceControllers.putIfAbsent(sourceSubject!.id,
            () => InfoController(collection)..bangumiItem = sourceSubject!);
        return Scaffold(body: SourceSheet(infoController: controller));
      });
      container.route('/video/', child: (_, state) {
        final args = state.arguments as OnlineVideoPlaybackArgs;
        return StubNativeVideoBoundary(
          args: args,
          history: history,
          repository: historyRepository,
          onOpened: () => openedVideoArgs.add(args),
        );
      });
    });
  }

  final String initialRoute;
  final BangumiItem? sourceSubject;
  late final Module module;
  late final CollectController collection;
  late final HistoryRepository historyRepository;
  late final HistoryController history;
  late final SearchPageController search;
  late final PluginsController plugins;
  late final HistoryPlaybackService playback;
  final openedSubjectIds = <int>[];
  final openedVideoArgs = <OnlineVideoPlaybackArgs>[];
  final _infoControllers = <int, InfoController>{};
  final _sourceControllers = <int, InfoController>{};

  @override
  Widget build(BuildContext context) => ModularApp(
        module: module,
        initialRoute: initialRoute,
        navigatorKey: rootNavigatorKey,
        navigatorObservers: [rootRouteObserver, KazumiDialog.observer],
        child: Builder(
          builder: (context) => MaterialApp.router(
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
              colorSchemeSeed: Colors.green,
              brightness: Brightness.dark,
            ),
            routerConfig: ModularApp.routerConfigOf(context),
            builder: (_, child) => TvAppShell(child: child!),
          ),
        ),
      );
}

// Forward to the unmodified production controllers/repository in the real
// test-runner zone. Widget fake-async frames otherwise retain Hive disk-write
// queue callbacks after the in-memory update and deadlock close/reopen.
class _RealIoCollectController extends CollectController {
  _RealIoCollectController(super.repository, this.ioZone);
  final Zone ioZone;

  @override
  Future<void> addCollect(BangumiItem item, {type = 1}) =>
      ioZone.run(() => super.addCollect(item, type: type));
}

class _RealIoHistoryController extends HistoryController {
  _RealIoHistoryController(super.repository, this.ioZone);
  final Zone ioZone;

  @override
  Future<void> updateHistory(
          PlaybackHistoryIdentity identity, Duration progress,
          {Duration duration = Duration.zero}) =>
      ioZone.run(
          () => super.updateHistory(identity, progress, duration: duration));
}

class _RealIoSearchHistoryRepository extends SearchHistoryRepository {
  _RealIoSearchHistoryRepository(this.ioZone);
  final Zone ioZone;

  @override
  Future<bool> saveHistory(String keyword) =>
      ioZone.run(() => super.saveHistory(keyword));
}

// The workflow is online. Fail loudly if it accidentally enters an untested
// download/native-service branch instead of silently faking its behavior.
class _UnusedOfflineDownloadBoundary implements DownloadController {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError(
      'Offline download boundary was invoked by an online workflow: '
      '${invocation.memberName}');
}

class StubNativeVideoBoundary extends StatefulWidget {
  const StubNativeVideoBoundary({
    super.key,
    required this.args,
    required this.history,
    required this.repository,
    required this.onOpened,
  });

  final OnlineVideoPlaybackArgs args;
  final HistoryController history;
  final IHistoryRepository repository;
  final VoidCallback onOpened;

  @override
  State<StubNativeVideoBoundary> createState() =>
      _StubNativeVideoBoundaryState();
}

class _StubNativeVideoBoundaryState extends State<StubNativeVideoBoundary> {
  late final OnlineHistoryResume? resume;
  late final PlaybackHistoryRecorder recorder;
  late final int episode;
  late final int road;
  late final int offset;

  @override
  void initState() {
    super.initState();
    widget.onOpened();
    final args = widget.args;
    final transfer = args.transfer;
    final validTransfer = transfer != null &&
        transfer.matches(
          currentBangumiId: args.bangumiItem.id,
          currentPlugin: args.plugin.name,
          currentSrc: args.src,
          roads: args.roads,
          baseUrl: args.plugin.baseUrl,
        );
    resume = args.allowHistoryResume
        ? resolveOnlineHistoryResume(
            history: widget.repository
                .getHistory(args.plugin.name, args.bangumiItem),
            roads: args.roads,
            baseUrl: args.plugin.baseUrl,
            currentSrc: args.src,
            playResume: true,
          )
        : null;
    episode = validTransfer ? transfer.episode : resume?.episode ?? 1;
    road = validTransfer ? transfer.road : resume?.road ?? 0;
    offset = validTransfer ? transfer.offset : resume?.offset ?? 0;
    recorder = PlaybackHistoryRecorder((position, duration) {
      final selected = args.roads[road];
      return widget.history.updateHistory(
        PlaybackHistoryIdentity.online(
          bangumiItem: args.bangumiItem,
          pluginName: args.plugin.name,
          episodeNumber: episode,
          episodeTitle: selected.identifier[episode - 1],
          road: road,
          onlineBangumiSrc: args.src,
          episodePageUrl: selected.data[episode - 1],
        ),
        position,
        duration: duration,
      );
    });
  }

  Future<void> _nativeSnapshot(bool playing) => recorder.record(
        // Explicit MPV state stub, independent of requested route offsets.
        position: const Duration(seconds: 347),
        duration: const Duration(minutes: 24),
        playing: playing,
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Stub MPV/native decoding boundary')),
        body: Column(children: [
          Text(
              'subject ${widget.args.bangumiItem.id}; episode $episode; offset $offset',
              key: const Key('workflow-native-selection')),
          FilledButton(
            key: const Key('workflow-unplayed-snapshot'),
            onPressed: () => _nativeSnapshot(false),
            child: const Text('Inject unplayed native state'),
          ),
          FilledButton(
            key: const Key('workflow-played-snapshot'),
            onPressed: () => _nativeSnapshot(true),
            child: const Text('Inject played native state'),
          ),
          TextButton(
            key: const Key('workflow-player-back'),
            onPressed: () => Navigator.of(context).maybePop(),
            child: const Text('Return from native boundary'),
          ),
        ]),
      );
}
