import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:cipherbook/models/vault_models.dart';
import 'package:cipherbook/services/clipboard_service.dart';
import 'package:cipherbook/services/crypto_service.dart';
import 'package:cipherbook/services/device_key_store.dart';
import 'package:cipherbook/services/import_export_service.dart';
import 'package:cipherbook/services/password_generator_service.dart';
import 'package:cipherbook/services/vault_repository.dart';
import 'package:cipherbook/state/vault_controller.dart';

void main() {
  test('quick unlock can reopen and continue saving', () async {
    final repository = _MemoryVaultRepository();
    final deviceKeyStore = _MemoryDeviceKeyStore();
    final controller = VaultController(
      repository: repository,
      cryptoService: CryptoService(),
      importExportService: _NoopImportExportService(),
      deviceKeyStore: deviceKeyStore,
      passwordGeneratorService: PasswordGeneratorService(random: Random(1)),
      clipboardService: _MemoryClipboardService(),
    );

    await controller.bootstrap();
    await controller.createVault('master-pass');
    await controller.enableQuickUnlock();
    await controller.lock();
    await controller.unlockWithQuickUnlock();
    await controller.addOrUpdateItem(
      title: 'Mail',
      username: 'alice',
      password: 'secret',
      url: 'https://example.com',
      notes: 'primary',
      tags: const ['mail'],
    );

    expect(controller.isUnlocked, isTrue);
    expect(controller.vaultData.activeItems.single.title, 'Mail');
    expect(deviceKeyStore.storedBytes, isNotNull);
    expect(repository.document, isNotNull);
  });
}

class _MemoryVaultRepository extends VaultRepository {
  EncryptedVaultDocument? document;

  @override
  Future<bool> exists() async => document != null;

  @override
  Future<EncryptedVaultDocument?> load() async => document;

  @override
  Future<Uint8List?> loadRaw() async => document?.encode();

  @override
  Future<void> save(EncryptedVaultDocument next) async {
    document = next;
  }

  @override
  Future<void> importRaw(Uint8List bytes) async {
    document = EncryptedVaultDocument.decode(bytes);
  }
}

class _MemoryDeviceKeyStore implements DeviceKeyStore {
  Uint8List? storedBytes;

  @override
  Future<void> clear() async {
    storedBytes = null;
  }

  @override
  Future<bool> isSupported() async => true;

  @override
  Future<Uint8List?> readWrappedDek() async => storedBytes;

  @override
  Future<void> storeWrappedDek(Uint8List wrappedDekBytes) async {
    storedBytes = Uint8List.fromList(wrappedDekBytes);
  }
}

class _NoopImportExportService extends ImportExportService {
  @override
  Future<String?> pickExportPath() async => null;

  @override
  Future<String?> pickImportPath() async => null;
}

class _MemoryClipboardService extends ClipboardService {
  String? lastCopiedText;

  @override
  Future<void> copyText(
    String text, {
    Duration clearAfter = const Duration(seconds: 30),
  }) async {
    lastCopiedText = text;
  }
}
