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
      metadata: _newMetadata(),
    );
  }

  Future<VaultSession> openVault({
    required EncryptedVaultDocument document,
    required String password,
  }) async {
    try {
      final kekBytes = await deriveKekBytes(password, document.kdf);
      return await openVaultWithKek(
        document: document,
        keyEncryptionKey: kekBytes,
      );
    } on VaultUnlockException {
      rethrow;
    } on SecretBoxAuthenticationError {
      throw const VaultUnlockException(
        '解锁失败：密码错误或密码库文件已被修改。',
      );
    } on FormatException {
      throw const VaultUnlockException('密码库文件格式无效。');
    } on Object {
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
        aad: _dekWrapAadFor(document),
      );
      final payloadBytes = await _decryptBytes(
        document.payload,
        SecretKey(dekBytes),
        aad: _vaultPayloadAadFor(document),
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
    } on Object {
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
    VaultMetadata? metadata,
  }) async {
    vaultData.validate();
    kdf.validate();
    final documentMetadata = metadata ?? _newMetadata();
    final aadDocument = EncryptedVaultDocument(
      version: currentVersion,
      kdf: kdf,
      metadata: documentMetadata,
      wrappedDek: _placeholderPayload(),
      payload: _placeholderPayload(),
    );
    final wrappedDek = await _encryptBytes(
      dataEncryptionKey,
      SecretKey(keyEncryptionKey),
      aad: _dekWrapAadFor(aadDocument),
    );
    final payload = await _encryptBytes(
      Uint8List.fromList(utf8.encode(jsonEncode(vaultData.toJson()))),
      SecretKey(dataEncryptionKey),
      aad: _vaultPayloadAadFor(aadDocument),
    );
    return EncryptedVaultDocument(
      version: currentVersion,
      kdf: kdf,
      wrappedDek: wrappedDek,
      payload: payload,
      metadata: documentMetadata,
    );
  }

  Future<EncryptedVaultDocument> rewrapMasterPassword({
    required EncryptedVaultDocument document,
    required String oldPassword,
    required String newPassword,
  }) async {
    final session = await openVault(document: document, password: oldPassword);
    final previous = document.metadata;
    final metadata = VaultMetadata(
      vaultId: previous?.vaultId ?? _newMetadata().vaultId,
      keyGeneration: (previous?.keyGeneration ?? 0) + 1,
      revision: (previous?.revision ?? 0) + 1,
    );
    final kdf = _newKdf();
    final kekBytes = await deriveKekBytes(newPassword, kdf);
    return saveVaultWithKek(
      vaultData: session.vaultData,
      keyEncryptionKey: kekBytes,
      dataEncryptionKey: _randomBytes(_keyLength),
      kdf: kdf,
      metadata: metadata,
    );
  }

  Future<EncryptedVaultDocument> createPasswordProtectedExport({
    required VaultData vaultData,
    required String password,
  }) =>
      createVault(password: password, vaultData: vaultData);

  Future<Uint8List> deriveKekBytes(String password, KdfConfig kdf) async {
    kdf.validate();
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

  KdfConfig _newKdf() => KdfConfig(
        memoryKiB: _argonMemoryKiB,
        iterations: _argonIterations,
        parallelism: _argonParallelism,
        salt: _randomBytes(vaultKdfSaltLength),
      );

  VaultMetadata _newMetadata() => VaultMetadata(
        vaultId: base64UrlEncode(_randomBytes(18)).replaceAll('=', ''),
        keyGeneration: 1,
        revision: 0,
      );

  CipherPayload _placeholderPayload() => CipherPayload(
        nonce: Uint8List(xchacha20NonceLength),
        cipherText: Uint8List.fromList([0]),
        mac: Uint8List(poly1305MacLength),
      );

  String _dekWrapAadFor(EncryptedVaultDocument document) {
    if (document.version == legacyVaultDocumentVersion) {
      return _dekWrapAad;
    }
    final metadata = document.metadata!;
    return '$_dekWrapAad:${metadata.vaultId}:${metadata.keyGeneration}:${metadata.revision}';
  }

  String _vaultPayloadAadFor(EncryptedVaultDocument document) {
    if (document.version == legacyVaultDocumentVersion) {
      return _vaultPayloadAad;
    }
    final metadata = document.metadata!;
    return '$_vaultPayloadAad:${metadata.vaultId}:${metadata.keyGeneration}:${metadata.revision}';
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
