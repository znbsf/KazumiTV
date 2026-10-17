import 'package:flutter/material.dart';
import 'package:kazumi/bean/card/rule_card.dart';
import 'package:kazumi/bean/widget/tv_visuals.dart';
import 'package:kazumi/pages/info/tv_detail_actions.dart';
import 'package:kazumi/pages/player/tv_player_controls.dart';

/// Local QA route only; import into the isolated debug hub, never production.
class FocusVisualFixture extends StatefulWidget {
  const FocusVisualFixture({super.key});
  @override
  State<FocusVisualFixture> createState() => _FocusVisualFixtureState();
}

class _FocusVisualFixtureState extends State<FocusVisualFixture> {
  int palette = 1;
  final play = FocusNode();
  @override
  void dispose() {
    play.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = TvVisuals.theme(
        ThemeData(
            colorSchemeSeed: Colors.green,
            brightness: palette == 0 ? Brightness.light : Brightness.dark),
        oled: palette == 2);
    return Theme(
        data: theme,
        child: Scaffold(
          appBar: AppBar(
              title: const Text('Focus / selected / disabled visual QA')),
          body: ListView(padding: const EdgeInsets.all(24), children: [
            Wrap(spacing: 16, children: [
              for (var i = 0; i < 3; i++)
                OutlinedButton(
                    onPressed: () => setState(() => palette = i),
                    child: Text(['Light', 'Dark', 'OLED'][i])),
            ]),
            const Text(
                'Use D-pad to compare each enabled target; hold OK for pressed.'),
            TvDetailActions(
                playFocus: play,
                onPlay: () {},
                onSelectSource: () {},
                onSourceHealth: () {},
                collectionBuilder: (node) => OutlinedButton(
                    focusNode: node, onPressed: () {}, child: const Text('收藏')),
                onReview: () {},
                onUp: () {},
                onDown: () {}),
            Wrap(spacing: 16, children: [
              FilledButton(onPressed: () {}, child: const Text('手机遥控')),
              OutlinedButton(
                  onPressed: () => showDialog<void>(
                      context: context,
                      builder: (_) => Theme(
                          data: theme,
                          child: AlertDialog(
                              title: const Text('临时连接'),
                              content: const Text('Dialog focus sample'),
                              actions: [
                                TextButton(
                                    onPressed: () => Navigator.pop(context),
                                    child: const Text('退出'))
                              ]))),
                  child: const Text('弹窗')),
              const FilledButton(onPressed: null, child: Text('禁用')),
            ]),
            RuleCard(title: '规则：普通', onTap: () {}),
            RuleCard(title: '规则：已选中', selected: true, onTap: () {}),
            const RuleCard(title: '规则：不可操作'),
            const Text(
                '播放器：普通 / selected / disabled (focus adds opaque fill + frame)'),
            Wrap(spacing: 16, children: [
              TvPlayerAction(label: '播放', onPressed: () {}),
              TvPlayerAction(label: '已选中', selected: true, onPressed: () {}),
              const TvPlayerAction(label: '不可用', onPressed: null),
            ]),
          ]),
        ));
  }
}
