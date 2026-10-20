import 'dart:async';

class QaCaseTicket {
  QaCaseTicket(this.id, this.generation);
  final String id;
  final int generation;
  bool cancelled = false, finished = false, cleanupConfirmed = false;
  void Function()? _cancel;
  final retired = Completer<Map<String, dynamic>>();
  void attachCancel(void Function() action) {
    if (cancelled) {
      action();
    } else {
      _cancel = action;
    }
  }

  void cancel() {
    if (cancelled) return;
    cancelled = true;
    _cancel?.call();
  }
}

class QaLifecycleGate {
  QaCaseTicket? current;
  int generation = 0;
  QaCaseTicket begin(String id) {
    final old = current;
    if (old != null && (!old.finished || !old.cleanupConfirmed)) {
      throw StateError('Old QA case retirement must be confirmed');
    }
    return current = QaCaseTicket(id, ++generation);
  }

  bool finish(QaCaseTicket ticket, Map<String, dynamic> row) {
    if (ticket.finished) return false;
    ticket.finished = true;
    ticket.cleanupConfirmed = row['cleanup'] == 'confirmed';
    ticket._cancel = null;
    ticket.retired.complete(row);
    return identical(current, ticket) && !ticket.cancelled;
  }
}

Future<Map<String, Object?>> retireQaResources({
  Future<void> Function()? player,
  Future<void> Function()? resolver,
  Future<void> Function()? subscription,
  Duration budget = const Duration(seconds: 4),
}) async {
  final result = <String, Object?>{'cleanup': 'confirmed'};
  final limit =
      budget < const Duration(seconds: 4) ? budget : const Duration(seconds: 4);
  for (final entry in {
    'subscription': subscription,
    'player': player,
    'resolver': resolver
  }.entries) {
    if (entry.value == null) {
      result['${entry.key}_release'] = 'not_created';
      continue;
    }
    try {
      await Future<void>.sync(entry.value!).timeout(limit);
      result['${entry.key}_release'] = 'confirmed';
    } catch (error) {
      result['cleanup'] = 'unconfirmed';
      result['${entry.key}_release'] = 'unconfirmed';
      result['${entry.key}_release_error_type'] = error.runtimeType.toString();
    }
  }
  return result;
}
