import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../models/vault_models.dart';
import 'crypto_service.dart';
import 'lan_network_service.dart';
import 'lan_pairing_store.dart';

const int lanSyncDiscoveryPort = 45821;
const int lanSyncMaxDocumentBytes = 16 * 1024 * 1024;
const String lanSyncPath = '/cipherbook/sync/v1/download';

class LanSyncPeer {
  const LanSyncPeer({
    required this.address,
    required this.port,
    required this.deviceName,
    required this.vaultId,
    required this.revision,
    this.deviceId,
    this.accessToken,
    this.kdf,
    this.challenge,
  });

  final String address;
  final int port;
  final String deviceName;
  final String vaultId;
  final int revision;
  final String? deviceId;
  final String? accessToken;
  final KdfConfig? kdf;
  final String? challenge;

  String get displayName => '$deviceName ($address:$port)';

  String get key => '$address:$port';

  LanSyncPeer copyWith({
    String? address,
    int? port,
    String? deviceName,
    String? vaultId,
    int? revision,
    String? deviceId,
    String? accessToken,
    KdfConfig? kdf,
    String? challenge,
  }) {
    return LanSyncPeer(
      address: address ?? this.address,
      port: port ?? this.port,
      deviceName: deviceName ?? this.deviceName,
      vaultId: vaultId ?? this.vaultId,
      revision: revision ?? this.revision,
      deviceId: deviceId ?? this.deviceId,
      accessToken: accessToken ?? this.accessToken,
      kdf: kdf ?? this.kdf,
      challenge: challenge ?? this.challenge,
    );
  }
}

class LanSyncHost {
  LanSyncHost._({
    required HttpServer server,
    required RawDatagramSocket? discoverySocket,
    required Uint8List documentBytes,
    required Future<void> Function()? releaseNetworkLock,
    required this.deviceId,
    required this.accessToken,
    required KdfConfig kdf,
    required this.challenge,
    required Uint8List? authorizationKey,
    required this.pairingCode,
    required this.deviceName,
    required this.addresses,
    required String vaultId,
    required int revision,
  })  : _server = server,
        _discoverySocket = discoverySocket,
        _documentBytes = documentBytes,
        _vaultId = vaultId,
        _revision = revision,
        _kdf = kdf,
        _releaseNetworkLock = releaseNetworkLock,
        _authorizationKey = authorizationKey == null
            ? null
            : Uint8List.fromList(authorizationKey);

  final HttpServer _server;
  final RawDatagramSocket? _discoverySocket;
  Uint8List _documentBytes;
  String _vaultId;
  int _revision;
  final Future<void> Function()? _releaseNetworkLock;
  final String deviceId;
  final String accessToken;
  KdfConfig _kdf;
  KdfConfig get kdf => _kdf;
  final String challenge;
  Uint8List? _authorizationKey;

  final String pairingCode;
  final String deviceName;
  final List<String> addresses;
  String get vaultId => _vaultId;
  int get revision => _revision;

  int get port => _server.port;

  void updateDocument(Uint8List documentBytes) {
    if (_closed || documentBytes.length > lanSyncMaxDocumentBytes) {
      return;
    }
    final document = EncryptedVaultDocument.decode(documentBytes);
    final metadata = document.metadata;
    if (metadata == null) {
      return;
    }
    _documentBytes = Uint8List.fromList(documentBytes);
    _vaultId = metadata.vaultId;
    _revision = metadata.revision;
    _kdf = document.kdf;
  }

  void updateAuthorizationKey(Uint8List authorizationKey) {
    if (_closed) {
      return;
    }
    _authorizationKey = Uint8List.fromList(authorizationKey);
  }

  bool _closed = false;

  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    _discoverySocket?.close();
    await _server.close(force: true);
    await _releaseNetworkLock?.call();
  }

  Future<void> handleRequest(HttpRequest request) async {
    if (request.uri.path != lanSyncPath || request.method != 'GET') {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }
    final requestedPairingCode =
        request.headers.value('x-cipherbook-pairing') ?? '';
    final requestedAccessToken =
        request.headers.value('x-cipherbook-device-token') ?? '';
    final pairingAuthorized = _constantTimeEquals(
      requestedPairingCode,
      pairingCode,
    );
    final tokenAuthorized = _constantTimeEquals(
      requestedAccessToken,
      accessToken,
    );
    final passwordProof =
        request.headers.value('x-cipherbook-password-proof') ?? '';
    final passwordAuthorized = await _verifyPasswordProof(passwordProof);
    if (_closed ||
        (!pairingAuthorized && !tokenAuthorized && !passwordAuthorized)) {
      request.response.statusCode = HttpStatus.unauthorized;
      await request.response.close();
      return;
    }

    final response = request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType('application', 'octet-stream')
      ..headers.contentLength = _documentBytes.length
      ..headers.set('x-cipherbook-vault-id', vaultId)
      ..headers.set('x-cipherbook-revision', '$revision')
      ..headers.set('x-cipherbook-device-id', deviceId)
      ..headers.set('x-cipherbook-device-token', accessToken);
    response.add(_documentBytes);
    await response.close();
  }

  Future<bool> _verifyPasswordProof(String proof) async {
    final authorizationKey = _authorizationKey;
    if (authorizationKey == null || proof.isEmpty) {
      return false;
    }
    try {
      final mac = await Hmac.sha256().calculateMac(
        utf8.encode(challenge),
        secretKey: SecretKey(authorizationKey),
      );
      return _constantTimeEquals(proof, base64UrlEncode(mac.bytes));
    } on Object {
      return false;
    }
  }
}

class LanSyncDownloadResult {
  const LanSyncDownloadResult({
    required this.bytes,
    this.deviceId,
    this.accessToken,
    this.revision,
  });

  final Uint8List bytes;
  final String? deviceId;
  final String? accessToken;
  final int? revision;
}

class LanSyncService {
  LanSyncService({
    LanNetworkService? networkService,
    LanPairingStore? pairingStore,
    CryptoService? cryptoService,
  })  : _networkService = networkService ?? LanNetworkService(),
        _pairingStore = pairingStore ?? LanPairingStore(),
        _cryptoService = cryptoService ?? CryptoService();

  static const String _discoveryRequest = 'cipherbook-sync-discover-v1';
  static const String _discoveryOffer = 'cipherbook-sync-offer-v1';
  static const String _pairingAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  static final Random _random = Random.secure();
  final LanNetworkService _networkService;
  final LanPairingStore _pairingStore;
  final CryptoService _cryptoService;

  Future<LanSyncHost> startHost({
    required Uint8List documentBytes,
    String? deviceName,
    Uint8List? authorizationKey,
  }) async {
    if (documentBytes.length > lanSyncMaxDocumentBytes) {
      throw const FormatException('密码库文件超过局域网同步支持的最大大小。');
    }
    final document = EncryptedVaultDocument.decode(documentBytes);
    final metadata = document.metadata;
    if (metadata == null) {
      throw const FormatException('旧版密码库不支持局域网同步。');
    }
    final identity = await _pairingStore.loadOrCreateIdentity();
    final challenge = _newChallenge();

    final server = await HttpServer.bind(
      InternetAddress.anyIPv4,
      0,
      shared: true,
    );
    RawDatagramSocket? discoverySocket;
    var networkLockAcquired = false;
    try {
      discoverySocket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        lanSyncDiscoveryPort,
        reuseAddress: true,
      );
      discoverySocket.broadcastEnabled = true;
      await _networkService.acquireMulticastLock();
      networkLockAcquired = true;
    } on SocketException {
      discoverySocket?.close();
      discoverySocket = null;
    }

    final host = LanSyncHost._(
      server: server,
      discoverySocket: discoverySocket,
      documentBytes: Uint8List.fromList(documentBytes),
      releaseNetworkLock:
          networkLockAcquired ? _networkService.releaseMulticastLock : null,
      deviceId: identity.deviceId,
      accessToken: identity.accessToken,
      kdf: document.kdf,
      challenge: challenge,
      authorizationKey: authorizationKey,
      pairingCode: _newPairingCode(),
      deviceName: deviceName?.trim().isNotEmpty == true
          ? deviceName!.trim()
          : Platform.localHostname,
      addresses: await _localAddresses(),
      vaultId: metadata.vaultId,
      revision: metadata.revision,
    );
    server.listen(host.handleRequest);
    discoverySocket?.listen((event) {
      if (event != RawSocketEvent.read) {
        return;
      }
      final datagram = discoverySocket!.receive();
      if (datagram == null) {
        return;
      }
      final request = _decodeJson(datagram.data);
      if (request?['type'] != _discoveryRequest) {
        return;
      }
      final offer = utf8.encode(
        jsonEncode({
          'type': _discoveryOffer,
          'deviceName': host.deviceName,
          'port': host.port,
          'vaultId': host.vaultId,
          'revision': host.revision,
          'deviceId': host.deviceId,
          'kdf': host.kdf.toJson(),
          'challenge': host.challenge,
        }),
      );
      discoverySocket.send(offer, datagram.address, datagram.port);
    });
    return host;
  }

  Future<List<LanSyncPeer>> discover({
    Duration timeout = const Duration(seconds: 2),
  }) async {
    await _networkService.acquireMulticastLock();
    try {
      return await _discover(timeout);
    } finally {
      await _networkService.releaseMulticastLock();
    }
  }

  Future<List<LanSyncPeer>> _discover(Duration timeout) async {
    final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    socket.broadcastEnabled = true;
    final peers = <String, LanSyncPeer>{};
    final subscription = socket.listen((event) {
      if (event != RawSocketEvent.read) {
        return;
      }
      final datagram = socket.receive();
      if (datagram == null) {
        return;
      }
      final offer = _decodeJson(datagram.data);
      if (offer?['type'] != _discoveryOffer) {
        return;
      }
      final port = offer?['port'];
      final revision = offer?['revision'];
      final deviceName = offer?['deviceName'];
      final vaultId = offer?['vaultId'];
      final deviceId = offer?['deviceId'];
      final rawKdf = offer?['kdf'];
      final challenge = offer?['challenge'];
      KdfConfig? kdf;
      if (rawKdf is Map<String, dynamic>) {
        try {
          kdf = KdfConfig.fromJson(rawKdf);
        } on FormatException {
          return;
        }
      }
      if (port is! int ||
          revision is! int ||
          deviceName is! String ||
          vaultId is! String ||
          deviceId is! String ||
          port < 1 ||
          port > 65535 ||
          vaultId.isEmpty ||
          deviceId.isEmpty ||
          kdf == null ||
          challenge is! String ||
          challenge.isEmpty) {
        return;
      }
      final peer = LanSyncPeer(
        address: datagram.address.address,
        port: port,
        deviceName: deviceName,
        vaultId: vaultId,
        revision: revision,
        deviceId: deviceId,
        kdf: kdf,
        challenge: challenge,
      );
      peers[peer.key] = peer;
    });
    final request = utf8.encode(jsonEncode({'type': _discoveryRequest}));
    final destinations = <String>{
      '255.255.255.255',
      ...await _subnetBroadcastAddresses(),
    };
    for (final destination in destinations) {
      socket.send(
        request,
        InternetAddress(destination),
        lanSyncDiscoveryPort,
      );
    }
    await Future<void>.delayed(timeout);
    await subscription.cancel();
    socket.close();
    return peers.values.toList()
      ..sort((a, b) => a.displayName.compareTo(b.displayName));
  }

  Future<Uint8List> download({
    required LanSyncPeer peer,
    required String pairingCode,
  }) async =>
      (await downloadDetailed(
        peer: peer,
        pairingCode: pairingCode,
      ))
          .bytes;

  Future<LanSyncDownloadResult> downloadDetailed({
    required LanSyncPeer peer,
    String? pairingCode,
    String? accessToken,
    String? sharedPassword,
  }) async {
    final normalizedCode = pairingCode?.trim().toUpperCase();
    final normalizedToken = accessToken?.trim();
    final canUsePasswordProof = sharedPassword?.trim().isNotEmpty == true &&
        peer.kdf != null &&
        peer.challenge?.isNotEmpty == true;
    if ((normalizedCode == null || normalizedCode.length < 6) &&
        (normalizedToken == null || normalizedToken.length < 32) &&
        !canUsePasswordProof) {
      throw ArgumentError('配对码无效。');
    }
    final client = HttpClient();
    try {
      final request = await client.get(peer.address, peer.port, lanSyncPath);
      if (normalizedCode != null && normalizedCode.isNotEmpty) {
        request.headers.set('x-cipherbook-pairing', normalizedCode);
      }
      if (normalizedToken != null && normalizedToken.isNotEmpty) {
        request.headers.set('x-cipherbook-device-token', normalizedToken);
      }
      if (canUsePasswordProof) {
        final key = await _cryptoService.deriveKekBytes(
          sharedPassword!.trim(),
          peer.kdf!,
        );
        final mac = await Hmac.sha256().calculateMac(
          utf8.encode(peer.challenge!),
          secretKey: SecretKey(key),
        );
        request.headers.set(
          'x-cipherbook-password-proof',
          base64UrlEncode(mac.bytes),
        );
      }
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        throw StateError(
          response.statusCode == HttpStatus.unauthorized
              ? '配对码错误或分享已关闭。'
              : '局域网同步请求失败（${response.statusCode}）。',
        );
      }
      final bytes = <int>[];
      await for (final chunk in response) {
        if (bytes.length + chunk.length > lanSyncMaxDocumentBytes) {
          throw const FormatException('局域网同步文件超过支持的最大大小。');
        }
        bytes.addAll(chunk);
      }
      final document = EncryptedVaultDocument.decode(Uint8List.fromList(bytes));
      if (document.metadata?.vaultId != peer.vaultId) {
        throw const FormatException('局域网设备返回的密码库身份不匹配。');
      }
      return LanSyncDownloadResult(
        bytes: Uint8List.fromList(bytes),
        deviceId: response.headers.value('x-cipherbook-device-id'),
        accessToken: response.headers.value('x-cipherbook-device-token'),
        revision: int.tryParse(
          response.headers.value('x-cipherbook-revision') ?? '',
        ),
      );
    } finally {
      client.close(force: true);
    }
  }

  String _newPairingCode() => List.generate(
        8,
        (_) => _pairingAlphabet[_random.nextInt(_pairingAlphabet.length)],
      ).join();

  String _newChallenge() => base64UrlEncode(
        List<int>.generate(24, (_) => _random.nextInt(256)),
      ).replaceAll('=', '');

  Future<List<String>> _localAddresses() async {
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );
      return interfaces
          .expand((networkInterface) => networkInterface.addresses)
          .map((address) => address.address)
          .where((address) => address.isNotEmpty)
          .toSet()
          .toList();
    } on Object {
      return const [];
    }
  }

  Future<List<String>> _subnetBroadcastAddresses() async {
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );
      final broadcasts = <String>{};
      for (final networkInterface in interfaces) {
        for (final address in networkInterface.addresses) {
          final octets = address.address.split('.');
          if (octets.length == 4 &&
              octets.every((octet) => int.tryParse(octet) != null)) {
            broadcasts.add('${octets[0]}.${octets[1]}.${octets[2]}.255');
          }
        }
      }
      return broadcasts.toList();
    } on Object {
      return const [];
    }
  }

  Map<String, dynamic>? _decodeJson(List<int> bytes) {
    try {
      final value = jsonDecode(utf8.decode(bytes));
      return value is Map<String, dynamic> ? value : null;
    } on Object {
      return null;
    }
  }
}

bool _constantTimeEquals(String first, String second) {
  final firstBytes = utf8.encode(first);
  final secondBytes = utf8.encode(second);
  var difference = firstBytes.length ^ secondBytes.length;
  final maxLength = max(firstBytes.length, secondBytes.length);
  for (var index = 0; index < maxLength; index++) {
    final firstByte = index < firstBytes.length ? firstBytes[index] : 0;
    final secondByte = index < secondBytes.length ? secondBytes[index] : 0;
    difference |= firstByte ^ secondByte;
  }
  return difference == 0;
}
