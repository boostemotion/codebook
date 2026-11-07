import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';

class ImportExportService {
  static const int maxVaultImportFileBytes = 16 * 1024 * 1024;
  static const XTypeGroup vaultFileGroup = XTypeGroup(
    label: '密码本文件',
    extensions: <String>['pwv'],
  );
  static const XTypeGroup bitwardenFileGroup = XTypeGroup(
    label: 'Bitwarden 交换文件',
    extensions: <String>['json', 'csv'],
  );
  static const XTypeGroup bitwardenJsonFileGroup = XTypeGroup(
    label: 'Bitwarden JSON',
    extensions: <String>['json'],
  );
  static const XTypeGroup bitwardenCsvFileGroup = XTypeGroup(
    label: 'Bitwarden CSV',
    extensions: <String>['csv'],
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

  Future<String?> pickBitwardenImportPath() {
    return openFile(acceptedTypeGroups: const [bitwardenFileGroup])
        .then((file) => file?.path);
  }

  Future<String?> pickBitwardenExportPath({required bool csv}) {
    final extension = csv ? 'csv' : 'json';
    final suggestedName = 'cipherbook-bitwarden.$extension';
    final typeGroup = csv ? bitwardenCsvFileGroup : bitwardenJsonFileGroup;
    if (Platform.isAndroid) {
      return getDirectoryPath().then((directory) {
        if (directory == null) {
          return null;
        }
        return '$directory${Platform.pathSeparator}$suggestedName';
      });
    }
    return getSaveLocation(
      suggestedName: suggestedName,
      acceptedTypeGroups: [typeGroup],
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
