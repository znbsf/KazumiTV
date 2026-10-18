import 'dart:convert';
import 'dart:io';
import '../../lib/services/qr_search_session.dart';

/// Local browser QA only; does not change the production binding policy.
Future<void> main(List<String> args) async {
  if (args.length != 1) throw ArgumentError('Provide an evidence directory');
  final directory = Directory(args.single)..createSync(recursive: true);
  final receipt = File('${directory.path}/receipt.jsonl');
  final session = QrSearchSession(onQuery: (query) {
    receipt.writeAsStringSync(
        '${jsonEncode({
              'query': query,
              'at': DateTime.now().toUtc().toIso8601String()
            })}\n',
        mode: FileMode.append);
  }, onClosed: () {
    File('${directory.path}/closed.txt')
        .writeAsStringSync(DateTime.now().toUtc().toIso8601String());
  });
  final uri = await session.start(address: InternetAddress.loopbackIPv4);
  File('${directory.path}/endpoint.txt').writeAsStringSync(uri.toString());
  stdout.writeln(uri);
}
