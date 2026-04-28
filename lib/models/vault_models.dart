import 'dart:convert';
import 'dart:typed_data';

const int vaultDocumentVersion = 1;
const String vaultKdfAlgorithmArgon2id = 'argon2id';
const int vaultKdfSaltLength = 16;
const int xchacha20NonceLength = 24;
const int poly1305MacLength = 16;

class KdfConfig {
  const KdfConfig({
    required this.memoryKiB,
    required this.iterations,
    required this.parallelism,
    required this.salt,
  });

  final int memoryKiB;
  final int iterations;
  final int parallelism;
  final Uint8List salt;

  Map<String, dynamic> toJson() => {
        'algorithm': vaultKdfAlgorithmArgon2id,
        'memoryKiB': memoryKiB,
        'iterations': iterations,
        'parallelism': parallelism,
        'salt': base64Encode(salt),
      };

  factory KdfConfig.fromJson(Map<String, dynamic> json) {
    final algorithm = _readRequiredString(json, key: 'algorithm');
    if (algorithm != vaultKdfAlgorithmArgon2id) {
      throw FormatException('Unsupported KDF algorithm: $algorithm');
    }
    final memoryKiB = _readPositiveInt(json, key: 'memoryKiB');
    final iterations = _readPositiveInt(json, key: 'iterations');
    final parallelism = _readPositiveInt(json, key: 'parallelism');
    final salt = _readBase64Bytes(json, key: 'salt');
    if (salt.length != vaultKdfSaltLength) {
      throw FormatException(
        'Invalid KDF salt length: ${salt.length}. Expected $vaultKdfSaltLength.',
      );
    }
    return KdfConfig(
      memoryKiB: memoryKiB,
      iterations: iterations,
      parallelism: parallelism,
      salt: salt,
    );
  }
}

class CipherPayload {
  const CipherPayload({
    required this.nonce,
    required this.cipherText,
    required this.mac,
  });

  final Uint8List nonce;
  final Uint8List cipherText;
  final Uint8List mac;

  Map<String, dynamic> toJson() => {
        'nonce': base64Encode(nonce),
        'cipherText': base64Encode(cipherText),
        'mac': base64Encode(mac),
      };

  factory CipherPayload.fromJson(Map<String, dynamic> json) {
    final nonce = _readBase64Bytes(json, key: 'nonce');
    final cipherText = _readBase64Bytes(json, key: 'cipherText');
    final mac = _readBase64Bytes(json, key: 'mac');
    return CipherPayload(
      nonce: nonce,
      cipherText: cipherText,
      mac: mac,
    );
  }
}

class EncryptedVaultDocument {
  const EncryptedVaultDocument({
    required this.version,
    required this.kdf,
    required this.wrappedDek,
    required this.payload,
  });

  final int version;
  final KdfConfig kdf;
  final CipherPayload wrappedDek;
  final CipherPayload payload;

  Map<String, dynamic> toJson() => {
        'version': version,
        'kdf': kdf.toJson(),
        'wrappedDek': wrappedDek.toJson(),
        'payload': payload.toJson(),
      };

  factory EncryptedVaultDocument.fromJson(Map<String, dynamic> json) {
    final document = EncryptedVaultDocument(
      version: _readRequiredInt(json, key: 'version'),
      kdf: KdfConfig.fromJson(_readRequiredMap(json, key: 'kdf')),
      wrappedDek:
          CipherPayload.fromJson(_readRequiredMap(json, key: 'wrappedDek')),
      payload: CipherPayload.fromJson(_readRequiredMap(json, key: 'payload')),
    );
    document._validate();
    return document;
  }

  Uint8List encode() => Uint8List.fromList(utf8.encode(jsonEncode(toJson())));

  factory EncryptedVaultDocument.decode(Uint8List bytes) =>
      EncryptedVaultDocument.fromJson(
        jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>,
      );

  void _validate() {
    if (version != vaultDocumentVersion) {
      throw FormatException(
        'Unsupported vault document version: $version. '
        'Expected $vaultDocumentVersion.',
      );
    }
    _validatePayload(wrappedDek, fieldName: 'wrappedDek');
    _validatePayload(payload, fieldName: 'payload');
  }

  void _validatePayload(
    CipherPayload payload, {
    required String fieldName,
  }) {
    if (payload.nonce.length != xchacha20NonceLength) {
      throw FormatException(
        'Invalid $fieldName nonce length: ${payload.nonce.length}. '
        'Expected $xchacha20NonceLength.',
      );
    }
    if (payload.mac.length != poly1305MacLength) {
      throw FormatException(
        'Invalid $fieldName mac length: ${payload.mac.length}. '
        'Expected $poly1305MacLength.',
      );
    }
    if (payload.cipherText.isEmpty) {
      throw FormatException('Invalid $fieldName ciphertext: empty.');
    }
  }
}

class VaultItem {
  const VaultItem({
    required this.id,
    required this.title,
    required this.username,
    required this.password,
    required this.url,
    required this.notes,
    required this.tags,
    required this.createdAt,
    required this.updatedAt,
    this.totpSecret,
    this.deletedAt,
  });

  final String id;
  final String title;
  final String username;
  final String password;
  final String url;
  final String notes;
  final List<String> tags;
  final String? totpSecret;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  bool get isDeleted => deletedAt != null;

  VaultItem copyWith({
    String? id,
    String? title,
    String? username,
    String? password,
    String? url,
    String? notes,
    List<String>? tags,
    Object? totpSecret = _unset,
    DateTime? createdAt,
    DateTime? updatedAt,
    Object? deletedAt = _unset,
  }) {
    return VaultItem(
      id: id ?? this.id,
      title: title ?? this.title,
      username: username ?? this.username,
      password: password ?? this.password,
      url: url ?? this.url,
      notes: notes ?? this.notes,
      tags: tags ?? this.tags,
      totpSecret: identical(totpSecret, _unset)
          ? this.totpSecret
          : totpSecret as String?,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: identical(deletedAt, _unset)
          ? this.deletedAt
          : deletedAt as DateTime?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'username': username,
        'password': password,
        'url': url,
        'notes': notes,
        'tags': tags,
        'totpSecret': totpSecret,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'updatedAt': updatedAt.toUtc().toIso8601String(),
        'deletedAt': deletedAt?.toUtc().toIso8601String(),
      };

  factory VaultItem.fromJson(Map<String, dynamic> json) => VaultItem(
        id: json['id'] as String,
        title: json['title'] as String? ?? '',
        username: json['username'] as String? ?? '',
        password: json['password'] as String? ?? '',
        url: json['url'] as String? ?? '',
        notes: json['notes'] as String? ?? '',
        tags: (json['tags'] as List<dynamic>? ?? const [])
            .map((tag) => tag as String)
            .toList(),
        totpSecret: json['totpSecret'] as String?,
        createdAt: DateTime.parse(json['createdAt'] as String).toLocal(),
        updatedAt: DateTime.parse(json['updatedAt'] as String).toLocal(),
        deletedAt: json['deletedAt'] == null
            ? null
            : DateTime.parse(json['deletedAt'] as String).toLocal(),
      );
}

class VaultData {
  const VaultData({
    required this.items,
    required this.updatedAt,
  });

  final List<VaultItem> items;
  final DateTime updatedAt;

  static VaultData empty() => VaultData(
        items: const [],
        updatedAt: DateTime.now(),
      );

  Map<String, dynamic> toJson() => {
        'items': items.map((item) => item.toJson()).toList(),
        'updatedAt': updatedAt.toUtc().toIso8601String(),
      };

  factory VaultData.fromJson(Map<String, dynamic> json) => VaultData(
        items: (json['items'] as List<dynamic>? ?? const [])
            .map((item) => VaultItem.fromJson(item as Map<String, dynamic>))
            .toList(),
        updatedAt: json['updatedAt'] == null
            ? DateTime.now()
            : DateTime.parse(json['updatedAt'] as String).toLocal(),
      );

  List<VaultItem> get activeItems => items
      .where((item) => !item.isDeleted)
      .toList()
    ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));

  VaultData upsert(VaultItem item) {
    final nextItems = [
      for (final existing in items)
        if (existing.id != item.id) existing,
      item,
    ];
    return copyWith(items: nextItems, updatedAt: item.updatedAt);
  }

  VaultData markDeleted(String id, DateTime deletedAt) {
    final nextItems = items.map((item) {
      if (item.id != id) {
        return item;
      }
      return item.copyWith(
        deletedAt: deletedAt,
        updatedAt: deletedAt,
      );
    }).toList();
    return copyWith(items: nextItems, updatedAt: deletedAt);
  }

  VaultData merge(VaultData incoming) {
    final byId = <String, VaultItem>{
      for (final item in items) item.id: item,
    };
    for (final incomingItem in incoming.items) {
      final current = byId[incomingItem.id];
      if (current == null ||
          incomingItem.updatedAt.isAfter(current.updatedAt)) {
        byId[incomingItem.id] = incomingItem;
      }
    }
    final mergedItems = byId.values.toList();
    final mergedUpdatedAt = [
      updatedAt,
      incoming.updatedAt,
      ...mergedItems.map((item) => item.updatedAt),
    ].reduce((a, b) => a.isAfter(b) ? a : b);
    return VaultData(items: mergedItems, updatedAt: mergedUpdatedAt);
  }

  VaultData copyWith({
    List<VaultItem>? items,
    DateTime? updatedAt,
  }) {
    return VaultData(
      items: items ?? this.items,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

enum ImportChangeKind {
  newItem,
  updatedItem,
  deletedItem,
  unchangedItem,
}

class ImportChangeDetail {
  const ImportChangeDetail({
    required this.id,
    required this.title,
    required this.kind,
    required this.incomingUpdatedAt,
    this.localUpdatedAt,
  });

  final String id;
  final String title;
  final ImportChangeKind kind;
  final DateTime incomingUpdatedAt;
  final DateTime? localUpdatedAt;
}

class ImportMergeSummary {
  const ImportMergeSummary({
    required this.incomingItems,
    required this.newItems,
    required this.updatedItems,
    required this.deletedItems,
    required this.unchangedItems,
    required this.replacesLocalVault,
    required this.details,
  });

  final int incomingItems;
  final int newItems;
  final int updatedItems;
  final int deletedItems;
  final int unchangedItems;
  final bool replacesLocalVault;
  final List<ImportChangeDetail> details;
}

const Object _unset = Object();

int _readRequiredInt(Map<String, dynamic> json, {required String key}) {
  final value = json[key];
  if (value is int) {
    return value;
  }
  throw FormatException('Invalid or missing integer field: $key');
}

int _readPositiveInt(Map<String, dynamic> json, {required String key}) {
  final value = _readRequiredInt(json, key: key);
  if (value > 0) {
    return value;
  }
  throw FormatException('Invalid non-positive integer field: $key');
}

String _readRequiredString(Map<String, dynamic> json, {required String key}) {
  final value = json[key];
  if (value is String && value.isNotEmpty) {
    return value;
  }
  throw FormatException('Invalid or missing string field: $key');
}

Map<String, dynamic> _readRequiredMap(
  Map<String, dynamic> json, {
  required String key,
}) {
  final value = json[key];
  if (value is Map<String, dynamic>) {
    return value;
  }
  throw FormatException('Invalid or missing object field: $key');
}

Uint8List _readBase64Bytes(Map<String, dynamic> json, {required String key}) {
  final encoded = _readRequiredString(json, key: key);
  try {
    return Uint8List.fromList(base64Decode(encoded));
  } on FormatException {
    throw FormatException('Invalid base64 payload in field: $key');
  }
}
