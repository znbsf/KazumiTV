import 'dart:io';
import 'dart:isolate';

import 'package:kazumi/request/config/api_endpoints.dart';
import 'package:kazumi/services/logging/logger.dart' as logging;
import 'package:kazumi/services/logging/log_export.dart';

Future<LogExport> createLogExport() async {
  final raw = await logging.readRecentLogs();
  final created = DateTime.now();
  final platform = Platform.operatingSystem;
  final text = await Isolate.run(() => formatLogExport(raw,
      createdAt: created, version: ApiEndpoints.version, platform: platform));
  return LogExport(text: text, createdAt: created);
}
