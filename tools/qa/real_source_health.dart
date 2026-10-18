// Internal single-attempt real-site QA. Never imported by production main.dart.
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:media_kit/media_kit.dart';
// ignore: depend_on_referenced_packages
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/pages/info/source_health_page.dart';
import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/services/platform/tv_mode.dart';
import 'package:kazumi/services/platform/webview_feature_service.dart';
import 'package:kazumi/services/source_health/source_health.dart';
import 'package:kazumi/services/storage/storage.dart';

// Captured 2026-10-17. No rule download or host request at runtime.
// https://raw.githubusercontent.com/Predidit/KazumiRules/main/giriGiriLove.json
const _ruleSha = '4d7b4a32c68fcbf27ac1b2dd719408dd960067e5c40599ba90a33c05e2a8e01b';
const _title = '命运之夜 无限剑制 Fate/stay night [Unlimited Blade Works]';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kDebugMode || (await PackageInfo.fromPlatform()).packageName !=
      'com.znbsf.kazumi.fluttertv.featureqa') {
    throw StateError('Requires isolated featureqa debug identity');
  }
  if (sha256.convert(utf8.encode(_ruleJson)).toString() != _ruleSha) {
    throw StateError('Pinned public rule digest mismatch');
  }
  await TvMode.initialize();
  if (Platform.isAndroid) await WebViewFeatureService.initialize();
  MediaKit.ensureInitialized();
  final root = await getApplicationSupportDirectory();
  await Hive.initFlutter('${root.path}/hive');
  await GStorage.init();
  FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTraditional;
  runApp(MaterialApp(
    theme: ThemeData.dark(useMaterial3: true),
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    supportedLocales: const [Locale('zh', 'CN')],
    locale: const Locale('zh', 'CN'),
    home: const _RealSourceQa(),
  ));
}

class _RealSourceQa extends StatefulWidget {
  const _RealSourceQa();
  @override
  State<_RealSourceQa> createState() => _RealSourceQaState();
}

class _RealSourceQaState extends State<_RealSourceQa> {
  bool _attempted = false;
  String _result = '尚未请求真实站点';
  Future<void> _probe() async {
    if (_attempted) return;
    setState(() => _attempted = true);
    final plugin = Plugin.fromJson(jsonDecode(_ruleJson) as Map<String, dynamic>);
    debugPrint('REAL_HEALTH_QA rule=giriGiriLove version=2.5 rawSha=$_ruleSha fingerprint=${ruleFingerprint(plugin)}');
    final item = BangumiItem(
      id: 990019, type: 2, name: _title, nameCn: _title,
      summary: 'QA-only UBW source title; not the 2006 Fate/stay night subject.',
      airDate: '', airWeekday: 0, rank: 0, images: {}, tags: [],
      alias: [], ratingScore: 0, votes: 0, votesCount: [], info: '',
    );
    final selected = await Navigator.of(context).push<HealthCandidate>(
      MaterialPageRoute(builder: (_) => SourceHealthPage(
        subject: item, plugins: [plugin], autoSelect: true,
        persistRecord: (record) async {
          // Only structured stage metadata. Never log resolved media URLs.
          debugPrint('REAL_HEALTH_QA_RECORD ${jsonEncode(record.toJson())}');
        },
      )),
    );
    if (mounted) {
      setState(() => _result = selected == null
          ? '已返回：未选中或已取消；请核对分级记录'
          : '真实首帧候选已返回；未启动正式播放');
    }
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('内部真实源单次验收')),
    body: Center(child: Padding(padding: const EdgeInsets.all(32), child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(_title),
        const SizedBox(height: 16),
        const Text('giriGiriLove 2.5 / API 9\n仅此规则、完整作品名精确匹配；35 秒探测 + 最多 4 秒释放等待。\n不重试、不绕过验证码、不保证全站可用。'),
        const SizedBox(height: 16),
        FilledButton(autofocus: true, onPressed: _attempted ? null : _probe,
          child: const Text('执行一次真实源探测')),
        const SizedBox(height: 16),
        Text(_result),
      ],
    ))),
  );
}

const _ruleJson = r'''{
    "api": "9",
    "type": "anime",
    "name": "giriGiriLove",
    "version": "2.5",
    "muliSources": true,
    "useWebview": true,
    "useNativePlayer": true,
    "usePost": false,
    "useLegacyParser": false,
    "adBlocker": false,
    "userAgent": "",
    "baseURL": "https://ani.girigirilove.com",
    "searchMode": "api",
    "chapterMode": "xpath",
    "searchApiConfig": {
        "request": {
            "method": "GET",
            "url": "https://ani.girigirilove.com/index.php/ajax/suggest",
            "query": {
                "mid": "1",
                "wd": "@keyword"
            }
        },
        "listPath": "$.list[*]",
        "namePath": "$.name",
        "sourcePath": "$.id",
        "sourceTemplate": "https://ani.girigirilove.com/GV@source/"
    },
    "searchURL": "",
    "searchList": "",
    "searchName": "",
    "searchResult": "",
    "chapterRoads": "//ul[@class='anthology-list-play size']",
    "chapterResult": "//li/a",
    "referer": ""
}
''';
