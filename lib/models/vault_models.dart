import 'dart:convert';
import 'dart:typed_data';

const int legacyVaultDocumentVersion = 1;
const int vaultDocumentVersion = 2;
const String vaultKdfAlgorithmArgon2id = 'argon2id';
const int vaultKdfSaltLength = 16;
const int xchacha20NonceLength = 24;
const int poly1305MacLength = 16;
const int minVaultKdfMemoryKiB = 16 * 1024;
const int maxVaultKdfMemoryKiB = 128 * 1024;
const int minVaultKdfIterations = 1;
const int maxVaultKdfIterations = 10;
const int minVaultKdfParallelism = 1;
const int maxVaultKdfParallelism = 8;
const int maxVaultCiphertextBytes = 8 * 1024 * 1024;
const int maxVaultItems = 10000;
const int maxVaultTitleLength = 512;
const int maxVaultUsernameLength = 1024;
const int maxVaultPasswordLength = 4096;
const int maxVaultUrlLength = 4096;
const int maxVaultNotesLength = 65536;
const int maxVaultTagCount = 64;
const int maxVaultTagLength = 128;
const int maxVaultCategories = 128;

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
    final config = KdfConfig(
      memoryKiB: memoryKiB,
      iterations: iterations,
      parallelism: parallelism,
      salt: salt,
    );
    config.validate();
    return config;
  }

  void validate() {
    if (memoryKiB < minVaultKdfMemoryKiB || memoryKiB > maxVaultKdfMemoryKiB) {
      throw FormatException('KDF memory is outside supported bounds.');
    }
    if (iterations < minVaultKdfIterations ||
        iterations > maxVaultKdfIterations) {
      throw FormatException('KDF iterations are outside supported bounds.');
    }
    if (parallelism < minVaultKdfParallelism ||
        parallelism > maxVaultKdfParallelism) {
      throw FormatException('KDF parallelism is outside supported bounds.');
    }
    if (salt.length != vaultKdfSaltLength) {
      throw FormatException(
        'Invalid KDF salt length: ${salt.length}. Expected $vaultKdfSaltLength.',
      );
    }
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

class VaultMetadata {
  const VaultMetadata({
    required this.vaultId,
    required this.keyGeneration,
    required this.revision,
  });

  final String vaultId;
  final int keyGeneration;
  final int revision;

  Map<String, dynamic> toJson() => {
        'vaultId': vaultId,
        'keyGeneration': keyGeneration,
        'revision': revision,
      };

  factory VaultMetadata.fromJson(Map<String, dynamic> json) {
    final metadata = VaultMetadata(
      vaultId: _readRequiredString(json, key: 'vaultId'),
      keyGeneration: _readRequiredInt(json, key: 'keyGeneration'),
      revision: _readRequiredInt(json, key: 'revision'),
    );
    if (metadata.vaultId.length > 128 ||
        metadata.keyGeneration < 1 ||
        metadata.revision < 0) {
      throw FormatException('Invalid vault metadata.');
    }
    return metadata;
  }
}

class EncryptedVaultDocument {
  const EncryptedVaultDocument({
    required this.version,
    required this.kdf,
    required this.wrappedDek,
    required this.payload,
    this.metadata,
  });

  final int version;
  final KdfConfig kdf;
  final CipherPayload wrappedDek;
  final CipherPayload payload;
  final VaultMetadata? metadata;

  Map<String, dynamic> toJson() => {
        'version': version,
        'kdf': kdf.toJson(),
        'wrappedDek': wrappedDek.toJson(),
        'payload': payload.toJson(),
        if (metadata != null) 'metadata': metadata!.toJson(),
      };

  factory EncryptedVaultDocument.fromJson(Map<String, dynamic> json) {
    final version = _readRequiredInt(json, key: 'version');
    final document = EncryptedVaultDocument(
      version: version,
      kdf: KdfConfig.fromJson(_readRequiredMap(json, key: 'kdf')),
      wrappedDek:
          CipherPayload.fromJson(_readRequiredMap(json, key: 'wrappedDek')),
      payload: CipherPayload.fromJson(_readRequiredMap(json, key: 'payload')),
      metadata: version == vaultDocumentVersion
          ? VaultMetadata.fromJson(_readRequiredMap(json, key: 'metadata'))
          : null,
    );
    document._validate();
    return document;
  }

  Uint8List encode() => Uint8List.fromList(utf8.encode(jsonEncode(toJson())));

  factory EncryptedVaultDocument.decode(Uint8List bytes) {
    if (bytes.length > maxVaultCiphertextBytes + 1024 * 1024) {
      throw FormatException('Vault document exceeds supported size.');
    }
    try {
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Vault document root must be an object.');
      }
      return EncryptedVaultDocument.fromJson(decoded);
    } on FormatException {
      rethrow;
    } on Object {
      throw const FormatException('Vault document is not valid UTF-8 JSON.');
    }
  }

  void _validate() {
    if (version != legacyVaultDocumentVersion &&
        version != vaultDocumentVersion) {
      throw FormatException('Unsupported vault document version: $version.');
    }
    if (version == vaultDocumentVersion && metadata == null) {
      throw const FormatException('Missing vault metadata.');
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
    if (payload.cipherText.isEmpty ||
        payload.cipherText.length > maxVaultCiphertextBytes) {
      throw FormatException('Invalid $fieldName ciphertext length.');
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
    this.kind = VaultItemKind.login,
    this.folder = '',
    this.favorite = false,
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
  final VaultItemKind kind;
  final String folder;
  final bool favorite;

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
    VaultItemKind? kind,
    String? folder,
    bool? favorite,
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
      kind: kind ?? this.kind,
      folder: folder ?? this.folder,
      favorite: favorite ?? this.favorite,
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
        'kind': kind.name,
        'folder': folder,
        'favorite': favorite,
      };

  factory VaultItem.fromJson(Map<String, dynamic> json) {
    final item = VaultItem(
      id: _readRequiredString(json, key: 'id'),
      title: _readOptionalString(json, key: 'title'),
      username: _readOptionalString(json, key: 'username'),
      password: _readOptionalString(json, key: 'password'),
      url: _readOptionalString(json, key: 'url'),
      notes: _readOptionalString(json, key: 'notes'),
      tags: _readStringList(json, key: 'tags'),
      totpSecret: _readOptionalNullableString(json, key: 'totpSecret'),
      createdAt: _readRequiredDateTime(json, key: 'createdAt'),
      updatedAt: _readRequiredDateTime(json, key: 'updatedAt'),
      deletedAt: json['deletedAt'] == null
          ? null
          : _readRequiredDateTime(json, key: 'deletedAt'),
      kind: _readVaultItemKind(json['kind']),
      folder: _readOptionalString(json, key: 'folder'),
      favorite: json['favorite'] == true,
    );
    item.validate();
    return item;
  }

  void validate() {
    if (id.length > 128 ||
        title.length > maxVaultTitleLength ||
        username.length > maxVaultUsernameLength ||
        password.length > maxVaultPasswordLength ||
        url.length > maxVaultUrlLength ||
        notes.length > maxVaultNotesLength ||
        folder.length > maxVaultTagLength ||
        tags.length > maxVaultTagCount ||
        tags.any((tag) => tag.length > maxVaultTagLength) ||
        (totpSecret?.length ?? 0) > 1024) {
      throw const FormatException('Vault item exceeds supported limits.');
    }
  }
}

class VaultCategory {
  const VaultCategory({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    this.sortIndex = 0,
  });

  final String id;
  final String name;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int sortIndex;

  VaultCategory copyWith({
    String? name,
    DateTime? updatedAt,
    int? sortIndex,
  }) {
    return VaultCategory(
      id: id,
      name: name ?? this.name,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      sortIndex: sortIndex ?? this.sortIndex,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'updatedAt': updatedAt.toUtc().toIso8601String(),
        'sortIndex': sortIndex,
      };

  factory VaultCategory.fromJson(Map<String, dynamic> json) {
    final category = VaultCategory(
      id: _readRequiredString(json, key: 'id'),
      name: _readOptionalString(json, key: 'name'),
      createdAt: _readRequiredDateTime(json, key: 'createdAt'),
      updatedAt: _readRequiredDateTime(json, key: 'updatedAt'),
      sortIndex: _readCategorySortIndex(json),
    );
    category.validate();
    return category;
  }

  void validate() {
    if (id.isEmpty ||
        id.length > 128 ||
        name.isEmpty ||
        name.length > maxVaultTagLength) {
      throw const FormatException('Vault category exceeds supported limits.');
    }
  }
}

int _readCategorySortIndex(Map<String, dynamic> json) {
  final value = json['sortIndex'];
  if (value == null) {
    return 0;
  }
  if (value is! int || value < 0) {
    throw const FormatException('Invalid vault category sort index.');
  }
  return value;
}

enum VaultItemKind {
  login,
  secureNote,
}

class VaultData {
  const VaultData({
    required this.items,
    required this.updatedAt,
    this.categories = const [],
  });

  final List<VaultItem> items;
  final DateTime updatedAt;
  final List<VaultCategory> categories;

  static VaultData empty() => VaultData(
        items: const [],
        updatedAt: DateTime.now(),
      );

  Map<String, dynamic> toJson() => {
        'items': items.map((item) => item.toJson()).toList(),
        'updatedAt': updatedAt.toUtc().toIso8601String(),
        'categories': categories.map((category) => category.toJson()).toList(),
      };

  factory VaultData.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    if (rawItems is! List<dynamic> || rawItems.length > maxVaultItems) {
      throw const FormatException('Invalid vault item collection.');
    }
    final data = VaultData(
      items: rawItems.map((item) {
        if (item is! Map<String, dynamic>) {
          throw const FormatException('Vault item must be an object.');
        }
        return VaultItem.fromJson(item);
      }).toList(),
      updatedAt: json['updatedAt'] == null
          ? DateTime.now()
          : _readRequiredDateTime(json, key: 'updatedAt'),
      categories: _readVaultCategories(json['categories']),
    );
    data.validate();
    return VaultData(
      items: data.items,
      categories: data.categories.isEmpty
          ? _migrateLegacyCategories(data.items)
          : data.categories,
      updatedAt: data.updatedAt,
    );
  }

  static List<VaultCategory> _migrateLegacyCategories(List<VaultItem> items) {
    final legacyCategoryNames = {
      for (final item in items.where((item) => item.folder.trim().isNotEmpty))
        item.folder.trim(),
    };
    if (legacyCategoryNames.isEmpty) {
      return const [];
    }
    final names = legacyCategoryNames.toList()..sort();
    return [
      for (var index = 0; index < names.length; index++)
        VaultCategory(
          id: 'legacy-folder-$index',
          name: names[index],
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          sortIndex: index,
        ),
    ];
  }

  void validate() {
    if (items.length > maxVaultItems) {
      throw const FormatException('Vault contains too many items.');
    }
    for (final item in items) {
      item.validate();
    }
    if (categories.length > maxVaultCategories) {
      throw const FormatException('Vault contains too many categories.');
    }
    final categoryIds = <String>{};
    final categoryNames = <String>{};
    for (final category in categories) {
      category.validate();
      if (!categoryIds.add(category.id) ||
          !categoryNames.add(category.name.toLowerCase())) {
        throw const FormatException('Vault categories must be unique.');
      }
    }
  }

  List<VaultItem> get activeItems => items
      .where((item) => !item.isDeleted)
      .toList()
    ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));

  List<VaultItem> get deletedItems =>
      items.where((item) => item.isDeleted).toList()
        ..sort((a, b) => b.deletedAt!.compareTo(a.deletedAt!));

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

  VaultData restoreItem(String id, DateTime restoredAt) {
    final nextItems = items.map((item) {
      if (item.id != id) {
        return item;
      }
      return item.copyWith(deletedAt: null, updatedAt: restoredAt);
    }).toList();
    return copyWith(items: nextItems, updatedAt: restoredAt);
  }

  VaultData removePermanently(String id, DateTime removedAt) => copyWith(
        items: items.where((item) => item.id != id).toList(),
        updatedAt: removedAt,
      );

  VaultCategory? categoryById(String? categoryId) {
    if (categoryId == null || categoryId.isEmpty) {
      return null;
    }
    for (final category in categories) {
      if (category.id == categoryId) {
        return category;
      }
    }
    return null;
  }

  VaultCategory? categoryByName(String name) {
    final normalized = name.trim().toLowerCase();
    if (normalized.isEmpty) {
      return null;
    }
    for (final category in categories) {
      if (category.name.trim().toLowerCase() == normalized) {
        return category;
      }
    }
    return null;
  }

  VaultData withCategoryAssigned({
    required String itemId,
    required String? categoryId,
    required DateTime updatedAt,
  }) {
    final nextItems = items.map((item) {
      if (item.id != itemId) {
        return item;
      }
      return item.copyWith(
        folder: categoryId ?? '',
        updatedAt: updatedAt,
      );
    }).toList();
    return copyWith(items: nextItems, updatedAt: updatedAt);
  }

  VaultData pruneCategories({required DateTime updatedAt}) {
    final usedCategoryIds = {
      for (final item in items.where((item) => !item.isDeleted))
        if (item.folder.isNotEmpty) item.folder,
    };
    final nextCategories = categories
        .where((category) => usedCategoryIds.contains(category.id))
        .toList();
    return nextCategories.length == categories.length
        ? this
        : copyWith(
            items: items, categories: nextCategories, updatedAt: updatedAt);
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
    final mergedCategoriesById = <String, VaultCategory>{
      for (final category in categories) category.id: category,
    };
    for (final incomingCategory in incoming.categories) {
      final current = mergedCategoriesById[incomingCategory.id];
      final sameNameCategory = categoryByName(incomingCategory.name);
      if (current == null &&
          sameNameCategory != null &&
          !sameNameCategory.id.startsWith('legacy-folder-')) {
        mergedCategoriesById[incomingCategory.id] = incomingCategory;
        continue;
      }
      if (current == null ||
          incomingCategory.updatedAt.isAfter(current.updatedAt)) {
        mergedCategoriesById[incomingCategory.id] = incomingCategory;
      }
    }
    final mergedItems = byId.values.toList();
    final mergedCategories = mergedCategoriesById.values.toList()
      ..sort((a, b) {
        final sortDifference = a.sortIndex.compareTo(b.sortIndex);
        return sortDifference != 0
            ? sortDifference
            : a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    final mergedUpdatedAt = [
      updatedAt,
      incoming.updatedAt,
      ...mergedItems.map((item) => item.updatedAt),
    ].reduce((a, b) => a.isAfter(b) ? a : b);
    return VaultData(
      items: mergedItems,
      categories: mergedCategories,
      updatedAt: mergedUpdatedAt,
    );
  }

  VaultData copyWith({
    List<VaultItem>? items,
    List<VaultCategory>? categories,
    DateTime? updatedAt,
  }) {
    return VaultData(
      items: items ?? this.items,
      categories: categories ?? this.categories,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

List<VaultCategory> _readVaultCategories(dynamic value) {
  if (value == null) {
    return const [];
  }
  if (value is! List<dynamic>) {
    throw const FormatException('Invalid vault category collection.');
  }
  return value.map((category) {
    if (category is! Map<String, dynamic>) {
      throw const FormatException('Vault category must be an object.');
    }
    return VaultCategory.fromJson(category);
  }).toList();
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

String _readOptionalString(Map<String, dynamic> json, {required String key}) {
  final value = json[key];
  if (value == null) {
    return '';
  }
  if (value is String) {
    return value;
  }
  throw FormatException('Invalid string field: $key');
}

String? _readOptionalNullableString(
  Map<String, dynamic> json, {
  required String key,
}) {
  final value = json[key];
  if (value == null || value is String) {
    return value as String?;
  }
  throw FormatException('Invalid nullable string field: $key');
}

List<String> _readStringList(Map<String, dynamic> json, {required String key}) {
  final value = json[key];
  if (value == null) {
    return const [];
  }
  if (value is! List<dynamic> || value.length > maxVaultTagCount) {
    throw FormatException('Invalid list field: $key');
  }
  if (value.any((entry) => entry is! String)) {
    throw FormatException('Invalid list item in field: $key');
  }
  return value.cast<String>();
}

VaultItemKind _readVaultItemKind(Object? value) {
  if (value is! String) {
    return VaultItemKind.login;
  }
  for (final kind in VaultItemKind.values) {
    if (kind.name == value) {
      return kind;
    }
  }
  return VaultItemKind.login;
}

DateTime _readRequiredDateTime(Map<String, dynamic> json,
    {required String key}) {
  final value = _readRequiredString(json, key: key);
  try {
    return DateTime.parse(value).toLocal();
  } on FormatException {
    throw FormatException('Invalid date field: $key');
  }
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
