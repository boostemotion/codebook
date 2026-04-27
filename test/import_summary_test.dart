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
  test('preview import summarizes new, updated, and deleted items', () async {
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

    await controller.bootstrap();
    await controller.createVault('local-pass');
    await controller.addOrUpdateItem(
      title: 'Mail',
      username: 'old-user',
      password: 'old-pass',
      url: '',
      notes: '',
      tags: const [],
    );
    final localItem = controller.vaultData.activeItems.single;

    final incomingVault = VaultData(
      items: [
        localItem.copyWith(
          username: 'new-user',
          password: 'new-pass',
          updatedAt: localItem.updatedAt.add(const Duration(minutes: 2)),
        ),
        VaultItem(
          id: 'brand-new',
          title: 'Bank',
          username: 'cashier',
          password: 'bank-pass',
          url: '',
          notes: '',
          tags: const [],
          createdAt: DateTime(2026, 1, 1),
          updatedAt: DateTime(2026, 1, 1, 12),
        ),
        VaultItem(
          id: 'deleted-item',
          title: 'Legacy',
          username: 'legacy',
          password: 'legacy-pass',
          url: '',
          notes: '',
          tags: const [],
          createdAt: DateTime(2026, 1, 1),
          updatedAt: DateTime(2026, 1, 1, 11),
          deletedAt: DateTime(2026, 1, 1, 11),
        ),
      ],
      updatedAt: DateTime(2026, 1, 1, 12),
    );
    final encryptedIncoming = await CryptoService().createVault(
      password: 'import-pass',
      vaultData: incomingVault,
    );
    importExport.nextImportBytes = encryptedIncoming.encode();

    final plan = await controller.previewImport('import-pass');

    expect(plan, isNotNull);
    expect(plan!.summary.newItems, 1);
    expect(plan.summary.updatedItems, 1);
    expect(plan.summary.deletedItems, 1);
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

  @override
  Future<String?> pickImportPath() async => 'memory-import.pwv';

  @override
  Future<Uint8List> readFile(String path) async => nextImportBytes!;
}

class _MemoryDeviceKeyStore implements DeviceKeyStore {
  Uint8List? storedBytes;

  @override
  Future<void> clear() async {
    storedBytes = null;
  }

  @override
  Future<bool> isSupported() async => false;

  @override
  Future<Uint8List?> readWrappedDek() async => storedBytes;

  @override
  Future<void> storeWrappedDek(Uint8List wrappedDekBytes) async {
    storedBytes = Uint8List.fromList(wrappedDekBytes);
  }
}

class _MemoryClipboardService extends ClipboardService {
  @override
  Future<void> copyText(
    String text, {
    Duration clearAfter = const Duration(seconds: 30),
  }) async {}
}
