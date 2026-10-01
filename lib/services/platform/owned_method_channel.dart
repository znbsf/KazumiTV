import 'package:flutter/services.dart';

typedef PlatformMethodHandler = Future<dynamic> Function(MethodCall call);

/// One dispatcher per channel, with lifetimes owned by the subscribing pages.
/// This stores callbacks only; business and playback state stay with Dart owners.
class OwnedMethodChannel {
  OwnedMethodChannel(this.channel, {this.onActiveChanged});

  final MethodChannel channel;
  final void Function(bool active)? onActiveChanged;
  final List<MethodChannelLease> _owners = [];
  int _revision = 0;
  bool get hasOwners => _owners.isNotEmpty;

  MethodChannelLease claim(PlatformMethodHandler handler,
      {void Function()? onActivated}) {
    final lease = MethodChannelLease._(this, handler, onActivated);
    final wasEmpty = _owners.isEmpty;
    _owners.add(lease);
    _revision++;
    if (wasEmpty) {
      channel.setMethodCallHandler(_dispatch);
      onActiveChanged?.call(true);
    }
    onActivated?.call();
    return lease;
  }

  Future<dynamic> _dispatch(MethodCall call) async {
    if (_owners.isEmpty) return null;
    return await _owners.last._handler(call);
  }

  void _release(MethodChannelLease lease) {
    final wasCurrent = lease.isCurrent;
    if (!_owners.remove(lease)) return;
    if (wasCurrent) _revision++;
    if (_owners.isEmpty) {
      channel.setMethodCallHandler(null);
      onActiveChanged?.call(false);
    } else if (wasCurrent) {
      _owners.last._onActivated?.call();
    }
  }
}

class MethodChannelLease {
  MethodChannelLease._(this._owner, this._handler, this._onActivated);
  final OwnedMethodChannel _owner;
  final PlatformMethodHandler _handler;
  final void Function()? _onActivated;
  bool get isCurrent =>
      _owner._owners.isNotEmpty && identical(_owner._owners.last, this);

  /// Captures one activation; regaining ownership does not revive old requests.
  bool Function() captureOwnership() {
    final revision = _owner._revision;
    return () => isCurrent && revision == _owner._revision;
  }

  void release() => _owner._release(this);
}
