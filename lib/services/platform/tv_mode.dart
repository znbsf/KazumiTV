import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show appFlavor;

/// Process-wide Android TV build identity available before the widget tree starts.
class TvMode {
  TvMode._();

  static bool _enabled = false;

  static bool get enabled => _enabled;

  static Future<void> initialize() async {
    // tv.gradle defines both the tv flavor and native IS_TV_BUILD=true.
    // audio_service can start Dart before MainActivity registers its channels;
    // querying that activity here would abort startup with MissingPluginException.
    _enabled = enabledForBuild(android: Platform.isAndroid, flavor: appFlavor);
  }

  @visibleForTesting
  static bool enabledForBuild(
      {required bool android, required String? flavor}) {
    return android && flavor == 'tv';
  }

  @visibleForTesting
  static void setEnabledForTesting(bool value) {
    _enabled = value;
  }
}
