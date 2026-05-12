import 'dart:io';
import 'dart:typed_data';

import '../lib/models/vault_models.dart';
import '../lib/services/crypto_service.dart';

Future<void> main() async {
  const password = 'debug-only-password';
  final now = DateTime.now();
  final items = List<VaultItem>.generate(10, (index) {
    final i = index + 1;
    final ts = now.subtract(Duration(minutes: 10 - index));
    return VaultItem(
      id: 'seed-$i',
      title: 'Test Account $i',
      username: 'user${1000 + index}@example.com',
      password: 'P@ss-${i}Xy!${200 + index}',
      url: 'https://example${(index % 3) + 1}.com',
      notes: 'Seed item $i',
      tags: ['debug', 'seed${(index % 3) + 1}'],
      createdAt: ts,
      updatedAt: ts,
      deletedAt: null,
    );
  });

  final data = VaultData(items: items, updatedAt: now);
  final crypto = CryptoService();
  final doc = await crypto.createVault(password: password, vaultData: data);

  final appData = Platform.environment['APPDATA'];
  if (appData == null || appData.isEmpty) {
    throw StateError('APPDATA not found');
  }
  final dir = Directory('$appData${Platform.pathSeparator}Cipherbook${Platform.pathSeparator}密码本');
  await dir.create(recursive: true);
  final file = File('${dir.path}${Platform.pathSeparator}vault.pwv');
  await file.writeAsBytes(doc.encode(), flush: true);

  final decoded = EncryptedVaultDocument.decode(Uint8List.fromList(await file.readAsBytes()));
  final session = await crypto.openVault(document: decoded, password: password);
  if (session.vaultData.activeItems.length != 10) {
    throw StateError('Seed verify failed: item count ${session.vaultData.activeItems.length}');
  }

  final localApp = Platform.environment['LOCALAPPDATA'];
  if (localApp != null && localApp.isNotEmpty) {
    final qu = File('$localApp${Platform.pathSeparator}Cipherbook${Platform.pathSeparator}quick_unlock.dpapi');
    if (await qu.exists()) {
      await qu.delete();
    }
  }

  stdout.writeln('seed-ok file=${file.path} count=${session.vaultData.activeItems.length} password=$password');
}
