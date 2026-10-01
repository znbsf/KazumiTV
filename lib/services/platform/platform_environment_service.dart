import 'dart:io';

import 'package:flutter/services.dart';
import 'package:kazumi/services/logging/logger.dart';

class PlatformEnvironmentService {
  PlatformEnvironmentService._();

  static const _intentChannel = MethodChannel('com.predidit.kazumi/intent');
  static const _videoChannel =
      MethodChannel('com.alexmercerind/media_kit_video');

  /// Reuse the frozen video plugin's own goldfish/ranchu detection. An explicit
  /// hwdec bypasses its default emulator protection, so auto TV output must
  /// consult the same capability before selecting an embedded codec Surface.
  static Future<bool> isAndroidEmulator() async {
    try {
      return await _videoChannel.invokeMethod<bool>('Utils.IsEmulator') ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException catch (e) {
      KazumiLogger().w('Failed to detect Android emulator', error: e);
      return false;
    }
  }

  static Future<bool> isInMultiWindowMode() async {
    if (!Platform.isAndroid) {
      return false;
    }
    try {
      return await _intentChannel.invokeMethod('checkIfInMultiWindowMode');
    } on PlatformException catch (e) {
      KazumiLogger().e("Failed to check multi window mode: '${e.message}'.");
      return false;
    }
  }

  static Future<bool> isRunningOnX11() async {
    if (!Platform.isLinux) {
      return false;
    }
    try {
      return await _intentChannel.invokeMethod('isRunningOnX11');
    } on PlatformException catch (e) {
      KazumiLogger().e("Failed to check X11 environment: '${e.message}'.");
      return false;
    }
  }

  static Future<int> getAndroidSdkVersion() async {
    if (!Platform.isAndroid) {
      return 0;
    }
    try {
      return await _intentChannel.invokeMethod('getAndroidSdkVersion');
    } on PlatformException catch (e) {
      KazumiLogger().e("Failed to get Android SDK version: '${e.message}'.");
      return 0;
    }
  }

  static Future<bool> isTelevision() async {
    if (!Platform.isAndroid) {
      return false;
    }
    try {
      return await _intentChannel.invokeMethod('isTelevision');
    } on PlatformException catch (e) {
      KazumiLogger().e("Failed to detect Android TV: '${e.message}'.");
      return false;
    }
  }
}
