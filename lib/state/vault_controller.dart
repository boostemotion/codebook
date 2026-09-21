import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:uuid/uuid.dart';

import '../models/vault_models.dart';
import '../services/clipboard_service.dart';
import '../services/crypto_service.dart';
import '../services/device_key_store.dart';
import '../services/import_export_service.dart';
import '../services/lan_pairing_store.dart';
import '../services/lan_sync_service.dart';
import '../services/password_generator_service.dart';
import '../services/totp_service.dart';
import '../services/vault_repository.dart';
import 'import_plan.dart';
import 'vault_controller_types.dart';

export 'import_plan.dart';
export 'vault_controller_types.dart';

AutoLockPreset? _presetForDuration(Duration duration) {
  for (final preset in AutoLockPreset.values) {
    if (preset.duration == duration) {
      return preset;
    }
  }
  return null;
}

class VaultController extends ChangeNotifier {
  VaultController({
    required VaultRepository repository,
    required CryptoService cryptoService,
    required ImportExportService importExportService,
    required DeviceKeyStore deviceKeyStore,
    required PasswordGeneratorService passwordGeneratorService,
    required ClipboardService clipboardService,
    LanSyncService? lanSyncService,
    LanPairingStore? pairingStore,
    Duration autoLockDuration = const Duration(minutes: 2),
  })  : _repository = repository,
        _cryptoService = cryptoService,
        _importExportService = importExportService,
        _deviceKeyStore = deviceKeyStore,
        _passwordGeneratorService = passwordGeneratorService,
        _clipboardService = clipboardService,
        _pairingStore = pairingStore ?? LanPairingStore(),
        _lanSyncService =
            lanSyncService ?? LanSyncService(pairingStore: pairingStore),
        _autoLockDuration = autoLockDuration,
        _autoLockPreset = _presetForDuration(autoLockDuration);

  final VaultRepository _repository;
  final CryptoService _cryptoService;
  final ImportExportService _importExportService;
  final DeviceKeyStore _deviceKeyStore;
  final PasswordGeneratorService _passwordGeneratorService;
  final ClipboardService _clipboardService;
  final LanPairingStore _pairingStore;
  final LanSyncService _lanSyncService;
  Duration _autoLockDuration;
  AutoLockPreset? _autoLockPreset;
  final Uuid _uuid = const Uuid();

  bool _busy = false;
  bool _hasVault = false;
  VaultStorageState _storageState = VaultStorageState.loading;
  int _sessionGeneration = 0;
  int _externalUiDepth = 0;
  bool _disposed = false;
  bool _isUnlocked = false;
  bool _quickUnlockSupported = false;
  bool _quickUnlockEnabled = false;
  bool _masterPasswordVerifiedThisLaunch = false;
  String? _message;
  VaultData _vaultData = VaultData.empty();
  EncryptedVaultDocument? _document;
  Uint8List? _dataEncryptionKey;
  Uint8List? _sessionKek;
  Timer? _autoLockTimer;
  Timer? _lanAutoSyncTimer;
  bool _lanAutoSyncInFlight = false;
  bool _lanAutoHostSuppressed = false;
  Future<void> _mutationTail = Future<void>.value();
  LanSyncHost? _lanSyncHost;
  List<LanSyncPeer> _lanSyncPeers = const [];

  bool get busy => _busy;
  bool get hasVault => _hasVault;
  VaultStorageState get storageState => _storageState;
  bool get canCreateVault => _storageState == VaultStorageState.absent;
  bool get canRecoverVault =>
      _storageState == VaultStorageState.recoveryAvailable;
  bool get externalUiActive => _externalUiDepth > 0;
  bool get isUnlocked => _isUnlocked;
  bool get quickUnlockSupported => _quickUnlockSupported;
  bool get quickUnlockEnabled => _quickUnlockEnabled;
  bool get canUseQuickUnlockNow =>
      _quickUnlockSupported &&
      _quickUnlockEnabled &&
      _masterPasswordVerifiedThisLaunch;
  String? get message => _message;
  VaultData get vaultData => _vaultData;
  AutoLockPreset? get autoLockPreset => _autoLockPreset;
  Duration get autoLockDuration => _autoLockDuration;
  LanSyncHost? get lanSyncHost => _lanSyncHost;
  List<LanSyncPeer> get lanSyncPeers => List.unmodifiable(_lanSyncPeers);

  void setAutoLockPreset(AutoLockPreset preset) {
    if (_autoLockPreset == preset && _autoLockDuration == preset.duration) {
      return;
    }
    _autoLockPreset = preset;
    _autoLockDuration = preset.duration;
    if (_isUnlocked) {
      _restartAutoLockTimer();
    }
    _notifyListeners();
  }

  Future<VaultOperationResult> bootstrap() {
    return _run(() async {
      final result = await _repository.inspect();
      _storageState = result.state;
      _document =
          result.state == VaultStorageState.available ? result.document : null;
      _hasVault = !result.canCreate;
      _quickUnlockSupported = await _deviceKeyStore.isSupported();
      _quickUnlockEnabled =
          _quickUnlockSupported && await _deviceKeyStore.hasWrappedDekCache();
      _masterPasswordVerifiedThisLaunch = result.canCreate;
      if (!result.canCreate && result.state != VaultStorageState.available) {
        _message = result.error ?? '密码库需要恢复或修复，不能创建新密码库。';
      }
      if (!_runningFlutterTests) {
        unawaited(_discoverLanPeersSilently());
      }
    });
  }

  Future<VaultOperationResult> recoverVault() {
    return _runMutation(() async {
      if (!canRecoverVault) {
        throw StateError('当前没有可恢复的密码库副本。');
      }
      await _repository.recover();
      final result = await _repository.inspect();
      if (result.state != VaultStorageState.available ||
          result.document == null) {
        throw StateError('恢复后的密码库未通过验证。');
      }
      _storageState = result.state;
      _document = result.document;
      _hasVault = true;
      _message = '已从验证过的备份恢复密码库。';
    });
  }

  Future<VaultOperationResult> prepareDebugSession({int seedCount = 10}) {
    return _runMutation(() async {
      if (await _repository.exists()) {
        throw StateError('Debug seed skipped: existing vault detected.');
      }
      await _deviceKeyStore.clear();
      _quickUnlockEnabled = false;
      _quickUnlockSupported = false;

      const debugPassword = 'debug-only-password';
      final sessionGeneration = _sessionGeneration;
      final document =
          await _cryptoService.createVault(password: debugPassword);
      _ensureSessionCurrent(sessionGeneration);
      await _repository.save(document);
      await _ensureSessionCurrentAfterWrite(sessionGeneration);
      _document = document;
      _hasVault = true;
      _storageState = VaultStorageState.available;
      await _unlockDocument(
        document,
        debugPassword,
        sessionGeneration: sessionGeneration,
      );

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
      _ensureSessionCurrent(sessionGeneration);
      _masterPasswordVerifiedThisLaunch = true;
      _message = null;
    });
  }

  Future<VaultOperationResult> createVault(String password) {
    return _runMutation(() async {
      if (!canCreateVault) {
        throw StateError('现有密码库需要恢复、导出或重置，不能覆盖创建。');
      }
      _requirePassword(password, fieldName: '主密码');
      final sessionGeneration = _sessionGeneration;
      final document = await _cryptoService.createVault(password: password);
      _ensureSessionCurrent(sessionGeneration);
      await _repository.save(document);
      await _ensureSessionCurrentAfterWrite(sessionGeneration);
      _document = document;
      _hasVault = true;
      _storageState = VaultStorageState.available;
      await _unlockDocument(
        document,
        password,
        sessionGeneration: sessionGeneration,
      );
      _masterPasswordVerifiedThisLaunch = true;
      await _syncQuickUnlockCache();
      _ensureSessionCurrent(sessionGeneration);
      _message = '已创建新的加密密码库。';
    });
  }

  Future<VaultOperationResult> unlock(String password) {
    final sessionGeneration = _sessionGeneration;
    return _run(() async {
      _requirePassword(password, fieldName: '主密码');
      if (_storageState != VaultStorageState.available) {
        throw StateError('密码库需要恢复或修复后才能解锁。');
      }
      final document = _document ?? await _repository.load();
      if (document == null) {
        throw const VaultUnlockException('未找到本地密码库。');
      }
      await _unlockDocument(
        document,
        password,
        sessionGeneration: sessionGeneration,
      );
      _ensureSessionCurrent(sessionGeneration);
      _masterPasswordVerifiedThisLaunch = true;
      _message = '密码库已解锁。';
    });
  }

  Future<VaultOperationResult> unlockWithQuickUnlock() {
    final sessionGeneration = _sessionGeneration;
    return _run(() async {
      if (!_masterPasswordVerifiedThisLaunch) {
        throw StateError('首次登录请使用主密码，之后可用 Windows Hello 快速解锁。');
      }
      if (!_quickUnlockSupported || !_quickUnlockEnabled) {
        throw StateError('当前设备未开启快速解锁。');
      }
      if (_storageState != VaultStorageState.available) {
        throw StateError('密码库需要恢复或修复后才能解锁。');
      }
      final document = _document ?? await _repository.load();
      if (document == null) {
        throw const VaultUnlockException('未找到本地密码库。');
      }
      final protectedKek = await _withExternalUi(
        _deviceKeyStore.readWrappedDek,
      );
      if (protectedKek == null) {
        throw StateError('快速解锁密钥不可用。');
      }
      final session = await _cryptoService.openVaultWithKek(
        document: document,
        keyEncryptionKey: protectedKek,
      );
      _ensureSessionCurrent(sessionGeneration);
      _document = document;
      _vaultData = session.vaultData;
      _dataEncryptionKey = session.dataEncryptionKey;
      _sessionKek = session.keyEncryptionKey;
      _isUnlocked = true;
      _restartAutoLockTimer();
      _scheduleLanAutoSync();
      _message = '已通过快速解锁打开密码库。';
    });
  }

  Future<ImportPlan?> previewImport(String importPassword) {
    final sessionGeneration = _sessionGeneration;
    final hadVaultAtPreview = _hasVault;
    return _runWithResult(() async {
      _requirePassword(importPassword, fieldName: '导入文件密码');
      final importPath = await _withExternalUi(
        _importExportService.pickImportPath,
      );
      _ensureSessionCurrent(sessionGeneration);
      if (importPath == null) {
        _message = '已取消导入。';
        return null;
      }
      final importBytes = await _importExportService.readFile(importPath);
      _ensureSessionCurrent(sessionGeneration);
      return _previewImportBytes(
        importBytes,
        importPassword,
        sessionGeneration: sessionGeneration,
        hadVaultAtPreview: hadVaultAtPreview,
      );
    });
  }

  Future<ImportPlan?> previewImportBytes(
    Uint8List importBytes,
    String importPassword,
  ) {
    final sessionGeneration = _sessionGeneration;
    return _runWithResult(() async {
      _requirePassword(importPassword, fieldName: '导入文件密码');
      return _previewImportBytes(
        importBytes,
        importPassword,
        sessionGeneration: sessionGeneration,
        hadVaultAtPreview: _hasVault,
      );
    });
  }

  Future<Uint8List?> downloadLanSync({
    required LanSyncPeer peer,
    String? pairingCode,
    String? sharedPassword,
  }) {
    return _runWithResult(() async {
      final result = await _lanSyncService.downloadDetailed(
        peer: peer,
        pairingCode: pairingCode,
        accessToken: peer.accessToken,
        sharedPassword: sharedPassword,
      );
      final deviceId = result.deviceId ?? peer.deviceId;
      final accessToken = result.accessToken ?? peer.accessToken;
      if (deviceId != null && accessToken != null) {
        await _pairingStore.savePeer(
          LanPairingRecord(
            deviceId: deviceId,
            deviceName: peer.deviceName,
            address: peer.address,
            port: peer.port,
            vaultId: peer.vaultId,
            accessToken: accessToken,
            revision: result.revision ?? peer.revision,
            lastSeen: DateTime.now(),
          ),
        );
      }
      return result.bytes;
    });
  }

  Future<VaultOperationResult> startLanSyncShare({String? deviceName}) {
    return _run(() async {
      _ensureUnlocked();
      _lanAutoHostSuppressed = false;
      final rawBytes = await _repository.loadRaw();
      if (rawBytes == null) {
        throw StateError('本地密码库不存在。');
      }
      await _lanSyncHost?.close();
      _lanSyncHost = await _lanSyncService.startHost(
        documentBytes: rawBytes,
        deviceName: deviceName,
        authorizationKey: _requireSessionKek(),
      );
      _message = '局域网分享已开启，配对码：${_lanSyncHost!.pairingCode}';
      _notifyListeners();
    });
  }

  Future<VaultOperationResult> stopLanSyncShare() {
    return _run(() async {
      _lanAutoHostSuppressed = true;
      await _lanSyncHost?.close();
      _lanSyncHost = null;
      _message = '已关闭局域网分享。';
      _notifyListeners();
    });
  }

  Future<VaultOperationResult> discoverLanSyncPeers() {
    return _run(() async {
      _lanSyncPeers = await _discoverPeers();
      _message = _lanSyncPeers.isEmpty ? '没有发现局域网分享设备。' : null;
      _notifyListeners();
    });
  }

  Future<List<LanSyncPeer>> _discoverPeers({
    Duration timeout = const Duration(seconds: 2),
  }) async {
    final peers = await _lanSyncService.discover(timeout: timeout);
    final records = await _pairingStore.loadPeers();
    return peers.map((peer) {
      final record = records.where((candidate) {
        return candidate.deviceId == peer.deviceId ||
            (candidate.address == peer.address &&
                candidate.vaultId == peer.vaultId);
      }).firstOrNull;
      return record == null
          ? peer
          : peer.copyWith(accessToken: record.accessToken);
    }).toList();
  }

  Future<void> _discoverLanPeersSilently() async {
    try {
      final peers = await _discoverPeers(timeout: const Duration(seconds: 1));
      if (_disposed) {
        return;
      }
      _lanSyncPeers = peers;
      _notifyListeners();
    } on Object {
      // Discovery is opportunistic and must never block opening the vault.
    }
  }

  Future<VaultOperationResult> applyImportPlan(ImportPlan plan) {
    return _runMutation(() async {
      _ensureSessionCurrent(plan.sessionGeneration);
      if (_hasVault != plan.hadVaultAtPreview) {
        throw StateError('本地密码库状态已变化，请重新预览导入。');
      }
      final sessionGeneration = _sessionGeneration;
      if (!_hasVault) {
        await _repository.importRaw(plan.rawBytes);
        await _ensureSessionCurrentAfterWrite(sessionGeneration);
        _document = plan.importedDocument;
        _hasVault = true;
        _storageState = VaultStorageState.available;
        _vaultData = plan.importedSession.vaultData;
        _dataEncryptionKey = plan.importedSession.dataEncryptionKey;
        _sessionKek = plan.importedSession.keyEncryptionKey;
        _isUnlocked = true;
        _restartAutoLockTimer();
        _scheduleLanAutoSync();
        await _syncQuickUnlockCache();
        _ensureSessionCurrent(sessionGeneration);
        _masterPasswordVerifiedThisLaunch = true;
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

  Future<VaultOperationResult> importIntoCurrentVault(
    String importPassword,
  ) async {
    final plan = await previewImport(importPassword);
    if (plan == null) {
      return const VaultOperationResult();
    }
    return applyImportPlan(plan);
  }

  Future<VaultOperationResult> exportVault({String? exportPassword}) {
    final sessionGeneration = _sessionGeneration;
    return _run(() async {
      _ensureSessionCurrent(sessionGeneration);
      _ensureUnlocked();
      final exportPath = await _withExternalUi(
        _importExportService.pickExportPath,
      );
      _ensureSessionCurrent(sessionGeneration);
      _ensureUnlocked();
      if (exportPath == null) {
        _message = '已取消导出。';
        return;
      }

      Uint8List bytesToWrite;
      if (exportPassword != null && exportPassword.trim().isNotEmpty) {
        _requirePassword(exportPassword, fieldName: '导出密码');
        _ensureSessionCurrent(sessionGeneration);
        _ensureUnlocked();
        final exported = await _cryptoService.createPasswordProtectedExport(
          vaultData: _vaultData,
          password: exportPassword,
        );
        _ensureSessionCurrent(sessionGeneration);
        _ensureUnlocked();
        bytesToWrite = exported.encode();
      } else {
        final raw = await _repository.loadRaw();
        _ensureSessionCurrent(sessionGeneration);
        _ensureUnlocked();
        if (raw == null) {
          throw StateError('本地密码库不存在。');
        }
        bytesToWrite = raw;
      }

      _ensureSessionCurrent(sessionGeneration);
      _ensureUnlocked();
      await _importExportService.writeFile(exportPath, bytesToWrite);
      _ensureSessionCurrent(sessionGeneration);
      _ensureUnlocked();
      _restartAutoLockTimer();
      _message = exportPassword == null || exportPassword.trim().isEmpty
          ? '已导出加密备份。'
          : '已使用独立导出密码导出加密备份。';
    });
  }

  Future<VaultOperationResult> addOrUpdateItem({
    String? id,
    required String title,
    required String username,
    required String password,
    required String url,
    required String notes,
    required List<String> tags,
    String? totpSecret,
  }) {
    return _runMutation(() async {
      _ensureUnlocked();
      if (title.trim().isEmpty) {
        throw ArgumentError('名称不能为空。');
      }
      final normalizedTotpSecret = totpSecret?.trim();
      if (normalizedTotpSecret?.isNotEmpty ?? false) {
        await const TotpService().generate(normalizedTotpSecret!);
      }
      final now = DateTime.now();
      final existing = id == null
          ? null
          : _vaultData.items.where((item) => item.id == id).firstOrNull;
      if (existing?.isDeleted ?? false) {
        throw StateError('请先从回收站恢复条目。');
      }
      final item = VaultItem(
        id: existing?.id ?? _uuid.v4(),
        title: title.trim(),
        username: username.trim(),
        password: password,
        url: url.trim(),
        notes: notes.trim(),
        tags: tags,
        totpSecret: (normalizedTotpSecret?.isEmpty ?? true)
            ? null
            : normalizedTotpSecret,
        createdAt: existing?.createdAt ?? now,
        updatedAt: now,
        deletedAt: null,
      );
      item.validate();
      await _saveState(
        vaultData: _vaultData.upsert(item),
        keyEncryptionKey: _requireSessionKek(),
      );
      _message = existing == null ? '条目已新增。' : '条目已更新。';
    });
  }

  Future<VaultOperationResult> deleteItem(String id) {
    return _runMutation(() async {
      _ensureUnlocked();
      final item = _vaultData.items.where((item) => item.id == id).firstOrNull;
      if (item == null || item.isDeleted) {
        throw StateError('未找到可删除的条目。');
      }
      final now = DateTime.now();
      await _saveState(
        vaultData: _vaultData.markDeleted(id, now),
        keyEncryptionKey: _requireSessionKek(),
      );
      _message = '条目已移至回收站。';
    });
  }

  Future<VaultOperationResult> restoreItem(String id) {
    return _runMutation(() async {
      _ensureUnlocked();
      final item = _vaultData.items.where((item) => item.id == id).firstOrNull;
      if (item == null || !item.isDeleted) {
        throw StateError('未找到可恢复的条目。');
      }
      final now = DateTime.now();
      await _saveState(
        vaultData: _vaultData.restoreItem(id, now),
        keyEncryptionKey: _requireSessionKek(),
      );
      _message = '条目已恢复。';
    });
  }

  Future<VaultOperationResult> deleteItemPermanently(String id) {
    return _runMutation(() async {
      _ensureUnlocked();
      final item = _vaultData.items.where((item) => item.id == id).firstOrNull;
      if (item == null || !item.isDeleted) {
        throw StateError('未找到可永久删除的条目。');
      }
      await _saveState(
        vaultData: _vaultData.removePermanently(id, DateTime.now()),
        keyEncryptionKey: _requireSessionKek(),
      );
      _message = '条目已永久删除。';
    });
  }

  Future<VaultOperationResult> changeMasterPassword({
    required String oldPassword,
    required String newPassword,
  }) {
    return _runMutation(() async {
      _requirePassword(oldPassword, fieldName: '当前主密码');
      _requirePassword(newPassword, fieldName: '新主密码');
      _ensureUnlocked();
      final sessionGeneration = _sessionGeneration;
      final document = _document;
      if (document == null) {
        throw StateError('本地密码库不存在。');
      }
      final rewrapped = await _cryptoService.rewrapMasterPassword(
        document: document,
        oldPassword: oldPassword,
        newPassword: newPassword,
      );
      _ensureSessionCurrent(sessionGeneration);
      await _repository.save(rewrapped);
      await _ensureSessionCurrentAfterWrite(sessionGeneration);
      final session = await _cryptoService.openVault(
        document: rewrapped,
        password: newPassword,
      );
      _ensureSessionCurrent(sessionGeneration);
      _document = rewrapped;
      _lanSyncHost?.updateDocument(rewrapped.encode());
      _dataEncryptionKey = session.dataEncryptionKey;
      _sessionKek = session.keyEncryptionKey;
      _lanSyncHost?.updateAuthorizationKey(_sessionKek!);
      _vaultData = session.vaultData;
      _isUnlocked = true;
      await _syncQuickUnlockCache();
      _ensureSessionCurrent(sessionGeneration);
      _restartAutoLockTimer();
      _message = '主密码已更新。';
    });
  }

  Future<VaultOperationResult> enableQuickUnlock() {
    return _runMutation(() async {
      _ensureUnlocked();
      if (!_quickUnlockSupported) {
        throw StateError('当前设备不支持快速解锁。');
      }
      await _syncQuickUnlockCache(forceEnable: true);
      _message = '已在当前设备开启快速解锁。';
    });
  }

  Future<VaultOperationResult> disableQuickUnlock() {
    return _runMutation(() async {
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

  Future<VaultOperationResult> copySecret(String text) {
    return _run(() async {
      _ensureUnlocked();
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

  Future<void> handleAppLifecycle(AppLifecycleState state) async {
    final isTerminalState = state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached;
    final pickerTemporarilyOwnsFocus =
        state == AppLifecycleState.inactive && externalUiActive;
    if (_isUnlocked && (isTerminalState || !pickerTemporarilyOwnsFocus)) {
      await lock();
    }
  }

  Future<void> handleAppPaused() =>
      handleAppLifecycle(AppLifecycleState.paused);

  Future<void> lock() async {
    _sessionGeneration++;
    _autoLockTimer?.cancel();
    _lanAutoSyncTimer?.cancel();
    _lanAutoSyncTimer = null;
    _lanAutoSyncInFlight = false;
    _lanAutoHostSuppressed = false;
    await _lanSyncHost?.close();
    _lanSyncHost = null;
    _isUnlocked = false;
    _vaultData = VaultData.empty();
    _dataEncryptionKey = null;
    _sessionKek = null;
    _message = '密码库已锁定。';
    await _clipboardService.clearIfOwned();
    _notifyListeners();
  }

  void clearMessage() {
    if (_message == null) {
      return;
    }
    _message = null;
    _notifyListeners();
  }

  Future<void> _unlockDocument(
    EncryptedVaultDocument document,
    String password, {
    int? sessionGeneration,
  }) async {
    final session = await _cryptoService.openVault(
      document: document,
      password: password,
    );
    if (sessionGeneration != null) {
      _ensureSessionCurrent(sessionGeneration);
    }
    _document = document;
    _vaultData = session.vaultData;
    _dataEncryptionKey = session.dataEncryptionKey;
    _sessionKek = session.keyEncryptionKey;
    _isUnlocked = true;
    _restartAutoLockTimer();
    _scheduleLanAutoSync();
  }

  Future<ImportPlan> _previewImportBytes(
    Uint8List importBytes,
    String importPassword, {
    required int sessionGeneration,
    required bool hadVaultAtPreview,
  }) async {
    _ensureSessionCurrent(sessionGeneration);
    final importedDocument = EncryptedVaultDocument.decode(importBytes);
    _ensureSessionCurrent(sessionGeneration);
    final importedSession = await _cryptoService.openVault(
      document: importedDocument,
      password: importPassword,
    );
    _ensureSessionCurrent(sessionGeneration);
    return ImportPlan(
      sessionGeneration: sessionGeneration,
      hadVaultAtPreview: hadVaultAtPreview,
      rawBytes: importBytes,
      importedDocument: importedDocument,
      importedSession: importedSession,
      summary: _buildImportSummary(importedSession.vaultData),
    );
  }

  Future<void> _saveState({
    required VaultData vaultData,
    required Uint8List keyEncryptionKey,
    int? revisionFloor,
  }) async {
    final sessionGeneration = _sessionGeneration;
    final currentDocument = _document;
    final dataEncryptionKey = _dataEncryptionKey;
    if (currentDocument == null || dataEncryptionKey == null) {
      throw StateError('密码库会话已锁定。');
    }
    final currentMetadata = currentDocument.metadata;
    final nextRevision =
        currentMetadata == null ? 0 : currentMetadata.revision + 1;
    final metadata = currentMetadata == null
        ? VaultMetadata(vaultId: _uuid.v4(), keyGeneration: 1, revision: 0)
        : VaultMetadata(
            vaultId: currentMetadata.vaultId,
            keyGeneration: currentMetadata.keyGeneration,
            revision: revisionFloor == null || nextRevision >= revisionFloor
                ? nextRevision
                : revisionFloor,
          );
    final updatedAt = DateTime.now();
    final document = await _cryptoService.saveVaultWithKek(
      vaultData: vaultData.copyWith(updatedAt: updatedAt),
      keyEncryptionKey: keyEncryptionKey,
      dataEncryptionKey: dataEncryptionKey,
      kdf: currentDocument.kdf,
      metadata: metadata,
    );
    _ensureSessionCurrent(sessionGeneration);
    await _repository.save(document);
    await _ensureSessionCurrentAfterWrite(sessionGeneration);
    _document = document;
    _lanSyncHost?.updateDocument(document.encode());
    _vaultData = vaultData.copyWith(updatedAt: updatedAt);
    _sessionKek = keyEncryptionKey;
    _lanSyncHost?.updateAuthorizationKey(keyEncryptionKey);
    _ensureSessionCurrent(sessionGeneration);
    _restartAutoLockTimer();
  }

  String _vaultFingerprint(VaultData data) {
    final items = data.items.map((item) => jsonEncode(item.toJson())).toList()
      ..sort();
    return '${data.updatedAt.toUtc().toIso8601String()}|${items.join('|')}';
  }

  void _ensureSessionCurrent(int expectedGeneration) {
    if (_disposed || expectedGeneration != _sessionGeneration) {
      throw StateError('密码库会话已锁定或已失效。');
    }
  }

  Future<void> _ensureSessionCurrentAfterWrite(int expectedGeneration) async {
    try {
      _ensureSessionCurrent(expectedGeneration);
    } on StateError {
      final result = await _repository.inspect();
      _storageState = result.state;
      _document =
          result.state == VaultStorageState.available ? result.document : null;
      _hasVault = !result.canCreate;
      rethrow;
    }
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

  void _scheduleLanAutoSync() {
    if (_runningFlutterTests) {
      return;
    }
    _lanAutoHostSuppressed = false;
    _lanAutoSyncTimer?.cancel();
    _lanAutoSyncTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => unawaited(_runLanAutoSync()),
    );
    unawaited(_runLanAutoSync());
  }

  bool get _runningFlutterTests =>
      Platform.environment['FLUTTER_TEST'] == 'true';

  Future<void> _runLanAutoSync() async {
    if (_disposed || !_isUnlocked || _lanAutoSyncInFlight) {
      return;
    }
    _lanAutoSyncInFlight = true;
    try {
      await _ensureLanAutoHost();
      final peers = await _discoverPeers(timeout: const Duration(seconds: 1));
      if (_disposed || !_isUnlocked) {
        return;
      }
      _lanSyncPeers = peers;
      _notifyListeners();

      final currentMetadata = _document?.metadata;
      final currentKek = _sessionKek;
      if (currentMetadata == null || currentKek == null) {
        return;
      }
      for (final peer in peers) {
        if (peer.accessToken == null ||
            peer.vaultId != currentMetadata.vaultId ||
            peer.revision <= currentMetadata.revision) {
          continue;
        }
        await _autoMergePeer(peer, currentKek);
      }
    } on Object {
      // Automatic sync is opportunistic. Manual pairing remains available if
      // a network changes or a peer needs its master password again.
    } finally {
      _lanAutoSyncInFlight = false;
    }
  }

  Future<void> _ensureLanAutoHost() async {
    if (_lanAutoHostSuppressed || _lanSyncHost != null || !_isUnlocked) {
      return;
    }
    final rawBytes = await _repository.loadRaw();
    if (rawBytes == null) {
      return;
    }
    _lanSyncHost = await _lanSyncService.startHost(
      documentBytes: rawBytes,
      authorizationKey: _requireSessionKek(),
    );
    _notifyListeners();
  }

  Future<void> _autoMergePeer(
    LanSyncPeer peer,
    Uint8List currentKek,
  ) async {
    final generation = _sessionGeneration;
    final operation = _mutationTail.then((_) async {
      _ensureSessionCurrent(generation);
      final result = await _lanSyncService.downloadDetailed(
        peer: peer,
        accessToken: peer.accessToken,
      );
      _ensureSessionCurrent(generation);
      final importedDocument = EncryptedVaultDocument.decode(result.bytes);
      if (importedDocument.metadata?.vaultId != _document?.metadata?.vaultId ||
          (importedDocument.metadata?.revision ?? 0) <=
              (_document?.metadata?.revision ?? 0)) {
        return;
      }
      final importedSession = await _cryptoService.openVaultWithKek(
        document: importedDocument,
        keyEncryptionKey: currentKek,
      );
      _ensureSessionCurrent(generation);
      final merged = _vaultData.merge(importedSession.vaultData);
      if (_vaultFingerprint(merged) == _vaultFingerprint(_vaultData)) {
        return;
      }
      await _saveState(
        vaultData: merged,
        keyEncryptionKey: currentKek,
        revisionFloor: (importedDocument.metadata?.revision ?? 0) + 1,
      );
      final deviceId = result.deviceId ?? peer.deviceId;
      final accessToken = result.accessToken ?? peer.accessToken;
      if (deviceId != null && accessToken != null) {
        await _pairingStore.savePeer(
          LanPairingRecord(
            deviceId: deviceId,
            deviceName: peer.deviceName,
            address: peer.address,
            port: peer.port,
            vaultId: peer.vaultId,
            accessToken: accessToken,
            revision: result.revision ?? peer.revision,
            lastSeen: DateTime.now(),
          ),
        );
      }
    });
    _mutationTail = operation.then<void>((_) {}).catchError((_) {});
    await operation;
  }

  void _restartAutoLockTimer() {
    _autoLockTimer?.cancel();
    _autoLockTimer = Timer(_autoLockDuration, () {
      if (_isUnlocked) {
        lock();
      }
    });
  }

  Future<T> _withExternalUi<T>(Future<T> Function() action) async {
    _externalUiDepth++;
    try {
      return await action();
    } finally {
      _externalUiDepth--;
    }
  }

  void _notifyListeners() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  Future<VaultOperationResult> _runMutation(Future<void> Function() action) {
    final sessionGeneration = _sessionGeneration;
    final operation = _mutationTail.then(
      (_) => _run(() async {
        _ensureSessionCurrent(sessionGeneration);
        await action();
      }),
    );
    _mutationTail = operation.then<void>((_) {});
    return operation;
  }

  Future<VaultOperationResult> _run(Future<void> Function() action) async {
    _busy = true;
    _message = null;
    _notifyListeners();
    try {
      await action();
      return const VaultOperationResult.success();
    } catch (error) {
      _message = error.toString();
      return VaultOperationResult(error: error);
    } finally {
      _busy = false;
      _notifyListeners();
    }
  }

  Future<T?> _runWithResult<T>(Future<T?> Function() action) async {
    _busy = true;
    _message = null;
    _notifyListeners();
    try {
      return await action();
    } catch (error) {
      _message = error.toString();
      return null;
    } finally {
      _busy = false;
      _notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _sessionGeneration++;
    _autoLockTimer?.cancel();
    _lanAutoSyncTimer?.cancel();
    unawaited(_lanSyncHost?.close());
    _lanSyncHost = null;
    _clipboardService.dispose();
    super.dispose();
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
