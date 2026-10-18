import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

class PhoneRemotePairing {
  PhoneRemotePairing(
      {required this.token,
      required this.port,
      required this.createdAt,
      required this.expiresAt,
      this.paused = false});
  final String token;
  final int port;
  final DateTime createdAt;
  final DateTime expiresAt;
  final bool paused;
  PhoneRemotePairing withPaused(bool value) => PhoneRemotePairing(
      token: token,
      port: port,
      createdAt: createdAt,
      expiresAt: expiresAt,
      paused: value);
  bool validAt(DateTime now) =>
      RegExp(r'^[a-f0-9]{32}$').hasMatch(token) &&
      port >= 1024 &&
      port <= 65535 &&
      !now.isBefore(createdAt) &&
      now.isBefore(expiresAt) &&
      expiresAt.isAfter(createdAt) &&
      expiresAt.difference(createdAt) <= const Duration(days: 7);
}

/// Local capability, deliberately outside Android backup and library export.
/// Pairing and manual pause persist; text consent and request state never do.
class PhoneRemotePairingStore {
  PhoneRemotePairingStore({this.directory});
  final Directory? directory;
  Future<File> _file() async {
    var dir = directory;
    if (dir == null && Platform.isAndroid) {
      final path = await const MethodChannel('com.predidit.kazumi/storage')
          .invokeMethod<String>('getNoBackupDirectory');
      if (path == null) throw StateError('No private storage');
      dir = Directory(path);
    }
    dir ??= await getApplicationSupportDirectory();
    return File('${dir.path}/phone-remote-pairing.json');
  }

  Future<PhoneRemotePairing?> read({DateTime? now}) async {
    final file = await _file();
    if (!await file.exists()) return null;
    try {
      if (await file.length() > 2048) return null;
      final data = jsonDecode(await file.readAsString()) as Map;
      if (data['version'] != 1 || data['revoked'] == true) return null;
      final pairing = PhoneRemotePairing(
          token: data['token'] as String,
          port: data['port'] as int,
          createdAt: DateTime.parse(data['createdAt'] as String),
          expiresAt: DateTime.parse(data['expiresAt'] as String),
          paused: (data['paused'] ?? false) as bool);
      return pairing.validAt(now ?? DateTime.now()) ? pairing : null;
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  Future<void> _write(Map<String, Object?> data) async {
    final file = await _file();
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(jsonEncode(data), flush: true);
    await temporary.rename(file.path);
  }

  Future<void> write(PhoneRemotePairing pairing) async {
    if (!pairing.validAt(DateTime.now())) throw StateError('Invalid pairing');
    await _write({
      'version': 1,
      'token': pairing.token,
      'port': pairing.port,
      'paused': pairing.paused,
      'createdAt': pairing.createdAt.toUtc().toIso8601String(),
      'expiresAt': pairing.expiresAt.toUtc().toIso8601String()
    });
  }

  // Persist revocation before reporting success, even if deletion is unavailable.
  Future<void> clear() => _write({'version': 1, 'revoked': true});
}
