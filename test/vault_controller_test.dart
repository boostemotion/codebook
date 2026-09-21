import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/widgets.dart' show AppLifecycleState;
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

  test('ordinary vault saves do not refresh the quick-unlock cache', () async {
    final repository = _MemoryVaultRepository();
    final deviceKeyStore = _MemoryDeviceKeyStore();
    final controller = _controller(
      repository: repository,
      deviceKeyStore: deviceKeyStore,
    );
    await controller.bootstrap();
    await controller.createVault('master-pass');
    await controller.enableQuickUnlock();
    expect(deviceKeyStore.storeCalls, 1);

    final result = await controller.addOrUpdateItem(
      title: 'Mail',
      username: 'alice',
      password: 'secret',
      url: '',
      notes: '',
      tags: const [],
    );

    expect(result.succeeded, isTrue);
    expect(deviceKeyStore.storeCalls, 1);
    expect(repository.document, isNotNull);
    controller.dispose();
  });

  test(
      'reports quick unlock as unavailable when the native store is unsupported',
      () async {
    final controller = _controller(
      repository: _MemoryVaultRepository(),
      deviceKeyStore: _MemoryDeviceKeyStore(supported: false),
    );
    await controller.bootstrap();
    await controller.createVault('master-pass');

    final result = await controller.enableQuickUnlock();

    expect(result.succeeded, isFalse);
    expect(result.error, isA<StateError>());
    expect(controller.quickUnlockSupported, isFalse);
    expect(controller.quickUnlockEnabled, isFalse);
    expect(controller.message, contains('不支持快速解锁'));
    controller.dispose();
  });

  test('controlled Windows external UI ignores inactive but locks when hidden',
      () async {
    for (final terminalState in [
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
    ]) {
      final picker = _ControlledExportService();
      final controller = _controller(
        repository: _MemoryVaultRepository(),
        importExportService: picker,
      );
      await controller.bootstrap();
      await controller.createVault('master-pass');

      final exporting = controller.exportVault();
      await picker.exportPickerOpened;
      expect(controller.externalUiActive, isTrue);

      await controller.handleAppLifecycle(
        AppLifecycleState.inactive,
      );
      expect(controller.isUnlocked, isTrue);

      await controller.handleAppLifecycle(terminalState);
      expect(controller.isUnlocked, isFalse);

      picker.cancelExportPicker();
      expect((await exporting).succeeded, isFalse);
      expect(picker.writeCalls, 0);
      controller.dispose();
    }
  });

  test('controlled Android external UI ignores inactive but locks when hidden',
      () async {
    final picker = _ControlledExportService();
    final controller = _controller(
      repository: _MemoryVaultRepository(),
      importExportService: picker,
    );
    await controller.bootstrap();
    await controller.createVault('master-pass');

    final exporting = controller.exportVault();
    await picker.exportPickerOpened;

    await controller.handleAppLifecycle(
      AppLifecycleState.inactive,
    );
    expect(controller.isUnlocked, isTrue);

    await controller.handleAppLifecycle(AppLifecycleState.hidden);
    expect(controller.isUnlocked, isFalse);

    picker.cancelExportPicker();
    await exporting;
    controller.dispose();
  });

  test('export fails if the session locks while the picker is open', () async {
    final picker = _ControlledExportService();
    final controller = _controller(
      repository: _MemoryVaultRepository(),
      importExportService: picker,
    );
    await controller.bootstrap();
    await controller.createVault('master-pass');

    final exporting = controller.exportVault(exportPassword: 'export-pass');
    await picker.exportPickerOpened;
    await controller.lock();
    picker.completeExportPicker('export.pwv');

    final result = await exporting;

    expect(result.succeeded, isFalse);
    expect(result.error, isA<StateError>());
    expect(picker.writeCalls, 0);
    expect(picker.writtenBytes, isNull);
    expect(controller.isUnlocked, isFalse);
    controller.dispose();
  });

  test('export fails if the session locks during dedicated export crypto',
      () async {
    final crypto = _ControllableCryptoService();
    final picker = _ControlledExportService();
    final controller = _controller(
      repository: _MemoryVaultRepository(),
      cryptoService: crypto,
      importExportService: picker,
    );
    await controller.bootstrap();
    await controller.createVault('master-pass');
    crypto.blockNextPasswordProtectedExport();

    final exporting = controller.exportVault(exportPassword: 'export-pass');
    await picker.exportPickerOpened;
    picker.completeExportPicker('export.pwv');
    await crypto.passwordProtectedExportStarted;
    await controller.lock();
    crypto.completeBlockedPasswordProtectedExport();

    final result = await exporting;

    expect(result.succeeded, isFalse);
    expect(result.error, isA<StateError>());
    expect(picker.writeCalls, 0);
    expect(picker.writtenBytes, isNull);
    expect(controller.isUnlocked, isFalse);
    controller.dispose();
  });

  test('export fails if the session locks during raw export loading', () async {
    final repository = _MemoryVaultRepository();
    final picker = _ControlledExportService();
    final controller = _controller(
      repository: repository,
      importExportService: picker,
    );
    await controller.bootstrap();
    await controller.createVault('master-pass');
    repository.blockNextLoadRaw();

    final exporting = controller.exportVault();
    await picker.exportPickerOpened;
    picker.completeExportPicker('export.pwv');
    await repository.loadRawStarted;
    await controller.lock();
    repository.completeBlockedLoadRaw();

    final result = await exporting;

    expect(result.succeeded, isFalse);
    expect(result.error, isA<StateError>());
    expect(picker.writeCalls, 0);
    expect(picker.writtenBytes, isNull);
    expect(controller.isUnlocked, isFalse);
    controller.dispose();
  });

  test('import preview is canceled if the session locks while reading',
      () async {
    final crypto = CryptoService();
    final importedDocument = await crypto.createVault(password: 'import-pass');
    final importService = _ControlledImportService(importedDocument.encode());
    final controller = _controller(
      repository: _MemoryVaultRepository(),
      importExportService: importService,
    );
    await controller.bootstrap();

    final previewing = controller.previewImport('import-pass');
    await importService.importPickerOpened;
    importService.completeImportPicker('import.pwv');
    await importService.readStarted;
    await controller.lock();
    importService.completeRead();

    final plan = await previewing;

    expect(plan, isNull);
    expect(controller.message, contains('会话'));
    controller.dispose();
  });

  test('import preview is canceled if the session locks during decryption',
      () async {
    final importCrypto = CryptoService();
    final importedDocument =
        await importCrypto.createVault(password: 'import-pass');
    final crypto = _ControllableCryptoService();
    final importService = _ControlledImportService(importedDocument.encode());
    final controller = _controller(
      repository: _MemoryVaultRepository(),
      cryptoService: crypto,
      importExportService: importService,
    );
    await controller.bootstrap();
    crypto.blockNextOpen();

    final previewing = controller.previewImport('import-pass');
    await importService.importPickerOpened;
    importService.completeImportPicker('import.pwv');
    await importService.readStarted;
    importService.completeRead();
    await crypto.openStarted;
    await controller.lock();
    crypto.completeBlockedOpen();

    final plan = await previewing;

    expect(plan, isNull);
    expect(controller.message, contains('会话'));
    controller.dispose();
  });

  test('locked session rejects a previously previewed import plan', () async {
    final crypto = CryptoService();
    final importedDocument = await crypto.createVault(password: 'import-pass');
    final importService = _ControlledImportService(importedDocument.encode());
    final controller = _controller(
      repository: _MemoryVaultRepository(),
      importExportService: importService,
    );
    await controller.bootstrap();

    final previewing = controller.previewImport('import-pass');
    await importService.importPickerOpened;
    importService.completeImportPicker('import.pwv');
    await importService.readStarted;
    importService.completeRead();
    final plan = await previewing;
    expect(plan, isNotNull);

    await controller.lock();
    final result = await controller.applyImportPlan(plan!);

    expect(result.succeeded, isFalse);
    expect(controller.isUnlocked, isFalse);
    expect(controller.hasVault, isFalse);
    controller.dispose();
  });

  test('previewed import plan rejects a vault created afterward', () async {
    final crypto = CryptoService();
    final importedDocument = await crypto.createVault(password: 'import-pass');
    final importService = _ControlledImportService(importedDocument.encode());
    final controller = _controller(
      repository: _MemoryVaultRepository(),
      importExportService: importService,
    );
    await controller.bootstrap();

    final previewing = controller.previewImport('import-pass');
    await importService.importPickerOpened;
    importService.completeImportPicker('import.pwv');
    await importService.readStarted;
    importService.completeRead();
    final plan = await previewing;
    expect(plan, isNotNull);

    await controller.createVault('master-pass');
    final result = await controller.applyImportPlan(plan!);

    expect(result.succeeded, isFalse);
    expect(controller.hasVault, isTrue);
    expect(controller.vaultData.activeItems, isEmpty);
    controller.dispose();
  });

  test('explicit lock clears the unlocked session and clipboard owner',
      () async {
    final clipboard = _MemoryClipboardService();
    final controller = _controller(
      repository: _MemoryVaultRepository(),
      clipboardService: clipboard,
    );
    await controller.bootstrap();
    await controller.createVault('master-pass');
    await controller.copySecret('sensitive text');

    await controller.lock();

    expect(controller.isUnlocked, isFalse);
    expect(controller.vaultData.activeItems, isEmpty);
    expect(clipboard.lastCopiedText, isNull);
    expect(clipboard.clearCalls, 1);
    controller.dispose();
  });

  test('copying a secret after locking is rejected', () async {
    final clipboard = _MemoryClipboardService();
    final controller = _controller(
      repository: _MemoryVaultRepository(),
      clipboardService: clipboard,
    );
    await controller.bootstrap();
    await controller.createVault('master-pass');
    await controller.lock();

    final result = await controller.copySecret('sensitive text');

    expect(result.succeeded, isFalse);
    expect(result.error, isA<StateError>());
    expect(clipboard.lastCopiedText, isNull);
    controller.dispose();
  });

  test('importing into an empty vault makes it unlockable after locking',
      () async {
    final repository = _MemoryVaultRepository();
    final crypto = CryptoService();
    final controller = VaultController(
      repository: repository,
      cryptoService: crypto,
      importExportService: _NoopImportExportService(),
      deviceKeyStore: _MemoryDeviceKeyStore(),
      passwordGeneratorService: PasswordGeneratorService(random: Random(2)),
      clipboardService: _MemoryClipboardService(),
    );
    final document = await crypto.createVault(password: 'import-pass');
    final session = await crypto.openVault(
      document: document,
      password: 'import-pass',
    );

    await controller.bootstrap();
    await controller.applyImportPlan(
      ImportPlan(
        sessionGeneration: 0,
        hadVaultAtPreview: false,
        rawBytes: document.encode(),
        importedDocument: document,
        importedSession: session,
        summary: const ImportMergeSummary(
          incomingItems: 0,
          newItems: 0,
          updatedItems: 0,
          deletedItems: 0,
          unchangedItems: 0,
          replacesLocalVault: true,
          details: [],
        ),
      ),
    );
    await controller.lock();
    await controller.unlock('import-pass');

    expect(controller.storageState, VaultStorageState.available);
    expect(controller.isUnlocked, isTrue);
  });

  test('serializes concurrent item mutations without losing either item',
      () async {
    final repository = _MemoryVaultRepository();
    final controller = VaultController(
      repository: repository,
      cryptoService: CryptoService(),
      importExportService: _NoopImportExportService(),
      deviceKeyStore: _MemoryDeviceKeyStore(),
      passwordGeneratorService: PasswordGeneratorService(random: Random(3)),
      clipboardService: _MemoryClipboardService(),
    );

    await controller.bootstrap();
    await controller.createVault('master-pass');
    await Future.wait([
      controller.addOrUpdateItem(
        title: 'First',
        username: '',
        password: 'one',
        url: '',
        notes: '',
        tags: const [],
      ),
      controller.addOrUpdateItem(
        title: 'Second',
        username: '',
        password: 'two',
        url: '',
        notes: '',
        tags: const [],
      ),
    ]);

    expect(
      controller.vaultData.activeItems.map((item) => item.title).toSet(),
      {'First', 'Second'},
    );
  });

  test('reports a failed item save without changing the displayed item state',
      () async {
    final repository = _MemoryVaultRepository();
    final controller = _controller(repository: repository);
    await controller.bootstrap();
    await controller.createVault('master-pass');
    await controller.addOrUpdateItem(
      title: 'Original',
      username: 'alice',
      password: 'one',
      url: '',
      notes: '',
      tags: const [],
    );
    final original = controller.vaultData.activeItems.single;
    repository.failNextSave = true;

    final result = await controller.addOrUpdateItem(
      id: original.id,
      title: 'Edited',
      username: 'alice',
      password: 'two',
      url: '',
      notes: '',
      tags: const [],
    );

    expect(result.succeeded, isFalse);
    expect(result.error, isA<FileSystemException>());
    expect(controller.vaultData.activeItems.single.title, 'Original');
    expect(controller.message, isNotNull);
  });

  test('locking while a save is in flight cannot restore an unlocked session',
      () async {
    final repository = _MemoryVaultRepository();
    final controller = _controller(repository: repository);
    await controller.bootstrap();
    await controller.createVault('master-pass');
    repository.blockNextSave();

    final saving = controller.addOrUpdateItem(
      title: 'Deferred',
      username: '',
      password: 'secret',
      url: '',
      notes: '',
      tags: const [],
    );
    await repository.saveStarted;
    await controller.lock();
    repository.completeBlockedSave();

    final result = await saving;

    expect(result.succeeded, isFalse);
    expect(controller.isUnlocked, isFalse);
    expect(controller.vaultData.activeItems, isEmpty);
  });

  test('locking while unlock is in flight cannot restore plaintext', () async {
    final crypto = _ControllableCryptoService();
    final controller = _controller(
      repository: _MemoryVaultRepository(),
      cryptoService: crypto,
    );
    await controller.bootstrap();
    await controller.createVault('master-pass');
    await controller.lock();
    crypto.blockNextOpen();

    final unlocking = controller.unlock('master-pass');
    await crypto.openStarted;
    await controller.lock();
    crypto.completeBlockedOpen();

    final result = await unlocking;

    expect(result.succeeded, isFalse);
    expect(controller.isUnlocked, isFalse);
    expect(controller.vaultData.activeItems, isEmpty);
  });

  test('a queued import cannot start after a lock invalidates its session',
      () async {
    final crypto = _ControllableCryptoService();
    final repository = _MemoryVaultRepository();
    final controller =
        _controller(repository: repository, cryptoService: crypto);
    final importCrypto = CryptoService();
    final importDocument =
        await importCrypto.createVault(password: 'import-pass');
    final importSession = await importCrypto.openVault(
      document: importDocument,
      password: 'import-pass',
    );
    await controller.bootstrap();
    crypto.blockNextCreate();

    final creating = controller.createVault('master-pass');
    await crypto.createStarted;
    final importing = controller.applyImportPlan(
      ImportPlan(
        sessionGeneration: 0,
        hadVaultAtPreview: false,
        rawBytes: importDocument.encode(),
        importedDocument: importDocument,
        importedSession: importSession,
        summary: const ImportMergeSummary(
          incomingItems: 0,
          newItems: 0,
          updatedItems: 0,
          deletedItems: 0,
          unchangedItems: 0,
          replacesLocalVault: true,
          details: [],
        ),
      ),
    );
    await controller.lock();
    crypto.completeBlockedCreate();

    expect((await creating).succeeded, isFalse);
    expect((await importing).succeeded, isFalse);
    expect(controller.isUnlocked, isFalse);
    expect(controller.hasVault, isFalse);
  });

  test('validates TOTP before saving and preserves the previous entry',
      () async {
    final controller = _controller(repository: _MemoryVaultRepository());
    await controller.bootstrap();
    await controller.createVault('master-pass');
    await controller.addOrUpdateItem(
      title: 'Authenticator',
      username: 'alice',
      password: 'secret',
      url: '',
      notes: '',
      tags: const [],
      totpSecret: 'JBSWY3DPEHPK3PXP',
    );
    final existing = controller.vaultData.activeItems.single;

    final result = await controller.addOrUpdateItem(
      id: existing.id,
      title: 'Changed title',
      username: 'alice',
      password: 'new-secret',
      url: '',
      notes: '',
      tags: const [],
      totpSecret: 'not a valid TOTP secret',
    );

    expect(result.succeeded, isFalse);
    expect(controller.vaultData.activeItems.single.title, 'Authenticator');
    expect(controller.vaultData.activeItems.single.password, 'secret');
  });

  test('editing a deleted item does not restore it', () async {
    final controller = _controller(repository: _MemoryVaultRepository());
    await controller.bootstrap();
    await controller.createVault('master-pass');
    await controller.addOrUpdateItem(
      title: 'Deleted',
      username: '',
      password: 'secret',
      url: '',
      notes: '',
      tags: const [],
    );
    final item = controller.vaultData.activeItems.single;
    await controller.deleteItem(item.id);

    final result = await controller.addOrUpdateItem(
      id: item.id,
      title: 'Unexpected restore',
      username: '',
      password: 'changed',
      url: '',
      notes: '',
      tags: const [],
    );

    expect(result.succeeded, isFalse);
    expect(controller.vaultData.activeItems, isEmpty);
    expect(controller.vaultData.deletedItems.single.title, 'Deleted');
    controller.dispose();
  });

  test('restores and permanently removes items from the recycle bin', () async {
    final controller = _controller(repository: _MemoryVaultRepository());
    await controller.bootstrap();
    await controller.createVault('master-pass');
    await controller.addOrUpdateItem(
      title: 'Disposable',
      username: '',
      password: '',
      url: '',
      notes: '',
      tags: const [],
    );
    final item = controller.vaultData.activeItems.single;

    expect((await controller.deleteItem(item.id)).succeeded, isTrue);
    expect(controller.vaultData.activeItems, isEmpty);
    expect(controller.vaultData.deletedItems.single.id, item.id);

    expect((await controller.restoreItem(item.id)).succeeded, isTrue);
    expect(controller.vaultData.activeItems.single.id, item.id);

    await controller.deleteItem(item.id);
    expect((await controller.deleteItemPermanently(item.id)).succeeded, isTrue);
    expect(controller.vaultData.items, isEmpty);
  });

  test('changes the session-only auto-lock duration using conservative presets',
      () async {
    final controller = _controller(repository: _MemoryVaultRepository());

    expect(controller.autoLockPreset, AutoLockPreset.twoMinutes);
    controller.setAutoLockPreset(AutoLockPreset.fiveMinutes);

    expect(controller.autoLockPreset, AutoLockPreset.fiveMinutes);
    expect(controller.autoLockDuration, const Duration(minutes: 5));
  });

  test('custom auto-lock duration has no selected preset', () {
    final controller = VaultController(
      repository: _MemoryVaultRepository(),
      cryptoService: CryptoService(),
      importExportService: _NoopImportExportService(),
      deviceKeyStore: _MemoryDeviceKeyStore(),
      passwordGeneratorService: PasswordGeneratorService(random: Random(9)),
      clipboardService: _MemoryClipboardService(),
      autoLockDuration: const Duration(minutes: 7),
    );

    expect(controller.autoLockDuration, const Duration(minutes: 7));
    expect(controller.autoLockPreset, isNull);
    controller.setAutoLockPreset(AutoLockPreset.twoMinutes);
    expect(controller.autoLockDuration, const Duration(minutes: 2));
  });
}

VaultController _controller({
  required _MemoryVaultRepository repository,
  CryptoService? cryptoService,
  ImportExportService? importExportService,
  DeviceKeyStore? deviceKeyStore,
  ClipboardService? clipboardService,
}) =>
    VaultController(
      repository: repository,
      cryptoService: cryptoService ?? CryptoService(),
      importExportService: importExportService ?? _NoopImportExportService(),
      deviceKeyStore: deviceKeyStore ?? _MemoryDeviceKeyStore(),
      passwordGeneratorService: PasswordGeneratorService(random: Random(4)),
      clipboardService: clipboardService ?? _MemoryClipboardService(),
    );

class _ControllableCryptoService extends CryptoService {
  Completer<void>? _createGate;
  Completer<void>? _openGate;
  Completer<void>? _passwordProtectedExportGate;
  Completer<void>? _createStarted;
  Completer<void>? _openStarted;
  Completer<void>? _passwordProtectedExportStarted;

  Future<void> get createStarted => _createStarted!.future;
  Future<void> get openStarted => _openStarted!.future;
  Future<void> get passwordProtectedExportStarted =>
      _passwordProtectedExportStarted!.future;

  void blockNextCreate() {
    _createGate = Completer<void>();
    _createStarted = Completer<void>();
  }

  void completeBlockedCreate() => _createGate?.complete();

  void blockNextOpen() {
    _openGate = Completer<void>();
    _openStarted = Completer<void>();
  }

  void completeBlockedOpen() => _openGate?.complete();

  void blockNextPasswordProtectedExport() {
    _passwordProtectedExportGate = Completer<void>();
    _passwordProtectedExportStarted = Completer<void>();
  }

  void completeBlockedPasswordProtectedExport() =>
      _passwordProtectedExportGate?.complete();

  @override
  Future<EncryptedVaultDocument> createVault({
    required String password,
    VaultData? vaultData,
  }) async {
    final gate = _createGate;
    if (gate != null) {
      _createStarted!.complete();
      await gate.future;
      _createGate = null;
      _createStarted = null;
    }
    return super.createVault(password: password, vaultData: vaultData);
  }

  @override
  Future<EncryptedVaultDocument> createPasswordProtectedExport({
    required VaultData vaultData,
    required String password,
  }) async {
    final gate = _passwordProtectedExportGate;
    if (gate != null) {
      _passwordProtectedExportStarted!.complete();
      await gate.future;
      _passwordProtectedExportGate = null;
      _passwordProtectedExportStarted = null;
    }
    return super.createPasswordProtectedExport(
      vaultData: vaultData,
      password: password,
    );
  }

  @override
  Future<VaultSession> openVault({
    required EncryptedVaultDocument document,
    required String password,
  }) async {
    final gate = _openGate;
    if (gate != null) {
      _openStarted!.complete();
      await gate.future;
      _openGate = null;
      _openStarted = null;
    }
    return super.openVault(document: document, password: password);
  }
}

class _MemoryVaultRepository extends VaultRepository {
  EncryptedVaultDocument? document;
  bool failNextSave = false;
  Completer<void>? _saveGate;
  Completer<void>? _saveStarted;
  Completer<void>? _loadRawGate;
  Completer<void>? _loadRawStarted;

  Future<void> get saveStarted => _saveStarted!.future;
  Future<void> get loadRawStarted => _loadRawStarted!.future;

  void blockNextSave() {
    _saveGate = Completer<void>();
    _saveStarted = Completer<void>();
  }

  void completeBlockedSave() => _saveGate?.complete();

  void blockNextLoadRaw() {
    _loadRawGate = Completer<void>();
    _loadRawStarted = Completer<void>();
  }

  void completeBlockedLoadRaw() => _loadRawGate?.complete();

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
  Future<Uint8List?> loadRaw() async {
    final gate = _loadRawGate;
    if (gate != null) {
      _loadRawStarted!.complete();
      await gate.future;
      _loadRawGate = null;
      _loadRawStarted = null;
    }
    return document?.encode();
  }

  @override
  Future<void> save(EncryptedVaultDocument next) async {
    if (failNextSave) {
      failNextSave = false;
      throw FileSystemException('Synthetic save failure');
    }
    final gate = _saveGate;
    if (gate != null) {
      _saveStarted!.complete();
      await gate.future;
      _saveGate = null;
      _saveStarted = null;
    }
    document = next;
  }

  @override
  Future<void> importRaw(Uint8List bytes) async {
    document = EncryptedVaultDocument.decode(bytes);
  }
}

class _MemoryDeviceKeyStore implements DeviceKeyStore {
  _MemoryDeviceKeyStore({this.supported = true});

  final bool supported;
  Uint8List? storedBytes;
  int storeCalls = 0;

  @override
  Future<void> clear() async {
    storedBytes = null;
  }

  @override
  Future<bool> isSupported() async => supported;

  @override
  Future<bool> hasWrappedDekCache() async => storedBytes != null;

  @override
  Future<Uint8List?> readWrappedDek() async => storedBytes;

  @override
  Future<void> storeWrappedDek(Uint8List wrappedDekBytes) async {
    storeCalls++;
    storedBytes = Uint8List.fromList(wrappedDekBytes);
  }
}

class _NoopImportExportService extends ImportExportService {
  @override
  Future<String?> pickExportPath() async => null;

  @override
  Future<String?> pickImportPath() async => null;
}

class _ControlledExportService extends ImportExportService {
  final Completer<void> _exportPickerOpened = Completer<void>();
  final Completer<String?> _exportPickerResult = Completer<String?>();
  int writeCalls = 0;
  Uint8List? writtenBytes;

  Future<void> get exportPickerOpened => _exportPickerOpened.future;

  void cancelExportPicker() => _exportPickerResult.complete(null);

  void completeExportPicker(String path) => _exportPickerResult.complete(path);

  @override
  Future<String?> pickExportPath() {
    _exportPickerOpened.complete();
    return _exportPickerResult.future;
  }

  @override
  Future<void> writeFile(String path, Uint8List bytes) async {
    writeCalls++;
    writtenBytes = Uint8List.fromList(bytes);
  }
}

class _ControlledImportService extends ImportExportService {
  _ControlledImportService(this._bytes);

  final Uint8List _bytes;
  final Completer<void> _importPickerOpened = Completer<void>();
  final Completer<String?> _importPickerResult = Completer<String?>();
  final Completer<void> _readStarted = Completer<void>();
  final Completer<void> _readGate = Completer<void>();

  Future<void> get importPickerOpened => _importPickerOpened.future;
  Future<void> get readStarted => _readStarted.future;

  void completeImportPicker(String path) => _importPickerResult.complete(path);

  void completeRead() => _readGate.complete();

  @override
  Future<String?> pickImportPath() {
    _importPickerOpened.complete();
    return _importPickerResult.future;
  }

  @override
  Future<Uint8List> readFile(String path) async {
    _readStarted.complete();
    await _readGate.future;
    return Uint8List.fromList(_bytes);
  }
}

class _MemoryClipboardService extends ClipboardService {
  String? lastCopiedText;
  int clearCalls = 0;

  @override
  Future<void> clearIfOwned() async {
    clearCalls++;
    lastCopiedText = null;
  }

  @override
  Future<void> copyText(
    String text, {
    Duration clearAfter = const Duration(seconds: 30),
  }) async {
    lastCopiedText = text;
  }
}
