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
    )..bootstrap();
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
      themeMode: ThemeMode.light,
      theme: _buildTheme(),
      home: HomePage(controller: _controller),
    );
  }
}

ThemeData _buildTheme() {
  const background = Color(0xFFF3EDEF);
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFFB16986),
    brightness: Brightness.light,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: background,
    visualDensity: VisualDensity.standard,
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      foregroundColor: const Color(0xFF20181C),
      elevation: 0,
      centerTitle: false,
      titleTextStyle: const TextStyle(
        color: Color(0xFF20181C),
        fontSize: 21,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.2,
      ),
      iconTheme: const IconThemeData(color: Color(0xFF20181C)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xD9FFFFFF),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0x26A56B82)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: scheme.primary, width: 1.2),
      ),
      labelStyle: const TextStyle(color: Color(0xFF6A5A60)),
      prefixIconColor: const Color(0xFF5F5057),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: const Color(0xFFF7EFF2),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: const Color(0xFF3A2D33),
      contentTextStyle: const TextStyle(color: Colors.white),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      behavior: SnackBarBehavior.floating,
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Color(0xFFF7EFF2),
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
    ),
  );
}
