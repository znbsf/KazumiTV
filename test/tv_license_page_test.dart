import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/bean/widget/tv_focus_navigation.dart';
import 'package:kazumi/pages/about/tv_license_page.dart';
import 'package:kazumi/services/platform/tv_mode.dart';

void main() {
  setUp(() => TvMode.setEnabledForTesting(true));
  tearDown(() => TvMode.setEnabledForTesting(false));

  testWidgets(
      'remote license reader preserves text, scrolls both ways and restores package focus',
      (tester) async {
    tester.view.physicalSize = const Size(960, 540);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final text = List.generate(
            70,
            (i) =>
                'Original legal paragraph $i. Copyright and permission remain unchanged.')
        .join('\n\n');
    final entry = LicenseEntryWithLineBreaks(['alpha', 'beta'], text);
    await tester.pumpWidget(MaterialApp(
      builder: (_, child) =>
          FocusTraversalGroup(policy: TvLoopTraversalPolicy(), child: child!),
      home: TvLicensePage(licenses: Stream.fromIterable([entry])),
    ));
    await tester.pumpAndSettle();
    expect(find.text('KazumiTV'), findsOneWidget);
    expect(
        find.text('Kazumi · GNU General Public License v3.0'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    final scroll = tester
        .widget<SingleChildScrollView>(
            find.byKey(const ValueKey('license-text-scroll')))
        .controller!;
    expect(scroll.offset, 0);
    for (final paragraph in entry.paragraphs) {
      expect(find.text(paragraph.text), findsOneWidget);
    }
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    final first = scroll.offset;
    expect(first, greaterThan(0));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(scroll.offset, first);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(scroll.offset, 0);
    for (var i = 0; i < 80; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    }
    await tester.pumpAndSettle();
    expect(scroll.offset, scroll.position.maxScrollExtent);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('license-text-scroll')), findsNothing);
    expect(
        Focus.of(tester.element(find
                .descendant(
                    of: find.byKey(const ValueKey('license-package-alpha')),
                    matching: find.byType(AnimatedScale))
                .first))
            .hasPrimaryFocus,
        isTrue);
    await tester.pumpWidget(const SizedBox());
  });
}
