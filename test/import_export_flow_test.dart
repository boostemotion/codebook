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
  test('export with dedicated password can be imported as a new local vault',
      () async {
    final sourceRepo = _MemoryVaultRepository();
    final sourceImportExport = _MemoryImportExportService();
    final source = VaultController(
      repository: sourceRepo,
      cryptoService: CryptoService(),
      importExportService: sourceImportExport,
      deviceKeyStore: _MemoryDeviceKeyStore(),
      passwordGeneratorService: PasswordGeneratorService(random: Random(1)),
      clipboardService: _MemoryClipboardService(),
    );
    await source.bootstrap();
    await source.createVault('local-pass');
    await source.addOrUpdateItem(
      title: 'Mail',
      username: 'alice',
      password: 'secret',
      url: 'https://example.com',
      notes: 'primary',
      tags: const ['mail'],
    );

    await source.exportVault(exportPassword: 'export-pass');
    final exportedBytes = sourceImportExport.writtenBytes;
    expect(exportedBytes, isNotNull);

    final destinationRepo = _MemoryVaultRepository();
    final destinationImportExport = _MemoryImportExportService()
      ..nextImportBytes = exportedBytes;
    final destination = VaultController(
      repository: destinationRepo,
      cryptoService: CryptoService(),
      importExportService: destinationImportExport,
      deviceKeyStore: _MemoryDeviceKeyStore(),
      passwordGeneratorService: PasswordGeneratorService(random: Random(2)),
      clipboardService: _MemoryClipboardService(),
    );
    await destination.bootstrap();

    final plan = await destination.previewImport('export-pass');
    expect(plan, isNotNull);
    await destination.applyImportPlan(plan!);

    expect(destination.hasVault, isTrue);
    expect(destination.isUnlocked, isTrue);
    expect(destination.vaultData.activeItems.single.title, 'Mail');
    expect(destinationRepo.document, isNotNull);
  });

  test('import preview rejects wrong import password', () async {
    final exportService = _MemoryImportExportService();
    final source = VaultController(
      repository: _MemoryVaultRepository(),
      cryptoService: CryptoService(),
      importExportService: exportService,
      deviceKeyStore: _MemoryDeviceKeyStore(),
      passwordGeneratorService: PasswordGeneratorService(random: Random(3)),
      clipboardService: _MemoryClipboardService(),
    );
    await source.bootstrap();
    await source.createVault('local-pass');
    await source.exportVault(exportPassword: 'export-pass');

    final destinationImportExport = _MemoryImportExportService()
      ..nextImportBytes = exportService.writtenBytes;
    final destination = VaultController(
      repository: _MemoryVaultRepository(),
      cryptoService: CryptoService(),
      importExportService: destinationImportExport,
      deviceKeyStore: _MemoryDeviceKeyStore(),
      passwordGeneratorService: PasswordGeneratorService(random: Random(4)),
      clipboardService: _MemoryClipboardService(),
    );
    await destination.bootstrap();

    final plan = await destination.previewImport('wrong-pass');
    expect(plan, isNull);
    expect(destination.message, contains('解锁失败'));
  });

  test('import preview rejects tampered encrypted file', () async {
    final exportService = _MemoryImportExportService();
    final source = VaultController(
      repository: _MemoryVaultRepository(),
      cryptoService: CryptoService(),
      importExportService: exportService,
      deviceKeyStore: _MemoryDeviceKeyStore(),
      passwordGeneratorService: PasswordGeneratorService(random: Random(5)),
      clipboardService: _MemoryClipboardService(),
    );
    await source.bootstrap();
    await source.createVault('local-pass');
    await source.exportVault(exportPassword: 'export-pass');

    final original = EncryptedVaultDocument.decode(
        Uint8List.fromList(exportService.writtenBytes!));
    final tamperedCipherText = Uint8List.fromList(original.payload.cipherText);
    tamperedCipherText[0] = tamperedCipherText[0] ^ 0x01;
    final tampered = EncryptedVaultDocument(
      version: original.version,
      kdf: original.kdf,
      wrappedDek: original.wrappedDek,
      payload: CipherPayload(
        nonce: original.payload.nonce,
        cipherText: tamperedCipherText,
        mac: original.payload.mac,
      ),
    );

    final destinationImportExport = _MemoryImportExportService()
      ..nextImportBytes = tampered.encode();
    final destination = VaultController(
      repository: _MemoryVaultRepository(),
      cryptoService: CryptoService(),
      importExportService: destinationImportExport,
      deviceKeyStore: _MemoryDeviceKeyStore(),
      passwordGeneratorService: PasswordGeneratorService(random: Random(6)),
      clipboardService: _MemoryClipboardService(),
    );
    await destination.bootstrap();

    final plan = await destination.previewImport('export-pass');
    expect(plan, isNull);
    expect(destination.message, contains('解锁失败'));
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

class _MemoryImportExportService extends ImportExportService {
  Uint8List? nextImportBytes;
  Uint8List? writtenBytes;

  @override
  Future<String?> pickExportPath() async => 'memory-export.pwv';

  @override
  Future<String?> pickImportPath() async =>
      nextImportBytes == null ? null : 'memory-import.pwv';

  @override
  Future<Uint8List> readFile(String path) async =>
      Uint8List.fromList(nextImportBytes!);

  @override
  Future<void> writeFile(String path, Uint8List bytes) async {
    writtenBytes = Uint8List.fromList(bytes);
  }
}

class _MemoryDeviceKeyStore implements DeviceKeyStore {
  @override
  Future<void> clear() async {}

  @override
  Future<bool> isSupported() async => false;

  @override
  Future<bool> hasWrappedDekCache() async => false;

  @override
  Future<Uint8List?> readWrappedDek() async => null;

  @override
  Future<void> storeWrappedDek(Uint8List wrappedDekBytes) async {}
}

class _MemoryClipboardService extends ClipboardService {
  @override
  Future<void> copyText(
    String text, {
    Duration clearAfter = const Duration(seconds: 30),
  }) async {}
}
