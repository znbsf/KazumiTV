import 'dart:math';

bool needUpdate(String localVersion, String remoteVersion) {
  final localVersionList = localVersion.split('.');
  final remoteVersionList = remoteVersion.split('.');
  final maxLength = max(localVersionList.length, remoteVersionList.length);
  for (var i = 0; i < maxLength; i++) {
    final localSegment =
        i < localVersionList.length ? int.parse(localVersionList[i]) : 0;
    final remoteSegment =
        i < remoteVersionList.length ? int.parse(remoteVersionList[i]) : 0;
    if (remoteSegment > localSegment) {
      return true;
    } else if (remoteSegment < localSegment) {
      return false;
    }
  }
  return false;
}

/// Stable app releases only. Rule versions retain their existing dotted-number
/// comparison above. No trimming, prerelease/build suffixes or leading zeroes.
String? normalizeStableVersion(String value, {bool allowVPrefix = true}) {
  final match = RegExp(r'v?(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)')
      .matchAsPrefix(value);
  if (match == null ||
      match.end != value.length ||
      (!allowVPrefix && value.startsWith('v'))) {
    return null;
  }
  return value.startsWith('v') ? value.substring(1) : value;
}

/// Invalid version metadata is a check failure, never "already up to date".
/// BigInt avoids overflow for otherwise valid numeric release components.
bool needStableUpdate(String localVersion, String remoteTag) {
  final local = normalizeStableVersion(localVersion, allowVPrefix: false);
  final remote = normalizeStableVersion(remoteTag);
  if (local == null || remote == null) {
    throw const FormatException('Invalid stable release version');
  }
  final localParts = local.split('.').map(BigInt.parse).toList();
  final remoteParts = remote.split('.').map(BigInt.parse).toList();
  for (var i = 0; i < 3; i++) {
    final comparison = remoteParts[i].compareTo(localParts[i]);
    if (comparison != 0) return comparison > 0;
  }
  return false;
}
