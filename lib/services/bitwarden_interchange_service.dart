import 'dart:convert';
import 'dart:typed_data';

import 'package:uuid/uuid.dart';

import '../models/bitwarden_bridge_models.dart';
import '../models/vault_models.dart';

class BitwardenInterchangeService {
  const BitwardenInterchangeService();

  static const int maxExchangeItems = 10000;
  static const String bridgeIdFieldName = 'cipherbook_id';

  static const List<String> csvColumns = <String>[
    'folder',
    'favorite',
    'type',
    'name',
    'notes',
    'fields',
    'reprompt',
    'login_uri',
    'login_username',
    'login_password',
    'login_totp',
  ];

  BitwardenParsedVault decode(Uint8List bytes) {
    if (bytes.isEmpty) {
      throw const FormatException('Bitwarden 文件为空。');
    }

    String text;
    try {
      text = utf8.decode(bytes).replaceFirst('\uFEFF', '');
    } on FormatException {
      throw const FormatException('Bitwarden 文件不是有效的 UTF-8 文本。');
    }

    final trimmed = text.trimLeft();
    if (trimmed.startsWith('{')) {
      return _decodeJson(trimmed);
    }
    return _decodeCsv(text);
  }

  Uint8List encodeJson(List<VaultItem> items) {
    final activeItems = items.where((item) => !item.isDeleted).toList();
    final folderNames = <String>{
      for (final item in activeItems)
        if (item.folder.trim().isNotEmpty) item.folder.trim(),
    }.toList()
      ..sort();
    final folders = <Map<String, Object?>>[
      for (var index = 0; index < folderNames.length; index++)
        <String, Object?>{
          'id': 'cipherbook-folder-$index',
          'name': folderNames[index],
        },
    ];
    final folderIds = <String, String>{
      for (var index = 0; index < folderNames.length; index++)
        folderNames[index]: 'cipherbook-folder-$index',
    };

    final root = <String, Object?>{
      'encrypted': false,
      'folders': folders,
      'items': [
        for (final item in activeItems)
          _itemToBitwardenJson(
            item,
            folderId: folderIds[item.folder.trim()],
          ),
      ],
    };
    return Uint8List.fromList(
      utf8.encode(const JsonEncoder.withIndent('  ').convert(root)),
    );
  }

  Uint8List encodeCsv(List<VaultItem> items) {
    final rows = <List<String>>[
      List<String>.from(csvColumns),
      for (final item in items)
        if (!item.isDeleted)
          <String>[
            item.folder,
            item.favorite ? '1' : '0',
            item.kind == VaultItemKind.secureNote ? 'note' : 'login',
            item.title,
            item.notes,
            '',
            '0',
            item.kind == VaultItemKind.login ? item.url : '',
            item.kind == VaultItemKind.login ? item.username : '',
            item.kind == VaultItemKind.login ? item.password : '',
            item.kind == VaultItemKind.login
                ? (_totpForBitwarden(item) ?? '')
                : '',
          ],
    ];
    final buffer = StringBuffer();
    for (final row in rows) {
      buffer.writeln(row.map(_encodeCsvField).join(','));
    }
    return Uint8List.fromList(utf8.encode(buffer.toString()));
  }

  BitwardenParsedVault _decodeJson(String source) {
    Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException {
      throw const FormatException('Bitwarden JSON 格式无效。');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Bitwarden JSON 根节点必须是对象。');
    }
    if (decoded['encrypted'] == true) {
      throw const FormatException(
        '暂不支持 Bitwarden 加密 JSON。请先导出未加密 JSON 或 CSV，导入完成后立即删除导出文件。',
      );
    }

    final rawItems = decoded['items'];
    if (rawItems is! List<dynamic> || rawItems.length > maxExchangeItems) {
      throw const FormatException('Bitwarden JSON 中的条目列表无效或数量过多。');
    }

    final folderNames = <String, String>{};
    final rawFolders = decoded['folders'];
    if (rawFolders is List<dynamic>) {
      for (final folder in rawFolders) {
        if (folder is! Map<String, dynamic>) {
          continue;
        }
        final id = _optionalString(folder['id']);
        final name = _optionalString(folder['name']).trim();
        if (id.isNotEmpty && name.isNotEmpty) {
          folderNames[id] = name;
        }
      }
    }

    var unsupportedItems = 0;
    final warnings = <String>[];
    var extraUriCount = 0;
    var ignoredCustomFieldCount = 0;
    var passkeyCount = 0;
    var attachmentCount = 0;
    var repromptCount = 0;
    var passwordHistoryCount = 0;
    final usedIds = <String>{};
    final items = <VaultItem>[];
    for (final rawItem in rawItems) {
      if (rawItem is! Map<String, dynamic>) {
        unsupportedItems++;
        continue;
      }
      final type = _readItemType(rawItem['type']);
      if (type == null) {
        unsupportedItems++;
        continue;
      }

      final fields = rawItem['fields'];
      String bridgeId = '';
      if (fields is List<dynamic>) {
        for (final field in fields) {
          if (field is! Map<String, dynamic>) {
            ignoredCustomFieldCount++;
            continue;
          }
          final name = _optionalString(field['name']).trim();
          if (name == bridgeIdFieldName) {
            bridgeId = _optionalString(field['value']).trim();
          } else {
            ignoredCustomFieldCount++;
          }
        }
      }
      final rawReprompt = rawItem['reprompt'];
      if ((rawReprompt is int && rawReprompt > 0) || rawReprompt == true) {
        repromptCount++;
      }
      final attachments = rawItem['attachments'];
      if (attachments is List<dynamic>) {
        attachmentCount += attachments.length;
      }
      final passwordHistory = rawItem['passwordHistory'];
      if (passwordHistory is List<dynamic>) {
        passwordHistoryCount += passwordHistory.length;
      }

      final id = _uniqueItemId(bridgeId, usedIds);
      final name = _optionalString(rawItem['name']).trim();
      final notes = _optionalString(rawItem['notes']);
      final favorite = rawItem['favorite'] == true;
      final folderId = _optionalString(rawItem['folderId']);
      final folder =
          folderNames[folderId] ?? _optionalString(rawItem['folder']);
      final createdAt = _readDate(rawItem['creationDate']) ?? DateTime.now();
      final updatedAt = _readDate(rawItem['revisionDate']) ??
          _readDate(rawItem['updateDate']) ??
          createdAt;

      String username = '';
      String password = '';
      String url = '';
      String? totpSecret;
      if (type == 1) {
        final login = rawItem['login'];
        if (login is! Map<String, dynamic>) {
          unsupportedItems++;
          continue;
        }
        username = _optionalString(login['username']);
        password = _optionalString(login['password']);
        final totp = _optionalString(login['totp']).trim();
        totpSecret = totp.isEmpty ? null : totp;
        final passkeys = login['fido2Credentials'];
        if (passkeys is List<dynamic>) {
          passkeyCount += passkeys.length;
        }
        final uris = login['uris'];
        if (uris is List<dynamic>) {
          final urls = <String>[];
          for (final uri in uris) {
            if (uri is Map<String, dynamic>) {
              final value = _optionalString(uri['uri']).trim();
              if (value.isNotEmpty) {
                urls.add(value);
              }
            }
          }
          if (urls.isNotEmpty) {
            url = urls.first;
            if (urls.length > 1) {
              extraUriCount += urls.length - 1;
            }
          }
        }
      }

      final item = VaultItem(
        id: id,
        title: name,
        username: username,
        password: password,
        url: url,
        notes: notes.trim(),
        tags: const [],
        totpSecret: totpSecret,
        createdAt: createdAt,
        updatedAt: updatedAt,
        kind: type == 2 ? VaultItemKind.secureNote : VaultItemKind.login,
        folder: folder,
        favorite: favorite,
      );
      try {
        item.validate();
      } on FormatException {
        unsupportedItems++;
        continue;
      }
      items.add(item);
    }

    if (extraUriCount > 0) {
      warnings.add('$extraUriCount 个额外网址未导入；当前条目模型只保存一个网址。');
    }
    if (ignoredCustomFieldCount > 0) {
      warnings.add('$ignoredCustomFieldCount 个 Bitwarden 自定义字段未导入。');
    }
    if (passkeyCount > 0) {
      warnings.add('$passkeyCount 个 Passkey 未导入。');
    }
    if (attachmentCount > 0) {
      warnings.add('$attachmentCount 个附件未导入。');
    }
    if (repromptCount > 0) {
      warnings.add('$repromptCount 个条目要求再次输入主密码，当前版本不支持该保护选项。');
    }
    if (passwordHistoryCount > 0) {
      warnings.add('$passwordHistoryCount 条历史密码记录未导入。');
    }
    return BitwardenParsedVault(
      items: items,
      unsupportedItems: unsupportedItems,
      warnings: warnings,
    );
  }

  BitwardenParsedVault _decodeCsv(String source) {
    final rows = _parseCsv(source);
    if (rows.isEmpty) {
      throw const FormatException('Bitwarden CSV 为空。');
    }
    final header = <String, int>{
      for (var index = 0; index < rows.first.length; index++)
        rows.first[index].trim().toLowerCase(): index,
    };
    if (!header.containsKey('name')) {
      throw const FormatException('无法识别 Bitwarden CSV 表头。');
    }

    var unsupportedItems = 0;
    var extraUriCount = 0;
    var ignoredCustomFieldCount = 0;
    var repromptCount = 0;
    final usedIds = <String>{};
    final items = <VaultItem>[];
    for (var rowIndex = 1; rowIndex < rows.length; rowIndex++) {
      final row = rows[rowIndex];
      if (row.every((value) => value.trim().isEmpty)) {
        continue;
      }
      if (rowIndex > maxExchangeItems) {
        throw const FormatException('Bitwarden CSV 条目数量过多。');
      }
      final type = _readCsvType(_cell(row, header, 'type'));
      if (type == null) {
        unsupportedItems++;
        continue;
      }
      final name = _cell(row, header, 'name').trim();
      final notes = _cell(row, header, 'notes');
      final folder = _cell(row, header, 'folder').trim();
      final favorite = _readBool(_cell(row, header, 'favorite'));
      if (_cell(row, header, 'fields').trim().isNotEmpty) {
        ignoredCustomFieldCount++;
      }
      final reprompt = _cell(row, header, 'reprompt').trim();
      if (reprompt.isNotEmpty && reprompt != '0' && reprompt != 'false') {
        repromptCount++;
      }
      final createdAt = DateTime.now();
      String username = '';
      String password = '';
      String url = '';
      String? totpSecret;
      if (type == 1) {
        username = _cell(row, header, 'login_username');
        password = _cell(row, header, 'login_password');
        final rawUrls = _cell(row, header, 'login_uri')
            .split(RegExp(r'\r?\n'))
            .map((value) => value.trim())
            .where((value) => value.isNotEmpty)
            .toList();
        if (rawUrls.isNotEmpty) {
          url = rawUrls.first;
          if (rawUrls.length > 1) {
            extraUriCount += rawUrls.length - 1;
          }
        }
        final totp = _cell(row, header, 'login_totp').trim();
        totpSecret = totp.isEmpty ? null : totp;
      }
      final id = _uniqueItemId('', usedIds);
      final item = VaultItem(
        id: id,
        title: name,
        username: username,
        password: password,
        url: url,
        notes: notes.trim(),
        tags: const [],
        totpSecret: totpSecret,
        createdAt: createdAt,
        updatedAt: createdAt,
        kind: type == 2 ? VaultItemKind.secureNote : VaultItemKind.login,
        folder: folder,
        favorite: favorite,
      );
      try {
        item.validate();
      } on FormatException {
        unsupportedItems++;
        continue;
      }
      items.add(item);
    }
    final warnings = <String>[];
    if (extraUriCount > 0) {
      warnings.add('$extraUriCount 个额外网址未导入；当前条目模型只保存一个网址。');
    }
    if (ignoredCustomFieldCount > 0) {
      warnings.add('$ignoredCustomFieldCount 个 Bitwarden 自定义字段未导入。');
    }
    if (repromptCount > 0) {
      warnings.add('$repromptCount 个条目要求再次输入主密码，当前版本不支持该保护选项。');
    }
    return BitwardenParsedVault(
      items: items,
      unsupportedItems: unsupportedItems,
      warnings: warnings,
    );
  }

  BitwardenImportPlan createImportPlan({
    required List<VaultItem> importedItems,
    required VaultData localVault,
    required int sessionGeneration,
    required int expectedRevision,
    int unsupportedItems = 0,
    List<String> warnings = const [],
  }) {
    final reviews = <BitwardenImportReview>[];
    for (final importedItem in importedItems) {
      final match = _bestLocalMatch(importedItem, localVault.activeItems);
      if (match != null) {
        reviews.add(match);
      }
    }
    final reusedPasswordCount = _countReusedPasswords(
      importedItems,
      localVault.activeItems,
    );
    return BitwardenImportPlan(
      sessionGeneration: sessionGeneration,
      expectedRevision: expectedRevision,
      importedItems: List.unmodifiable(importedItems),
      reviews: List.unmodifiable(reviews),
      unsupportedItems: unsupportedItems,
      reusedPasswordCount: reusedPasswordCount,
      warnings: List.unmodifiable(warnings),
    );
  }

  BitwardenDeltaExportPlan createDeltaExportPlan({
    required VaultData localVault,
    required List<VaultItem> bitwardenItems,
    required int sessionGeneration,
    required int expectedRevision,
    int unsupportedItems = 0,
    List<String> warnings = const [],
  }) {
    final activeLocalItems = localVault.activeItems;
    final missingItems = <VaultItem>[];
    final missingSignatures = <String>{};
    var matchedItemCount = 0;
    var duplicateCodebookCount = 0;

    for (final localItem in activeLocalItems) {
      final match = _bestLocalMatch(localItem, bitwardenItems);
      if (match != null) {
        matchedItemCount++;
        continue;
      }
      final signature = _deltaItemSignature(localItem);
      if (!missingSignatures.add(signature)) {
        duplicateCodebookCount++;
        continue;
      }
      missingItems.add(localItem);
    }

    return BitwardenDeltaExportPlan(
      sessionGeneration: sessionGeneration,
      expectedRevision: expectedRevision,
      baselineItemCount: bitwardenItems.length,
      localItemCount: activeLocalItems.length,
      matchedItemCount: matchedItemCount,
      missingItems: List.unmodifiable(missingItems),
      duplicateCodebookCount: duplicateCodebookCount,
      unsupportedItems: unsupportedItems,
      warnings: List.unmodifiable(warnings),
    );
  }

  Map<String, Object?> _itemToBitwardenJson(
    VaultItem item, {
    required String? folderId,
  }) {
    final isLogin = item.kind == VaultItemKind.login;
    return <String, Object?>{
      'id': item.id,
      'organizationId': null,
      'folderId': folderId,
      'type': isLogin ? 1 : 2,
      'reprompt': 0,
      'name': item.title,
      'notes': item.notes,
      'favorite': item.favorite,
      'fields': <Map<String, Object?>>[
        <String, Object?>{
          'name': bridgeIdFieldName,
          'value': item.id,
          'type': 1,
        },
      ],
      if (isLogin)
        'login': <String, Object?>{
          'username': item.username,
          'password': item.password,
          'totp': _totpForBitwarden(item),
          'uris': <Map<String, Object?>>[
            if (item.url.trim().isNotEmpty)
              <String, Object?>{
                'match': null,
                'uri': item.url.trim(),
              },
          ],
        },
      'creationDate': item.createdAt.toUtc().toIso8601String(),
      'revisionDate': item.updatedAt.toUtc().toIso8601String(),
    };
  }

  BitwardenImportReview? _bestLocalMatch(
    VaultItem imported,
    List<VaultItem> localItems,
  ) {
    BitwardenImportReview? best;
    var bestScore = -1;
    var equallyRankedMatchCount = 0;
    final importedAliases = identityAliases(imported.username);
    final importedHost = normalizedHost(imported.url);
    for (final local in localItems) {
      if (local.kind != imported.kind) {
        continue;
      }
      final sharedAliases = <String>{};
      var score = 0;
      var reason = '';
      final sameSource = local.id == imported.id;
      final titleMatches =
          normalizedText(local.title) == normalizedText(imported.title);
      final passwordsEqual =
          _passwordValuesEqual(local.password, imported.password);
      final localAliases = identityAliases(local.username);
      sharedAliases.addAll(importedAliases.intersection(localAliases));

      if (sameSource) {
        score = 1000;
        reason = '来源 ID 相同';
        sharedAliases.addAll(importedAliases);
      } else if (imported.kind == VaultItemKind.secureNote) {
        final titleMatches =
            normalizedText(local.title) == normalizedText(imported.title);
        final notesMatch = normalizedText(local.notes).isNotEmpty &&
            normalizedText(local.notes) == normalizedText(imported.notes);
        if (!titleMatches && !notesMatch) {
          continue;
        }
        score = (titleMatches ? 45 : 0) + (notesMatch ? 35 : 0);
        reason = titleMatches && notesMatch
            ? '安全笔记标题和内容相同'
            : titleMatches
                ? '安全笔记标题相同'
                : '安全笔记内容相同';
      } else {
        final localHost = normalizedHost(local.url);
        final hostsComparable = importedHost != null && localHost != null;
        if (hostsComparable && importedHost != localHost) {
          continue;
        }
        if (hostsComparable) {
          if (sharedAliases.isEmpty && !titleMatches) {
            continue;
          }
          score = sharedAliases.isEmpty ? 20 : 60 + sharedAliases.length;
          reason = sharedAliases.isEmpty ? '同网站且标题相同' : '同网站且账号别名相同';
        } else {
          if (!titleMatches || (sharedAliases.isEmpty && !passwordsEqual)) {
            continue;
          }
          score = 25;
          reason = sharedAliases.isEmpty ? '标题和密码相同' : '标题和账号信息相同';
        }
        if (titleMatches) {
          score += 10;
        }
      }
      if (passwordsEqual) {
        score += 40;
      }
      if ((local.totpSecret ?? '') == (imported.totpSecret ?? '')) {
        score += 5;
      }
      if (best != null) {
        if (score < bestScore) {
          continue;
        }
        if (score == bestScore) {
          equallyRankedMatchCount++;
          continue;
        }
      }
      final notesMatch = imported.kind == VaultItemKind.secureNote &&
          normalizedText(local.notes).isNotEmpty &&
          normalizedText(local.notes) == normalizedText(imported.notes);
      final exactMatch = imported.kind == VaultItemKind.secureNote
          ? sameSource || (titleMatches && notesMatch)
          : passwordsEqual && (sameSource || sharedAliases.isNotEmpty);
      final kind = exactMatch
          ? BitwardenImportMatchKind.exactDuplicate
          : sameSource || sharedAliases.isNotEmpty || titleMatches
              ? BitwardenImportMatchKind.passwordConflict
              : BitwardenImportMatchKind.possibleDuplicate;
      bestScore = score;
      equallyRankedMatchCount = 1;
      best = BitwardenImportReview(
        importedItem: imported,
        localItem: local,
        kind: kind,
        reason: reason,
        sharedAliases: sharedAliases.toList()..sort(),
        equallyRankedMatchCount: equallyRankedMatchCount,
      );
    }
    if (best != null && equallyRankedMatchCount > 1) {
      best = BitwardenImportReview(
        importedItem: best.importedItem,
        localItem: best.localItem,
        kind: best.kind,
        reason: best.reason,
        sharedAliases: best.sharedAliases,
        equallyRankedMatchCount: equallyRankedMatchCount,
      );
    }
    return best;
  }

  int _countReusedPasswords(
    List<VaultItem> importedItems,
    List<VaultItem> localItems,
  ) {
    var count = 0;
    for (final imported in importedItems) {
      if (imported.password.isEmpty) {
        continue;
      }
      final importedHost = normalizedHost(imported.url);
      final importedAliases = identityAliases(imported.username);
      for (final local in localItems) {
        if (local.password != imported.password) {
          continue;
        }
        final localHost = normalizedHost(local.url);
        final sameAccount = importedHost != null &&
            localHost != null &&
            importedHost == localHost &&
            importedAliases
                .intersection(identityAliases(local.username))
                .isNotEmpty;
        if (!sameAccount) {
          count++;
          break;
        }
      }
    }
    return count;
  }

  static String? normalizedHost(String url) {
    final value = url.trim();
    if (value.isEmpty) {
      return null;
    }
    final uri = Uri.tryParse(
      value.contains('://') ? value : 'https://$value',
    );
    var host = uri?.host.trim().toLowerCase();
    if (host == null || host.isEmpty) {
      return null;
    }
    if (host.endsWith('.')) {
      host = host.substring(0, host.length - 1);
    }
    if (host.startsWith('www.')) {
      host = host.substring(4);
    }
    return host.isEmpty ? null : host;
  }

  static String normalizedText(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  static String _deltaItemSignature(VaultItem item) {
    if (item.kind == VaultItemKind.secureNote) {
      return 'note:${normalizedText(item.title)}:${normalizedText(item.notes)}';
    }
    final host = normalizedHost(item.url);
    final username = normalizedText(item.username);
    final password = item.password;
    final totp = item.totpSecret?.trim() ?? '';
    final title = host == null ? normalizedText(item.title) : '';
    return 'login:$host:$title:$username:$password:$totp';
  }

  static Set<String> identityAliases(String rawUsername) {
    final trimmed = rawUsername.trim();
    if (trimmed.isEmpty) {
      return const <String>{};
    }
    final aliases = <String>{
      'raw:${trimmed.toLowerCase()}',
    };
    for (final match in RegExp(
      r'[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}',
      caseSensitive: false,
    ).allMatches(trimmed)) {
      final email = match.group(0)!.trim();
      final separator = email.lastIndexOf('@');
      final localPart = email.substring(0, separator);
      final domain = email.substring(separator + 1).toLowerCase();
      aliases.add('email:${localPart.toLowerCase()}@$domain');
    }

    final withoutEmails = trimmed.replaceAll(
      RegExp(
        r'[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}',
        caseSensitive: false,
      ),
      ' ',
    );
    for (final match in RegExp(
      r'(?:\+?\d[\d\s\-().]*){7,16}\d',
    ).allMatches(withoutEmails)) {
      final rawPhone = match.group(0)!.trim();
      final hasCountryCode = rawPhone.startsWith('+');
      final digits = rawPhone.replaceAll(RegExp(r'\D'), '');
      if (digits.length < 8 || digits.length > 15) {
        continue;
      }
      if (hasCountryCode) {
        aliases.add('phone:+$digits');
      } else {
        aliases.add('phone:$digits');
        if (digits.length == 11 && digits.startsWith('1')) {
          aliases.add('phone:+86$digits');
        }
      }
    }
    return aliases;
  }

  static List<List<String>> _parseCsv(String source) {
    final rows = <List<String>>[];
    var row = <String>[];
    final field = StringBuffer();
    var inQuotes = false;
    for (var index = 0; index < source.length; index++) {
      final char = source[index];
      if (inQuotes) {
        if (char == '"') {
          if (index + 1 < source.length && source[index + 1] == '"') {
            field.write('"');
            index++;
          } else {
            inQuotes = false;
          }
        } else {
          field.write(char);
        }
        continue;
      }
      if (char == '"') {
        inQuotes = true;
      } else if (char == ',') {
        row.add(field.toString());
        field.clear();
      } else if (char == '\n') {
        row.add(field.toString());
        field.clear();
        rows.add(row);
        row = <String>[];
      } else if (char != '\r') {
        field.write(char);
      }
    }
    if (inQuotes) {
      throw const FormatException('Bitwarden CSV 存在未闭合的引号。');
    }
    if (field.isNotEmpty || row.isNotEmpty) {
      row.add(field.toString());
      rows.add(row);
    }
    return rows;
  }

  static String _encodeCsvField(String value) {
    if (!value.contains(RegExp(r'[",\r\n]'))) {
      return value;
    }
    return '"${value.replaceAll('"', '""')}"';
  }

  static String _cell(
    List<String> row,
    Map<String, int> header,
    String name,
  ) {
    final index = header[name];
    if (index == null || index < 0 || index >= row.length) {
      return '';
    }
    return row[index];
  }

  static int? _readItemType(Object? value) {
    if (value is int) {
      return value == 1 || value == 2 ? value : null;
    }
    if (value is String) {
      return _readCsvType(value);
    }
    return null;
  }

  static int? _readCsvType(String value) {
    switch (value.trim().toLowerCase()) {
      case '1':
      case 'login':
        return 1;
      case '2':
      case 'note':
      case 'securenote':
      case 'secure note':
        return 2;
      default:
        return null;
    }
  }

  static bool _readBool(String value) {
    final normalized = value.trim().toLowerCase();
    return normalized == '1' || normalized == 'true' || normalized == 'yes';
  }

  static String _uniqueItemId(String preferred, Set<String> usedIds) {
    var candidate = preferred.trim();
    if (candidate.isEmpty ||
        candidate.length > 128 ||
        usedIds.contains(candidate)) {
      candidate = const Uuid().v4();
    }
    usedIds.add(candidate);
    return candidate;
  }

  static String _optionalString(Object? value) {
    return value is String ? value : '';
  }

  static DateTime? _readDate(Object? value) {
    if (value is! String || value.trim().isEmpty) {
      return null;
    }
    try {
      final parsed = DateTime.parse(value).toLocal();
      return parsed.isAfter(DateTime.now().add(const Duration(days: 1)))
          ? DateTime.now()
          : parsed;
    } on FormatException {
      return null;
    }
  }

  static bool _passwordValuesEqual(String first, String second) {
    if (first.isEmpty || second.isEmpty) {
      return false;
    }
    return first == second;
  }

  static String? _totpForBitwarden(VaultItem item) {
    final value = item.totpSecret?.trim();
    if (value == null || value.isEmpty) {
      return null;
    }
    if (value.toLowerCase().startsWith('otpauth://')) {
      return value;
    }
    final label =
        item.username.trim().isEmpty ? item.title.trim() : item.username.trim();
    final secret = value.toUpperCase().replaceAll(RegExp(r'[\s-]'), '');
    return 'otpauth://totp/${Uri.encodeComponent(label)}'
        '?secret=${Uri.encodeComponent(secret)}';
  }
}

class BitwardenParsedVault {
  const BitwardenParsedVault({
    required this.items,
    required this.unsupportedItems,
    required this.warnings,
  });

  final List<VaultItem> items;
  final int unsupportedItems;
  final List<String> warnings;
}
