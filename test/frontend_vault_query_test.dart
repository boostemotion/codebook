import 'package:cipherbook/models/vault_models.dart';
import 'package:cipherbook/presentation/dashboard/dashboard_metrics.dart';
import 'package:cipherbook/presentation/vault/vault_query.dart';
import 'package:cipherbook/presentation/vault/vault_sort.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late VaultData data;
  late Set<String> repeatedIds;
  late Set<String> weakIds;

  List<VaultItem> filter(
    VaultQuery query, {
    VaultItemSort sort = VaultItemSort.recentlyUpdated,
  }) => filterVaultItems(
    data,
    query,
    repeatedItemIds: repeatedIds,
    weakItemIds: weakIds,
    sort: sort,
  );

  setUp(() {
    data = VaultData(
      updatedAt: DateTime(2026, 1, 3),
      categories: [
        VaultCategory(
          id: 'finance',
          name: '财务',
          createdAt: DateTime(2026, 1, 1),
          updatedAt: DateTime(2026, 1, 1),
        ),
        VaultCategory(
          id: 'personal',
          name: '个人',
          createdAt: DateTime(2026, 1, 1),
          updatedAt: DateTime(2026, 1, 1),
        ),
      ],
      items: [
        _item(
          id: 'alpha',
          title: 'Alpha Bank',
          username: 'owner@example.com',
          password: 'shared-password',
          url: 'https://bank.example/login',
          notes: 'Recovery codes in the safe',
          folder: 'finance',
          totpSecret: 'JBSWY3DPEHPK3PXP',
          favorite: true,
          updatedAt: DateTime(2026, 1, 2, 10),
        ),
        _item(
          id: 'beta',
          title: 'Beta',
          username: 'beta-user',
          password: 'shared-password',
          folder: 'personal',
          updatedAt: DateTime(2026, 1, 2, 12),
        ),
        _item(
          id: 'gamma',
          title: 'Gamma',
          username: 'gamma-user',
          password: '123',
          updatedAt: DateTime(2026, 1, 2, 11),
        ),
        _item(
          id: 'trashed',
          title: 'Old Alpha',
          username: 'old-user',
          password: 'old-password',
          updatedAt: DateTime(2026, 1, 1),
          deletedAt: DateTime(2026, 1, 3),
        ),
      ],
    );
    final metrics = DashboardMetrics.fromVaultData(data);
    repeatedIds = {
      for (final group in metrics.repeatedGroups)
        for (final item in group.items) item.id,
    };
    weakIds = metrics.weakItems.map((item) => item.id).toSet();
  });

  test('all-password search is case-insensitive and newest first', () {
    final all = filter(const VaultQuery());
    expect(all.map((item) => item.id), ['beta', 'gamma', 'alpha']);

    final search = filter(const VaultQuery(search: '  BANK.EXAMPLE '));
    expect(search.map((item) => item.id), ['alpha']);

    final usernameSearch = filter(const VaultQuery(search: 'GAMMA-USER'));
    expect(usernameSearch.map((item) => item.id), ['gamma']);

    final notesSearch = filter(const VaultQuery(search: 'recovery codes'));
    expect(notesSearch.map((item) => item.id), ['alpha']);
  });

  test('all-password sorting can be changed without changing the filter', () {
    final alphabetical = filter(
      const VaultQuery(),
      sort: VaultItemSort.titleAscending,
    );
    expect(alphabetical.map((item) => item.id), ['alpha', 'beta', 'gamma']);

    final reverseAlphabetical = filter(
      const VaultQuery(),
      sort: VaultItemSort.titleDescending,
    );
    expect(reverseAlphabetical.map((item) => item.id), [
      'gamma',
      'beta',
      'alpha',
    ]);
  });

  test(
    'dashboard filters select favorites, repeated, weak and TOTP records',
    () {
      expect(
        filter(
          const VaultQuery(filter: VaultListFilter.favorites),
        ).map((item) => item.id),
        ['alpha'],
      );
      expect(
        filter(
          const VaultQuery(filter: VaultListFilter.repeated),
        ).map((item) => item.id),
        ['beta', 'alpha'],
      );
      expect(
        filter(
          const VaultQuery(filter: VaultListFilter.weak),
        ).map((item) => item.id),
        ['gamma'],
      );
      expect(
        filter(
          const VaultQuery(filter: VaultListFilter.totp),
        ).map((item) => item.id),
        ['alpha'],
      );
    },
  );

  test('category and recycle-bin filters use the correct source', () {
    expect(
      filter(
        const VaultQuery(
          filter: VaultListFilter.category,
          categoryId: 'finance',
        ),
      ).map((item) => item.id),
      ['alpha'],
    );
    expect(
      filter(
        const VaultQuery(filter: VaultListFilter.category, categoryId: 'none'),
      ),
      isEmpty,
    );
    expect(
      filter(
        const VaultQuery(filter: VaultListFilter.deleted, search: 'old alpha'),
      ).map((item) => item.id),
      ['trashed'],
    );
  });
}

VaultItem _item({
  required String id,
  required String title,
  required String username,
  required String password,
  required DateTime updatedAt,
  String url = '',
  String notes = '',
  String folder = '',
  String? totpSecret,
  bool favorite = false,
  DateTime? deletedAt,
}) {
  return VaultItem(
    id: id,
    title: title,
    username: username,
    password: password,
    url: url,
    notes: notes,
    tags: const [],
    totpSecret: totpSecret,
    createdAt: DateTime(2026, 1, 1),
    updatedAt: updatedAt,
    deletedAt: deletedAt,
    folder: folder,
    favorite: favorite,
  );
}
