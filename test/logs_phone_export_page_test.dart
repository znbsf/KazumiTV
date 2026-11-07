import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kazumi/pages/logs/logs_page.dart';
import 'package:kazumi/services/logging/log_export.dart';
import 'package:kazumi/services/logging/logger.dart' as logging;
import 'package:kazumi/services/phone_keyboard.dart';
import 'package:kazumi/services/phone_keyboard_session.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.path);
  final String path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
}

class _ConnectedPhone extends PhoneKeyboard {
  @override
  int get onlineCount => 1;
}

void main() {
  late Directory directory;
  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('phone_log_page_');
    PathProviderPlatform.instance = _Paths(directory.path);
    Hive.init(directory.path);
    await GStorage.init();
  });
  tearDownAll(() async {
    await logging.flushLogs();
    await Hive.close();
    await directory.delete(recursive: true);
  });

  Future<PhoneKeyboard> connectedPhone(WidgetTester tester) async {
    final phone = _ConnectedPhone();
    await tester.runAsync(() async {
      final session = PhoneKeyboardSession();
      phone.session = session;
      await session.start(address: InternetAddress.loopbackIPv4);
    });
    return phone;
  }

  testWidgets('TV export action publishes a snapshot and stop revokes it',
      (tester) async {
    final phone = await connectedPhone(tester);
    var exports = 0;
    await tester.pumpWidget(MaterialApp(
        home: LogsPage(
            phoneKeyboard: phone,
            exportBuilder: () async {
              exports++;
              return LogExport(
                  text: 'safe snapshot', createdAt: DateTime.utc(2026, 10, 31));
            })));
    await tester.pump();
    expect(phone.session!.state['logExport'], isNull);
    await tester.tap(find.text('手机导出'));
    await tester.pump();
    expect(exports, 1);
    expect(phone.session!.state['logExport'], isNotNull);
    expect(find.text('停止导出'), findsOneWidget);
    await tester.tap(find.text('停止导出'));
    await tester.pump();
    expect(phone.session!.state['logExport'], isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async {
      await phone.session!.close();
    });
    phone.dispose();
  });

  testWidgets(
      'clear during export prevents late snapshot from restoring sharing',
      (tester) async {
    final phone = await connectedPhone(tester);
    final pending = Completer<LogExport>();
    await tester.pumpWidget(MaterialApp(
        home: LogsPage(
            phoneKeyboard: phone, exportBuilder: () => pending.future)));
    await tester.pump();
    await tester.tap(find.text('手机导出'));
    await tester.pump();
    expect(find.text('正在准备…'), findsOneWidget);
    await tester.tap(find.byTooltip('清空日志'));
    pending.complete(
        LogExport(text: 'old snapshot', createdAt: DateTime.utc(2026)));
    await tester.pump();
    expect(phone.session!.state['logExport'], isNull);
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 30));
    });
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async {
      await phone.session!.close();
    });
    phone.dispose();
  });
}
