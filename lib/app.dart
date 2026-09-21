import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'services/clipboard_service.dart';
import 'services/crypto_service.dart';
import 'services/device_key_store.dart';
import 'services/import_export_service.dart';
import 'services/password_generator_service.dart';
import 'services/vault_repository.dart';
import 'state/vault_controller.dart';
import 'ui/home_page.dart';

class CipherbookApp extends StatefulWidget {
  const CipherbookApp({super.key});

  @override
  State<CipherbookApp> createState() => _CipherbookAppState();
}

class _CipherbookAppState extends State<CipherbookApp> {
  late final VaultController _controller;

  @override
  void initState() {
    super.initState();
    _controller = VaultController(
      repository: VaultRepository(),
      cryptoService: CryptoService(),
      importExportService: ImportExportService(),
      deviceKeyStore: MethodChannelDeviceKeyStore(),
      passwordGeneratorService: PasswordGeneratorService(),
      clipboardService: ClipboardService(),
    );

    _initializeController();
  }

  Future<void> _initializeController() async {
    await _controller.bootstrap();
    const seedDebugVault = bool.fromEnvironment('CIPHERBOOK_SEED_DEBUG_VAULT');
    if (kDebugMode && seedDebugVault && _controller.canCreateVault) {
      await _controller.prepareDebugSession(seedCount: 10);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '密码本',
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [
        Locale('zh', 'CN'),
      ],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      themeMode: defaultTargetPlatform == TargetPlatform.android
          ? ThemeMode.system
          : ThemeMode.light,
      theme: _buildTheme(Brightness.light),
      darkTheme: _buildTheme(Brightness.dark),
      home: HomePage(controller: _controller),
    );
  }
}

ThemeData _buildTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF2563EB),
    brightness: brightness,
  );
  if (defaultTargetPlatform == TargetPlatform.android) {
    final isDark = brightness == Brightness.dark;
    final androidBackground =
        isDark ? const Color(0xFF0F172A) : const Color(0xFFF6F7F9);
    final androidSurface =
        isDark ? const Color(0xFF1E293B) : const Color(0xFFFFFFFF);
    final androidBorder =
        isDark ? const Color(0xFF334155) : const Color(0xFFE4E7EC);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: androidBackground,
      visualDensity: VisualDensity.standard,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: androidBackground,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        color: androidSurface,
        elevation: 0,
        margin: EdgeInsets.zero,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: androidBorder),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: scheme.surfaceTint,
        showDragHandle: true,
      ),
    );
  }

  const background = Color(0xFFF6F7F9);
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: background,
    visualDensity: VisualDensity.standard,
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      foregroundColor: const Color(0xFF101828),
      elevation: 0,
      centerTitle: false,
      titleTextStyle: const TextStyle(
        color: Color(0xFF101828),
        fontSize: 21,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.2,
      ),
      iconTheme: const IconThemeData(color: Color(0xFF20181C)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFFFFFFFF),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFFD9DEE5)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: scheme.primary, width: 1.2),
      ),
      labelStyle: const TextStyle(color: Color(0xFF475467)),
      prefixIconColor: const Color(0xFF667085),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: const Color(0xE8FFFFFF),
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: const Color(0xFF1D2939),
      contentTextStyle: const TextStyle(color: Colors.white),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      behavior: SnackBarBehavior.floating,
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Color(0xE8FFFFFF),
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
    ),
  );
}
