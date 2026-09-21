import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path_provider/path_provider.dart';

class LanPairingIdentity {
  const LanPairingIdentity({required this.deviceId, required this.accessToken});

  final String deviceId;
  final String accessToken;

  Map<String, dynamic> toJson() => {
        'deviceId': deviceId,
        'accessToken': accessToken,
      };

  factory LanPairingIdentity.fromJson(Map<String, dynamic> json) {
    final deviceId = json['deviceId'];
    final accessToken = json['accessToken'];
    if (deviceId is! String ||
        deviceId.length < 8 ||
        accessToken is! String ||
        accessToken.length < 32) {
      throw const FormatException('局域网设备身份记录无效。');
    }
    return LanPairingIdentity(deviceId: deviceId, accessToken: accessToken);
  }
}

class LanPairingRecord {
  const LanPairingRecord({
    required this.deviceId,
    required this.deviceName,
    required this.address,
    required this.port,
    required this.vaultId,
    required this.accessToken,
    required this.revision,
    required this.lastSeen,
  });

  final String deviceId;
  final String deviceName;
  final String address;
  final int port;
  final String vaultId;
  final String accessToken;
  final int revision;
  final DateTime lastSeen;

  Map<String, dynamic> toJson() => {
        'deviceId': deviceId,
        'deviceName': deviceName,
        'address': address,
        'port': port,
        'vaultId': vaultId,
        'accessToken': accessToken,
        'revision': revision,
        'lastSeen': lastSeen.toUtc().toIso8601String(),
      };

  factory LanPairingRecord.fromJson(Map<String, dynamic> json) {
    final deviceId = json['deviceId'];
    final deviceName = json['deviceName'];
    final address = json['address'];
    final port = json['port'];
    final vaultId = json['vaultId'];
    final accessToken = json['accessToken'];
    final revision = json['revision'];
    final lastSeen = json['lastSeen'];
    if (deviceId is! String ||
        deviceId.length < 8 ||
        deviceName is! String ||
        deviceName.isEmpty ||
        address is! String ||
        address.isEmpty ||
        port is! int ||
        port < 1 ||
        port > 65535 ||
        vaultId is! String ||
        vaultId.isEmpty ||
        accessToken is! String ||
        accessToken.length < 32 ||
        revision is! int ||
        revision < 0 ||
        lastSeen is! String) {
      throw const FormatException('局域网配对设备记录无效。');
    }
    return LanPairingRecord(
      deviceId: deviceId,
      deviceName: deviceName,
      address: address,
      port: port,
      vaultId: vaultId,
      accessToken: accessToken,
      revision: revision,
      lastSeen: DateTime.parse(lastSeen).toLocal(),
    );
  }
}

class LanPairingStore {
  LanPairingStore({
    Directory? directory,
    Future<Directory> Function()? directoryProvider,
  })  : _directory = directory,
        _directoryProvider = directoryProvider;

  static final Random _random = Random.secure();
  final Directory? _directory;
  final Future<Directory> Function()? _directoryProvider;

  Future<LanPairingIdentity> loadOrCreateIdentity() async {
    final file = await _file('lan-identity.json');
    try {
      if (await file.exists()) {
        return LanPairingIdentity.fromJson(
          jsonDecode(await file.readAsString()) as Map<String, dynamic>,
        );
      }
    } on Object {
      // A malformed identity is replaced with a fresh one. It contains no
      // vault data; rotating it only requires pairing this device again.
    }
    final identity = LanPairingIdentity(
      deviceId: 'cb-${_token(12)}',
      accessToken: _token(32),
    );
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(identity.toJson()), flush: true);
    return identity;
  }

  Future<List<LanPairingRecord>> loadPeers() async {
    final file = await _file('lan-peers.json');
    if (!await file.exists()) {
      return const [];
    }
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List<dynamic>) {
        return const [];
      }
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(LanPairingRecord.fromJson)
          .toList();
    } on Object {
      return const [];
    }
  }

  Future<void> savePeer(LanPairingRecord record) async {
    final peers = await loadPeers();
    final next = [
      for (final peer in peers)
        if (peer.deviceId != record.deviceId) peer,
      record,
    ];
    final file = await _file('lan-peers.json');
    await file.parent.create(recursive: true);
    await file.writeAsString(
      jsonEncode(next.map((peer) => peer.toJson()).toList()),
      flush: true,
    );
  }

  Future<File> _file(String name) async {
    Directory directory;
    if (_directory != null) {
      directory = _directory;
    } else {
      try {
        directory = await (_directoryProvider?.call() ??
            getApplicationSupportDirectory());
      } on Object {
        directory = Directory(
          '${Directory.systemTemp.path}${Platform.pathSeparator}cipherbook-lan-sync',
        );
      }
    }
    return File('${directory.path}${Platform.pathSeparator}$name');
  }

  String _token(int byteCount) => base64UrlEncode(
        List<int>.generate(byteCount, (_) => _random.nextInt(256)),
      ).replaceAll('=', '');
}
