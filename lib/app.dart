import 'package:flutter/material.dart';

import 'services/crypto_service.dart';
import 'services/device_key_store.dart';
import 'services/import_export_service.dart';
import 'services/password_generator_service.dart';
import 'services/vault_repository.dart';
import 'services/clipboard_service.dart';
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
      title: 'Cipherbook',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1E6F5C),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      home: HomePage(controller: _controller),
    );
  }
}
