import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/bbcode/bbcode_widget.dart';
import 'package:kazumi/services/platform/tv_mode.dart';

void main() {
  tearDown(() => TvMode.setEnabledForTesting(false));
  for (final tv in [true, false]) {
    testWidgets('inline image loading and error placeholders (TV=$tv)',
        (tester) async {
      TvMode.setEnabledForTesting(tv);
      await tester.pumpWidget(const MaterialApp(
          home: Scaffold(
              body: BBCodeWidget(
                  bbcode: '[img]https://invalid.test/a.png[/img]'))));
      final image =
          tester.widget<CachedNetworkImage>(find.byType(CachedNetworkImage));
      final context = tester.element(find.byType(CachedNetworkImage));
      // Render the actual production callbacks deterministically; no HTTP or cache dependency.
      final loading = image.placeholder!(context, image.imageUrl);
      final error =
          image.errorWidget!(context, image.imageUrl, Exception('fixture'));
      for (final entry in [(loading, '图片加载中'), (error, '图片无法显示')]) {
        await tester.pumpWidget(
            MaterialApp(home: Scaffold(body: Center(child: entry.$1))));
        if (tv) {
          expect(find.text(entry.$2), findsOneWidget);
          expect(find.byType(Icon), findsOneWidget);
          expect(tester.widget<Text>(find.text(entry.$2)).style!.fontSize,
              greaterThanOrEqualTo(14));
          expect(tester.getSize(find.byWidget(entry.$1)), const Size(180, 48));
        } else if (entry.$2 == '图片加载中') {
          expect(tester.getSize(find.byWidget(entry.$1)), const Size(1, 1));
        } else {
          expect(find.text('.'), findsOneWidget);
        }
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
