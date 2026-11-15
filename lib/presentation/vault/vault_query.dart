import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/vault_models.dart';
import 'vault_sort.dart';

enum VaultListFilter { all, favorites, repeated, weak, totp, deleted, category }

class VaultQuery {
  const VaultQuery({
    this.filter = VaultListFilter.all,
    this.search = '',
    this.categoryId,
    this.selectedItemId,
  });

  final VaultListFilter filter;
  final String search;
  final String? categoryId;
  final String? selectedItemId;

  VaultQuery copyWith({
    VaultListFilter? filter,
    String? search,
    String? categoryId,
    String? selectedItemId,
    bool clearCategory = false,
    bool clearSelectedItem = false,
  }) {
    return VaultQuery(
      filter: filter ?? this.filter,
      search: search ?? this.search,
      categoryId: clearCategory ? null : categoryId ?? this.categoryId,
      selectedItemId: clearSelectedItem
          ? null
          : selectedItemId ?? this.selectedItemId,
    );
  }
}

class VaultQueryController extends Notifier<VaultQuery> {
  @override
  VaultQuery build() => const VaultQuery();

  void showAll() {
    state = const VaultQuery();
  }

  void setFilter(
    VaultListFilter filter, {
    String? categoryId,
    String? selectedItemId,
  }) {
    state = VaultQuery(
      filter: filter,
      search: state.search,
      categoryId: categoryId,
      selectedItemId: selectedItemId,
    );
  }

  void setSearch(String search) {
    state = state.copyWith(search: search);
  }
}

final vaultQueryProvider = NotifierProvider<VaultQueryController, VaultQuery>(
  VaultQueryController.new,
);

List<VaultItem> filterVaultItems(
  VaultData data,
  VaultQuery query, {
  required Set<String> repeatedItemIds,
  required Set<String> weakItemIds,
  VaultItemSort sort = VaultItemSort.recentlyUpdated,
}) {
  final source = switch (query.filter) {
    VaultListFilter.deleted => data.deletedItems,
    _ => data.activeItems,
  };
  final normalizedSearch = query.search.trim().toLowerCase();

  final filtered = source.where((item) {
    final filterMatches = switch (query.filter) {
      VaultListFilter.all || VaultListFilter.deleted => true,
      VaultListFilter.favorites => item.favorite,
      VaultListFilter.repeated => repeatedItemIds.contains(item.id),
      VaultListFilter.weak => weakItemIds.contains(item.id),
      VaultListFilter.totp => (item.totpSecret ?? '').trim().isNotEmpty,
      VaultListFilter.category => item.folder == query.categoryId,
    };
    if (!filterMatches) {
      return false;
    }
    if (normalizedSearch.isEmpty) {
      return true;
    }
    return item.title.toLowerCase().contains(normalizedSearch) ||
        item.username.toLowerCase().contains(normalizedSearch) ||
        item.url.toLowerCase().contains(normalizedSearch) ||
        item.notes.toLowerCase().contains(normalizedSearch);
  }).toList();

  sortVaultItems(
    filtered,
    sort,
    deleted: query.filter == VaultListFilter.deleted,
  );
  return filtered;
}
