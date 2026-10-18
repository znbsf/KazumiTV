import 'package:kazumi/utils/version.dart';

/// Only stable TV builds query the stable project release feed. Checking a
/// version is not authorization to install an APK: the TV asset selector and
/// native bridge separately verify the download, ABI, package and certificate.
class ProjectUpdatePolicy {
  static bool canCheck(
          {required bool releaseMode,
          required bool tv,
          required String version}) =>
      releaseMode &&
      tv &&
      normalizeStableVersion(version, allowVPrefix: false) != null;

  static bool acceptsRelease(Map<String, dynamic> release) {
    final uri = Uri.tryParse(release['html_url']?.toString() ?? '');
    final tag = release['tag_name']?.toString() ?? '';
    return release['draft'] == false &&
        release['prerelease'] == false &&
        normalizeStableVersion(tag) != null &&
        uri?.scheme == 'https' &&
        uri?.host == 'github.com' &&
        uri?.userInfo == '' &&
        uri?.port == 443 &&
        uri?.path == '/znbsf/KazumiTV/releases/tag/$tag' &&
        uri?.query == '' &&
        uri?.fragment == '';
  }
}
