import 'package:flutter_test/flutter_test.dart';

import 'package:cipherbook/models/vault_models.dart';

void main() {
  test('merge keeps latest item update', () {
    final original = VaultData(
      items: [
        VaultItem(
          id: 'abc',
          title: 'GitHub',
          username: 'old-user',
          password: 'old-pass',
          url: '',
          notes: '',
          tags: const [],
          createdAt: DateTime(2026, 1, 1),
          updatedAt: DateTime(2026, 1, 1, 10),
        ),
      ],
      updatedAt: DateTime(2026, 1, 1, 10),
    );
    final incoming = VaultData(
      items: [
        VaultItem(
          id: 'abc',
          title: 'GitHub',
          username: 'new-user',
          password: 'new-pass',
          url: '',
          notes: '',
          tags: const [],
          createdAt: DateTime(2026, 1, 1),
          updatedAt: DateTime(2026, 1, 1, 12),
        ),
      ],
      updatedAt: DateTime(2026, 1, 1, 12),
    );

    final merged = original.merge(incoming);

    expect(merged.items.single.username, 'new-user');
    expect(merged.updatedAt, DateTime(2026, 1, 1, 12));
  });

  test('merge keeps tombstones', () {
    final original = VaultData(
      items: [
        VaultItem(
          id: 'abc',
          title: 'GitHub',
          username: 'user',
          password: 'pass',
          url: '',
          notes: '',
          tags: const [],
          createdAt: DateTime(2026, 1, 1),
          updatedAt: DateTime(2026, 1, 1, 10),
        ),
      ],
      updatedAt: DateTime(2026, 1, 1, 10),
    );
    final deletedAt = DateTime(2026, 1, 1, 11);
    final incoming = VaultData(
      items: [
        VaultItem(
          id: 'abc',
          title: 'GitHub',
          username: 'user',
          password: 'pass',
          url: '',
          notes: '',
          tags: const [],
          createdAt: DateTime(2026, 1, 1),
          updatedAt: deletedAt,
          deletedAt: deletedAt,
        ),
      ],
      updatedAt: deletedAt,
    );

    final merged = original.merge(incoming);

    expect(merged.items.single.deletedAt, deletedAt);
  });
}
