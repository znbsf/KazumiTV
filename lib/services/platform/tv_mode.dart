import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show appFlavor;

/// Process-wide Android TV build identity available before the widget tree starts.
class TvMode {
  TvMode._();

  static bool _enabled = false;
  static bool _debugParserQaFullUi = false;

  static bool get enabled => _enabled;

  static Future<void> initialize() async {
    // tv.gradle defines both the tv flavor and native IS_TV_BUILD=true.
    // audio_service can start Dart before MainActivity registers its channels;
    // querying that activity here would abort startup with MissingPluginException.
    _enabled = enabledForBuild(
        android: Platform.isAndroid,
        flavor: appFlavor,
        parserQaFullUi: _debugParserQaFullUi);
  }

  @visibleForTesting
  static bool enabledForBuild(
      {required bool android,
      required String? flavor,
      bool parserQaFullUi = false}) {
    return android &&
        (flavor == 'tv' ||
            (kDebugMode && parserQaFullUi && flavor == 'parserQa'));
  }

  /// Only a debug entrypoint with a positive native QA profile handshake may
  /// install this override. Ordinary parserQa and all release builds ignore it.
  @visibleForTesting
  static void setDebugParserQaFullUi(bool value) {
    if (kDebugMode) _debugParserQaFullUi = value;
  }

  @visibleForTesting
  static void setEnabledForTesting(bool value) {
    _enabled = value;
  }
}
