import 'dart:async';

import 'package:flutter/services.dart';

class ClipboardService {
  Timer? _clearTimer;
  String? _lastCopiedText;

  Future<void> copyText(
    String text, {
    Duration clearAfter = const Duration(seconds: 30),
  }) async {
    _clearTimer?.cancel();
    _lastCopiedText = text;
    await Clipboard.setData(ClipboardData(text: text));
    _clearTimer = Timer(clearAfter, () async {
      final current = await Clipboard.getData('text/plain');
      if (current?.text == _lastCopiedText) {
        await Clipboard.setData(const ClipboardData(text: ''));
      }
      _lastCopiedText = null;
    });
  }

  void dispose() {
    _clearTimer?.cancel();
  }
}
