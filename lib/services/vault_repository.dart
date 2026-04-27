import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import '../models/vault_models.dart';

class VaultRepository {
  Future<bool> exists() async => (await _vaultFile()).exists();

  Future<EncryptedVaultDocument?> load() async {
    final file = await _vaultFile();
    if (!await file.exists()) {
      return null;
    }
    final bytes = await file.readAsBytes();
    return EncryptedVaultDocument.decode(Uint8List.fromList(bytes));
  }

  Future<Uint8List?> loadRaw() async {
    final file = await _vaultFile();
    if (!await file.exists()) {
      return null;
    }
    return Uint8List.fromList(await file.readAsBytes());
  }

  Future<void> save(EncryptedVaultDocument document) async {
    final file = await _vaultFile();
    await file.parent.create(recursive: true);
    final tempFile = File('${file.path}.tmp');
    await tempFile.writeAsBytes(document.encode(), flush: true);
    await _replaceWithBackup(file, tempFile);
  }

  Future<void> importRaw(Uint8List bytes) async {
    final file = await _vaultFile();
    await file.parent.create(recursive: true);
    final tempFile = File('${file.path}.tmp');
    await tempFile.writeAsBytes(bytes, flush: true);
    await _replaceWithBackup(file, tempFile);
  }

  Future<File> _vaultFile() async {
    final directory = await getApplicationSupportDirectory();
    return File('${directory.path}${Platform.pathSeparator}vault.pwv');
  }

  Future<void> _replaceWithBackup(File target, File tempFile) async {
    final backupFile = File('${target.path}.bak');
    if (await backupFile.exists()) {
      await backupFile.delete();
    }
    if (await target.exists()) {
      await target.rename(backupFile.path);
    }
    try {
      await tempFile.rename(target.path);
      if (await backupFile.exists()) {
        await backupFile.delete();
      }
    } catch (_) {
      if (await backupFile.exists()) {
        await backupFile.rename(target.path);
      }
      rethrow;
    }
  }
}
