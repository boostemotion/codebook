import 'dart:async';

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
      _quickUnlockEnabled =
          _quickUnlockSupported && await _deviceKeyStore.hasWrappedDekCache();
    });
  }

  Future<void> prepareDebugSession({int seedCount = 10}) async {
    await _run(() async {
      if (await _repository.exists()) {
        throw StateError('Debug seed skipped: existing vault detected.');
      }
      await _deviceKeyStore.clear();
      _quickUnlockEnabled = false;
      _quickUnlockSupported = false;

      const debugPassword = 'debug-only-password';
      final document = await _cryptoService.createVault(password: debugPassword);
      await _repository.save(document);
      _document = document;
      _hasVault = true;
      await _unlockDocument(document, debugPassword);

      final now = DateTime.now();
      final seededItems = List.generate(seedCount, (index) {
        final offset = seedCount - index;
        final timestamp = now.subtract(Duration(minutes: offset));
        return VaultItem(
          id: _uuid.v4(),
          title: 'Test Account ${index + 1}',
          username: 'user${1000 + index}@example.com',
          password: _passwordGeneratorService.generate(
            length: 14 + (index % 5),
            includeUppercase: true,
            includeDigits: true,
            includeSymbols: true,
          ),
          url: 'https://example${(index % 3) + 1}.com',
          notes: 'Debug seed item ${index + 1}',
          tags: ['debug', 'sample${(index % 3) + 1}'],
          createdAt: timestamp,
          updatedAt: timestamp,
          deletedAt: null,
        );
      });

      await _saveState(
        vaultData: VaultData(
          items: seededItems,
          updatedAt: now,
        ),
        keyEncryptionKey: _requireSessionKek(),
      );
      _message = null;
    });
  }

  Future<void> createVault(String password) async {
    await _run(() async {
      _requirePassword(password, fieldName: '主密码');
      final document = await _cryptoService.createVault(password: password);
      await _repository.save(document);
      _document = document;
      _hasVault = true;
      await _unlockDocument(document, password);
      await _syncQuickUnlockCache();
      _message = '已创建新的加密密码库。';
    });
  }

  Future<void> unlock(String password) async {
    await _run(() async {
      _requirePassword(password, fieldName: '主密码');
      final document = _document ?? await _repository.load();
      if (document == null) {
        throw const VaultUnlockException('未找到本地密码库。');
      }
      await _unlockDocument(document, password);
      _message = '密码库已解锁。';
    });
  }

  Future<void> unlockWithQuickUnlock() async {
    await _run(() async {
      if (!_quickUnlockSupported || !_quickUnlockEnabled) {
        throw StateError('当前设备未开启快速解锁。');
      }
      final document = _document ?? await _repository.load();
      if (document == null) {
        throw const VaultUnlockException('未找到本地密码库。');
      }
      final protectedKek = await _deviceKeyStore.readWrappedDek();
      if (protectedKek == null) {
        throw StateError('快速解锁密钥不可用。');
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
      _message = '已通过快速解锁打开密码库。';
    });
  }

  Future<ImportPlan?> previewImport(String importPassword) {
    return _runWithResult(() async {
      _requirePassword(importPassword, fieldName: '导入文件密码');
      final importPath = await _importExportService.pickImportPath();
      if (importPath == null) {
        _message = '已取消导入。';
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
        _message = '已导入为本地密码库。';
        return;
      }

      _ensureUnlocked();
      final merged = _vaultData.merge(plan.importedSession.vaultData);
      await _saveState(
        vaultData: merged,
        keyEncryptionKey: _requireSessionKek(),
      );
      _message = '导入完成，已按更新时间合并。';
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
        _message = '已取消导出。';
        return;
      }

      Uint8List bytesToWrite;
      if (exportPassword != null && exportPassword.trim().isNotEmpty) {
        _requirePassword(exportPassword, fieldName: '导出密码');
        final exported = await _cryptoService.saveVault(
          vaultData: _vaultData,
          password: exportPassword,
          dataEncryptionKey: _dataEncryptionKey!,
        );
        bytesToWrite = exported.encode();
      } else {
        final raw = await _repository.loadRaw();
        if (raw == null) {
          throw StateError('本地密码库不存在。');
        }
        bytesToWrite = raw;
      }

      await _importExportService.writeFile(exportPath, bytesToWrite);
      _restartAutoLockTimer();
      _message = exportPassword == null || exportPassword.trim().isEmpty
          ? '已导出加密备份。'
          : '已使用独立导出密码导出加密备份。';
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
        throw ArgumentError('名称不能为空。');
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
      _message = existing == null ? '条目已新增。' : '条目已更新。';
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
      _message = '条目已删除。';
    });
  }

  Future<void> changeMasterPassword({
    required String oldPassword,
    required String newPassword,
  }) async {
    await _run(() async {
      _requirePassword(oldPassword, fieldName: '当前主密码');
      _requirePassword(newPassword, fieldName: '新主密码');
      final document = _document;
      if (document == null) {
        throw StateError('本地密码库不存在。');
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
      _message = '主密码已更新。';
    });
  }

  Future<void> enableQuickUnlock() async {
    await _run(() async {
      _ensureUnlocked();
      if (!_quickUnlockSupported) {
        throw StateError('当前设备不支持快速解锁。');
      }
      await _syncQuickUnlockCache(forceEnable: true);
      _message = '已在当前设备开启快速解锁。';
    });
  }

  Future<void> disableQuickUnlock() async {
    await _run(() async {
      await _deviceKeyStore.clear();
      _quickUnlockEnabled = false;
      _message = '已关闭当前设备的快速解锁。';
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
        throw ArgumentError('没有可复制的内容。');
      }
      await _clipboardService.copyText(text);
      _restartAutoLockTimer();
      _message = '已复制到剪贴板，30 秒后自动清空。';
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
    _message = '密码库已锁定。';
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
      throw StateError('密码库已锁定。');
    }
  }

  Uint8List _requireSessionKek() {
    if (_sessionKek == null) {
      throw StateError(
        '此操作需要快速解锁或已通过密码认证的会话。',
      );
    }
    return _sessionKek!;
  }

  void _requirePassword(String value, {required String fieldName}) {
    if (value.trim().isEmpty) {
      throw ArgumentError('$fieldName不能为空。');
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
        details: incoming.items
            .map(
              (item) => ImportChangeDetail(
                id: item.id,
                title: item.title,
                kind: item.isDeleted
                    ? ImportChangeKind.deletedItem
                    : ImportChangeKind.newItem,
                incomingUpdatedAt: item.updatedAt,
              ),
            )
            .toList(),
      );
    }

    var newItems = 0;
    var updatedItems = 0;
    var deletedItems = 0;
    var unchangedItems = 0;
    final details = <ImportChangeDetail>[];
    final currentById = <String, VaultItem>{
      for (final item in _vaultData.items) item.id: item,
    };
    for (final incomingItem in incoming.items) {
      final current = currentById[incomingItem.id];
      if (current == null) {
        if (incomingItem.isDeleted) {
          deletedItems++;
          details.add(
            ImportChangeDetail(
              id: incomingItem.id,
              title: incomingItem.title,
              kind: ImportChangeKind.deletedItem,
              incomingUpdatedAt: incomingItem.updatedAt,
            ),
          );
        } else {
          newItems++;
          details.add(
            ImportChangeDetail(
              id: incomingItem.id,
              title: incomingItem.title,
              kind: ImportChangeKind.newItem,
              incomingUpdatedAt: incomingItem.updatedAt,
            ),
          );
        }
        continue;
      }
      if (incomingItem.updatedAt.isAfter(current.updatedAt)) {
        if (incomingItem.isDeleted && !current.isDeleted) {
          deletedItems++;
          details.add(
            ImportChangeDetail(
              id: incomingItem.id,
              title: incomingItem.title,
              kind: ImportChangeKind.deletedItem,
              incomingUpdatedAt: incomingItem.updatedAt,
              localUpdatedAt: current.updatedAt,
            ),
          );
        } else {
          updatedItems++;
          details.add(
            ImportChangeDetail(
              id: incomingItem.id,
              title: incomingItem.title,
              kind: ImportChangeKind.updatedItem,
              incomingUpdatedAt: incomingItem.updatedAt,
              localUpdatedAt: current.updatedAt,
            ),
          );
        }
      } else {
        unchangedItems++;
        details.add(
          ImportChangeDetail(
            id: incomingItem.id,
            title: incomingItem.title,
            kind: ImportChangeKind.unchangedItem,
            incomingUpdatedAt: incomingItem.updatedAt,
            localUpdatedAt: current.updatedAt,
          ),
        );
      }
    }

    return ImportMergeSummary(
      incomingItems: incoming.items.length,
      newItems: newItems,
      updatedItems: updatedItems,
      deletedItems: deletedItems,
      unchangedItems: unchangedItems,
      replacesLocalVault: false,
      details: details,
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
