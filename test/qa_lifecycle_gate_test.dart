import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import '../tools/qa/source_batch/lifecycle_gate.dart';

void main() {
  test('cancelled page cannot publish late media even if its future succeeds',
      () {
    final gate = QaLifecycleGate();
    final old = gate.begin('old');
    old.cancel();
    expect(gate.finish(old, {'stage': 'first_frame', 'cleanup': 'confirmed'}),
        false);
  });
  test('switch waits for old cleanup and rejects its late duplicate result',
      () {
    final gate = QaLifecycleGate();
    final old = gate.begin('old');
    old.cancel();
    expect(() => gate.begin('next'), throwsStateError);
    expect(gate.finish(old, {'stage': 'first_frame', 'cleanup': 'confirmed'}),
        false);
    final next = gate.begin('different-next');
    expect(gate.finish(old, {'stage': 'first_frame', 'cleanup': 'confirmed'}),
        false);
    expect(gate.finish(next, {'stage': 'first_frame', 'cleanup': 'confirmed'}),
        true);
    expect(next.id, 'different-next');
    expect(next.generation, 2);
  });
  test('unconfirmed cleanup blocks a new producer', () {
    final gate = QaLifecycleGate();
    final old = gate.begin('old');
    old.cancel();
    gate.finish(old, {'cleanup': 'unconfirmed'});
    expect(() => gate.begin('next'), throwsStateError);
  });
  test('early cancellation reaches a service attached after page disposal', () {
    final ticket = QaCaseTicket('early', 1)..cancel();
    var calls = 0;
    ticket.attachCancel(() => calls++);
    ticket.cancel();
    expect(calls, 1);
  });
  test(
      'player cleanup failure never skips resolver retirement or exports error text',
      () async {
    var resolverClosed = false;
    final result = await retireQaResources(
        player: () async => throw StateError('PRIVATE_SENTINEL'),
        resolver: () async {
          resolverClosed = true;
        });
    expect(resolverClosed, true);
    expect(result['cleanup'], 'unconfirmed');
    expect(result['resolver_release'], 'confirmed');
    expect(result.toString(), isNot(contains('PRIVATE_SENTINEL')));
  });
  test('stalled cleanup is bounded and subsequent resources are attempted',
      () async {
    final result = await retireQaResources(
        player: () => Completer<void>().future,
        resolver: () async {},
        budget: const Duration(milliseconds: 2));
    expect(result['player_release'], 'unconfirmed');
    expect(result['resolver_release'], 'confirmed');
  });
  test('resources never constructed are reported separately from released',
      () async {
    final result = await retireQaResources();
    expect(result['cleanup'], 'confirmed');
    expect(result['player_release'], 'not_created');
    expect(result['resolver_release'], 'not_created');
  });
}
