import 'dart:convert';
import 'dart:typed_data';

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
        'algorithm': 'argon2id',
        'memoryKiB': memoryKiB,
        'iterations': iterations,
        'parallelism': parallelism,
        'salt': base64Encode(salt),
      };

  factory KdfConfig.fromJson(Map<String, dynamic> json) => KdfConfig(
        memoryKiB: json['memoryKiB'] as int,
        iterations: json['iterations'] as int,
        parallelism: json['parallelism'] as int,
        salt: Uint8List.fromList(base64Decode(json['salt'] as String)),
      );
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

  factory CipherPayload.fromJson(Map<String, dynamic> json) => CipherPayload(
        nonce: Uint8List.fromList(base64Decode(json['nonce'] as String)),
        cipherText:
            Uint8List.fromList(base64Decode(json['cipherText'] as String)),
        mac: Uint8List.fromList(base64Decode(json['mac'] as String)),
      );
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

  factory EncryptedVaultDocument.fromJson(Map<String, dynamic> json) =>
      EncryptedVaultDocument(
        version: json['version'] as int,
        kdf: KdfConfig.fromJson(json['kdf'] as Map<String, dynamic>),
        wrappedDek:
            CipherPayload.fromJson(json['wrappedDek'] as Map<String, dynamic>),
        payload: CipherPayload.fromJson(json['payload'] as Map<String, dynamic>),
      );

  Uint8List encode() => Uint8List.fromList(utf8.encode(jsonEncode(toJson())));

  factory EncryptedVaultDocument.decode(Uint8List bytes) =>
      EncryptedVaultDocument.fromJson(
        jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>,
      );
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

  List<VaultItem> get activeItems =>
      items.where((item) => !item.isDeleted).toList()
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
      if (current == null || incomingItem.updatedAt.isAfter(current.updatedAt)) {
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

const Object _unset = Object();

