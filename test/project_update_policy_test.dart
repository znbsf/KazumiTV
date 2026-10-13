import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/bean/settings/settings_detail_scaffold.dart';
import 'package:kazumi/pages/about/about_page.dart';

import 'package:kazumi/pages/about/credits_page.dart';
import 'package:kazumi/request/config/api_endpoints.dart';
import 'package:kazumi/services/update/project_update_policy.dart';

void main() {
  test('only release TV stable versions check the project stable feed', () {
    expect(
        ProjectUpdatePolicy.canCheck(
            releaseMode: true, tv: true, version: '0.4.1'),
        isTrue);
    for (final version in [
      '0.4.2-tv.58-emu',
      '0.4.2-qa',
      '0.4.0-preview.1',
      '0.0.0+test'
    ]) {
      expect(
          ProjectUpdatePolicy.canCheck(
              releaseMode: true, tv: true, version: version),
          isFalse);
    }
    expect(
        ProjectUpdatePolicy.canCheck(
            releaseMode: false, tv: true, version: '0.4.1'),
        isFalse);
    expect(
        ProjectUpdatePolicy.canCheck(
            releaseMode: true, tv: false, version: '0.4.1'),
        isFalse);
  });
  test('reject upstream, wrong release identity, prerelease and drafts', () {
    final data = <String, dynamic>{
      'tag_name': 'v0.4.2',
      'html_url': 'https://github.com/znbsf/KazumiTV/releases/tag/v0.4.2',
      'draft': false,
      'prerelease': false
    };
    expect(ProjectUpdatePolicy.acceptsRelease(data), isTrue);
    for (final url in [
      'https://github.com/Predidit/Kazumi/releases/tag/v0.4.2',
      'https://github.com/znbsf/KazumiTV/releases/tag/v0.4.3',
      'https://github.com.evil.test/znbsf/KazumiTV/releases/tag/v0.4.2',
      'http://github.com/znbsf/KazumiTV/releases/tag/v0.4.2'
    ]) {
      expect(ProjectUpdatePolicy.acceptsRelease({...data, 'html_url': url}),
          isFalse);
    }
    expect(
        ProjectUpdatePolicy.acceptsRelease({...data, 'draft': true}), isFalse);
    expect(ProjectUpdatePolicy.acceptsRelease({...data, 'prerelease': true}),
        isFalse);
    expect(
        ProjectUpdatePolicy.acceptsRelease({...data, 'tag_name': 'v0.4.2-qa'}),
        isFalse);
  });
  Future<void> show(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        theme: ThemeData.dark(),
        home: SettingsPaneScope(
            embedded: true,
            showBackButton: false,
            onBack: () {},
            child: child)));
    await tester.pumpAndSettle();
  }

  testWidgets('about project actions target this fork and inherit dark theme',
      (tester) async {
    await show(tester, AboutPage(onCheckUpdate: () async => true));
    expect(find.text('KazumiTV'), findsOneWidget);
    expect(ApiEndpoints.projectUrl, ApiEndpoints.sourceUrl);
    expect(ApiEndpoints.latestApp,
        'https://api.github.com/repos/znbsf/KazumiTV/releases/latest');
    expect(find.text('KazumiTV 问题反馈'), findsOneWidget);
    expect(find.text('KazumiTV 讨论'), findsOneWidget);
    expect(find.text('上游 Kazumi 主页'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'credits has exactly one upstream acknowledgement with dependencies retained',
      (tester) async {
    await show(tester, const CreditsPage());
    expect(
        ApiEndpoints.upstreamProjectUrl, 'https://github.com/Predidit/Kazumi');
    expect(find.text('上游项目致谢'), findsOneWidget);
    expect(find.text('media-kit'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
