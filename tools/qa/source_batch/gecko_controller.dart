import 'dart:async';
import 'package:flutter/services.dart';
import 'package:kazumi/webview/video/video_webview_controller.dart';
import 'package:kazumi/webview/video/video_parser_url.dart';

const qaChannel = MethodChannel('kazumi/parser_qa');

class GeckoQaController extends VideoWebviewController<dynamic> {
  GeckoQaController(this.userAgent);
  final String userAgent;
  static GeckoQaController? _owner;
  static int _nextToken = 0;
  int _generation = ++_nextToken;
  int? _nativeOwner;
  Future<int>? _acquisition;
  bool _acquisitionRejected = false;
  bool _active = false;
  bool _disposed = false;
  Future<void>? _initialization, _disposal;
  bool get _ownsChannel => identical(_owner, this);

  @override
  Future<void> init() {
    if (_disposed) return Future.error(StateError('Gecko QA retired'));
    return _initialization ??= _init();
  }

  Future<void> _init() async {
    if (_owner != null && !_ownsChannel) {
      throw StateError('Gecko QA channel already owned');
    }
    _owner = this;
    qaChannel.setMethodCallHandler((call) async {
      if (!_ownsChannel || !_active || _disposed || call.arguments is! Map) {
        return;
      }
      final args = Map<String, dynamic>.from(call.arguments as Map);
      if (args['owner'] != _nativeOwner || args['generation'] != _generation) {
        return;
      }
      if (call.method == 'geckoDiagnostic') {
        reportDiagnostic(args['stage'] as String, args['url'] as String,
            args['detail'] as String);
        return;
      }
      if (call.method != 'geckoEvent') return;
      final raw = args['url'] as String;
      if (args['handler'] == 'JSBridgeDebug') {
        final media = embeddedVideoParserUrl(raw);
        if (media != null) {
          notifyVideoSourceResolved(media);
          return;
        }
        final page = nestedVideoPageUrl(raw, fromPlayerQuery: true);
        if (page != null) notifyNestedPageCandidate(page);
      } else {
        final page = nestedVideoPageUrl(raw);
        if (page != null) {
          notifyNestedPageCandidate(page);
          return;
        }
        if (isVideoParserNetworkUrl(raw) && !isVideoParserAdUrl(raw)) {
          notifyVideoSourceResolved(raw);
        }
      }
    });
    final owner = await (_acquisition ??= _acquire());
    if (_disposed || !_ownsChannel) throw StateError('Gecko QA retired');
    await qaChannel.invokeMethod<void>('geckoInit', {'owner': owner});
    if (_disposed || !_ownsChannel) throw StateError('Gecko QA retired');
    initEventController.add(true);
  }

  Future<int> _acquire() async {
    try {
      // Native process-wide monotonic tokens also distinguish Flutter isolates.
      final owner = await qaChannel.invokeMethod<int>('geckoAcquire');
      if (owner == null || owner <= 0) {
        throw StateError('Gecko QA lease unconfirmed');
      }
      _nativeOwner = owner;
      return owner;
    } on PlatformException catch (error) {
      // Only an explicit no-allocation response permits clean release on error.
      _acquisitionRejected = error.code == 'gecko_busy';
      rethrow;
    }
  }

  @override
  Future<void> loadUrl(String url, bool useLegacyParser,
      {int offset = 0}) async {
    // Deliberately explicit prototype limitation; never silently change modes.
    if (useLegacyParser) throw UnsupportedError('Gecko QA iframe-only mode');
    if (_disposed || !_ownsChannel) throw StateError('Gecko QA unavailable');
    await unloadPage();
    if (_disposed || !_ownsChannel) throw StateError('Gecko QA retired');
    this.offset = offset;
    _active = true;
    await qaChannel.invokeMethod<void>('geckoLoad', {
      'url': url,
      'ua': userAgent,
      'generation': _generation,
      'owner': _nativeOwner,
    });
  }

  @override
  Future<void> unloadPage() async {
    _active = false;
    _generation = ++_nextToken;
    if (_disposed || !_ownsChannel) return;
    final closed = await qaChannel.invokeMethod<bool>('geckoClose', {
      'owner': _nativeOwner,
      'release': false,
    });
    if (closed != true) throw StateError('Gecko QA close unconfirmed');
  }

  @override
  Future<void> dispose() => _disposal ??= _dispose();

  Future<void> _dispose() async {
    _disposed = true;
    _active = false;
    _generation = ++_nextToken;
    try {
      if (_ownsChannel) {
        if (_acquisition != null) {
          try {
            await _acquisition;
          } catch (_) {
            if (!_acquisitionRejected) rethrow;
          }
        }
        if (_nativeOwner != null) {
          final closed = await qaChannel.invokeMethod<bool>('geckoClose', {
            'owner': _nativeOwner,
            'release': true,
          });
          if (closed != true) {
            throw StateError('Gecko QA retirement unconfirmed');
          }
        }
        // An old dispose can never clear a newer route's handler/lease.
        if (_ownsChannel) {
          qaChannel.setMethodCallHandler(null);
          _owner = null;
        }
      }
    } finally {
      disposeEventControllers();
    }
    // If close fails, retain the inactive owner. A new engine must fail closed.
  }
}
