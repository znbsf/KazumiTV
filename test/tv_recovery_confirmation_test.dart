import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/pages/player/tv_playback_info.dart';
import 'package:kazumi/pages/player/tv_recovery_confirmation.dart';

void main() {
  testWidgets(
      'defaults to cancel, back cancels, right/enter confirms and restores focus',
      (tester) async {
    final presenter = TvPlaybackInfoPresenter();
    final focus = FocusNode();
    addTearDown(focus.dispose);
    late BuildContext owner;
    var confirmed = 0;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) {
      owner = context;
      return Scaffold(
          body: TextButton(
              focusNode: focus, onPressed: () {}, child: const Text('Player')));
    })));
    void open() {
      focus.requestFocus();
      unawaited(presenter.show(owner,
          fallbackFocus: focus,
          builder: (_) => TvRecoveryConfirmation(
                onCancel: presenter.close,
                onConfirm: () {
                  confirmed++;
                  presenter.close();
                },
              )));
    }

    open();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(confirmed, 0);
    expect(presenter.isOpen, isFalse);
    expect(focus.hasFocus, isTrue);
    open();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(confirmed, 0);
    expect(focus.hasFocus, isTrue);
    open();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(confirmed, 1);
    expect(presenter.isOpen, isFalse);
    expect(focus.hasFocus, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
