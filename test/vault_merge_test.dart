import 'package:flutter_test/flutter_test.dart';

import 'package:cipherbook/models/vault_models.dart';

void main() {
  test('merge keeps items created independently on both devices', () {
    final createdAt = DateTime(2026, 1, 1);
    final local = VaultData(
      items: [
        VaultItem(
          id: 'device-a-entry',
          title: 'A entry',
          username: 'a',
          password: 'a-secret',
          url: '',
          notes: '',
          tags: const [],
          createdAt: createdAt,
          updatedAt: createdAt,
        ),
      ],
      updatedAt: createdAt,
    );
    final remote = VaultData(
      items: [
        VaultItem(
          id: 'device-b-entry',
          title: 'B entry',
          username: 'b',
          password: 'b-secret',
          url: '',
          notes: '',
          tags: const [],
          createdAt: createdAt,
          updatedAt: createdAt,
        ),
      ],
      updatedAt: createdAt,
    );

    final merged = local.merge(remote);

    expect(
        merged.items.map((item) => item.id),
        containsAll([
          'device-a-entry',
          'device-b-entry',
        ]));
  });

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
