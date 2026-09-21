import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:cipherbook/services/crypto_service.dart';
import 'package:cipherbook/services/lan_sync_service.dart';

void main() {
  test('serves and downloads an encrypted vault over loopback', () async {
    final crypto = CryptoService();
    final document = await crypto.createVault(password: 'sync-password');
    final service = LanSyncService();
    final host = await service.startHost(
      documentBytes: document.encode(),
      deviceName: 'Test device',
    );
    addTearDown(host.close);

    final peer = LanSyncPeer(
      address: '127.0.0.1',
      port: host.port,
      deviceName: host.deviceName,
      vaultId: host.vaultId,
      revision: host.revision,
    );
    final bytes = await service.download(
      peer: peer,
      pairingCode: host.pairingCode,
    );

    expect(bytes, Uint8List.fromList(document.encode()));
  });

  test('rejects an invalid pairing code', () async {
    final crypto = CryptoService();
    final document = await crypto.createVault(password: 'sync-password');
    final service = LanSyncService();
    final host = await service.startHost(documentBytes: document.encode());
    addTearDown(host.close);

    final peer = LanSyncPeer(
      address: '127.0.0.1',
      port: host.port,
      deviceName: host.deviceName,
      vaultId: host.vaultId,
      revision: host.revision,
    );

    await expectLater(
      service.download(peer: peer, pairingCode: 'WRONGCODE'),
      throwsA(
        predicate<Object>(
          (error) => error.toString().contains('配对码错误'),
        ),
      ),
    );
  });

  test('downloads with a persisted device token after pairing', () async {
    final crypto = CryptoService();
    final document = await crypto.createVault(password: 'sync-password');
    final service = LanSyncService();
    final host = await service.startHost(documentBytes: document.encode());
    addTearDown(host.close);

    final peer = LanSyncPeer(
      address: '127.0.0.1',
      port: host.port,
      deviceName: host.deviceName,
      vaultId: host.vaultId,
      revision: host.revision,
      deviceId: host.deviceId,
    );
    final result = await service.downloadDetailed(
      peer: peer,
      accessToken: host.accessToken,
    );

    expect(result.bytes, Uint8List.fromList(document.encode()));
    expect(result.deviceId, host.deviceId);
    expect(result.accessToken, host.accessToken);
  });

  test('uses the shared master password proof without a pairing code',
      () async {
    final crypto = CryptoService();
    const password = 'sync-password';
    final document = await crypto.createVault(password: password);
    final authorizationKey = await crypto.deriveKekBytes(
      password,
      document.kdf,
    );
    final service = LanSyncService();
    final host = await service.startHost(
      documentBytes: document.encode(),
      authorizationKey: authorizationKey,
    );
    addTearDown(host.close);

    final peer = LanSyncPeer(
      address: '127.0.0.1',
      port: host.port,
      deviceName: host.deviceName,
      vaultId: host.vaultId,
      revision: host.revision,
      deviceId: host.deviceId,
      kdf: host.kdf,
      challenge: host.challenge,
    );
    final result = await service.downloadDetailed(
      peer: peer,
      sharedPassword: password,
    );

    expect(result.bytes, Uint8List.fromList(document.encode()));
  });
}
