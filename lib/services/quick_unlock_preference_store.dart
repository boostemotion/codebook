import 'dart:io';

import 'package:path_provider/path_provider.dart';

abstract class QuickUnlockPreferenceStore {
  Future<bool> allowQuickUnlockOnFirstLaunch();

  Future<void> setAllowQuickUnlockOnFirstLaunch(bool value);
}

class FileQuickUnlockPreferenceStore implements QuickUnlockPreferenceStore {
  const FileQuickUnlockPreferenceStore();

  static const String _fileName = 'quick-unlock-preferences.txt';

  @override
  Future<bool> allowQuickUnlockOnFirstLaunch() async {
    try {
      final file = await _file();
      if (!await file.exists()) {
        return false;
      }
      return (await file.readAsString()).trim().toLowerCase() == 'true';
    } on Object {
      return false;
    }
  }

  @override
  Future<void> setAllowQuickUnlockOnFirstLaunch(bool value) async {
    final file = await _file();
    await file.parent.create(recursive: true);
    await file.writeAsString(value ? 'true' : 'false', flush: true);
  }

  Future<File> _file() async {
    final directory = await getApplicationSupportDirectory();
    return File('${directory.path}${Platform.pathSeparator}$_fileName');
  }
}

class MemoryQuickUnlockPreferenceStore implements QuickUnlockPreferenceStore {
  MemoryQuickUnlockPreferenceStore({bool allowOnFirstLaunch = false})
      : _allowOnFirstLaunch = allowOnFirstLaunch;

  bool _allowOnFirstLaunch;

  @override
  Future<bool> allowQuickUnlockOnFirstLaunch() async => _allowOnFirstLaunch;

  @override
  Future<void> setAllowQuickUnlockOnFirstLaunch(bool value) async {
    _allowOnFirstLaunch = value;
  }
}
