import 'dart:collection';

import 'package:flutter/foundation.dart';

/// Keeps the latest diagnostics without rebuilding an unopened viewer.
class BoundedLogBuffer extends ChangeNotifier {
  final _lines = ListQueue<String>();
  List<String> get lines => List.unmodifiable(_lines);

  void add(String line) {
    _lines.addLast(line.length > 4096 ? '${line.substring(0, 4096)}…' : line);
    if (_lines.length > 100) _lines.removeFirst();
    notifyListeners();
  }

  void clear() {
    if (_lines.isEmpty) return;
    _lines.clear();
    notifyListeners();
  }
}
