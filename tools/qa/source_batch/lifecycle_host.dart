import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'lifecycle_gate.dart';

typedef QaPageBuilder = Widget Function(
    Map<String, dynamic>,
    QaCaseTicket,
    void Function(Map<String, dynamic>),
    void Function(Map<String, Object?>),
    VoidCallback);

class QaLifecycleHost extends StatefulWidget {
  const QaLifecycleHost(
      {required this.config,
      required this.pageBuilder,
      required this.channel,
      super.key});
  final Map<String, dynamic> config;
  final QaPageBuilder pageBuilder;
  final MethodChannel channel;
  @override
  State<QaLifecycleHost> createState() => _QaLifecycleHostState();
}

class _QaLifecycleHostState extends State<QaLifecycleHost> {
  final gate = QaLifecycleGate();
  final events = <Map<String, Object?>>[];
  final children = <Map<String, dynamic>>[];
  final switchFocus = FocusNode(debugLabel: 'qa-lifecycle-switch');
  QaCaseTicket? visible;
  Map<String, dynamic>? config;
  bool acted = false, published = false;
  Map<String, dynamic>? get spec => widget.config['qa_lifecycle'] == null
      ? null
      : Map<String, dynamic>.from(widget.config['qa_lifecycle'] as Map);
  void event(String stage, QaCaseTicket ticket) {
    if (events.length < 80) {
      events.add({
        'stage': stage,
        'generation': ticket.generation,
        'case_id': ticket.id,
        'epoch_ms': DateTime.now().millisecondsSinceEpoch
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _begin(widget.config);
  }

  Future<void> _begin(Map<String, dynamic> next) async {
    final ticket = gate.begin(next['id'] as String);
    await widget.channel.invokeMethod<void>(
        'qaBegin', {'generation': ticket.generation, 'case_id': ticket.id});
    event('page_started', ticket);
    if (mounted) {
      setState(() {
        config = next;
        visible = ticket;
      });
    }
  }

  Future<void> _write(
      Map<String, dynamic> row, int generation, String caseId) async {
    if (published || !mounted) return;
    final output = {
      ...row,
      'id': widget.config['id'],
      'qa_generation': generation,
      'qa_case_id': caseId
    };
    if (spec != null) {
      output['lifecycle'] = {
        'action': spec!['action'],
        'events': events,
        'children': children,
        'actual_page_disposals':
            events.where((e) => e['stage'] == 'page_disposed').length
      };
      if (spec!['action'] == 'switch') {
        (output['lifecycle'] as Map<String, Object?>)['native_key_events'] =
            await widget.channel.invokeMethod<Object?>('qaKeyState');
      }
    }
    final accepted =
        await widget.channel.invokeMethod<bool>('result', jsonEncode(output));
    if (accepted != true) {
      throw StateError('Native QA publisher rejected current generation');
    }
    published = true;
  }

  void _finish(QaCaseTicket ticket, Map<String, dynamic> row) {
    if (ticket.finished) return;
    event('case_retired', ticket);
    final accepted = gate.finish(ticket, row);
    if (spec != null) {
      children.add({
        ...row,
        'qa_generation': ticket.generation,
        'cancelled_by_ui': ticket.cancelled,
        'normal_publication_allowed': accepted
      });
    }
    if (accepted) _write(row, ticket.generation, ticket.id);
  }

  void _signal(QaCaseTicket ticket, Map<String, Object?> signal) {
    if (spec == null || ticket.cancelled || ticket.finished) return;
    if (spec!['action'] == 'switch' &&
        !acted &&
        ticket.generation == 1 &&
        signal['phase'] == spec!['trigger_phase'] &&
        signal['stage'] == 'started') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !acted && !ticket.cancelled) switchFocus.requestFocus();
      });
    }
    widget.channel.invokeMethod<void>('qaState', {
      'generation': ticket.generation,
      'case_id': ticket.id,
      'phase': signal['phase'],
      'stage': signal['stage']
    });
  }

  Future<void> _transition() async {
    final old = visible;
    if (spec == null || acted || published || old == null || old.finished) {
      return;
    }
    acted = true;
    event('ui_transition', old);
    old.cancel();
    await widget.channel
        .invokeMethod<void>('qaInvalidate', {'generation': old.generation});
    if (!mounted) return;
    setState(() {
      visible = null;
      config = null;
    });
    // A real widget disposal follows this frame. Do not create the next service
    // until that page reports bounded production-service/player retirement.
    await WidgetsBinding.instance.endOfFrame;
    final retired = await old.retired.future;
    final clean = retired['cleanup'] == 'confirmed';
    final reportGeneration = gate.generation + 1;
    final target = spec!['action'] == 'switch' && clean
        ? Map<String, dynamic>.from(spec!['target'] as Map)
        : null;
    final nextId = target?['id'] as String? ?? widget.config['id'] as String;
    await widget.channel.invokeMethod<void>(
        'qaBegin', {'generation': reportGeneration, 'case_id': nextId});
    // Exercise the actual native writer with a synthetic late old result.
    final staleAccepted = await widget.channel.invokeMethod<bool>(
        'result',
        jsonEncode({
          'id': old.id,
          'qa_case_id': old.id,
          'qa_generation': old.generation,
          'stage': 'first_frame',
          'synthetic_late_probe': true
        }));
    events
        .add({'stage': 'native_stale_result_probe', 'accepted': staleAccepted});
    if (staleAccepted != false) {
      throw StateError('Stale QA result was accepted');
    }
    if (target != null) {
      final next = {...widget.config, ...target}..remove('qa_lifecycle');
      // Native begin was acknowledged above; retain the same ticket sequence.
      final ticket = gate.begin(nextId);
      event('page_started', ticket);
      if (mounted) {
        setState(() {
          config = next;
          visible = ticket;
        });
      }
    } else {
      await _write({
        ...retired,
        'stage':
            clean ? 'lifecycle_cancelled' : 'lifecycle_cleanup_unconfirmed',
        'old_result_suppressed': true
      }, reportGeneration, nextId);
    }
  }

  @override
  void dispose() {
    gate.current?.cancel();
    switchFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ticket = visible;
    final pageConfig = config;
    return PopScope(
        canPop: spec == null,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _transition();
        },
        child: Stack(children: [
          if (ticket != null && pageConfig != null)
            widget.pageBuilder(
                pageConfig,
                ticket,
                (row) => _finish(ticket, row),
                (signal) => _signal(ticket, signal),
                () => event('page_disposed', ticket))
          else
            const Scaffold(
                body: Text('QA case released; waiting for retirement')),
          if (spec?['action'] == 'switch' && !acted)
            Positioned(
                bottom: 24,
                left: 24,
                child: TextButton(
                    autofocus: true,
                    focusNode: switchFocus,
                    onPressed: _transition,
                    child: const Text('Switch QA fixture'))),
        ]));
  }
}
