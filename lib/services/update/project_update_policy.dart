/// Only stable TV builds query the stable project release feed. Checking a
/// version is not authorization to install an APK: package, ABI and signing
/// identity have no trusted update manifest yet, so updates remain manual.
class ProjectUpdatePolicy {
  static bool canCheck(
          {required bool releaseMode,
          required bool tv,
          required String version}) =>
      releaseMode && tv && RegExp(r'^\d+\.\d+\.\d+$').hasMatch(version);

  static bool acceptsRelease(Map<String, dynamic> release) {
    final uri = Uri.tryParse(release['html_url']?.toString() ?? '');
    final tag = release['tag_name']?.toString() ?? '';
    return release['draft'] == false &&
        release['prerelease'] == false &&
        RegExp(r'^v?\d+\.\d+\.\d+$').hasMatch(tag) &&
        uri?.scheme == 'https' &&
        uri?.host == 'github.com' &&
        uri?.userInfo == '' &&
        uri?.port == 443 &&
        uri?.path == '/znbsf/KazumiTV/releases/tag/$tag' &&
        uri?.query == '' &&
        uri?.fragment == '';
  }
}
