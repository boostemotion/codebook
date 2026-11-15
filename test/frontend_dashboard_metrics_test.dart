import 'package:cipherbook/models/vault_models.dart';
import 'package:cipherbook/presentation/dashboard/dashboard_metrics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'dashboard metrics summarize active vault data without leaking values',
    () {
      final category = VaultCategory(
        id: 'work',
        name: '工作',
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      );
      final data = VaultData(
        categories: [category],
        updatedAt: DateTime(2026, 1, 3),
        items: [
          _item(
            id: 'mail',
            title: 'Mail',
            password: 'shared-password',
            folder: 'work',
            favorite: true,
            totpSecret: 'JBSWY3DPEHPK3PXP',
            updatedAt: DateTime(2026, 1, 2, 10),
          ),
          _item(
            id: 'bank',
            title: 'Bank',
            password: 'shared-password',
            folder: 'work',
            updatedAt: DateTime(2026, 1, 2, 11),
          ),
          _item(
            id: 'numeric',
            title: 'Numeric PIN',
            password: '12345678',
            updatedAt: DateTime(2026, 1, 2, 12),
          ),
          _item(
            id: 'short',
            title: 'Short record',
            password: 'short',
            folder: 'missing-category',
            updatedAt: DateTime(2026, 1, 2, 13),
          ),
          _item(
            id: 'strong',
            title: 'Strong',
            password: 'a-long-password',
            folder: 'work',
            updatedAt: DateTime(2026, 1, 2, 14),
          ),
          _item(
            id: 'empty',
            title: 'Empty record',
            password: '',
            folder: '',
            updatedAt: DateTime(2026, 1, 2, 9),
          ),
          _item(
            id: 'trashed',
            title: 'Trashed',
            password: 'shared-password',
            updatedAt: DateTime(2026, 1, 3),
            deletedAt: DateTime(2026, 1, 3),
          ),
        ],
      );

      final metrics = DashboardMetrics.fromVaultData(data);

      expect(metrics.activeCount, 6);
      expect(metrics.favoriteCount, 1);
      expect(metrics.categoryCount, 1);
      expect(metrics.deletedCount, 1);
      expect(metrics.totpCount, 1);
      expect(metrics.uncategorizedCount, 3);
      expect(metrics.weakCount, 3);
      expect(metrics.weakItems.map((item) => item.id), [
        'empty',
        'numeric',
        'short',
      ]);
      expect(metrics.repeatedGroups, hasLength(1));
      expect(metrics.repeatedGroups.single.items.map((item) => item.id), [
        'bank',
        'mail',
      ]);
      expect(metrics.repeatedAccountCount, 2);
      expect(metrics.lastUpdatedAt, DateTime(2026, 1, 2, 14));
    },
  );

  test('dashboard metrics handle an empty vault', () {
    final metrics = DashboardMetrics.fromVaultData(
      VaultData(items: const [], updatedAt: DateTime(2026, 1, 1)),
    );

    expect(metrics.activeCount, 0);
    expect(metrics.favoriteCount, 0);
    expect(metrics.categoryCount, 0);
    expect(metrics.deletedCount, 0);
    expect(metrics.totpCount, 0);
    expect(metrics.uncategorizedCount, 0);
    expect(metrics.weakCount, 0);
    expect(metrics.repeatedGroups, isEmpty);
    expect(metrics.repeatedAccountCount, 0);
    expect(metrics.lastUpdatedAt, isNull);
  });
}

VaultItem _item({
  required String id,
  required String title,
  required String password,
  required DateTime updatedAt,
  String folder = '',
  String? totpSecret,
  bool favorite = false,
  DateTime? deletedAt,
}) {
  return VaultItem(
    id: id,
    title: title,
    username: '$id@example.com',
    password: password,
    url: 'https://$id.example',
    notes: '',
    tags: const [],
    totpSecret: totpSecret,
    createdAt: DateTime(2026, 1, 1),
    updatedAt: updatedAt,
    deletedAt: deletedAt,
    folder: folder,
    favorite: favorite,
  );
}
