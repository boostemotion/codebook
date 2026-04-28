import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../models/vault_models.dart';

class VaultUnlockException implements Exception {
  const VaultUnlockException(this.message);

  final String message;

  @override
  String toString() => message;
}

class CryptoService {
  CryptoService({Cryptography? cryptography})
      : _cryptography = cryptography ?? Cryptography.instance;

  static const int currentVersion = vaultDocumentVersion;
  static const int _keyLength = 32;
  static const int _argonMemoryKiB = 64 * 1024;
  static const int _argonIterations = 3;
  static const int _argonParallelism = 1;
  static const String _dekWrapAad = 'cipherbook:dek-wrap:v1';
  static const String _vaultPayloadAad = 'cipherbook:vault-payload:v1';
  static final Random _random = Random.secure();

  final Cryptography _cryptography;

  Cipher get _cipher => _cryptography.xchacha20Poly1305Aead();

  Future<EncryptedVaultDocument> createVault({
    required String password,
    VaultData? vaultData,
  }) async {
    final salt = _randomBytes(16);
    final dek = _randomBytes(_keyLength);
    final kdf = KdfConfig(
      memoryKiB: _argonMemoryKiB,
      iterations: _argonIterations,
      parallelism: _argonParallelism,
      salt: salt,
    );
    final kekBytes = await deriveKekBytes(password, kdf);
    return saveVaultWithKek(
      vaultData: vaultData ?? VaultData.empty(),
      keyEncryptionKey: kekBytes,
      dataEncryptionKey: dek,
      kdf: kdf,
    );
  }

  Future<VaultSession> openVault({
    required EncryptedVaultDocument document,
    required String password,
  }) async {
    try {
      final kekBytes = await deriveKekBytes(password, document.kdf);
      return openVaultWithKek(
        document: document,
        keyEncryptionKey: kekBytes,
      );
    } on SecretBoxAuthenticationError {
      throw const VaultUnlockException(
        '解锁失败：密码错误或密码库文件已被修改。',
      );
    } on FormatException {
      throw const VaultUnlockException('密码库文件格式无效。');
    }
  }

  Future<VaultSession> openVaultWithKek({
    required EncryptedVaultDocument document,
    required Uint8List keyEncryptionKey,
  }) async {
    try {
      final dekBytes = await _decryptBytes(
        document.wrappedDek,
        SecretKey(keyEncryptionKey),
        aad: _dekWrapAad,
      );
      final payloadBytes = await _decryptBytes(
        document.payload,
        SecretKey(dekBytes),
        aad: _vaultPayloadAad,
      );
      return _sessionFromPayload(
        payloadBytes: payloadBytes,
        dataEncryptionKey: Uint8List.fromList(dekBytes),
        keyEncryptionKey: Uint8List.fromList(keyEncryptionKey),
      );
    } on SecretBoxAuthenticationError {
      throw const VaultUnlockException(
        '解锁失败：密码错误或密码库文件已被修改。',
      );
    } on FormatException {
      throw const VaultUnlockException('密码库文件格式无效。');
    }
  }

  Future<EncryptedVaultDocument> saveVault({
    required VaultData vaultData,
    required String password,
    required Uint8List dataEncryptionKey,
    KdfConfig? kdfOverride,
  }) async {
    final kdf = kdfOverride ??
        KdfConfig(
          memoryKiB: _argonMemoryKiB,
          iterations: _argonIterations,
          parallelism: _argonParallelism,
          salt: _randomBytes(16),
        );
    final kekBytes = await deriveKekBytes(password, kdf);
    return saveVaultWithKek(
      vaultData: vaultData,
      keyEncryptionKey: kekBytes,
      dataEncryptionKey: dataEncryptionKey,
      kdf: kdf,
    );
  }

  Future<EncryptedVaultDocument> saveVaultWithKek({
    required VaultData vaultData,
    required Uint8List keyEncryptionKey,
    required Uint8List dataEncryptionKey,
    required KdfConfig kdf,
  }) async {
    final wrappedDek = await _encryptBytes(
      dataEncryptionKey,
      SecretKey(keyEncryptionKey),
      aad: _dekWrapAad,
    );
    final payload = await _encryptBytes(
      Uint8List.fromList(utf8.encode(jsonEncode(vaultData.toJson()))),
      SecretKey(dataEncryptionKey),
      aad: _vaultPayloadAad,
    );
    return EncryptedVaultDocument(
      version: currentVersion,
      kdf: kdf,
      wrappedDek: wrappedDek,
      payload: payload,
    );
  }

  Future<EncryptedVaultDocument> rewrapMasterPassword({
    required EncryptedVaultDocument document,
    required String oldPassword,
    required String newPassword,
  }) async {
    final session = await openVault(document: document, password: oldPassword);
    return saveVault(
      vaultData: session.vaultData,
      password: newPassword,
      dataEncryptionKey: session.dataEncryptionKey,
      kdfOverride: document.kdf,
    );
  }

  Future<Uint8List> deriveKekBytes(String password, KdfConfig kdf) async {
    final argon = Argon2id(
      memory: kdf.memoryKiB,
      iterations: kdf.iterations,
      parallelism: kdf.parallelism,
      hashLength: _keyLength,
    );
    final secretKey = await argon.deriveKeyFromPassword(
      password: password,
      nonce: kdf.salt,
    );
    return Uint8List.fromList(await secretKey.extractBytes());
  }

  Future<CipherPayload> _encryptBytes(
    List<int> data,
    SecretKey key, {
    required String aad,
  }) async {
    final nonce = _cipher.newNonce();
    final box = await _cipher.encrypt(
      data,
      secretKey: key,
      nonce: nonce,
      aad: utf8.encode(aad),
    );
    return CipherPayload(
      nonce: Uint8List.fromList(box.nonce),
      cipherText: Uint8List.fromList(box.cipherText),
      mac: Uint8List.fromList(box.mac.bytes),
    );
  }

  Future<Uint8List> _decryptBytes(
    CipherPayload payload,
    SecretKey key, {
    required String aad,
  }) async {
    final box = SecretBox(
      payload.cipherText,
      nonce: payload.nonce,
      mac: Mac(payload.mac),
    );
    final bytes = await _cipher.decrypt(
      box,
      secretKey: key,
      aad: utf8.encode(aad),
    );
    return Uint8List.fromList(bytes);
  }

  VaultSession _sessionFromPayload({
    required Uint8List payloadBytes,
    required Uint8List dataEncryptionKey,
    required Uint8List? keyEncryptionKey,
  }) {
    final vaultJson =
        jsonDecode(utf8.decode(payloadBytes)) as Map<String, dynamic>;
    return VaultSession(
      vaultData: VaultData.fromJson(vaultJson),
      dataEncryptionKey: Uint8List.fromList(dataEncryptionKey),
      keyEncryptionKey: keyEncryptionKey == null
          ? null
          : Uint8List.fromList(keyEncryptionKey),
    );
  }

  Uint8List _randomBytes(int length) {
    final bytes = Uint8List(length);
    for (var i = 0; i < length; i++) {
      bytes[i] = _random.nextInt(256);
    }
    return bytes;
  }
}

class VaultSession {
  const VaultSession({
    required this.vaultData,
    required this.dataEncryptionKey,
    required this.keyEncryptionKey,
  });

  final VaultData vaultData;
  final Uint8List dataEncryptionKey;
  final Uint8List? keyEncryptionKey;
}
