import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:cipherbook/models/vault_models.dart';
import 'package:cipherbook/services/crypto_service.dart';

void main() {
  test('encrypted vault document roundtrip keeps schema fields', () async {
    final document = await CryptoService().createVault(password: 'master-pass');
    final decoded = EncryptedVaultDocument.decode(document.encode());

    expect(decoded.version, vaultDocumentVersion);
    expect(decoded.kdf.salt.length, vaultKdfSaltLength);
    expect(decoded.wrappedDek.nonce.length, xchacha20NonceLength);
    expect(decoded.wrappedDek.mac.length, poly1305MacLength);
    expect(decoded.payload.nonce.length, xchacha20NonceLength);
    expect(decoded.payload.mac.length, poly1305MacLength);
    expect(decoded.payload.cipherText, isNotEmpty);
  });

  test('encrypted vault document rejects unsupported version', () async {
    final document = await CryptoService().createVault(password: 'master-pass');
    final map = document.toJson();
    map['version'] = 999;

    expect(
      () => EncryptedVaultDocument.decode(_encodeJson(map)),
      throwsA(isA<FormatException>()),
    );
  });

  test('encrypted vault document rejects unsupported KDF algorithm', () async {
    final document = await CryptoService().createVault(password: 'master-pass');
    final map = document.toJson();
    (map['kdf'] as Map<String, dynamic>)['algorithm'] = 'pbkdf2';

    expect(
      () => EncryptedVaultDocument.decode(_encodeJson(map)),
      throwsA(isA<FormatException>()),
    );
  });

  test('encrypted vault document rejects invalid nonce length', () async {
    final document = await CryptoService().createVault(password: 'master-pass');
    final map = document.toJson();
    (map['payload'] as Map<String, dynamic>)['nonce'] =
        base64Encode(Uint8List(12));

    expect(
      () => EncryptedVaultDocument.decode(_encodeJson(map)),
      throwsA(isA<FormatException>()),
    );
  });

  test('vault data can restore and permanently remove soft-deleted items', () {
    final createdAt = DateTime.utc(2026, 1, 1);
    final item = VaultItem(
      id: 'recycle-me',
      title: 'Recycle me',
      username: '',
      password: '',
      url: '',
      notes: '',
      tags: const [],
      createdAt: createdAt,
      updatedAt: createdAt,
    );
    final deleted = VaultData(items: [item], updatedAt: createdAt).markDeleted(
      item.id,
      createdAt.add(const Duration(minutes: 1)),
    );

    expect(deleted.activeItems, isEmpty);
    expect(deleted.deletedItems.single.id, item.id);

    final restored = deleted.restoreItem(
      item.id,
      createdAt.add(const Duration(minutes: 2)),
    );
    expect(restored.activeItems.single.id, item.id);
    expect(restored.deletedItems, isEmpty);

    final removed = deleted.removePermanently(
      item.id,
      createdAt.add(const Duration(minutes: 3)),
    );
    expect(removed.items, isEmpty);
    expect(removed.updatedAt, createdAt.add(const Duration(minutes: 3)));
  });
}

Uint8List _encodeJson(Map<String, dynamic> map) =>
    Uint8List.fromList(utf8.encode(jsonEncode(map)));
