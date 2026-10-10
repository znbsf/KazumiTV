import 'package:flutter_modular/flutter_modular.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/pages/index_module.dart';
import 'package:kazumi/pages/settings/settings_module.dart';

void main() {
  test('tab and personal-center history routes both survive composition', () {
    final graph = bootstrapModule(createModule(register: (c) {
      c
        ..module(tabModule)
        ..module(settingsModule);
    }));
    for (final path in ['/tab/history/', '/settings/history/']) {
      final route = graph.routes.match(Uri.parse(path));
      expect(route, isNotNull, reason: '$path must remain reachable');
      expect(route!.last.route.path, contains('history'));
    }
  });
}
