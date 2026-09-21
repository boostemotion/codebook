import 'dart:io';

import 'package:flutter/services.dart';

class LanNetworkService {
  LanNetworkService({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(_channelName);

  static const String _channelName = 'dev.codex.cipherbook/lan_network';

  final MethodChannel _channel;
  int _leaseCount = 0;

  Future<void> acquireMulticastLock() async {
    if (!Platform.isAndroid) {
      return;
    }
    _leaseCount++;
    if (_leaseCount != 1) {
      return;
    }
    try {
      await _channel.invokeMethod<void>('acquireMulticastLock');
    } on MissingPluginException {
      _leaseCount = 0;
    } on PlatformException {
      _leaseCount = 0;
    }
  }

  Future<void> releaseMulticastLock() async {
    if (!Platform.isAndroid || _leaseCount == 0) {
      return;
    }
    _leaseCount--;
    if (_leaseCount != 0) {
      return;
    }
    try {
      await _channel.invokeMethod<void>('releaseMulticastLock');
    } on MissingPluginException {
      // Older Android builds do not expose the optional network channel.
    } on PlatformException {
      // Releasing is best effort; the process teardown also releases it.
    }
  }
}
