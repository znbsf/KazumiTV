// Debug-only feature acceptance entry. Never imported by production main.dart.
import 'dart:io';
import 'dart:async';
import 'package:dio/dio.dart';
import 'package:kazumi/request/config/api_endpoints.dart';
import 'package:kazumi/request/core/dio_factory.dart';
import 'package:kazumi/pages/info/source_health_page.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/roads/road_module.dart';
import 'package:kazumi/modules/search/plugin_search_module.dart';
import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/services/plugin/rule_engine_models.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:media_kit/media_kit.dart';
// ignore: depend_on_referenced_packages
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:kazumi/pages/search/qr_search_dialog.dart';
import 'package:kazumi/pages/popular/popular_page.dart';
import 'package:kazumi/pages/popular/tv_popular_controller.dart';
import 'package:kazumi/services/platform/tv_mode.dart';
import 'package:kazumi/services/platform/webview_feature_service.dart';
import 'package:kazumi/services/qr_search_session.dart';
import 'package:kazumi/services/storage/storage.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kDebugMode ||
      (await PackageInfo.fromPlatform()).packageName !=
          'com.znbsf.kazumi.fluttertv.featureqa') {
    throw StateError('Requires isolated featureqa debug identity');
  }
  await TvMode.initialize();
  if (Platform.isAndroid) await WebViewFeatureService.initialize();
  MediaKit.ensureInitialized();
  final root = await getApplicationSupportDirectory();
  await Hive.initFlutter('${root.path}/hive');
  await GStorage.init();
  FocusManager.instance.highlightStrategy =
      FocusHighlightStrategy.alwaysTraditional;
  runApp(MaterialApp(
    title: 'KazumiTV Feature QA',
    theme: ThemeData.dark(useMaterial3: true),
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    supportedLocales: const [Locale('zh', 'CN')],
    locale: const Locale('zh', 'CN'),
    home: const _FeatureHub(),
  ));
}

class _ObservableSession extends QrSearchSession {
  _ObservableSession(
      void Function(String) query, void Function() closed, this.ready)
      : super(onQuery: query, onClosed: closed);
  final ValueChanged<Uri> ready;
  @override
  Future<Uri> start({InternetAddress? address}) async {
    // Only this isolated fixture binds loopback for adb forward. Production
    // QrSearchDialog still uses its unchanged private-LAN binding policy.
    final uri = await super.start(address: InternetAddress.loopbackIPv4);
    ready(uri);
    return uri;
  }
}

class _FeatureHub extends StatefulWidget {
  const _FeatureHub();
  @override
  State<_FeatureHub> createState() => _FeatureHubState();
}

class _FeatureHubState extends State<_FeatureHub> {
  final _qrFocus = FocusNode(debugLabel: 'Feature QA QR entry');
  String _result = '尚未收到关键词';
  Future<void> _health(bool automatic) async {
    final subject = BangumiItem(
        id: 990017,
        type: 2,
        name: 'Target',
        nameCn: 'Target',
        summary: 'Synthetic acceptance fixture',
        airDate: '',
        airWeekday: 0,
        rank: 0,
        images: {},
        tags: [],
        alias: [],
        ratingScore: 0,
        votes: 0,
        votesCount: [],
        info: '');
    final result = await Navigator.of(context).push(MaterialPageRoute<Object?>(
        builder: (_) => SourceHealthPage(
            subject: subject,
            plugins: [_FixtureRule(false), _FixtureRule(true)],
            autoSelect: automatic)));
    if (mounted)
      setState(
          () => _result = '健康页已返回：${result == null ? '未选择/取消' : '有限候选已选择'}');
  }

  @override
  void dispose() {
    _qrFocus.dispose();
    super.dispose();
  }

  Future<void> _openQr() async {
    final url = ValueNotifier<String>('正在开启短时会话');
    final query = await showDialog<String>(
        context: context,
        builder: (_) => Column(children: [
              Expanded(
                  child: QrSearchDialog(
                      sessionFactory: (query, closed) =>
                          _ObservableSession(query, closed, (uri) {
                            debugPrint('FEATURE_QA_QR_URL $uri');
                            url.value = uri.toString();
                          }))),
              Material(
                  color: Colors.black,
                  child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: ValueListenableBuilder<String>(
                          valueListenable: url,
                          builder: (_, value, child) => Text(
                              'QA loopback: $value',
                              style: const TextStyle(
                                  fontSize: 12, color: Colors.white))))),
            ]));
    url.dispose();
    if (!mounted) return;
    _qrFocus.requestFocus();
    setState(() => _result = query == null ? '已退出，监听已关闭' : '已确认：$query');
  }

  Future<void> _openHome() async {
    final mode = await showDialog<_HomeQaMode>(
        context: context,
        builder: (context) => SimpleDialog(
              title: const Text('首页缓存 QA · 选择本次请求模式'),
              children: [
                const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                    child:
                        Text('先用真实网络填充缓存，返回后选择失败模式。\n旧磁盘缓存继续读取；不改系统网络或正式数据。')),
                for (final mode in _HomeQaMode.values)
                  TextButton(
                      autofocus: mode == _HomeQaMode.normal,
                      onPressed: () => Navigator.pop(context, mode),
                      child: Text(mode.label)),
              ],
            ));
    if (!mounted || mode == null) return;
    await Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => _HomeQaPage(mode: mode)));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Feature QA · 隔离数据 · 合成验收')),
        body: Padding(
            padding: const EdgeInsets.all(24),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              FilledButton(
                  focusNode: _qrFocus,
                  autofocus: true,
                  onPressed: _openQr,
                  child: const Text('手机输入 · 生产二维码弹窗')),
              const SizedBox(height: 16),
              FilledButton(
                  onPressed: () => _health(false),
                  child: const Text('源健康 · 手动探测合成规则')),
              FilledButton(
                  onPressed: () => _health(true),
                  child: const Text('源健康 · 首次有限选源')),
              const SizedBox(height: 16),
              Text(_result),
              const SizedBox(height: 24),
              FilledButton(
                  onPressed: _openHome, child: const Text('生产首页 · 展示与缓存')),
              const SizedBox(height: 16),
              const Text(
                  '首页可选真实网络/立即失败/延迟15秒失败；只拦截本页热门元信息。详情路由未接入。\n二维码使用受控loopback，不能证明真实Wi-Fi扫码可达性。'),
            ])),
      );
}

enum _HomeQaMode {
  normal('正常 · 真实数据填充缓存'),
  fail('刷新明确失败 · 保留旧缓存'),
  slowFail('延迟15秒后失败 · 验证缓存优先');

  const _HomeQaMode(this.label);
  final String label;
}

/// Request interception exists only while this isolated QA route is mounted.
/// Production controller/cache, images, search and source health are unchanged.
class _HomeQaPage extends StatefulWidget {
  const _HomeQaPage({required this.mode});
  final _HomeQaMode mode;
  @override
  State<_HomeQaPage> createState() => _HomeQaPageState();
}

class _HomeQaPageState extends State<_HomeQaPage> {
  final _controller = TvPopularController();
  final _delays = <Completer<void>, Timer>{};
  Dio? _dio;
  Interceptor? _interceptor;
  bool _active = true;

  @override
  void initState() {
    super.initState();
    debugPrint('FEATURE_QA_HOME_MODE ${widget.mode.name}');
    if (widget.mode == _HomeQaMode.normal) return;
    _dio = DioFactory.apiDio;
    _interceptor = InterceptorsWrapper(onRequest: (options, handler) async {
      final path = options.uri.path;
      if (path != ApiEndpoints.bangumiTrendsNext &&
          path != ApiEndpoints.bangumiMirrorPopularSubjects) {
        handler.next(options);
        return;
      }
      // Only the default popular page is under test, not category/search APIs.
      if ((options.uri.queryParameters['tag'] ?? '').isNotEmpty) {
        handler.next(options);
        return;
      }
      debugPrint('FEATURE_QA_HOME_REQUEST ${widget.mode.name}');
      if (widget.mode == _HomeQaMode.slowFail && _active) {
        final done = Completer<void>();
        _delays[done] =
            Timer(const Duration(seconds: 15), () => done.complete());
        await done.future;
        _delays.remove(done)?.cancel();
      }
      debugPrint(
          'FEATURE_QA_HOME_RESULT ${_active ? 'injected_failure' : 'route_closed'}');
      handler.reject(DioException(
          requestOptions: options,
          type: _active
              ? DioExceptionType.connectionError
              : DioExceptionType.cancel,
          message: 'Isolated home QA: ${widget.mode.name}'));
    });
    _dio!.interceptors.insert(0, _interceptor!);
  }

  @override
  void dispose() {
    _active = false;
    if (_interceptor != null) _dio?.interceptors.remove(_interceptor);
    for (final entry in _delays.entries) {
      entry.value.cancel();
      if (!entry.key.isCompleted) entry.key.complete();
    }
    _delays.clear();
    debugPrint('FEATURE_QA_HOME_CLOSED');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: Text('首页缓存 QA · ${widget.mode.label}')),
      body: PopularPage(controller: _controller));
}

class _FixtureRule extends Plugin {
  _FixtureRule(this.playable)
      : super(
            api: '9',
            type: 'anime',
            name: playable ? 'QA Playable' : 'QA NoMatch',
            version: '1',
            muliSources: true,
            useWebview: true,
            useNativePlayer: true,
            usePost: false,
            useLegacyParser: false,
            adBlocker: false,
            userAgent: '',
            baseUrl: 'http://127.0.0.1:18743',
            searchURL: '',
            searchList: '',
            searchName: '',
            searchResult: '',
            chapterRoads: '',
            chapterResult: '',
            referer: '');
  final bool playable;
  @override
  Future<PluginSearchResponse> queryBangumi(String keyword,
          {bool shouldRethrow = false, RuleCancelToken? cancelToken}) async =>
      PluginSearchResponse(
          pluginName: name,
          data: playable ? [SearchItem(name: 'Target', src: '/target')] : []);
  @override
  Future<List<Road>> queryChapterRoads(String source,
          {RuleCancelToken? cancelToken}) async =>
      [
        Road(
            name: 'QA',
            data: ['http://127.0.0.1:18743/fixture.html'],
            identifier: ['1'])
      ];
}
