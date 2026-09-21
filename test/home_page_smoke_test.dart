import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cipherbook/models/vault_models.dart';
import 'package:cipherbook/services/clipboard_service.dart';
import 'package:cipherbook/services/crypto_service.dart';
import 'package:cipherbook/services/device_key_store.dart';
import 'package:cipherbook/services/import_export_service.dart';
import 'package:cipherbook/services/password_generator_service.dart';
import 'package:cipherbook/services/vault_repository.dart';
import 'package:cipherbook/state/vault_controller.dart';
import 'package:cipherbook/ui/home_page.dart';

void main() {
  testWidgets('locked view shows password input', (tester) async {
    final controller = _buildController();
    await controller.bootstrap();
    await tester.pumpWidget(_buildApp(controller));

    expect(find.byType(TextField), findsAtLeastNWidgets(1));
    expect(find.byType(FilledButton), findsOneWidget);

    controller.dispose();
  });

  testWidgets('Android unlocked view uses Material list, FAB, and overflow',
      (tester) async {
    final controller = _buildController();
    await controller.bootstrap();
    await controller.createVault('master-pass');
    await controller.addOrUpdateItem(
      title: 'GitHub',
      username: 'alice',
      password: 'secret',
      url: 'https://github.com',
      notes: '',
      tags: const [],
    );
    await tester.pumpWidget(_buildApp(controller));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('android-vault-list')), findsOneWidget);
    expect(find.byKey(const ValueKey('android-vault-fab')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('android-vault-overflow')), findsOneWidget);
    expect(find.byKey(const ValueKey('liquid-dock')), findsNothing);

    controller.dispose();
  });

  testWidgets('busy overlay is visible while creating vault', (tester) async {
    final controller = _buildController(
      cryptoService:
          _SlowCryptoService(delay: const Duration(milliseconds: 200)),
    );
    await controller.bootstrap();
    await tester.pumpWidget(_buildApp(controller));

    await tester.enterText(find.byType(TextField).first, 'master-pass');
    await tester.tap(find.byType(FilledButton).first);
    await tester.pump(const Duration(milliseconds: 20));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 260));
    controller.dispose();
  });

  testWidgets('scroll keeps dock and search visible', (tester) async {
    final controller = _buildController();
    await controller.bootstrap();
    await controller.createVault('master-pass');
    for (var i = 0; i < 16; i++) {
      await controller.addOrUpdateItem(
        title: 'item-$i',
        username: 'user-$i',
        password: 'pw-$i',
        url: '',
        notes: '',
        tags: const [],
      );
    }

    await tester.pumpWidget(_buildApp(controller));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('android-vault-fab')), findsOneWidget);
    expect(find.byIcon(Icons.search_rounded), findsOneWidget);
    expect(find.byKey(const ValueKey('android-vault-list')), findsOneWidget);

    await tester.drag(find.byType(ListView).first, const Offset(0, -260));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 20));

    expect(find.byKey(const ValueKey('android-vault-fab')), findsOneWidget);
    expect(find.byIcon(Icons.search_rounded), findsOneWidget);
    expect(find.byKey(const ValueKey('android-vault-list')), findsOneWidget);

    controller.dispose();
  });

  testWidgets('Android search replaces the app bar and Windows keeps its dock',
      (tester) async {
    final controller = _buildController();
    await controller.bootstrap();
    await controller.createVault('master-pass');
    await controller.addOrUpdateItem(
      title: 'Alpha',
      username: 'alice',
      password: 'pw',
      url: '',
      notes: '',
      tags: const [],
    );

    await tester.pumpWidget(_buildApp(controller));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('搜索'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('android-search-field')), findsOneWidget);
    expect(find.byKey(const ValueKey('liquid-dock')), findsNothing);

    await tester.pumpWidget(
      _buildApp(controller, platform: TargetPlatform.windows),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('liquid-dock')), findsOneWidget);

    controller.dispose();
  });

  testWidgets(
      'Windows unlocked view uses desktop dock instead of Android actions',
      (tester) async {
    final controller = _buildController();
    await controller.bootstrap();
    await controller.createVault('master-pass');
    await tester.pumpWidget(
      _buildApp(controller, platform: TargetPlatform.windows),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('liquid-dock')), findsOneWidget);
    expect(find.byKey(const ValueKey('android-vault-fab')), findsNothing);
    expect(find.byKey(const ValueKey('android-vault-overflow')), findsNothing);

    controller.dispose();
  });

  testWidgets('Windows sidebar exposes the pairing workspace', (tester) async {
    final controller = _buildController();
    await controller.bootstrap();
    await controller.createVault('master-pass');
    await tester.pumpWidget(
      _buildApp(controller, platform: TargetPlatform.windows),
    );
    await tester.pumpAndSettle();

    final sidebar = find.byKey(const ValueKey('liquid-dock'));
    await tester.tap(find.descendant(of: sidebar, matching: find.text('配对同步')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('vault-page-pairing')), findsOneWidget);
    expect(find.text('打开设备配对'), findsOneWidget);
    controller.dispose();
  });

  testWidgets('Windows content expands with a wide window', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1800, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = _buildController();
    await controller.bootstrap();
    await controller.createVault('master-pass');
    await tester.pumpWidget(
      _buildApp(controller, platform: TargetPlatform.windows),
    );
    await tester.pumpAndSettle();

    expect(
      tester.getSize(find.byKey(const ValueKey('vault-header'))).width,
      greaterThan(1400),
    );
    controller.dispose();
  });

  testWidgets('storage repair view prevents vault creation', (tester) async {
    for (final result in [
      const VaultLoadResult(
        state: VaultStorageState.corrupt,
        error: 'corrupt vault',
      ),
      const VaultLoadResult(
        state: VaultStorageState.recoveryAvailable,
        error: 'recovery required',
      ),
    ]) {
      final controller = _buildController(
        repository: _MemoryVaultRepository(initialLoadResult: result),
      );
      await controller.bootstrap();
      await tester.pumpWidget(_buildApp(controller));
      await tester.pumpAndSettle();

      expect(find.text('创建密码库'), findsNothing);
      expect(find.byType(TextField), findsNothing);
      expect(
          find.text('密码库需要修复').evaluate().isNotEmpty ||
              find.text('检测到可恢复的密码库').evaluate().isNotEmpty,
          isTrue);

      controller.dispose();
    }
  });

  testWidgets('Windows entry details mask passwords until requested',
      (tester) async {
    final controller = _buildController();
    await controller.bootstrap();
    await controller.createVault('master-pass');
    await controller.addOrUpdateItem(
      title: 'Desktop private entry',
      username: 'alice',
      password: 'do-not-display',
      url: '',
      notes: '',
      tags: const [],
    );
    await tester.pumpWidget(
      _buildApp(controller, platform: TargetPlatform.windows),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('查看'));
    await tester.pumpAndSettle();
    expect(find.text('do-not-display'), findsNothing);
    expect(find.text('显示密码'), findsOneWidget);

    await tester.tap(find.text('显示密码'));
    await tester.pumpAndSettle();
    expect(find.text('do-not-display'), findsOneWidget);

    controller.dispose();
  });

  testWidgets('locking dismisses a Windows detail dialog with revealed secrets',
      (tester) async {
    final controller = _buildController();
    await controller.bootstrap();
    await controller.createVault('master-pass');
    await controller.addOrUpdateItem(
      title: 'Desktop private entry',
      username: 'alice',
      password: 'do-not-display',
      url: '',
      notes: '',
      tags: const [],
    );
    await tester.pumpWidget(
      _buildApp(controller, platform: TargetPlatform.windows),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('查看'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('显示密码'));
    await tester.pumpAndSettle();
    expect(find.text('do-not-display'), findsOneWidget);

    await controller.lock();
    await tester.pumpAndSettle();

    expect(find.text('do-not-display'), findsNothing);
    expect(find.text('显示密码'), findsNothing);
    controller.dispose();
  });

  testWidgets('Windows editor retains input after a failed save',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = _buildController();
    await controller.bootstrap();
    await controller.createVault('master-pass');
    await tester.pumpWidget(
      _buildApp(controller, platform: TargetPlatform.windows),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('新增'));
    await tester.pumpAndSettle();
    final passwordField = find.byWidgetPredicate(
      (widget) => widget is TextField && widget.decoration?.labelText == '密码',
    );
    expect(tester.widget<TextField>(passwordField).obscureText, isTrue);
    expect(find.byTooltip('显示密码'), findsOneWidget);
    await tester.tap(find.byTooltip('显示密码'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(passwordField).obscureText, isFalse);
    final titleField = find.byWidgetPredicate(
      (widget) => widget is TextField && widget.decoration?.labelText == '名称',
    );
    final totpField = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.decoration?.labelText == 'TOTP 密钥 / URI',
    );
    await tester.enterText(titleField, 'Retain this entry');
    await tester.enterText(totpField, 'not a valid TOTP secret');
    await tester.tap(find.text('保存条目'));
    await tester.pumpAndSettle();

    expect(tester.widget<TextField>(titleField).controller!.text,
        'Retain this entry');
    expect(controller.vaultData.activeItems, isEmpty);

    controller.dispose();
  });

  testWidgets('Windows add page masks the next password after saving',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = _buildController();
    await controller.bootstrap();
    await controller.createVault('master-pass');
    await tester.pumpWidget(
      _buildApp(controller, platform: TargetPlatform.windows),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('新增'));
    await tester.pumpAndSettle();
    final titleField = find.byWidgetPredicate(
      (widget) => widget is TextField && widget.decoration?.labelText == '名称',
    );
    final passwordField = find.byWidgetPredicate(
      (widget) => widget is TextField && widget.decoration?.labelText == '密码',
    );
    await tester.enterText(titleField, 'Saved entry');
    await tester.tap(find.byTooltip('显示密码'));
    await tester.enterText(passwordField, 'saved-secret');
    await tester.tap(find.text('保存条目'));
    await tester.pumpAndSettle();

    expect(tester.widget<TextField>(passwordField).obscureText, isTrue);
    controller.dispose();
  });

  testWidgets('Windows dock resets password masking when reopening add page',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = _buildController();
    await controller.bootstrap();
    await controller.createVault('master-pass');
    await tester.pumpWidget(
      _buildApp(controller, platform: TargetPlatform.windows),
    );
    await tester.pumpAndSettle();

    final dock = find.byKey(const ValueKey('liquid-dock'));
    await tester.tap(find.descendant(of: dock, matching: find.text('新增')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('显示密码'));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: dock, matching: find.text('设置')));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: dock, matching: find.text('新增')));
    await tester.pumpAndSettle();

    final passwordField = find.byWidgetPredicate(
      (widget) => widget is TextField && widget.decoration?.labelText == '密码',
    );
    expect(tester.widget<TextField>(passwordField).obscureText, isTrue);
    controller.dispose();
  });

  testWidgets('Windows editor retains input after a persistence failure',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _MemoryVaultRepository();
    final controller = _buildController(repository: repository);
    await controller.bootstrap();
    await controller.createVault('master-pass');
    await tester.pumpWidget(
      _buildApp(controller, platform: TargetPlatform.windows),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('新增'));
    await tester.pumpAndSettle();
    final titleField = find.byWidgetPredicate(
      (widget) => widget is TextField && widget.decoration?.labelText == '名称',
    );
    final passwordField = find.byWidgetPredicate(
      (widget) => widget is TextField && widget.decoration?.labelText == '密码',
    );
    await tester.enterText(titleField, 'Retain after disk failure');
    await tester.enterText(passwordField, 'keep-this-secret');
    repository.failNextSave = true;

    await tester.tap(find.text('保存条目'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('vault-page-add')), findsOneWidget);
    expect(
      tester.widget<TextField>(titleField).controller!.text,
      'Retain after disk failure',
    );
    expect(
      tester.widget<TextField>(passwordField).controller!.text,
      'keep-this-secret',
    );
    expect(controller.vaultData.activeItems, isEmpty);

    controller.dispose();
  });

  testWidgets('Windows retains a failed import preview for retry',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _MemoryVaultRepository();
    final importExport = _MemoryImportExportService();
    final imported = await _FastCryptoService().createVault(
      password: 'import-pass',
    );
    importExport.importBytes = imported.encode();
    final controller = _buildController(
      repository: repository,
      importExportService: importExport,
    );
    await controller.bootstrap();
    await controller.createVault('master-pass');
    await tester.pumpWidget(
      _buildApp(controller, platform: TargetPlatform.windows),
    );
    await tester.pumpAndSettle();

    final dock = find.byKey(const ValueKey('liquid-dock'));
    await tester.tap(find.descendant(of: dock, matching: find.text('导入')));
    await tester.pumpAndSettle();
    final passwordField = find.byWidgetPredicate(
      (widget) =>
          widget is TextField && widget.decoration?.labelText == '导入文件密码',
    );
    await tester.enterText(passwordField, 'import-pass');
    await tester.tap(find.text('预览导入'));
    await tester.pumpAndSettle();
    repository.failNextSave = true;
    await tester.tap(find.text('确认导入'));
    await tester.pumpAndSettle();

    final confirmButton = find.ancestor(
      of: find.text('确认导入'),
      matching: find.byType(FilledButton),
    );
    expect(tester.widget<FilledButton>(confirmButton).onPressed, isNotNull);
    controller.dispose();
  });

  testWidgets('Windows clears master passwords after a successful change',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = _buildController();
    await controller.bootstrap();
    await controller.createVault('master-pass');
    await tester.pumpWidget(
      _buildApp(controller, platform: TargetPlatform.windows),
    );
    await tester.pumpAndSettle();

    final dock = find.byKey(const ValueKey('liquid-dock'));
    await tester.tap(find.descendant(of: dock, matching: find.text('设置')));
    await tester.pumpAndSettle();
    final oldPassword = find.byWidgetPredicate(
      (widget) =>
          widget is TextField && widget.decoration?.labelText == '当前主密码',
    );
    final newPassword = find.byWidgetPredicate(
      (widget) => widget is TextField && widget.decoration?.labelText == '新主密码',
    );
    await tester.enterText(oldPassword, 'master-pass');
    await tester.enterText(newPassword, 'updated-master-pass');
    await tester.tap(find.text('修改主密码'));
    await tester.pumpAndSettle();

    expect(tester.widget<TextField>(oldPassword).controller!.text, isEmpty);
    expect(tester.widget<TextField>(newPassword).controller!.text, isEmpty);
    controller.dispose();
  });

  testWidgets('Android settings opens from the overflow menu', (tester) async {
    final controller = _buildController();
    await controller.bootstrap();
    await controller.createVault('master-pass');

    await tester.pumpWidget(_buildApp(controller));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('android-vault-overflow')));
    await tester.pumpAndSettle();
    expect(find.text('设备配对与同步'), findsOneWidget);
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();

    expect(
        find.byKey(const ValueKey('android-settings-sheet')), findsOneWidget);
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.text('此设置仅在当前应用会话中生效。'), findsOneWidget);

    controller.dispose();
  });

  testWidgets('Android editor obscures passwords and retains input on failure',
      (tester) async {
    final controller = _buildController();
    await controller.bootstrap();
    await controller.createVault('master-pass');

    await tester.pumpWidget(_buildApp(controller));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('android-vault-fab')));
    await tester.pumpAndSettle();

    final passwordField = find.byWidgetPredicate(
      (widget) => widget is TextField && widget.decoration?.labelText == '密码',
    );
    final titleField = find.byWidgetPredicate(
      (widget) => widget is TextField && widget.decoration?.labelText == '名称',
    );
    final totpField = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.decoration?.labelText == 'TOTP 密钥 / URI',
    );
    final passwordWidget = tester.widget<TextField>(passwordField);
    expect(passwordWidget.obscureText, isTrue);
    expect(passwordWidget.enableSuggestions, isFalse);
    expect(passwordWidget.autocorrect, isFalse);

    await tester.enterText(titleField, 'TOTP failure');
    await tester.enterText(totpField, 'not a valid TOTP secret');
    final scrollable = find.descendant(
      of: find.byType(DraggableScrollableSheet),
      matching: find.byType(Scrollable),
    );
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('android-item-save')),
      300,
      scrollable: scrollable.first,
    );
    await tester.tap(find.byKey(const ValueKey('android-item-save')));
    await tester.pumpAndSettle();

    expect(find.byType(BottomSheet), findsOneWidget);
    final retainedTitleField = find.byWidgetPredicate(
      (widget) => widget is TextField && widget.decoration?.labelText == '名称',
    );
    await tester.scrollUntilVisible(
      retainedTitleField,
      -300,
      scrollable: scrollable.first,
    );
    expect(
      tester.widget<TextField>(retainedTitleField).controller!.text,
      'TOTP failure',
    );

    controller.dispose();
  });

  testWidgets('Android entry details obscure password until requested',
      (tester) async {
    final controller = _buildController();
    await controller.bootstrap();
    await controller.createVault('master-pass');
    await controller.addOrUpdateItem(
      title: 'Private entry',
      username: 'alice',
      password: 'do-not-display',
      url: '',
      notes: '',
      tags: const [],
    );

    await tester.pumpWidget(_buildApp(controller));
    await tester.pumpAndSettle();
    final item = controller.vaultData.activeItems.single;
    await tester.tap(find.byKey(ValueKey('android-vault-item-${item.id}')));
    await tester.pumpAndSettle();

    expect(find.byTooltip('显示密码'), findsOneWidget);
    expect(find.text('do-not-display'), findsNothing);

    controller.dispose();
  });

  testWidgets('Android recycle bin restores a deleted entry', (tester) async {
    final controller = _buildController();
    await controller.bootstrap();
    await controller.createVault('master-pass');
    await controller.addOrUpdateItem(
      title: 'Restore me',
      username: 'alice',
      password: 'secret',
      url: '',
      notes: '',
      tags: const [],
    );
    final item = controller.vaultData.activeItems.single;
    await controller.deleteItem(item.id);

    await tester.pumpWidget(_buildApp(controller));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('android-vault-overflow')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('回收站'));
    await tester.pumpAndSettle();
    expect(find.text('Restore me'), findsOneWidget);

    await tester.tap(find.byTooltip('恢复 Restore me'));
    await tester.pumpAndSettle();
    expect(controller.vaultData.deletedItems, isEmpty);
    expect(controller.vaultData.activeItems.single.title, 'Restore me');

    controller.dispose();
  });
}

Widget _buildApp(
  VaultController controller, {
  TargetPlatform platform = TargetPlatform.android,
}) {
  return MaterialApp(
    theme: ThemeData(useMaterial3: true, platform: platform),
    home: HomePage(controller: controller),
  );
}

VaultController _buildController({
  CryptoService? cryptoService,
  VaultRepository? repository,
  ImportExportService? importExportService,
}) {
  return VaultController(
    repository: repository ?? _MemoryVaultRepository(),
    cryptoService: cryptoService ?? _FastCryptoService(),
    importExportService: importExportService ?? _NoopImportExportService(),
    deviceKeyStore: _MemoryDeviceKeyStore(),
    passwordGeneratorService: PasswordGeneratorService(random: Random(1)),
    clipboardService: _MemoryClipboardService(),
  );
}

class _SlowCryptoService extends _FastCryptoService {
  _SlowCryptoService({required this.delay});

  final Duration delay;

  @override
  Future<EncryptedVaultDocument> createVault({
    required String password,
    VaultData? vaultData,
  }) async {
    await Future<void>.delayed(delay);
    return super.createVault(password: password, vaultData: vaultData);
  }
}

class _FastCryptoService extends CryptoService {
  @override
  Future<Uint8List> deriveKekBytes(String password, KdfConfig kdf) async {
    final source = utf8.encode(password);
    final result = Uint8List(32);
    for (var i = 0; i < result.length; i++) {
      result[i] = source[i % source.length];
    }
    return result;
  }
}

class _MemoryVaultRepository extends VaultRepository {
  _MemoryVaultRepository({this.initialLoadResult});

  final VaultLoadResult? initialLoadResult;
  EncryptedVaultDocument? document;
  bool failNextSave = false;

  @override
  Future<bool> exists() async => document != null;

  @override
  Future<VaultLoadResult> inspect() async =>
      initialLoadResult ??
      (document == null
          ? const VaultLoadResult(state: VaultStorageState.absent)
          : VaultLoadResult(
              state: VaultStorageState.available,
              document: document,
              rawBytes: document!.encode(),
            ));

  @override
  Future<EncryptedVaultDocument?> load() async => document;

  @override
  Future<Uint8List?> loadRaw() async => document?.encode();

  @override
  Future<void> save(EncryptedVaultDocument next) async {
    if (failNextSave) {
      failNextSave = false;
      throw FileSystemException('Synthetic save failure');
    }
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
  Future<bool> hasWrappedDekCache() async => storedBytes != null;

  @override
  Future<Uint8List?> readWrappedDek() async => storedBytes;

  @override
  Future<void> storeWrappedDek(Uint8List wrappedDekBytes) async {
    storedBytes = Uint8List.fromList(wrappedDekBytes);
  }
}

class _MemoryImportExportService extends ImportExportService {
  Uint8List? importBytes;

  @override
  Future<String?> pickImportPath() async => 'memory-import.pwv';

  @override
  Future<Uint8List> readFile(String path) async => importBytes!;
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
