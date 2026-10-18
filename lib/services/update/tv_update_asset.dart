import 'package:flutter/services.dart';
import 'package:kazumi/utils/version.dart';
import 'project_update_policy.dart';

/// An exact, digest-bearing APK from this project's stable GitHub release.
class TvUpdateAsset {
  const TvUpdateAsset(
      {required this.version,
      required this.abi,
      required this.url,
      required this.sha256,
      required this.size});
  final String version, abi, url, sha256;
  final int size;

  static const packageName = 'com.znbsf.kazumi.fluttertv';
  static const certificate =
      '3225e3b8676eed2d2f28fad6255881120f6335ade615bbb27673d974727ce806';
  static const channel = MethodChannel('com.znbsf.kazumi/update');

  static Future<TvUpdateAsset> forDevice(Map<String, dynamic> release) async {
    final identity = await channel.invokeMapMethod<String, dynamic>('identity');
    if (identity == null ||
        identity['package'] != packageName ||
        identity['certificate'] != certificate ||
        identity['debuggable'] != false) {
      throw const FormatException('此安装包不参与正式版升级');
    }
    return select(release, List<String>.from(identity['abis'] as List));
  }

  static TvUpdateAsset select(Map<String, dynamic> release, List<String> abis) {
    if (!ProjectUpdatePolicy.acceptsRelease(release)) {
      throw const FormatException('更新来源无效');
    }
    final tag = release['tag_name'] as String;
    final version = normalizeStableVersion(tag)!;
    final assets = release['assets'];
    if (assets is! List) throw const FormatException('发布版本缺少安装包');
    for (final abi in abis) {
      if (!['arm64-v8a', 'armeabi-v7a', 'x86_64'].contains(abi)) continue;
      final name = 'KazumiTV-$version-$abi.apk';
      final matches =
          assets.whereType<Map>().where((a) => a['name'] == name).toList();
      if (matches.isEmpty) continue;
      if (matches.length != 1) throw const FormatException('安装包名称重复');
      final asset = matches.single;
      final url = asset['browser_download_url'];
      final digest = asset['digest'];
      final size = asset['size'];
      if (url !=
              'https://github.com/znbsf/KazumiTV/releases/download/$tag/$name' ||
          digest is! String ||
          !RegExp(r'^sha256:[a-fA-F0-9]{64}$').hasMatch(digest) ||
          size is! int ||
          size <= 0 ||
          size > 512 * 1024 * 1024 ||
          asset['state'] != 'uploaded') {
        throw const FormatException('安装包下载地址或校验信息无效');
      }
      return TvUpdateAsset(
          version: version,
          abi: abi,
          url: url as String,
          sha256: digest.substring(7).toLowerCase(),
          size: size);
    }
    throw const FormatException('此版本没有适合当前电视架构的安装包');
  }

  Map<String, Object> arguments(String path) => {
        'path': path,
        'version': version,
        'abi': abi,
        'sha256': sha256,
        'size': size,
      };

  Future<void> validate(String path) =>
      channel.invokeMethod<void>('validate', arguments(path));

  Future<String> install(String path) async =>
      await channel.invokeMethod<String>('install', arguments(path)) ??
      'failed';

  static Future<void> openPermissionSettings() =>
      channel.invokeMethod<void>('permissionSettings');
}
