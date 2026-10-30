import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:cipherbook/services/crypto_service.dart';
import 'package:cipherbook/services/lan_sync_service.dart';
import 'package:cipherbook/services/lan_pairing_store.dart';

void main() {
  test('upload requires authorization and confirms only a successful merge',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('cipherbook-upload-');
    addTearDown(() => directory.delete(recursive: true));
    final document =
        await CryptoService().createVault(password: 'sync-password');
    final service =
        LanSyncService(pairingStore: LanPairingStore(directory: directory));
    var merged = 0;
    var rejectMerge = false;
    final host = await service.startHost(
      documentBytes: document.encode(),
      onMerge: (bytes) async {
        if (rejectMerge) throw StateError('Storage unavailable');
        expect(bytes, document.encode());
        merged++;
      },
    );
    addTearDown(host.close);
    final peer = LanSyncPeer(
        address: '127.0.0.1',
        port: host.port,
        deviceName: host.deviceName,
        vaultId: host.vaultId,
        revision: host.revision);
    await expectLater(
        service.uploadMerged(
            peer: peer,
            accessToken: 'invalid-token',
            documentBytes: document.encode()),
        throwsStateError);
    expect(merged, 0);
    await service.uploadMerged(
        peer: peer,
        accessToken: host.accessToken,
        documentBytes: document.encode());
    expect(merged, 1);
    rejectMerge = true;
    await expectLater(
        service.uploadMerged(
            peer: peer,
            accessToken: host.accessToken,
            documentBytes: document.encode()),
        throwsStateError);
    expect(merged, 1);
  });

  test('an authorized download registers the requesting device on the host',
      () async {
    final crypto = CryptoService();
    final document = await crypto.createVault(password: 'sync-password');
    final hostDirectory = await Directory.systemTemp.createTemp(
      'cipherbook-pairing-test-',
    );
    final clientDirectory = await Directory.systemTemp.createTemp(
      'cipherbook-pairing-client-test-',
    );
    addTearDown(() => hostDirectory.delete(recursive: true));
    addTearDown(() => clientDirectory.delete(recursive: true));
    final hostStore = LanPairingStore(directory: hostDirectory);
    final service = LanSyncService(pairingStore: hostStore);
    final clientService = LanSyncService(
      pairingStore: LanPairingStore(directory: clientDirectory),
    );
    final clientIdentity = await LanPairingStore(directory: clientDirectory)
        .loadOrCreateIdentity();
    final host = await service.startHost(documentBytes: document.encode());
    addTearDown(host.close);

    await clientService.downloadDetailed(
      peer: LanSyncPeer(
        address: '127.0.0.1',
        port: host.port,
        deviceName: host.deviceName,
        vaultId: host.vaultId,
        revision: host.revision,
      ),
      pairingCode: host.pairingCode,
    );

    final registered = await hostStore.loadPeers();
    expect(registered, hasLength(1));
    expect(registered.single.deviceId, clientIdentity.deviceId);
    expect(registered.single.accessToken, clientIdentity.accessToken);
    expect(registered.single.revision, 0);
  });

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
