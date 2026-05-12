import 'dart:convert';
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

  testWidgets('unlocked view shows search and liquid dock actions',
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

    expect(find.byIcon(Icons.search_rounded), findsOneWidget);
    expect(find.byIcon(Icons.add_circle_outline_rounded), findsOneWidget);
    expect(find.byTooltip('排序方式'), findsOneWidget);
    expect(find.byKey(const ValueKey('vault-toolbar')), findsOneWidget);
    expect(find.byKey(const ValueKey('liquid-dock')), findsOneWidget);

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
    expect(find.byKey(const ValueKey('liquid-dock')), findsOneWidget);
    expect(find.byIcon(Icons.search_rounded), findsOneWidget);
    expect(find.byKey(const ValueKey('vault-list')), findsOneWidget);

    await tester.drag(find.byType(ListView).first, const Offset(0, -260));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 20));

    expect(find.byKey(const ValueKey('liquid-dock')), findsOneWidget);
    expect(find.byIcon(Icons.search_rounded), findsOneWidget);
    expect(find.byKey(const ValueKey('vault-list')), findsOneWidget);

    controller.dispose();
  });

  testWidgets('search focus hides dock on mobile but keeps dock on windows',
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
    await tester.tap(find.byType(TextField).first);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('liquid-dock-hidden')), findsOneWidget);

    await tester.pumpWidget(
      _buildApp(controller, platform: TargetPlatform.windows),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(TextField).first);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('liquid-dock')), findsOneWidget);

    controller.dispose();
  });

  testWidgets('settings action switches to settings page', (tester) async {
    final controller = _buildController();
    await controller.bootstrap();
    await controller.createVault('master-pass');

    await tester.pumpWidget(_buildApp(controller));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.settings_rounded));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('vault-page-settings')), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);

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

VaultController _buildController({CryptoService? cryptoService}) {
  return VaultController(
    repository: _MemoryVaultRepository(),
    cryptoService: cryptoService ?? _FastCryptoService(),
    importExportService: _NoopImportExportService(),
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
  Future<bool> hasWrappedDekCache() async => storedBytes != null;

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
