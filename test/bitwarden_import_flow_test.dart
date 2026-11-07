import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:cipherbook/models/bitwarden_bridge_models.dart';
import 'package:cipherbook/models/vault_models.dart';
import 'package:cipherbook/services/bitwarden_interchange_service.dart';
import 'package:cipherbook/services/clipboard_service.dart';
import 'package:cipherbook/services/crypto_service.dart';
import 'package:cipherbook/services/device_key_store.dart';
import 'package:cipherbook/services/import_export_service.dart';
import 'package:cipherbook/services/password_generator_service.dart';
import 'package:cipherbook/services/vault_repository.dart';
import 'package:cipherbook/state/vault_controller.dart';

void main() {
  const testEmail = 'flow.user' '@' 'example.test';

  test('Bitwarden import requires a decision and can keep both records',
      () async {
    final repository = _MemoryVaultRepository();
    final importExport = _MemoryImportExportService();
    final controller = VaultController(
      repository: repository,
      cryptoService: CryptoService(),
      importExportService: importExport,
      deviceKeyStore: _MemoryDeviceKeyStore(),
      passwordGeneratorService: PasswordGeneratorService(random: Random(1)),
      clipboardService: _MemoryClipboardService(),
    );
    addTearDown(controller.dispose);

    await controller.bootstrap();
    await controller.createVault('master-password');
    await controller.addOrUpdateItem(
      title: '示例站点',
      username: '15500001111 / $testEmail',
      password: 'same-password',
      url: 'https://example.com/login',
      notes: '',
      tags: const [],
    );

    final now = DateTime(2026, 1, 1);
    final importedItem = VaultItem(
      id: 'bitwarden-import',
      title: '示例站点',
      username: testEmail,
      password: 'same-password',
      url: 'https://example.com',
      notes: '从 Bitwarden 导入',
      tags: const [],
      createdAt: now,
      updatedAt: now,
    );
    final bytes = const BitwardenInterchangeService().encodeJson(
      <VaultItem>[importedItem],
    );

    final plan = await controller.previewBitwardenImportBytes(bytes);
    expect(plan, isNotNull);
    expect(plan!.reviews, hasLength(1));
    expect(
      plan.reviews.single.kind,
      BitwardenImportMatchKind.exactDuplicate,
    );

    final keepLocal = await controller.applyBitwardenImport(
      plan,
      decisions: <String, BitwardenImportAction>{
        importedItem.id: BitwardenImportAction.keepLocal,
      },
    );
    expect(keepLocal.succeeded, isTrue);
    expect(controller.vaultData.activeItems, hasLength(1));

    final secondPlan = await controller.previewBitwardenImportBytes(bytes);
    expect(secondPlan, isNotNull);
    final keepBoth = await controller.applyBitwardenImport(
      secondPlan!,
      decisions: <String, BitwardenImportAction>{
        importedItem.id: BitwardenImportAction.keepBoth,
      },
    );
    expect(keepBoth.succeeded, isTrue);
    expect(controller.vaultData.activeItems, hasLength(2));
  });

  test('Bitwarden JSON export writes a decodable plain exchange file',
      () async {
    final repository = _MemoryVaultRepository();
    final importExport = _MemoryImportExportService();
    final controller = VaultController(
      repository: repository,
      cryptoService: CryptoService(),
      importExportService: importExport,
      deviceKeyStore: _MemoryDeviceKeyStore(),
      passwordGeneratorService: PasswordGeneratorService(random: Random(2)),
      clipboardService: _MemoryClipboardService(),
    );
    addTearDown(controller.dispose);

    await controller.bootstrap();
    await controller.createVault('master-password');
    await controller.addOrUpdateItem(
      title: '导出示例',
      username: testEmail,
      password: 'export-password',
      url: 'https://example.com',
      notes: '',
      tags: const [],
    );

    final result = await controller.exportBitwarden(
      BitwardenExchangeFormat.json,
    );

    expect(result.succeeded, isTrue, reason: controller.message);
    expect(importExport.writtenBytes, isNotNull);
    final parsed =
        const BitwardenInterchangeService().decode(importExport.writtenBytes!);
    expect(parsed.items, hasLength(1));
    expect(parsed.items.single.username, testEmail);
    expect(parsed.items.single.password, 'export-password');
  });

  test('exports only Codebook entries missing from a Bitwarden baseline',
      () async {
    final repository = _MemoryVaultRepository();
    final importExport = _MemoryImportExportService();
    final controller = VaultController(
      repository: repository,
      cryptoService: CryptoService(),
      importExportService: importExport,
      deviceKeyStore: _MemoryDeviceKeyStore(),
      passwordGeneratorService: PasswordGeneratorService(random: Random(3)),
      clipboardService: _MemoryClipboardService(),
    );
    addTearDown(controller.dispose);

    await controller.bootstrap();
    await controller.createVault('master-password');
    await controller.addOrUpdateItem(
      title: 'Bitwarden 已有',
      username: testEmail,
      password: 'existing-password',
      url: 'https://existing.example.com',
      notes: '',
      tags: const [],
    );
    await controller.addOrUpdateItem(
      title: '仅 Codebook 有',
      username: 'missing@example.test',
      password: 'missing-password',
      url: 'https://missing.example.com',
      notes: '',
      tags: const [],
    );

    final existing = controller.vaultData.activeItems
        .firstWhere((item) => item.title == 'Bitwarden 已有');
    final baseline = const BitwardenInterchangeService().encodeJson(
      <VaultItem>[existing.copyWith(id: 'bitwarden-existing')],
    );

    final plan = await controller.previewBitwardenDeltaExportBytes(baseline);
    expect(plan, isNotNull);
    expect(plan!.matchedItemCount, 1);
    expect(plan.missingItemCount, 1);
    expect(plan.missingItems.single.title, '仅 Codebook 有');

    final result = await controller.exportBitwardenDelta(
      plan,
      BitwardenExchangeFormat.json,
    );
    expect(result.succeeded, isTrue, reason: controller.message);
    expect(importExport.writtenBytes, isNotNull);

    final exported =
        const BitwardenInterchangeService().decode(importExport.writtenBytes!);
    expect(exported.items, hasLength(1));
    expect(exported.items.single.title, '仅 Codebook 有');
    expect(controller.vaultData.activeItems, hasLength(2));
  });
}

class _MemoryVaultRepository extends VaultRepository {
  EncryptedVaultDocument? document;

  @override
  Future<bool> exists() async => document != null;

  @override
  Future<VaultLoadResult> inspect() async => document == null
      ? const VaultLoadResult(state: VaultStorageState.absent)
      : VaultLoadResult(
          state: VaultStorageState.available,
          document: document,
          rawBytes: document!.encode(),
        );

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
  Uint8List? writtenBytes;

  @override
  Future<String?> pickBitwardenExportPath({required bool csv}) async =>
      csv ? 'memory-export.csv' : 'memory-export.json';

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
