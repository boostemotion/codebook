import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/vault_models.dart';
import '../services/clipboard_service.dart';
import '../services/crypto_service.dart';
import '../services/device_key_store.dart';
import '../services/import_export_service.dart';
import '../services/password_generator_service.dart';
import '../services/vault_repository.dart';

class VaultController extends ChangeNotifier {
  VaultController({
    required VaultRepository repository,
    required CryptoService cryptoService,
    required ImportExportService importExportService,
    required DeviceKeyStore deviceKeyStore,
    required PasswordGeneratorService passwordGeneratorService,
    required ClipboardService clipboardService,
    Duration autoLockDuration = const Duration(minutes: 2),
  })  : _repository = repository,
        _cryptoService = cryptoService,
        _importExportService = importExportService,
        _deviceKeyStore = deviceKeyStore,
        _passwordGeneratorService = passwordGeneratorService,
        _clipboardService = clipboardService,
        _autoLockDuration = autoLockDuration;

  final VaultRepository _repository;
  final CryptoService _cryptoService;
  final ImportExportService _importExportService;
  final DeviceKeyStore _deviceKeyStore;
  final PasswordGeneratorService _passwordGeneratorService;
  final ClipboardService _clipboardService;
  final Duration _autoLockDuration;
  final Uuid _uuid = const Uuid();

  bool _busy = false;
  bool _hasVault = false;
  bool _isUnlocked = false;
  bool _quickUnlockSupported = false;
  bool _quickUnlockEnabled = false;
  String? _message;
  VaultData _vaultData = VaultData.empty();
  EncryptedVaultDocument? _document;
  Uint8List? _dataEncryptionKey;
  Uint8List? _sessionKek;
  Timer? _autoLockTimer;

  bool get busy => _busy;
  bool get hasVault => _hasVault;
  bool get isUnlocked => _isUnlocked;
  bool get quickUnlockSupported => _quickUnlockSupported;
  bool get quickUnlockEnabled => _quickUnlockEnabled;
  String? get message => _message;
  VaultData get vaultData => _vaultData;

  Future<void> bootstrap() async {
    await _run(() async {
      _document = await _repository.load();
      _hasVault = _document != null;
      _quickUnlockSupported = await _deviceKeyStore.isSupported();
      _quickUnlockEnabled = _quickUnlockSupported &&
          (await _deviceKeyStore.readWrappedDek()) != null;
    });
  }

  Future<void> createVault(String password) async {
    await _run(() async {
      _requirePassword(password, fieldName: 'Master password');
      final document = await _cryptoService.createVault(password: password);
      await _repository.save(document);
      _document = document;
      _hasVault = true;
      await _unlockDocument(document, password);
      await _syncQuickUnlockCache();
      _message = 'Created a new encrypted vault.';
    });
  }

  Future<void> unlock(String password) async {
    await _run(() async {
      _requirePassword(password, fieldName: 'Master password');
      final document = _document ?? await _repository.load();
      if (document == null) {
        throw const VaultUnlockException('No local vault was found.');
      }
      await _unlockDocument(document, password);
      _message = 'Vault unlocked.';
    });
  }

  Future<void> unlockWithQuickUnlock() async {
    await _run(() async {
      if (!_quickUnlockSupported || !_quickUnlockEnabled) {
        throw StateError('Quick unlock is not enabled on this device.');
      }
      final document = _document ?? await _repository.load();
      if (document == null) {
        throw const VaultUnlockException('No local vault was found.');
      }
      final protectedKek = await _deviceKeyStore.readWrappedDek();
      if (protectedKek == null) {
        throw StateError('Quick unlock key is unavailable.');
      }
      final session = await _cryptoService.openVaultWithKek(
        document: document,
        keyEncryptionKey: protectedKek,
      );
      _document = document;
      _vaultData = session.vaultData;
      _dataEncryptionKey = session.dataEncryptionKey;
      _sessionKek = session.keyEncryptionKey;
      _isUnlocked = true;
      _restartAutoLockTimer();
      _message = 'Vault unlocked with quick unlock.';
    });
  }

  Future<ImportPlan?> previewImport(String importPassword) {
    return _runWithResult(() async {
      _requirePassword(importPassword, fieldName: 'Import file password');
      final importPath = await _importExportService.pickImportPath();
      if (importPath == null) {
        _message = 'Import cancelled.';
        return null;
      }
      final importBytes = await _importExportService.readFile(importPath);
      final importedDocument = EncryptedVaultDocument.decode(importBytes);
      final importedSession = await _cryptoService.openVault(
        document: importedDocument,
        password: importPassword,
      );
      return ImportPlan(
        rawBytes: importBytes,
        importedDocument: importedDocument,
        importedSession: importedSession,
        summary: _buildImportSummary(importedSession.vaultData),
      );
    });
  }

  Future<void> applyImportPlan(ImportPlan plan) async {
    await _run(() async {
      if (!_hasVault) {
        await _repository.importRaw(plan.rawBytes);
        _document = plan.importedDocument;
        _hasVault = true;
        _vaultData = plan.importedSession.vaultData;
        _dataEncryptionKey = plan.importedSession.dataEncryptionKey;
        _sessionKek = plan.importedSession.keyEncryptionKey;
        _isUnlocked = true;
        _restartAutoLockTimer();
        await _syncQuickUnlockCache();
        _message = 'Imported vault into local storage.';
        return;
      }

      _ensureUnlocked();
      final merged = _vaultData.merge(plan.importedSession.vaultData);
      await _saveState(
        vaultData: merged,
        keyEncryptionKey: _requireSessionKek(),
      );
      _message = 'Import completed and merged by updatedAt.';
    });
  }

  Future<void> importIntoCurrentVault(String importPassword) async {
    final plan = await previewImport(importPassword);
    if (plan == null) {
      return;
    }
    await applyImportPlan(plan);
  }

  Future<void> exportVault({String? exportPassword}) async {
    await _run(() async {
      _ensureUnlocked();
      final exportPath = await _importExportService.pickExportPath();
      if (exportPath == null) {
        _message = 'Export cancelled.';
        return;
      }

      Uint8List bytesToWrite;
      if (exportPassword != null && exportPassword.trim().isNotEmpty) {
        _requirePassword(exportPassword, fieldName: 'Export password');
        final exported = await _cryptoService.saveVault(
          vaultData: _vaultData,
          password: exportPassword,
          dataEncryptionKey: _dataEncryptionKey!,
        );
        bytesToWrite = exported.encode();
      } else {
        final raw = await _repository.loadRaw();
        if (raw == null) {
          throw StateError('Local vault does not exist.');
        }
        bytesToWrite = raw;
      }

      await _importExportService.writeFile(exportPath, bytesToWrite);
      _restartAutoLockTimer();
      _message = exportPassword == null || exportPassword.trim().isEmpty
          ? 'Exported encrypted snapshot.'
          : 'Exported encrypted snapshot with a dedicated export password.';
    });
  }

  Future<void> addOrUpdateItem({
    String? id,
    required String title,
    required String username,
    required String password,
    required String url,
    required String notes,
    required List<String> tags,
    String? totpSecret,
  }) async {
    await _run(() async {
      _ensureUnlocked();
      if (title.trim().isEmpty) {
        throw ArgumentError('Title cannot be empty.');
      }
      final now = DateTime.now();
      final existing = id == null
          ? null
          : _vaultData.items.where((item) => item.id == id).firstOrNull;
      final item = VaultItem(
        id: existing?.id ?? _uuid.v4(),
        title: title.trim(),
        username: username.trim(),
        password: password,
        url: url.trim(),
        notes: notes.trim(),
        tags: tags,
        totpSecret: (totpSecret?.trim().isEmpty ?? true) ? null : totpSecret,
        createdAt: existing?.createdAt ?? now,
        updatedAt: now,
        deletedAt: null,
      );
      await _saveState(
        vaultData: _vaultData.upsert(item),
        keyEncryptionKey: _requireSessionKek(),
      );
      _message = existing == null ? 'Entry added.' : 'Entry updated.';
    });
  }

  Future<void> deleteItem(String id) async {
    await _run(() async {
      _ensureUnlocked();
      final now = DateTime.now();
      await _saveState(
        vaultData: _vaultData.markDeleted(id, now),
        keyEncryptionKey: _requireSessionKek(),
      );
      _message = 'Entry deleted.';
    });
  }

  Future<void> changeMasterPassword({
    required String oldPassword,
    required String newPassword,
  }) async {
    await _run(() async {
      _requirePassword(oldPassword, fieldName: 'Current master password');
      _requirePassword(newPassword, fieldName: 'New master password');
      final document = _document;
      if (document == null) {
        throw StateError('Local vault does not exist.');
      }
      final rewrapped = await _cryptoService.rewrapMasterPassword(
        document: document,
        oldPassword: oldPassword,
        newPassword: newPassword,
      );
      await _repository.save(rewrapped);
      _document = rewrapped;
      final session = await _cryptoService.openVault(
        document: rewrapped,
        password: newPassword,
      );
      _dataEncryptionKey = session.dataEncryptionKey;
      _sessionKek = session.keyEncryptionKey;
      _vaultData = session.vaultData;
      _isUnlocked = true;
      await _syncQuickUnlockCache();
      _restartAutoLockTimer();
      _message = 'Master password updated.';
    });
  }

  Future<void> enableQuickUnlock() async {
    await _run(() async {
      _ensureUnlocked();
      if (!_quickUnlockSupported) {
        throw StateError('Quick unlock is not supported on this device.');
      }
      await _syncQuickUnlockCache(forceEnable: true);
      _message = 'Quick unlock enabled for this device.';
    });
  }

  Future<void> disableQuickUnlock() async {
    await _run(() async {
      await _deviceKeyStore.clear();
      _quickUnlockEnabled = false;
      _message = 'Quick unlock disabled for this device.';
    });
  }

  String generatePassword({
    int length = 20,
    bool includeUppercase = true,
    bool includeDigits = true,
    bool includeSymbols = true,
  }) {
    return _passwordGeneratorService.generate(
      length: length,
      includeUppercase: includeUppercase,
      includeDigits: includeDigits,
      includeSymbols: includeSymbols,
    );
  }

  Future<void> copySecret(String text) async {
    await _run(() async {
      if (text.isEmpty) {
        throw ArgumentError('Nothing to copy.');
      }
      await _clipboardService.copyText(text);
      _restartAutoLockTimer();
      _message = 'Copied to clipboard. It will be cleared in 30 seconds.';
    });
  }

  void registerActivity() {
    if (_isUnlocked) {
      _restartAutoLockTimer();
    }
  }

  Future<void> handleAppPaused() async {
    if (_isUnlocked) {
      await lock();
    }
  }

  Future<void> lock() async {
    _autoLockTimer?.cancel();
    _isUnlocked = false;
    _vaultData = VaultData.empty();
    _dataEncryptionKey = null;
    _sessionKek = null;
    _message = 'Vault locked.';
    notifyListeners();
  }

  void clearMessage() {
    if (_message == null) {
      return;
    }
    _message = null;
    notifyListeners();
  }

  Future<void> _unlockDocument(
    EncryptedVaultDocument document,
    String password,
  ) async {
    final session = await _cryptoService.openVault(
      document: document,
      password: password,
    );
    _document = document;
    _vaultData = session.vaultData;
    _dataEncryptionKey = session.dataEncryptionKey;
    _sessionKek = session.keyEncryptionKey;
    _isUnlocked = true;
    _restartAutoLockTimer();
  }

  Future<void> _saveState({
    required VaultData vaultData,
    required Uint8List keyEncryptionKey,
  }) async {
    final updatedAt = DateTime.now();
    final document = await _cryptoService.saveVaultWithKek(
      vaultData: vaultData.copyWith(updatedAt: updatedAt),
      keyEncryptionKey: keyEncryptionKey,
      dataEncryptionKey: _dataEncryptionKey!,
      kdf: _document!.kdf,
    );
    await _repository.save(document);
    _document = document;
    _vaultData = vaultData.copyWith(updatedAt: updatedAt);
    _sessionKek = keyEncryptionKey;
    await _syncQuickUnlockCache();
    _restartAutoLockTimer();
  }

  void _ensureUnlocked() {
    if (!_isUnlocked || _dataEncryptionKey == null) {
      throw StateError('Vault is locked.');
    }
  }

  Uint8List _requireSessionKek() {
    if (_sessionKek == null) {
      throw StateError(
        'This action requires quick unlock or a password-authenticated session.',
      );
    }
    return _sessionKek!;
  }

  void _requirePassword(String value, {required String fieldName}) {
    if (value.trim().isEmpty) {
      throw ArgumentError('$fieldName cannot be empty.');
    }
  }

  Future<void> _syncQuickUnlockCache({bool forceEnable = false}) async {
    if (!_quickUnlockSupported || _sessionKek == null) {
      return;
    }
    if (_quickUnlockEnabled || forceEnable) {
      await _deviceKeyStore.storeWrappedDek(_sessionKek!);
      _quickUnlockEnabled = true;
    }
  }

  ImportMergeSummary _buildImportSummary(VaultData incoming) {
    if (!_hasVault) {
      return ImportMergeSummary(
        incomingItems: incoming.items.length,
        newItems: incoming.activeItems.length,
        updatedItems: 0,
        deletedItems: incoming.items.where((item) => item.isDeleted).length,
        unchangedItems: 0,
        replacesLocalVault: true,
      );
    }

    var newItems = 0;
    var updatedItems = 0;
    var deletedItems = 0;
    var unchangedItems = 0;
    final currentById = <String, VaultItem>{
      for (final item in _vaultData.items) item.id: item,
    };
    for (final incomingItem in incoming.items) {
      final current = currentById[incomingItem.id];
      if (current == null) {
        if (incomingItem.isDeleted) {
          deletedItems++;
        } else {
          newItems++;
        }
        continue;
      }
      if (incomingItem.updatedAt.isAfter(current.updatedAt)) {
        if (incomingItem.isDeleted && !current.isDeleted) {
          deletedItems++;
        } else {
          updatedItems++;
        }
      } else {
        unchangedItems++;
      }
    }

    return ImportMergeSummary(
      incomingItems: incoming.items.length,
      newItems: newItems,
      updatedItems: updatedItems,
      deletedItems: deletedItems,
      unchangedItems: unchangedItems,
      replacesLocalVault: false,
    );
  }

  void _restartAutoLockTimer() {
    _autoLockTimer?.cancel();
    _autoLockTimer = Timer(_autoLockDuration, () {
      if (_isUnlocked) {
        lock();
      }
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    _busy = true;
    _message = null;
    notifyListeners();
    try {
      await action();
    } catch (error) {
      _message = error.toString();
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<T?> _runWithResult<T>(Future<T?> Function() action) async {
    _busy = true;
    _message = null;
    notifyListeners();
    try {
      return await action();
    } catch (error) {
      _message = error.toString();
      return null;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _autoLockTimer?.cancel();
    _clipboardService.dispose();
    super.dispose();
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

class ImportPlan {
  const ImportPlan({
    required this.rawBytes,
    required this.importedDocument,
    required this.importedSession,
    required this.summary,
  });

  final Uint8List rawBytes;
  final EncryptedVaultDocument importedDocument;
  final VaultSession importedSession;
  final ImportMergeSummary summary;
}
