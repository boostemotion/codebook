import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:cipherbook/models/vault_models.dart';
import 'package:cipherbook/services/crypto_service.dart';

void main() {
  test('creates and opens a vault', () async {
    final cryptoService = CryptoService();
    final vault = VaultData(
      items: [
        VaultItem(
          id: '1',
          title: 'Mail',
          username: 'user@example.com',
          password: 'secret',
          url: 'https://example.com',
          notes: 'primary account',
          tags: const ['mail'],
          createdAt: DateTime(2026, 1, 1),
          updatedAt: DateTime(2026, 1, 1),
        ),
      ],
      updatedAt: DateTime(2026, 1, 1),
    );

    final document = await cryptoService.createVault(
      password: 'correct horse battery staple',
      vaultData: vault,
    );
    final session = await cryptoService.openVault(
      document: document,
      password: 'correct horse battery staple',
    );

    expect(session.vaultData.activeItems.single.title, 'Mail');
  });

  test('rejects invalid password', () async {
    final cryptoService = CryptoService();
    final document = await cryptoService.createVault(password: 'right');

    await expectLater(
      cryptoService.openVault(document: document, password: 'wrong'),
      throwsA(isA<VaultUnlockException>()),
    );
  });

  test('rewraps vault with a new master password', () async {
    final cryptoService = CryptoService();
    final original = await cryptoService.createVault(
      password: 'old-pass',
      vaultData: VaultData(
        items: [
          VaultItem(
            id: '1',
            title: 'Forum',
            username: 'user',
            password: 'secret',
            url: '',
            notes: '',
            tags: const [],
            createdAt: DateTime(2026, 1, 1),
            updatedAt: DateTime(2026, 1, 1),
          ),
        ],
        updatedAt: DateTime(2026, 1, 1),
      ),
    );

    final rewrapped = await cryptoService.rewrapMasterPassword(
      document: original,
      oldPassword: 'old-pass',
      newPassword: 'new-pass',
    );
    final session = await cryptoService.openVault(
      document: rewrapped,
      password: 'new-pass',
    );

    expect(session.vaultData.activeItems.single.title, 'Forum');
    await expectLater(
      cryptoService.openVault(document: rewrapped, password: 'old-pass'),
      throwsA(isA<VaultUnlockException>()),
    );
  });

  test('rejects KDF settings outside conservative Argon2 bounds', () {
    for (final memoryKiB in [
      minVaultKdfMemoryKiB - 1,
      256 * 1024,
    ]) {
      expect(
        () => KdfConfig.fromJson({
          'algorithm': vaultKdfAlgorithmArgon2id,
          'memoryKiB': memoryKiB,
          'iterations': 3,
          'parallelism': 1,
          'salt': 'AAAAAAAAAAAAAAAAAAAAAA==',
        }),
        throwsA(isA<FormatException>()),
      );
    }
  });

  test('rejects direct out-of-bounds KDFs before deriving a key', () async {
    final cryptoService = CryptoService();

    await expectLater(
      cryptoService.deriveKekBytes(
        'test-password',
        KdfConfig(
          memoryKiB: minVaultKdfMemoryKiB - 1,
          iterations: 3,
          parallelism: 1,
          salt: Uint8List(vaultKdfSaltLength),
        ),
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('rekeying rejects an old wrapped DEK with the new payload', () async {
    final cryptoService = CryptoService();
    final original = await cryptoService.createVault(password: 'old-pass');
    final rekeyed = await cryptoService.rewrapMasterPassword(
      document: original,
      oldPassword: 'old-pass',
      newPassword: 'new-pass',
    );
    final mixed = EncryptedVaultDocument(
      version: rekeyed.version,
      kdf: original.kdf,
      wrappedDek: original.wrappedDek,
      payload: rekeyed.payload,
      metadata: rekeyed.metadata,
    );

    await expectLater(
      cryptoService.openVault(document: mixed, password: 'old-pass'),
      throwsA(isA<VaultUnlockException>()),
    );
  });

  test('password-protected export has an independent DEK', () async {
    final cryptoService = CryptoService();
    final original = await cryptoService.createVault(password: 'master-pass');
    final session = await cryptoService.openVault(
      document: original,
      password: 'master-pass',
    );
    final exported = await cryptoService.createPasswordProtectedExport(
      vaultData: session.vaultData,
      password: 'export-pass',
    );
    final mixed = EncryptedVaultDocument(
      version: exported.version,
      kdf: original.kdf,
      wrappedDek: original.wrappedDek,
      payload: exported.payload,
      metadata: exported.metadata,
    );

    await expectLater(
      cryptoService.openVault(document: mixed, password: 'master-pass'),
      throwsA(isA<VaultUnlockException>()),
    );
  });

  test('opens a vault with a cached key-encryption key', () async {
    final cryptoService = CryptoService();
    final document = await cryptoService.createVault(
      password: 'master-pass',
      vaultData: VaultData(
        items: [
          VaultItem(
            id: '2',
            title: 'Bank',
            username: 'cashier',
            password: 'vault-pass',
            url: '',
            notes: '',
            tags: const [],
            createdAt: DateTime(2026, 1, 1),
            updatedAt: DateTime(2026, 1, 1),
          ),
        ],
        updatedAt: DateTime(2026, 1, 1),
      ),
    );
    final passwordSession = await cryptoService.openVault(
      document: document,
      password: 'master-pass',
    );
    final kekSession = await cryptoService.openVaultWithKek(
      document: document,
      keyEncryptionKey: passwordSession.keyEncryptionKey!,
    );

    expect(kekSession.vaultData.activeItems.single.title, 'Bank');
  });

  test('can re-encrypt the same data under a dedicated export password',
      () async {
    final cryptoService = CryptoService();
    final original = await cryptoService.createVault(
      password: 'master-pass',
      vaultData: VaultData(
        items: [
          VaultItem(
            id: '3',
            title: 'Docs',
            username: 'writer',
            password: 'draft-pass',
            url: '',
            notes: '',
            tags: const [],
            createdAt: DateTime(2026, 1, 1),
            updatedAt: DateTime(2026, 1, 1),
          ),
        ],
        updatedAt: DateTime(2026, 1, 1),
      ),
    );
    final session = await cryptoService.openVault(
      document: original,
      password: 'master-pass',
    );
    final exported = await cryptoService.saveVault(
      vaultData: session.vaultData,
      password: 'export-pass',
      dataEncryptionKey: session.dataEncryptionKey,
    );

    final exportSession = await cryptoService.openVault(
      document: exported,
      password: 'export-pass',
    );

    expect(exportSession.vaultData.activeItems.single.title, 'Docs');
    await expectLater(
      cryptoService.openVault(document: exported, password: 'master-pass'),
      throwsA(isA<VaultUnlockException>()),
    );
  });
}
