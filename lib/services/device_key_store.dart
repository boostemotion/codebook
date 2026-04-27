import 'dart:typed_data';

import 'package:flutter/services.dart';

abstract class DeviceKeyStore {
  Future<bool> isSupported();

  Future<void> storeWrappedDek(Uint8List wrappedDekBytes);

  Future<Uint8List?> readWrappedDek();

  Future<void> clear();
}

class MethodChannelDeviceKeyStore implements DeviceKeyStore {
  static const MethodChannel _channel =
      MethodChannel('dev.codex.cipherbook/device_key_store');

  @override
  Future<void> clear() async {
    try {
      await _channel.invokeMethod<void>('clear');
    } on MissingPluginException {
      return;
    }
  }

  @override
  Future<bool> isSupported() async {
    try {
      return (await _channel.invokeMethod<bool>('isSupported')) ?? false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<Uint8List?> readWrappedDek() async {
    try {
      final bytes = await _channel.invokeMethod<Uint8List>('readWrappedDek');
      return bytes;
    } on MissingPluginException {
      return null;
    }
  }

  @override
  Future<void> storeWrappedDek(Uint8List wrappedDekBytes) async {
    try {
      await _channel.invokeMethod<void>(
        'storeWrappedDek',
        wrappedDekBytes,
      );
    } on MissingPluginException {
      return;
    }
  }
}

