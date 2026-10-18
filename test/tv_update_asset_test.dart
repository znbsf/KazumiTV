import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/services/update/tv_update_asset.dart';

Map<String, dynamic> release({List<Map<String, dynamic>>? assets}) => {
      'tag_name': 'v0.4.5',
      'html_url': 'https://github.com/znbsf/KazumiTV/releases/tag/v0.4.5',
      'draft': false,
      'prerelease': false,
      'assets': assets ?? [apk('armeabi-v7a'), apk('arm64-v8a'), apk('x86_64')],
    };
Map<String, dynamic> apk(String abi) => {
      'name': 'KazumiTV-0.4.5-$abi.apk',
      'browser_download_url':
          'https://github.com/znbsf/KazumiTV/releases/download/v0.4.5/KazumiTV-0.4.5-$abi.apk',
      'digest': 'sha256:${'a' * 64}',
      'size': 30000000,
      'state': 'uploaded',
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('uses OS ABI order, not asset order or physical CPU marketing name', () {
    final r = release();
    expect(
        TvUpdateAsset.select(r, ['arm64-v8a', 'armeabi-v7a']).abi, 'arm64-v8a');
    expect(TvUpdateAsset.select(r, ['armeabi-v7a']).abi, 'armeabi-v7a');
    expect(TvUpdateAsset.select(r, ['x86_64', 'x86']).abi, 'x86_64');
    expect(() => TvUpdateAsset.select(r, ['x86']), throwsFormatException);
    expect(
        TvUpdateAsset.select(release(assets: [apk('armeabi-v7a')]),
            ['arm64-v8a', 'armeabi-v7a']).abi,
        'armeabi-v7a');
  });
  test(
      'takes exact GitHub asset link and digest, ignores mirror and other files',
      () {
    final r = release(assets: [
      {...apk('armeabi-v7a'), 'name': 'KazumiTV-0.4.5-armeabi-v7a.apk.json'},
      {
        ...apk('armeabi-v7a'),
        'mirror_download_url': 'https://wrong.test/app.apk'
      },
    ]);
    final selected = TvUpdateAsset.select(r, ['armeabi-v7a']);
    expect(selected.url, apk('armeabi-v7a')['browser_download_url']);
    expect(selected.sha256, 'a' * 64);
    expect(selected.version, '0.4.5');
  });
  test('rejects wrong repository, tag, architecture and malformed release', () {
    for (final change in <Map<String, dynamic>>[
      {'prerelease': true},
      {'draft': true},
      {'tag_name': 'v0.4.5-rc.1'},
      {'html_url': 'https://github.com/Predidit/Kazumi/releases/tag/v0.4.5'},
      {'assets': null},
      {'assets': []},
      {
        'assets': [apk('x86_64')]
      },
      {
        'assets': [apk('armeabi-v7a'), apk('armeabi-v7a')]
      },
    ]) {
      expect(
          () =>
              TvUpdateAsset.select({...release(), ...change}, ['armeabi-v7a']),
          throwsFormatException,
          reason: '$change');
    }
  });
  test('fails closed for missing digest or unsafe asset URL and size', () {
    for (final change in <Map<String, dynamic>>[
      {'digest': null},
      {'digest': ''},
      {'digest': 'sha256:abc'},
      {'browser_download_url': 'http://github.com/znbsf/KazumiTV/app.apk'},
      {'browser_download_url': 'https://github.com.evil.test/app.apk'},
      {
        'browser_download_url':
            '${apk('armeabi-v7a')['browser_download_url']}?token=x'
      },
      {'browser_download_url': '${apk('arm64-v8a')['browser_download_url']}'},
      {'size': 0},
      {'size': 536870913},
      {'size': '30000000'},
      {'state': 'new'},
    ]) {
      expect(
          () => TvUpdateAsset.select(
              release(assets: [
                {...apk('armeabi-v7a'), ...change}
              ]),
              ['armeabi-v7a']),
          throwsFormatException);
    }
  });
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(
      () => messenger.setMockMethodCallHandler(TvUpdateAsset.channel, null));
  test(
      'only the installed formal package and pinned signature can select a download',
      () async {
    final valid = <String, dynamic>{
      'package': TvUpdateAsset.packageName,
      'certificate': TvUpdateAsset.certificate,
      'debuggable': false,
      'abis': ['armeabi-v7a']
    };
    for (final change in <Map<String, dynamic>>[
      {'package': '${TvUpdateAsset.packageName}.remoteqa'},
      {'certificate': 'wrong'},
      {'debuggable': true},
    ]) {
      messenger.setMockMethodCallHandler(
          TvUpdateAsset.channel, (_) async => {...valid, ...change});
      await expectLater(
          TvUpdateAsset.forDevice(release()), throwsFormatException);
    }
    messenger.setMockMethodCallHandler(
        TvUpdateAsset.channel, (_) async => valid);
    expect((await TvUpdateAsset.forDevice(release())).abi, 'armeabi-v7a');
  });
  test('native validation and install receive the same exact hash and identity',
      () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(TvUpdateAsset.channel, (call) async {
      calls.add(call);
      if (call.method == 'install') return 'permission_required';
      return null;
    });
    final asset = TvUpdateAsset.select(release(), ['armeabi-v7a']);
    await asset.validate('/cache/app.apk');
    expect(await asset.install('/cache/app.apk'), 'permission_required');
    expect(calls.map((c) => c.method), ['validate', 'install']);
    expect(calls[0].arguments, calls[1].arguments);
    expect(calls[0].arguments, asset.arguments('/cache/app.apk'));
  });
  test('platform rejection propagates; no installer fallback', () async {
    messenger.setMockMethodCallHandler(TvUpdateAsset.channel, (_) async {
      throw PlatformException(code: 'UPDATE_REJECTED', message: '签名不匹配');
    });
    final asset = TvUpdateAsset.select(release(), ['armeabi-v7a']);
    await expectLater(
        asset.validate('/cache/app.apk'), throwsA(isA<PlatformException>()));
    await expectLater(
        asset.install('/cache/app.apk'), throwsA(isA<PlatformException>()));
  });
}
