// QA-only identity guard before parsing an alternate episode/road.
import 'dart:convert';
import 'package:crypto/crypto.dart';

bool qaEpisodeMatches(Map<String, dynamic> config,
    {required String url, required String label}) {
  final expectedHash = config['expected_episode_page_sha256'];
  final expectedLabel = config['expected_episode_label'];
  if (expectedHash == null && expectedLabel == null) return true;
  if (expectedHash is! String ||
      !RegExp(r'^[a-f0-9]{64}$').hasMatch(expectedHash) ||
      expectedLabel is! String ||
      expectedLabel.isEmpty) {
    throw const FormatException('QA episode hash and exact label required');
  }
  return label == expectedLabel &&
      sha256.convert(utf8.encode(url)).toString() == expectedHash;
}
