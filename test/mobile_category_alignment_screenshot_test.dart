import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cipherbook/models/vault_models.dart';
import 'package:cipherbook/presentation/app/cipherbook_destinations.dart';
import 'package:cipherbook/presentation/app/cipherbook_ui_localizations.dart';
import 'package:cipherbook/presentation/bridge/vault_controller_provider.dart';
import 'package:cipherbook/presentation/shell/cipherbook_navigation.dart';
import 'package:cipherbook/presentation/theme/cipherbook_visual_tokens.dart';
import 'package:cipherbook/services/clipboard_service.dart';
import 'package:cipherbook/services/crypto_service.dart';
import 'package:cipherbook/services/device_key_store.dart';
import 'package:cipherbook/services/import_export_service.dart';
import 'package:cipherbook/services/password_generator_service.dart';
import 'package:cipherbook/services/vault_repository.dart';
import 'package:cipherbook/state/vault_controller.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_ui/prism_ui.dart';
import 'package:prism_shell/prism_shell.dart';

const _captureKey = ValueKey('mobile-category-alignment-capture');
const _screenshotDirectory =
    'docs/design/frontend-v2/mobile-category-alignment/screenshots';
const _screenshotPhase = String.fromEnvironment(
  'ALIGNMENT_SCREENSHOT_PHASE',
  defaultValue: 'final',
);

void main() {
  setUpAll(() async {
    final bytes = await File(r'C:\Windows\Fonts\Deng.ttf').readAsBytes();
    final data = ByteData.sublistView(bytes);
    final loader = FontLoader('Deng')..addFont(Future<ByteData>.value(data));
    await loader.load();
  });

  testWidgets('captures aligned vault and category screenshots', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
    });
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final controller = _buildController();
    addTearDown(controller.dispose);
    await controller.bootstrap();
    await controller.createVault('synthetic-only-password');

    await tester.pumpWidget(
      RepaintBoundary(
        key: _captureKey,
        child: _ScreenshotApp(controller: controller),
      ),
    );
    await tester.pumpAndSettle();

    await _setSize(tester, const Size(375, 812));
    await _showDestination(tester, CipherbookDestinationId.vault);
    expect(find.byKey(const ValueKey('prism-vault-filters')), findsOneWidget);
    final screenshotPrefix = _screenshotPhase == 'before' ? 'before-' : '';
    await _capture('${screenshotPrefix}all-passwords-375.png');

    await _showDestination(tester, CipherbookDestinationId.categories);
    expect(
      find.byKey(const ValueKey('prism-category-workbench')),
      findsOneWidget,
    );
    await _capture('${screenshotPrefix}categories-375.png');

    if (_screenshotPhase == 'final') {
      await _setSize(tester, const Size(1440, 900));
      await _showDestination(tester, CipherbookDestinationId.vault);
      await _capture('all-passwords-1440.png');

      await _showDestination(tester, CipherbookDestinationId.categories);
      await _capture('categories-1440.png');
    }

    await controller.lock();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('vault and category password rows keep the same typography', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(375, 812);
    addTearDown(tester.view.reset);

    final controller = _buildController();
    addTearDown(controller.dispose);
    await controller.bootstrap();
    await controller.createVault('synthetic-only-password');

    await tester.pumpWidget(_ScreenshotApp(controller: controller));
    await tester.pumpAndSettle();
    final item = controller.vaultData.activeItems.first;

    await _showDestination(tester, CipherbookDestinationId.vault);
    final vaultTitleKey = ValueKey('prism-password-title-${item.id}');
    final vaultMetadataKey = ValueKey('prism-password-metadata-${item.id}');
    final vaultTitle = tester.widget<Text>(find.byKey(vaultTitleKey)).style!;
    final vaultMetadata = tester
        .widget<Text>(find.byKey(vaultMetadataKey))
        .style!;
    final vaultRowHeight = tester
        .getSize(find.byKey(ValueKey('prism-vault-entry-${item.id}')))
        .height;

    await _showDestination(tester, CipherbookDestinationId.categories);
    final categoryTitle = tester.widget<Text>(find.byKey(vaultTitleKey)).style!;
    final categoryMetadata = tester
        .widget<Text>(find.byKey(vaultMetadataKey))
        .style!;
    final categoryRowHeight = tester
        .getSize(find.byKey(ValueKey('prism-password-drag-${item.id}')))
        .height;

    expect(categoryTitle.fontSize, vaultTitle.fontSize);
    expect(categoryTitle.fontWeight, vaultTitle.fontWeight);
    expect(categoryTitle.height, vaultTitle.height);
    expect(
      categoryTitle.fontSize! * categoryTitle.height!,
      vaultTitle.fontSize! * vaultTitle.height!,
    );
    expect(vaultTitle.fontSize, 15);
    expect(vaultTitle.fontWeight, FontWeight.w600);
    expect(vaultTitle.height, closeTo(4 / 3, 0.0001));

    expect(categoryMetadata.fontSize, vaultMetadata.fontSize);
    expect(categoryMetadata.fontWeight, vaultMetadata.fontWeight);
    expect(categoryMetadata.height, vaultMetadata.height);
    expect(
      categoryMetadata.fontSize! * categoryMetadata.height!,
      vaultMetadata.fontSize! * vaultMetadata.height!,
    );
    expect(vaultMetadata.fontSize, 13);
    expect(vaultMetadata.fontWeight, FontWeight.w400);
    expect(vaultMetadata.height, closeTo(18 / 13, 0.0001));
    expect(categoryRowHeight, vaultRowHeight);

    await controller.lock();
    await tester.pumpAndSettle();
    debugDefaultTargetPlatformOverride = null;
  });
}

Future<void> _showDestination(WidgetTester tester, String destination) async {
  final shellContext = tester.element(find.byType(ResponsiveShell));
  ProviderScope.containerOf(
    shellContext,
  ).read(currentShellDestinationProvider.notifier).go(destination);
  await tester.pumpAndSettle();
}

Future<void> _setSize(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  await tester.pumpAndSettle();
}

Future<void> _capture(String fileName) async {
  await expectLater(
    find.byKey(_captureKey),
    matchesGoldenFile('../$_screenshotDirectory/$fileName'),
  );
}

class _ScreenshotApp extends StatelessWidget {
  const _ScreenshotApp({required this.controller});

  final VaultController controller;

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      overrides: [
        vaultControllerProvider.overrideWithValue(controller),
        initialShellSettingsProvider.overrideWithValue(
          const ShellSettings(
            themeMode: ThemeMode.dark,
            seedColor: CipherbookVisualTokens.accent,
            liquidGlass: false,
            sidebarExpanded: true,
            floatingNavigationBar: true,
            compactDensity: false,
            fontFamily: 'Deng',
            locale: 'zh_CN',
          ),
        ),
      ],
      child: FrontendShellApp(
        title: 'Cipherbook',
        supportedLocales: const [Locale('zh', 'CN')],
        localizationsDelegates: const [
          CipherbookUiLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        desktopTopInset: 0,
        themeBuilder: cipherbookPrismTheme,
        home: ButtonTheme(
          data: CipherbookVisualTokens.buttonTheme,
          child: Builder(
            builder: (context) => ResponsiveShell(
              initialDestinationId: CipherbookDestinationId.vault,
              destinations: cipherbookDestinationsOf(context),
            ),
          ),
        ),
      ),
    );
  }
}

VaultController _buildController() {
  return VaultController(
    repository: _MemoryVaultRepository(),
    cryptoService: _FastCryptoService(initialVaultData: _syntheticVaultData()),
    importExportService: _NoopImportExportService(),
    deviceKeyStore: _MemoryDeviceKeyStore(),
    passwordGeneratorService: PasswordGeneratorService(random: Random(7)),
    clipboardService: _MemoryClipboardService(),
  );
}

class _FastCryptoService extends CryptoService {
  _FastCryptoService({required this.initialVaultData});

  final VaultData initialVaultData;

  @override
  Future<EncryptedVaultDocument> createVault({
    required String password,
    VaultData? vaultData,
  }) {
    return super.createVault(password: password, vaultData: initialVaultData);
  }

  @override
  Future<Uint8List> deriveKekBytes(String password, KdfConfig kdf) async {
    final source = utf8.encode(password);
    final result = Uint8List(32);
    for (var index = 0; index < result.length; index++) {
      result[index] = source[index % source.length];
    }
    return result;
  }
}

VaultData _syntheticVaultData() {
  final updatedAt = DateTime(2026, 11, 14, 14, 25);
  final categories = [
    VaultCategory(
      id: 'synthetic-category-work',
      name: '工作',
      createdAt: updatedAt,
      updatedAt: updatedAt,
      sortIndex: 0,
    ),
    VaultCategory(
      id: 'synthetic-category-personal',
      name: '个人',
      createdAt: updatedAt,
      updatedAt: updatedAt,
      sortIndex: 1,
    ),
    VaultCategory(
      id: 'synthetic-category-finance',
      name: '财务',
      createdAt: updatedAt,
      updatedAt: updatedAt,
      sortIndex: 2,
    ),
    VaultCategory(
      id: 'synthetic-category-archive',
      name: '归档',
      createdAt: updatedAt,
      updatedAt: updatedAt,
      sortIndex: 3,
    ),
  ];
  final categoryIds = {
    for (final category in categories) category.name: category.id,
  };
  const entries = [
    ('GitHub', 'builder@example.test', '工作'),
    ('云控制台', 'ops@example.test', '工作'),
    ('邮箱', 'hello@example.test', '工作'),
    ('旅行证件', 'travel@example.test', '个人'),
    ('储蓄账户', 'finance@example.test', '财务'),
    ('家庭 NAS', 'home@example.test', null),
    ('待整理服务', 'service@example.test', null),
  ];
  final items = [
    for (final (index, entry) in entries.indexed)
      VaultItem(
        id: 'synthetic-item-$index',
        title: entry.$1,
        username: entry.$2,
        password: 'synthetic-only-$index',
        url: 'https://example.test/$index',
        notes: '',
        tags: const [],
        createdAt: updatedAt,
        updatedAt: updatedAt,
        folder: entry.$3 == null ? '' : categoryIds[entry.$3]!,
      ),
  ];
  return VaultData(items: items, categories: categories, updatedAt: updatedAt);
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

class _MemoryDeviceKeyStore implements DeviceKeyStore {
  Uint8List? storedBytes;

  @override
  Future<void> clear() async {
    storedBytes = null;
  }

  @override
  Future<bool> hasWrappedDekCache() async => storedBytes != null;

  @override
  Future<bool> isSupported() async => false;

  @override
  Future<Uint8List?> readWrappedDek() async => storedBytes;

  @override
  Future<void> storeWrappedDek(Uint8List wrappedDekBytes) async {
    storedBytes = Uint8List.fromList(wrappedDekBytes);
  }
}

class _NoopImportExportService extends ImportExportService {
  @override
  Future<String?> pickImportPath() async => null;

  @override
  Future<Uint8List> readFile(String path) async => Uint8List(0);

  @override
  Future<String?> pickExportPath() async => null;

  @override
  Future<void> writeFile(String path, Uint8List bytes) async {}
}

class _MemoryClipboardService extends ClipboardService {
  @override
  Future<void> copyText(
    String text, {
    Duration clearAfter = const Duration(seconds: 30),
  }) async {}
}
