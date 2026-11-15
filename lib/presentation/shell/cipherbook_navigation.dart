import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prism_shell/prism_shell.dart';

import '../vault/vault_query.dart';

abstract final class CipherbookDestinationId {
  static const dashboard = 'dashboard';
  static const vault = 'vault';
  static const categories = 'categories';
  static const security = 'security';
  static const sync = 'sync';
  static const tools = 'tools';
}

void openVault(
  BuildContext context,
  WidgetRef ref, {
  VaultListFilter filter = VaultListFilter.all,
  String? categoryId,
  String? selectedItemId,
}) {
  ref
      .read(vaultQueryProvider.notifier)
      .setFilter(
        filter,
        categoryId: categoryId,
        selectedItemId: selectedItemId,
      );
  ShellNavigationScope.navigationOf(
    context,
  ).select(CipherbookDestinationId.vault);
}
