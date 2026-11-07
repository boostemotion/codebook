import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:cipherbook/models/bitwarden_bridge_models.dart';
import 'package:cipherbook/models/vault_models.dart';
import 'package:cipherbook/services/bitwarden_interchange_service.dart';

void main() {
  const service = BitwardenInterchangeService();
  const testEmail = 'demo.user' '@' 'example.test';
  const testPhone = '155' '00001111';

  test('decodes Bitwarden logins, secure notes, folders, and bridge ids', () {
    final parsed = service.decode(
      _jsonBytes(<String, Object?>{
        'encrypted': false,
        'folders': <Map<String, Object?>>[
          <String, Object?>{'id': 'folder-1', 'name': '工作'},
        ],
        'items': <Map<String, Object?>>[
          <String, Object?>{
            'id': 'bitwarden-login',
            'folderId': 'folder-1',
            'type': 1,
            'name': '示例站点',
            'notes': '备注',
            'favorite': true,
            'fields': <Map<String, Object?>>[
              <String, Object?>{
                'name': BitwardenInterchangeService.bridgeIdFieldName,
                'value': 'cipherbook-login',
                'type': 1,
              },
            ],
            'login': <String, Object?>{
              'username': '$testPhone / $testEmail',
              'password': 'sample-password',
              'totp': 'JBSWY3DPEHPK3PXP',
              'uris': <Map<String, Object?>>[
                <String, Object?>{'uri': 'https://example.com'},
              ],
            },
          },
          <String, Object?>{
            'id': 'bitwarden-note',
            'type': 2,
            'name': '安全笔记',
            'notes': '这是一条笔记',
          },
          <String, Object?>{
            'id': 'unsupported-card',
            'type': 3,
            'name': '银行卡',
          },
        ],
      }),
    );

    expect(parsed.items, hasLength(2));
    expect(parsed.unsupportedItems, 1);
    final login = parsed.items.first;
    expect(login.id, 'cipherbook-login');
    expect(login.username, contains(testEmail));
    expect(login.password, 'sample-password');
    expect(login.totpSecret, 'JBSWY3DPEHPK3PXP');
    expect(login.folder, '工作');
    expect(login.favorite, isTrue);
    expect(login.kind, VaultItemKind.login);
    expect(parsed.items.last.kind, VaultItemKind.secureNote);
  });

  test('matches mixed phone and email aliases as a manual duplicate candidate',
      () {
    final now = DateTime(2026, 1, 1);
    final local = VaultData(
      items: <VaultItem>[
        VaultItem(
          id: 'local',
          title: '示例站点',
          username: '$testPhone / $testEmail',
          password: 'same-password',
          url: 'https://www.example.com/login',
          notes: '',
          tags: const [],
          createdAt: now,
          updatedAt: now,
        ),
      ],
      updatedAt: now,
    );
    final imported = VaultItem(
      id: 'imported',
      title: 'Example',
      username: testEmail,
      password: 'same-password',
      url: 'https://www.example.com',
      notes: '',
      tags: const [],
      createdAt: now,
      updatedAt: now,
    );

    final plan = service.createImportPlan(
      importedItems: <VaultItem>[imported],
      localVault: local,
      sessionGeneration: 1,
      expectedRevision: 2,
    );

    expect(plan.reviews, hasLength(1));
    expect(
      plan.reviews.single.kind,
      BitwardenImportMatchKind.exactDuplicate,
    );
    expect(
      plan.reviews.single.sharedAliases,
      contains('email:$testEmail'),
    );
  });

  test('same password on another site is reported as reuse, not duplicate', () {
    final now = DateTime(2026, 1, 1);
    final local = VaultData(
      items: <VaultItem>[
        VaultItem(
          id: 'local',
          title: '本机站点',
          username: testEmail,
          password: 'same-password',
          url: 'https://local.example',
          notes: '',
          tags: const [],
          createdAt: now,
          updatedAt: now,
        ),
      ],
      updatedAt: now,
    );
    final imported = VaultItem(
      id: 'imported',
      title: '另一站点',
      username: testEmail,
      password: 'same-password',
      url: 'https://remote.example',
      notes: '',
      tags: const [],
      createdAt: now,
      updatedAt: now,
    );

    final plan = service.createImportPlan(
      importedItems: <VaultItem>[imported],
      localVault: local,
      sessionGeneration: 1,
      expectedRevision: 1,
    );

    expect(plan.reviews, isEmpty);
    expect(plan.reusedPasswordCount, 1);
  });

  test('same account with a different password is marked as a conflict', () {
    final now = DateTime(2026, 1, 1);
    final local = VaultData(
      items: <VaultItem>[
        VaultItem(
          id: 'local',
          title: '示例站点',
          username: '$testPhone / $testEmail',
          password: 'local-password',
          url: 'https://example.com',
          notes: '',
          tags: const [],
          createdAt: now,
          updatedAt: now,
        ),
      ],
      updatedAt: now,
    );
    final imported = local.items.single.copyWith(
      id: 'imported',
      username: testEmail,
      password: 'imported-password',
    );

    final plan = service.createImportPlan(
      importedItems: <VaultItem>[imported],
      localVault: local,
      sessionGeneration: 1,
      expectedRevision: 1,
    );

    expect(plan.reviews, hasLength(1));
    expect(
      plan.reviews.single.kind,
      BitwardenImportMatchKind.passwordConflict,
    );
  });

  test('delta export contains only Codebook items missing from Bitwarden', () {
    final now = DateTime(2026, 1, 1);
    VaultItem login({
      required String id,
      required String title,
      required String username,
      required String password,
      required String url,
    }) =>
        VaultItem(
          id: id,
          title: title,
          username: username,
          password: password,
          url: url,
          notes: '',
          tags: const [],
          createdAt: now,
          updatedAt: now,
        );
    final matched = login(
      id: 'matched',
      title: '已有站点',
      username: '$testPhone / $testEmail',
      password: 'same-password',
      url: 'https://www.example.com/login',
    );
    final missingLogin = login(
      id: 'missing-login',
      title: '仅 Codebook 有',
      username: 'new.account@example.test',
      password: 'new-password',
      url: 'https://only-codebook.example',
    );
    final missingNote = VaultItem(
      id: 'missing-note',
      title: '安全笔记',
      username: '',
      password: '',
      url: '',
      notes: '仅 Codebook 保存的笔记',
      tags: const [],
      createdAt: now,
      updatedAt: now,
      kind: VaultItemKind.secureNote,
    );
    final local = VaultData(
      items: <VaultItem>[matched, missingLogin, missingNote],
      updatedAt: now,
    );
    final baseline = <VaultItem>[
      matched.copyWith(
        id: 'bitwarden-match',
        username: testEmail,
        url: 'https://example.com',
      ),
      login(
        id: 'bitwarden-only',
        title: '仅 Bitwarden 有',
        username: 'bitwarden@example.test',
        password: 'bitwarden-password',
        url: 'https://bitwarden-only.example',
      ),
    ];

    final plan = service.createDeltaExportPlan(
      localVault: local,
      bitwardenItems: baseline,
      sessionGeneration: 3,
      expectedRevision: 8,
    );

    expect(plan.baselineItemCount, 2);
    expect(plan.localItemCount, 3);
    expect(plan.matchedItemCount, 1);
    expect(plan.missingItemCount, 2);
    expect(
      plan.missingItems.map((item) => item.id),
      containsAll(<String>['missing-login', 'missing-note']),
    );
  });

  test('delta export matches notes and collapses exact Codebook duplicates',
      () {
    final now = DateTime(2026, 1, 1);
    VaultItem note(String id) => VaultItem(
          id: id,
          title: '相同笔记',
          username: '',
          password: '',
          url: '',
          notes: '完全相同的内容',
          tags: const [],
          createdAt: now,
          updatedAt: now,
          kind: VaultItemKind.secureNote,
        );
    final local = VaultData(
      items: <VaultItem>[note('note-a'), note('note-b')],
      updatedAt: now,
    );

    final plan = service.createDeltaExportPlan(
      localVault: local,
      bitwardenItems: const <VaultItem>[],
      sessionGeneration: 1,
      expectedRevision: 1,
    );

    expect(plan.matchedItemCount, 0);
    expect(plan.missingItemCount, 1);
    expect(plan.duplicateCodebookCount, 1);
  });

  test('equally strong matches are marked as ambiguous for manual review', () {
    final now = DateTime(2026, 1, 1);
    VaultItem localItem(String id, String title) => VaultItem(
          id: id,
          title: title,
          username: testEmail,
          password: 'same-password',
          url: 'https://example.com',
          notes: '',
          tags: const [],
          createdAt: now,
          updatedAt: now,
        );
    final local = VaultData(
      items: <VaultItem>[
        localItem('local-a', '账号 A'),
        localItem('local-b', '账号 B'),
      ],
      updatedAt: now,
    );
    final imported = localItem('imported', '导入账号');

    final plan = service.createImportPlan(
      importedItems: <VaultItem>[imported],
      localVault: local,
      sessionGeneration: 1,
      expectedRevision: 1,
    );

    expect(plan.reviews, hasLength(1));
    expect(plan.reviews.single.hasAmbiguousMatches, isTrue);
    expect(plan.reviews.single.equallyRankedMatchCount, 2);
  });

  test('rejects encrypted Bitwarden JSON with a clear instruction', () {
    expect(
      () => service.decode(
        _jsonBytes(<String, Object?>{
          'encrypted': true,
          'data': 'encrypted',
        }),
      ),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('未加密 JSON'),
        ),
      ),
    );
  });

  test('JSON export round-trips login and secure note fields', () {
    final now = DateTime.utc(2026, 1, 1, 12);
    final exported = service.encodeJson(<VaultItem>[
      VaultItem(
        id: 'login-id',
        title: '示例登录',
        username: '{{EMAIL_sv62qz1r}}',
        password: 'secret-value',
        url: 'https://example.com',
        notes: '说明',
        tags: const [],
        totpSecret: 'JBSWY3DPEHPK3PXP',
        createdAt: now,
        updatedAt: now,
        folder: '工作',
        favorite: true,
      ),
      VaultItem(
        id: 'note-id',
        title: '安全笔记',
        username: '',
        password: '',
        url: '',
        notes: '笔记内容',
        tags: const [],
        createdAt: now,
        updatedAt: now,
        kind: VaultItemKind.secureNote,
      ),
    ]);

    final parsed = service.decode(exported);

    expect(parsed.items, hasLength(2));
    final login = parsed.items.firstWhere((item) => item.id == 'login-id');
    expect(login.username, '{{EMAIL_sv62qz1r}}');
    expect(login.password, 'secret-value');
    expect(login.totpSecret, startsWith('otpauth://totp/'));
    expect(login.totpSecret, contains('secret='));
    expect(login.folder, '工作');
    expect(login.favorite, isTrue);
    final note = parsed.items.firstWhere((item) => item.id == 'note-id');
    expect(note.kind, VaultItemKind.secureNote);
    expect(note.notes, '笔记内容');
  });

  test('CSV import handles quoted commas and newlines', () {
    final parsed = service.decode(
      Uint8List.fromList(
        utf8.encode(
          'folder,favorite,type,name,notes,fields,reprompt,'
          'login_uri,login_username,login_password,login_totp\n'
          '"工作",1,login,"示例,站点","第一行\n第二行",,0,'
          'https://example.com,{{EMAIL_sv62qz1r}},secret-value,'
          'JBSWY3DPEHPK3PXP\n',
        ),
      ),
    );

    expect(parsed.items, hasLength(1));
    expect(parsed.items.single.title, '示例,站点');
    expect(parsed.items.single.notes, '第一行\n第二行');
    expect(parsed.items.single.folder, '工作');
    expect(parsed.items.single.favorite, isTrue);
  });

  test('vault item persistence keeps Bitwarden bridge metadata', () {
    final now = DateTime(2026, 1, 1);
    final item = VaultItem(
      id: 'secure-note',
      title: '笔记',
      username: '',
      password: '',
      url: '',
      notes: '内容',
      tags: const [],
      createdAt: now,
      updatedAt: now,
      kind: VaultItemKind.secureNote,
      folder: '工作',
      favorite: true,
    );

    final restored = VaultItem.fromJson(item.toJson());

    expect(restored.kind, VaultItemKind.secureNote);
    expect(restored.folder, '工作');
    expect(restored.favorite, isTrue);
  });
}

Uint8List _jsonBytes(Map<String, Object?> value) {
  return Uint8List.fromList(utf8.encode(jsonEncode(value)));
}
