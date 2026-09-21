import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';

class ImportExportService {
  static const int maxVaultImportFileBytes = 16 * 1024 * 1024;
  static const XTypeGroup vaultFileGroup = XTypeGroup(
    label: '密码本文件',
    extensions: <String>['pwv'],
  );

  Future<String?> pickImportPath() {
    return openFile(acceptedTypeGroups: const [vaultFileGroup])
        .then((file) => file?.path);
  }

  Future<String?> pickExportPath() {
    if (Platform.isAndroid) {
      return getDirectoryPath().then((directory) {
        if (directory == null) {
          return null;
        }
        return '$directory${Platform.pathSeparator}cipherbook-export.pwv';
      });
    }
    return getSaveLocation(
      suggestedName: 'cipherbook-export.pwv',
      acceptedTypeGroups: const [vaultFileGroup],
    ).then((location) => location?.path);
  }

  Future<Uint8List> readFile(String path) async {
    final file = File(path);
    if (await file.length() > maxVaultImportFileBytes) {
      throw FormatException('导入文件超过支持的最大大小。');
    }
    return Uint8List.fromList(await file.readAsBytes());
  }

  Future<void> writeFile(String path, Uint8List bytes) async {
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes, flush: true);
  }
}
