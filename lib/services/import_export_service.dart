import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';

class ImportExportService {
  static const XTypeGroup vaultFileGroup = XTypeGroup(
    label: 'Cipherbook Vault',
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
    return Uint8List.fromList(await File(path).readAsBytes());
  }

  Future<void> writeFile(String path, Uint8List bytes) async {
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes, flush: true);
  }
}
