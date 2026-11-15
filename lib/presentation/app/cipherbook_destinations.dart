import 'package:flutter/widgets.dart';
import 'package:prism_shell/prism_shell.dart';

import '../categories/categories_page.dart';
import '../dashboard/dashboard_page.dart';
import '../security/security_page.dart';
import '../shell/cipherbook_navigation.dart';
import '../sync/sync_page.dart';
import '../theme/cipherbook_glyphs.dart';
import '../tools/tools_page.dart';
import '../vault/vault_page.dart';

List<ShellDestinationSpec> cipherbookDestinationsOf(BuildContext context) {
  return [
    ShellDestinationSpec(
      id: CipherbookDestinationId.dashboard,
      glyph: VaultGlyphs.dashboard,
      label: (_) => '仪表盘',
      mobile: true,
      builder: (_) => const CipherbookDashboardPage(),
    ),
    ShellDestinationSpec(
      id: CipherbookDestinationId.vault,
      glyph: VaultGlyphs.vault,
      label: (_) => '全部密码',
      mobile: true,
      builder: (_) => const CipherbookVaultPage(),
    ),
    ShellDestinationSpec(
      id: CipherbookDestinationId.categories,
      glyph: VaultGlyphs.categories,
      label: (_) => '分类',
      mobile: true,
      builder: (_) => const CipherbookCategoriesPage(),
    ),
    ShellDestinationSpec(
      id: CipherbookDestinationId.security,
      glyph: VaultGlyphs.shield,
      label: (_) => '密码检查',
      builder: (_) => const CipherbookSecurityPage(),
    ),
    ShellDestinationSpec(
      id: CipherbookDestinationId.sync,
      glyph: VaultGlyphs.sync,
      label: (_) => '设备同步',
      mobile: true,
      builder: (_) => const CipherbookSyncPage(),
    ),
    ShellDestinationSpec(
      id: CipherbookDestinationId.tools,
      glyph: VaultGlyphs.tools,
      label: (_) => '工具',
      mobile: true,
      builder: (_) => const CipherbookToolsPage(),
    ),
  ];
}
