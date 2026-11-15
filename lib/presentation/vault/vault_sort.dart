import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/vault_models.dart';

enum VaultItemSort {
  recentlyUpdated('最近修改'),
  titleAscending('名称 A-Z'),
  titleDescending('名称 Z-A'),
  createdNewest('最近添加'),
  createdOldest('最早添加');

  const VaultItemSort(this.label);

  final String label;

  String labelFor({bool deleted = false}) {
    return deleted && this == VaultItemSort.recentlyUpdated ? '最近删除' : label;
  }
}

enum VaultCategorySort {
  defaultOrder('默认顺序'),
  nameAscending('名称 A-Z'),
  nameDescending('名称 Z-A'),
  mostItems('密码最多'),
  fewestItems('密码最少');

  const VaultCategorySort(this.label);

  final String label;
}

class VaultSortPreferences {
  const VaultSortPreferences({
    this.allPasswords = VaultItemSort.recentlyUpdated,
    this.categoryPasswords = VaultItemSort.titleAscending,
    this.categories = VaultCategorySort.defaultOrder,
  });

  final VaultItemSort allPasswords;
  final VaultItemSort categoryPasswords;
  final VaultCategorySort categories;

  VaultSortPreferences copyWith({
    VaultItemSort? allPasswords,
    VaultItemSort? categoryPasswords,
    VaultCategorySort? categories,
  }) {
    return VaultSortPreferences(
      allPasswords: allPasswords ?? this.allPasswords,
      categoryPasswords: categoryPasswords ?? this.categoryPasswords,
      categories: categories ?? this.categories,
    );
  }
}

class VaultSortController extends Notifier<VaultSortPreferences> {
  @override
  VaultSortPreferences build() => const VaultSortPreferences();

  void setAllPasswords(VaultItemSort sort) {
    state = state.copyWith(allPasswords: sort);
  }

  void setCategoryPasswords(VaultItemSort sort) {
    state = state.copyWith(categoryPasswords: sort);
  }

  void setCategories(VaultCategorySort sort) {
    state = state.copyWith(categories: sort);
  }
}

final vaultSortProvider =
    NotifierProvider<VaultSortController, VaultSortPreferences>(
      VaultSortController.new,
    );

void sortVaultItems(
  List<VaultItem> items,
  VaultItemSort sort, {
  bool deleted = false,
}) {
  items.sort((a, b) {
    return switch (sort) {
      VaultItemSort.recentlyUpdated => _compareThenTitle(
        deleted
            ? (b.deletedAt ?? b.updatedAt).compareTo(a.deletedAt ?? a.updatedAt)
            : b.updatedAt.compareTo(a.updatedAt),
        a,
        b,
      ),
      VaultItemSort.titleAscending => _compareThenTitle(
        _compareTitles(a, b),
        a,
        b,
      ),
      VaultItemSort.titleDescending => _compareThenTitle(
        _compareTitles(b, a),
        a,
        b,
      ),
      VaultItemSort.createdNewest => _compareThenTitle(
        b.createdAt.compareTo(a.createdAt),
        a,
        b,
      ),
      VaultItemSort.createdOldest => _compareThenTitle(
        a.createdAt.compareTo(b.createdAt),
        a,
        b,
      ),
    };
  });
}

void sortVaultCategories(
  List<VaultCategory> categories,
  VaultCategorySort sort,
  Map<String, int> counts,
) {
  categories.sort((a, b) {
    return switch (sort) {
      VaultCategorySort.defaultOrder => a.sortIndex.compareTo(b.sortIndex),
      VaultCategorySort.nameAscending => _compareCategoryNames(a, b),
      VaultCategorySort.nameDescending => _compareCategoryNames(b, a),
      VaultCategorySort.mostItems => _compareThenCategoryNames(
        (counts[b.id] ?? 0).compareTo(counts[a.id] ?? 0),
        a,
        b,
      ),
      VaultCategorySort.fewestItems => _compareThenCategoryNames(
        (counts[a.id] ?? 0).compareTo(counts[b.id] ?? 0),
        a,
        b,
      ),
    };
  });
}

int _compareThenTitle(int primary, VaultItem a, VaultItem b) {
  if (primary != 0) {
    return primary;
  }
  final titleOrder = _compareTitles(a, b);
  if (titleOrder != 0) {
    return titleOrder;
  }
  return b.updatedAt.compareTo(a.updatedAt);
}

int _compareThenCategoryNames(int primary, VaultCategory a, VaultCategory b) {
  return primary != 0 ? primary : _compareCategoryNames(a, b);
}

int _compareTitles(VaultItem a, VaultItem b) {
  final aTitle = a.title.trim().isEmpty ? '未命名' : a.title.trim();
  final bTitle = b.title.trim().isEmpty ? '未命名' : b.title.trim();
  return aTitle.toLowerCase().compareTo(bTitle.toLowerCase());
}

int _compareCategoryNames(VaultCategory a, VaultCategory b) {
  return a.name.toLowerCase().compareTo(b.name.toLowerCase());
}
