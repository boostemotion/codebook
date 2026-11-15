import '../../models/vault_models.dart';

class RepeatedPasswordGroup {
  const RepeatedPasswordGroup(this.items);

  final List<VaultItem> items;
}

class DashboardMetrics {
  const DashboardMetrics({
    required this.activeCount,
    required this.favoriteCount,
    required this.categoryCount,
    required this.deletedCount,
    required this.totpCount,
    required this.weakCount,
    required this.uncategorizedCount,
    required this.repeatedGroups,
    required this.weakItems,
    required this.lastUpdatedAt,
  });

  factory DashboardMetrics.fromVaultData(VaultData data) {
    final activeItems = data.activeItems;
    final categoryIds = {for (final category in data.categories) category.id};
    final repeatedGroups = <RepeatedPasswordGroup>[];
    final weakItems = <VaultItem>[];
    final passwordGroups = <String, List<VaultItem>>{};

    DateTime? lastUpdatedAt;
    var favoriteCount = 0;
    var totpCount = 0;
    var uncategorizedCount = 0;

    for (final item in activeItems) {
      if (item.favorite) {
        favoriteCount++;
      }
      if ((item.totpSecret ?? '').trim().isNotEmpty) {
        totpCount++;
      }
      if (item.folder.trim().isEmpty || !categoryIds.contains(item.folder)) {
        uncategorizedCount++;
      }
      if (_isWeakPassword(item.password)) {
        weakItems.add(item);
      }
      if (item.password.isNotEmpty) {
        passwordGroups.putIfAbsent(item.password, () => []).add(item);
      }
      final updatedAt = item.updatedAt;
      if (lastUpdatedAt == null || updatedAt.isAfter(lastUpdatedAt)) {
        lastUpdatedAt = updatedAt;
      }
    }

    for (final entry in passwordGroups.entries) {
      if (entry.value.length > 1) {
        repeatedGroups.add(
          RepeatedPasswordGroup(List.unmodifiable(entry.value)),
        );
      }
    }
    repeatedGroups.sort((a, b) => b.items.length.compareTo(a.items.length));
    weakItems.sort((a, b) => a.title.compareTo(b.title));

    return DashboardMetrics(
      activeCount: activeItems.length,
      favoriteCount: favoriteCount,
      categoryCount: data.categories.length,
      deletedCount: data.deletedItems.length,
      totpCount: totpCount,
      weakCount: weakItems.length,
      uncategorizedCount: uncategorizedCount,
      repeatedGroups: List.unmodifiable(repeatedGroups),
      weakItems: List.unmodifiable(weakItems),
      lastUpdatedAt: lastUpdatedAt,
    );
  }

  final int activeCount;
  final int favoriteCount;
  final int categoryCount;
  final int deletedCount;
  final int totpCount;
  final int weakCount;
  final int uncategorizedCount;
  final List<RepeatedPasswordGroup> repeatedGroups;
  final List<VaultItem> weakItems;
  final DateTime? lastUpdatedAt;

  int get repeatedAccountCount =>
      repeatedGroups.fold(0, (total, group) => total + group.items.length);

  static bool _isWeakPassword(String password) {
    if (password.isEmpty || password.length < 8) {
      return true;
    }
    return RegExp(r'^\d+$').hasMatch(password);
  }
}
