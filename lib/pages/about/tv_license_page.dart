import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kazumi/bean/widget/tv_focusable_surface.dart';
import 'package:kazumi/request/config/api_endpoints.dart';

/// The bundled license browser's wide detail pane has no D-pad focus target.
/// Keep the registry's original paragraphs, with a dedicated remote reader.
class TvLicensePage extends StatefulWidget {
  const TvLicensePage({super.key, this.licenses});

  final Stream<LicenseEntry>? licenses;

  @override
  State<TvLicensePage> createState() => _TvLicensePageState();
}

class _TvLicensePageState extends State<TvLicensePage> {
  late final _packages = _load();

  Future<Map<String, List<LicenseEntry>>> _load() async {
    final packages = <String, List<LicenseEntry>>{};
    await for (final entry in widget.licenses ?? LicenseRegistry.licenses) {
      for (final package in entry.packages) {
        packages.putIfAbsent(package, () => []).add(entry);
      }
    }
    return Map.fromEntries(packages.entries.toList()
      ..sort((a, b) => a.key.toLowerCase().compareTo(b.key.toLowerCase())));
  }

  Future<void> _open(String package, List<LicenseEntry> entries) async {
    final returnFocus = FocusManager.instance.primaryFocus;
    await Navigator.of(context).push<void>(MaterialPageRoute(
      builder: (_) => _LicenseReader(package: package, entries: entries),
    ));
    if (mounted &&
        returnFocus?.context != null &&
        returnFocus!.canRequestFocus) {
      returnFocus.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('第三方许可证')),
        body: FutureBuilder<Map<String, List<LicenseEntry>>>(
          future: _packages,
          builder: (context, snapshot) {
            if (snapshot.hasError) return const Center(child: Text('无法读取许可证'));
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final packages = snapshot.data!.entries.toList();
            // Bundled dependency names are bounded at build time. Keep each remote
            // target mounted so a wrap reaches the actual end, not a cache edge.
            return SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('KazumiTV',
                        style: Theme.of(context).textTheme.headlineMedium),
                    const Text(ApiEndpoints.version),
                    const Text('Kazumi · GNU General Public License v3.0'),
                    const SizedBox(height: 16),
                    for (var index = 0; index < packages.length; index++)
                      TvFocusableSurface(
                        key: ValueKey('license-package-${packages[index].key}'),
                        autofocus: index == 0,
                        focusScale: 1,
                        onPressed: () =>
                            _open(packages[index].key, packages[index].value),
                        child: ListTile(
                          title: Text(packages[index].key),
                          subtitle: Text('${packages[index].value.length} 份许可'),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: () =>
                              _open(packages[index].key, packages[index].value),
                        ),
                      ),
                  ]),
            );
          },
        ),
      );
}

class _LicenseReader extends StatefulWidget {
  const _LicenseReader({required this.package, required this.entries});
  final String package;
  final List<LicenseEntry> entries;

  @override
  State<_LicenseReader> createState() => _LicenseReaderState();
}

class _LicenseReaderState extends State<_LicenseReader> {
  final _scroll = ScrollController();
  final _back = FocusNode();

  @override
  void dispose() {
    _scroll.dispose();
    _back.dispose();
    super.dispose();
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final down = event.logicalKey == LogicalKeyboardKey.arrowDown;
    final up = event.logicalKey == LogicalKeyboardKey.arrowUp;
    if (!down && !up) return KeyEventResult.ignored;
    if (!_scroll.hasClients) return KeyEventResult.handled;
    final position = _scroll.position;
    if (up && position.pixels <= position.minScrollExtent) {
      _back.requestFocus();
    } else {
      final step = position.viewportDimension * .65;
      _scroll.jumpTo((position.pixels + (down ? step : -step))
          .clamp(position.minScrollExtent, position.maxScrollExtent));
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          leading: IconButton(
              focusNode: _back,
              tooltip: '返回',
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.arrow_back)),
          title: Text(widget.package),
        ),
        body: Column(children: [
          const Padding(
              padding: EdgeInsets.all(8), child: Text('上下键滚动阅读 · 返回关闭')),
          Expanded(
              child: Focus(
            autofocus: true,
            debugLabel: 'License text reader',
            onKeyEvent: _key,
            child: SingleChildScrollView(
              key: const ValueKey('license-text-scroll'),
              controller: _scroll,
              padding: const EdgeInsets.all(24),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var index = 0;
                        index < widget.entries.length;
                        index++) ...[
                      if (index > 0) const Divider(height: 40),
                      for (final paragraph in widget.entries[index].paragraphs)
                        Padding(
                          padding: EdgeInsets.only(
                              bottom: 12,
                              left: paragraph.indent < 0
                                  ? 0
                                  : paragraph.indent * 16.0),
                          child: Text(paragraph.text,
                              textAlign: paragraph.indent ==
                                      LicenseParagraph.centeredIndent
                                  ? TextAlign.center
                                  : TextAlign.start),
                        ),
                    ],
                  ]),
            ),
          )),
        ]),
      );
}
