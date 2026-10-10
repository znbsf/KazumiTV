import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/pages/history/history_page.dart';
import 'package:kazumi/pages/history/history_controller.dart';

// Each route mount needs its own module identity: flutter_modular deduplicates
// shared instances, which would otherwise drop the settings history shortcut.
final historyModule = createHistoryModule();

Module createHistoryModule() => createModule(
  path: '/history',
  register: (c) {
    c.route(
      '/',
      child: (context, state) => HistoryPage(
        controller: inject<HistoryController>(),
      ),
    );
  },
);
