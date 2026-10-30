import 'dart:async';
import 'package:kazumi/modules/search/plugin_search_module.dart';
import 'package:kazumi/pages/info/info_controller.dart';
import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/plugins/plugins_controller.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/plugin/rule_engine_models.dart';
import 'package:kazumi/utils/async_session.dart';

class PluginSearchService {
  PluginSearchService({
    required this.infoController,
    required this.pluginsController,
    this.maxConcurrent = 4,
  }) : assert(maxConcurrent > 0);

  final InfoController infoController;
  final PluginsController pluginsController;
  final int maxConcurrent;
  final Map<String, RuleCancelToken> _tokens = {};
  final List<Completer<void>> _waiters = [];
  int _running = 0;

  /// Per-plugin sessions so a replacement query (alias/manual search)
  /// invalidates the write-back of the still-running previous one.
  final Map<String, AsyncSessionOwner> _querySessions = {};
  bool _isCancelled = false;

  Future<void> querySource(String keyword, String pluginName) async {
    if (_isCancelled) return;
    for (final plugin in pluginsController.enabledPlugins) {
      if (plugin.name == pluginName) {
        infoController.pluginSearchResponseList.removeWhere(
          (response) => response.pluginName == pluginName,
        );
        infoController.pluginSearchStatus[pluginName] =
            PluginSearchStatus.pending;
        await _queryPlugin(plugin, keyword);
        return;
      }
    }
  }

  /// Publishes the result page harvested by the captcha webview, skipping
  /// one network round trip. Returns false when the HTML does not parse
  /// into results; callers should fall back to [querySource].
  bool applyHarvestedSearchResult(String pluginName, String html) {
    if (_isCancelled) return false;
    for (final plugin in pluginsController.enabledPlugins) {
      if (plugin.name != pluginName) continue;
      final result = plugin.parseHarvestedSearch(html);
      if (result == null) return false;
      // Verification is a replacement result for this source. An earlier
      // network request may still finish after the captcha page is accepted.
      _querySessions[pluginName]?.cancel();
      _tokens.remove(pluginName)?.cancel('verified result');
      infoController.pluginSearchResponseList.removeWhere(
        (response) => response.pluginName == pluginName,
      );
      infoController.pluginSearchStatus[pluginName] =
          PluginSearchStatus.success;
      pluginsController.validityTracker.markSearchValid(pluginName);
      infoController.pluginSearchResponseList.add(result);
      return true;
    }
    return false;
  }

  Future<void> queryAllSource(String keyword) async {
    if (_isCancelled) return;
    infoController.pluginSearchResponseList.clear();
    infoController.pluginSearchStatus.clear();

    final plugins = List<Plugin>.of(pluginsController.enabledPlugins);
    for (final plugin in plugins) {
      infoController.pluginSearchStatus[plugin.name] =
          PluginSearchStatus.pending;
    }
    await Future.wait(
      plugins.map((plugin) => _queryPlugin(plugin, keyword)),
    );
  }

  Future<void> _queryPlugin(Plugin plugin, String keyword) async {
    if (_isCancelled) return;
    final session =
        _querySessions.putIfAbsent(plugin.name, AsyncSessionOwner.new).begin();
    _tokens.remove(plugin.name)?.cancel('replacement query');
    final token = RuleCancelToken();
    _tokens[plugin.name] = token;
    if (_running >= maxConcurrent) {
      final waiter = Completer<void>();
      _waiters.add(waiter);
      await waiter.future;
    } else {
      _running++;
    }
    try {
      if (_isCancelled ||
          session.isStale ||
          token.isCancelled ||
          !_isCurrentSource(plugin)) return;
      final result = await plugin.queryBangumi(
        keyword,
        shouldRethrow: true,
        cancelToken: token,
      );
      if (_isCancelled || session.isStale || !_isCurrentSource(plugin)) {
        return;
      }
      infoController.pluginSearchStatus[plugin.name] =
          PluginSearchStatus.success;
      if (result.data.isNotEmpty) {
        pluginsController.validityTracker.markSearchValid(plugin.name);
      }
      infoController.pluginSearchResponseList.add(result);
    } catch (error) {
      if (_isCancelled || session.isStale || !_isCurrentSource(plugin)) {
        return;
      }
      _handleSearchError(plugin, error);
    } finally {
      if (identical(_tokens[plugin.name], token)) _tokens.remove(plugin.name);
      if (_waiters.isNotEmpty) {
        _waiters.removeAt(0).complete();
      } else {
        _running--;
      }
    }
  }

  // Pause/resume, removal and rule replacement retire the original instance.
  // Checking only the name would accept an old request after a quick resume.
  bool _isCurrentSource(Plugin plugin) => pluginsController.enabledPlugins.any(
        (current) => identical(current, plugin),
      );

  void _handleSearchError(Plugin plugin, Object error) {
    if (error is CaptchaRequiredException) {
      KazumiLogger().i(
        'PluginSearchService: captcha required for ${error.pluginName}',
      );
      infoController.pluginSearchStatus[error.pluginName] =
          PluginSearchStatus.captcha;
      return;
    }
    if (error is NoResultException) {
      KazumiLogger().i(
        'PluginSearchService: no results for ${error.pluginName}',
      );
      infoController.pluginSearchStatus[error.pluginName] =
          PluginSearchStatus.noResult;
      return;
    }
    final name = error is SearchErrorException ? error.pluginName : plugin.name;
    KazumiLogger().w('PluginSearchService: search error for $name');
    infoController.pluginSearchStatus[name] = PluginSearchStatus.error;
  }

  void cancel() {
    _isCancelled = true;
    for (final token in _tokens.values) {
      token.cancel('search cancelled');
    }
    for (final session in _querySessions.values) {
      session.cancel();
    }
  }
}
