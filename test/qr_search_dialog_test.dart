import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/pages/search/qr_search_dialog.dart';
import 'package:kazumi/services/qr_search_session.dart';

class FakeSession extends QrSearchSession {
  FakeSession(void Function(String) query, void Function() closed)
      : super(onQuery: query, onClosed: closed);
  bool closed = false;
  @override
  Future<Uri> start({InternetAddress? address}) async =>
      Uri.parse('http://127.0.0.1:1234/token');
  @override
  Future<void> close() async {
    closed = true;
  }
}

void main() {
  testWidgets('receive preview, confirm, close and restore entry focus',
      (tester) async {
    late FakeSession session;
    String? result;
    final focus = FocusNode();
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    focusNode: focus,
                    autofocus: true,
                    onPressed: () async {
                      result = await showDialog<String>(
                          context: context,
                          builder: (_) => QrSearchDialog(
                              sessionFactory: (query, closed) =>
                                  session = FakeSession(query, closed)));
                      focus.requestFocus();
                    },
                    child: const Text('手机输入'))))));
    await tester.tap(find.text('手机输入'));
    await tester.pumpAndSettle();
    session.onQuery('测试番剧');
    await tester.pumpAndSettle();
    expect(find.text('已收到：测试番剧'), findsOneWidget);
    await tester.tap(find.text('搜索'));
    await tester.pumpAndSettle();
    expect(result, '测试番剧');
    expect(session.closed, isTrue);
    expect(focus.hasFocus, isTrue);
    await tester.tap(find.text('手机输入'));
    await tester.pumpAndSettle();
    session.onClosed!();
    await tester.pumpAndSettle();
    expect(find.text('会话已过期，请退出后重新扫码'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(session.closed, isTrue);
    expect(focus.hasFocus, isTrue);
    await tester.pumpWidget(const SizedBox());
    focus.dispose();
  });
}
