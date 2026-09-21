import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:cipherbook/services/import_export_service.dart';

void main() {
  test('rejects an oversized import before reading its contents', () async {
    final directory =
        await Directory.systemTemp.createTemp('cipherbook-import-');
    addTearDown(() => directory.delete(recursive: true));
    final file =
        File('${directory.path}${Platform.pathSeparator}oversized.pwv');
    await file.create();
    final handle = await file.open(mode: FileMode.write);
    await handle.truncate(ImportExportService.maxVaultImportFileBytes + 1);
    await handle.close();

    await expectLater(
      ImportExportService().readFile(file.path),
      throwsA(isA<FormatException>()),
    );
  });
}
