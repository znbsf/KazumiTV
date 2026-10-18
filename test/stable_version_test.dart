import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/services/update/project_update_policy.dart';
import 'package:kazumi/utils/version.dart';

Map<String, dynamic> release(String tag) => {
      'tag_name': tag,
      'html_url': 'https://github.com/znbsf/KazumiTV/releases/tag/$tag',
      'draft': false,
      'prerelease': false,
    };
void main() {
  test('canonical stable tags with optional v compare identically', () {
    for (final prefix in ['', 'v']) {
      expect(needStableUpdate('0.4.3', '${prefix}0.4.4'), true);
      expect(needStableUpdate('0.4.3', '${prefix}0.4.3'), false);
      expect(needStableUpdate('0.4.3', '${prefix}0.4.2'), false);
      expect(needStableUpdate('0.9.9', '${prefix}0.10.0'), true);
      expect(needStableUpdate('1.0.0', '${prefix}0.999.999'), false);
      expect(
          ProjectUpdatePolicy.acceptsRelease(release('${prefix}0.4.4')), true);
    }
  });
  test('invalid and non-stable tags are rejected before comparison', () {
    for (final tag in [
      '',
      'V0.4.4',
      'vv0.4.4',
      '0.4',
      '0.4.4.1',
      '0.04.4',
      '01.4.4',
      '-1.4.4',
      '0.a.4',
      ' 0.4.4',
      '0.4.4 ',
      '0.4.4\n',
      'v0.4.4-qa4',
      '0.4.4-rc.1',
      '0.4.4+build',
      'v0.4.4/path'
    ]) {
      expect(normalizeStableVersion(tag), isNull, reason: tag);
      expect(ProjectUpdatePolicy.acceptsRelease(release(tag)), false,
          reason: tag);
      expect(() => needStableUpdate('0.4.3', tag), throwsFormatException,
          reason: tag);
    }
  });
  test('QA local builds and prerelease metadata never qualify for upgrade', () {
    for (final local in [
      '0.4.3-qa4',
      '0.4.3-preview.1',
      '0.4.3+test',
      'v0.4.3'
    ]) {
      expect(
          ProjectUpdatePolicy.canCheck(
              releaseMode: true, tv: true, version: local),
          false);
      expect(() => needStableUpdate(local, 'v0.4.4'), throwsFormatException);
    }
    expect(
        ProjectUpdatePolicy.acceptsRelease(
            {...release('v0.4.4'), 'prerelease': true}),
        false);
    expect(
        ProjectUpdatePolicy.acceptsRelease(
            {...release('v0.4.4'), 'draft': true}),
        false);
  });
  test('large stable components compare without integer overflow', () {
    expect(
        needStableUpdate('0.4.3', 'v999999999999999999999999999999.0.0'), true);
    expect(needStableUpdate('999999999999999999999999999999.0.0', 'v0.4.4'),
        false);
  });
  test('rule dotted versions keep existing short-version semantics', () {
    expect(needUpdate('2.5', '2.6'), true);
    expect(needUpdate('2.5', '2.5.0'), false);
    expect(needUpdate('2.5.1', '2.5'), false);
  });
}
