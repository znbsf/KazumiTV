// Local metadata navigation fixture. Never imported by production main.dart.
// Build only with the isolated featureqa debug application identity.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
// ignore: depend_on_referenced_packages
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/bean/widget/tv_app_shell.dart';
import 'package:kazumi/bean/widget/tv_visuals.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/navigation.dart';
import 'package:kazumi/pages/info/source_health_page.dart';
import 'package:kazumi/services/platform/tv_mode.dart';
import 'package:kazumi/services/source_health/source_health.dart';
import 'package:kazumi/services/storage/storage.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kDebugMode ||
      (await PackageInfo.fromPlatform()).packageName !=
          'com.znbsf.kazumi.fluttertv.featureqa') {
    throw StateError('Requires isolated featureqa debug identity');
  }
  await TvMode.initialize();
  if (!TvMode.enabled) throw StateError('Requires TV flavor');
  final root = await getApplicationSupportDirectory();
  await Hive.initFlutter('${root.path}/health-navigation-hive');
  await GStorage.init();
  FocusManager.instance.highlightStrategy =
      FocusHighlightStrategy.alwaysTraditional;
  FocusManager.instance.addListener(() {
    final focus = FocusManager.instance.primaryFocus;
    debugPrint('HEALTH_NAV_QA focus=${focus?.debugLabel} '
        'route=${focus?.context == null ? null : ModalRoute.of(focus!.context!)?.settings.name}');
  });
  runApp(MaterialApp(
    navigatorKey: rootNavigatorKey,
    scaffoldMessengerKey: rootScaffoldMessengerKey,
    navigatorObservers: [
      KazumiDialog.observer,
      rootRouteObserver,
      _QaObserver()
    ],
    theme: TvVisuals.theme(ThemeData.dark(useMaterial3: true)),
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    supportedLocales: const [Locale('zh', 'CN')],
    locale: const Locale('zh', 'CN'),
    builder: (_, child) => TvAppShell(child: child!),
    home: const _HealthNavigation(),
  ));
}

class _QaObserver extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      debugPrint(
          'HEALTH_NAV_QA push=${route.settings.name} type=${route.runtimeType}');
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => debugPrint(
      'HEALTH_NAV_QA pop=${route.settings.name} return=${previousRoute?.settings.name}');
}

List<HealthRecord> _records(int count) {
  final now = DateTime.now();
  return List.generate(count, (i) {
    final date = now.subtract(Duration(days: [0, 2, 30][i % 3], minutes: i));
    HealthRecord record(HealthStage stage, DateTime time) => HealthRecord(
          subject: 990019,
          rule: 'QA record ${i.toString().padLeft(3, '0')}',
          fingerprint: 'local-metadata-$i',
          environment: 'synthetic-navigation-only',
          checkedAt: time,
          stage: stage,
          reason: '本地导航样本；并非真实探测证据',
          ruleVersion: 'qa.1',
          episode: '1',
        );
    final stage = [
      HealthStage.firstFrame,
      HealthStage.error,
      HealthStage.timeout,
      HealthStage.noMatch
    ][i % 4];
    return record(stage, date).withSuccess(i % 4 == 1
        ? record(HealthStage.firstFrame, date.subtract(const Duration(days: 1)))
        : null);
  });
}

class _HealthNavigation extends StatefulWidget {
  const _HealthNavigation();
  @override
  State<_HealthNavigation> createState() => _HealthNavigationState();
}

class _HealthNavigationState extends State<_HealthNavigation> {
  final nodes =
      List.generate(3, (i) => FocusNode(debugLabel: 'health-qa-entry-$i'));
  Future<void> open(int index, int count) async {
    await GStorage.putSetting(SettingsKeys.sourceHealthGlobal, true);
    await GStorage.putSetting(SettingsKeys.sourceHealthRecords,
        HealthRecordCodec.encode(_records(count)));
    if (!mounted) return;
    debugPrint('HEALTH_NAV_QA open count=$count autoSelect=false plugins=0');
    await Navigator.of(context).push(MaterialPageRoute<void>(
      settings: RouteSettings(name: 'health-records-$count'),
      builder: (_) => SourceHealthPage(
        subject: BangumiItem(
            id: 990019,
            type: 2,
            name: 'Local navigation QA',
            nameCn: '本地健康记录导航',
            summary: '',
            airDate: '',
            airWeekday: 0,
            rank: 0,
            images: {},
            tags: [],
            alias: [],
            ratingScore: 0,
            votes: 0,
            votesCount: [],
            info: ''),
        // No loaded rules means even an explicit Start cannot make requests.
        // Record details correctly identify these as unloaded historic rules.
        plugins: const [],
      ),
    ));
    if (!mounted) return;
    nodes[index].requestFocus();
    debugPrint('HEALTH_NAV_QA returned count=$count');
  }

  @override
  void dispose() {
    for (final node in nodes) {
      node.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('健康记录导航 QA')),
        body: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('隔离本地样本；不访问网络，不自动探测。\n用方向键遍历记录，确认打开详情，返回检查焦点。'),
          for (var i = 0; i < 3; i++)
            Padding(
              padding: const EdgeInsets.all(12),
              child: FilledButton(
                  focusNode: nodes[i],
                  autofocus: i == 0,
                  onPressed: () => open(i, [0, 1, 128][i]),
                  child: Text('${[0, 1, 128][i]} 条记录')),
            ),
        ])),
      );
}
