import 'dart:convert';
import 'dart:math';

import 'package:cipherbook/models/vault_models.dart';
import 'package:cipherbook/presentation/app/cipherbook_prism_app.dart';
import 'package:cipherbook/presentation/shell/cipherbook_navigation.dart';
import 'package:cipherbook/presentation/theme/cipherbook_visual_tokens.dart';
import 'package:cipherbook/presentation/vault/vault_page.dart';
import 'package:cipherbook/presentation/vault/vault_query.dart';
import 'package:cipherbook/services/clipboard_service.dart';
import 'package:cipherbook/services/crypto_service.dart';
import 'package:cipherbook/services/device_key_store.dart';
import 'package:cipherbook/services/import_export_service.dart';
import 'package:cipherbook/services/lan_sync_service.dart';
import 'package:cipherbook/services/password_generator_service.dart';
import 'package:cipherbook/services/vault_repository.dart';
import 'package:cipherbook/state/vault_controller.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_shell/prism_shell.dart';
import 'package:prism_ui/prism_ui.dart';

Finder _categoryListItem(String text) {
  return find.descendant(
    of: find.byKey(const ValueKey('prism-category-list-pane')),
    matching: find.text(text),
  );
}

void main() {
  testWidgets('Prism frontend shows real dashboard data and vault entries', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 800);
    addTearDown(tester.view.reset);

    final controller = _buildController();
    addTearDown(controller.dispose);
    await controller.bootstrap();
    await controller.createVault('master-pass');
    await controller.addCategory('工作');
    await controller.addOrUpdateItem(
      title: 'GitHub',
      username: 'alice@example.com',
      password: 'shared-password',
      url: 'https://github.com',
      notes: 'Work account',
      tags: const [],
    );
    await controller.addOrUpdateItem(
      title: 'Mail',
      username: 'alice@example.com',
      password: 'shared-password',
      url: 'https://mail.example.com',
      notes: '',
      tags: const [],
    );
    final category = controller.vaultData.categories.single;
    final github = controller.vaultData.activeItems.singleWhere(
      (item) => item.title == 'GitHub',
    );
    await controller.assignItemToCategory(
      itemId: github.id,
      categoryId: category.id,
    );

    await tester.pumpWidget(CipherbookPrismApp(controller: controller));
    await tester.pumpAndSettle();

    final localizationContext = tester.element(find.text('密码库'));
    expect(UiLocalizations.of(localizationContext).back, '返回');
    expect(find.text('仪表盘'), findsWidgets);
    expect(find.text('密码库'), findsOneWidget);
    expect(find.text('全部密码'), findsWidgets);
    expect(find.text('分类'), findsWidgets);

    await tester.tap(find.text('全部密码').first);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('prism-vault-add-password')),
      findsOneWidget,
    );
    expect(find.text('GitHub'), findsWidgets);
    expect(find.text('Mail'), findsOneWidget);
    expect(find.text('alice@example.com'), findsWidgets);
    expect(find.text('工作'), findsWidgets);
    final githubRow = find.byKey(ValueKey('prism-vault-entry-${github.id}'));
    final githubTitle = find.byKey(
      ValueKey('prism-password-title-${github.id}'),
    );
    expect(
      tester.getTopLeft(githubTitle).dx - tester.getTopLeft(githubRow).dx,
      closeTo(61, 0.5),
    );
    expect(
      find.byKey(const ValueKey('prism-detail-copy-password')),
      findsOneWidget,
    );
    final favoriteButton = find.byKey(const ValueKey('prism-detail-favorite'));
    expect(favoriteButton, findsOneWidget);
    expect(find.text('收藏'), findsWidgets);
    expect(find.textContaining('当前为只读工作区'), findsNothing);

    final filters = find.byKey(const ValueKey('prism-vault-filters'));
    expect(filters, findsOneWidget);
    final detailCard = find.byKey(const ValueKey('prism-vault-detail-card'));
    expect(detailCard, findsOneWidget);
    expect(tester.widget(detailCard), isA<Column>());
    expect(
      find.ancestor(of: detailCard, matching: find.byType(Card)),
      findsNothing,
    );
    expect(tester.getSize(detailCard).width, lessThanOrEqualTo(1000));
    expect(
      find.byKey(const ValueKey('prism-detail-credential-grid')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('prism-detail-metadata-strip')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('prism-detail-main-column')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('prism-detail-side-column')),
      findsNothing,
    );
    final detailPane = find.byKey(const ValueKey('prism-vault-detail-pane'));
    expect(
      tester.getTopLeft(detailCard).dy - tester.getTopLeft(detailPane).dy,
      closeTo(CipherbookVisualTokens.space12, 0.5),
    );
    expect(
      tester.getBottomRight(detailPane).dy -
          tester.getBottomRight(detailCard).dy,
      closeTo(CipherbookVisualTokens.space20, 0.5),
    );
    await tester.tap(favoriteButton);
    await tester.pumpAndSettle();
    expect(
      controller.vaultData.activeItems
          .singleWhere((item) => item.id == github.id)
          .favorite,
      isTrue,
    );
    expect(find.text('取消收藏'), findsOneWidget);

    await tester.tap(find.descendant(of: filters, matching: find.text('收藏')));
    await tester.pumpAndSettle();

    final providerContainer = ProviderScope.containerOf(
      tester.element(find.byType(CipherbookVaultPage)),
    );
    expect(
      providerContainer.read(vaultQueryProvider).filter,
      VaultListFilter.favorites,
    );
    expect(find.text('GitHub'), findsWidgets);
    expect(find.text('Mail'), findsNothing);

    await controller.lock();
    await tester.pumpAndSettle();

    expect(find.text('输入主密码'), findsOneWidget);
    expect(find.text('密码库'), findsNothing);
    expect(find.text('本地加密 · 不上传云端'), findsNothing);
  });

  testWidgets('all passwords can change the password sort order', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 800);
    addTearDown(tester.view.reset);

    final controller = _buildController();
    addTearDown(controller.dispose);
    await controller.bootstrap();
    await controller.createVault('master-pass');
    await controller.addOrUpdateItem(
      title: 'Alpha',
      username: '',
      password: 'pw',
      url: '',
      notes: '',
      tags: const [],
    );
    await controller.addOrUpdateItem(
      title: 'Zulu',
      username: '',
      password: 'pw',
      url: '',
      notes: '',
      tags: const [],
    );
    final alpha = controller.vaultData.activeItems.singleWhere(
      (item) => item.title == 'Alpha',
    );
    final zulu = controller.vaultData.activeItems.singleWhere(
      (item) => item.title == 'Zulu',
    );

    await tester.pumpWidget(CipherbookPrismApp(controller: controller));
    await tester.pumpAndSettle();
    await tester.tap(find.text('全部密码').first);
    await tester.pumpAndSettle();

    final alphaCard = find.byKey(ValueKey('prism-vault-entry-${alpha.id}'));
    final zuluCard = find.byKey(ValueKey('prism-vault-entry-${zulu.id}'));

    await tester.tap(find.byKey(const ValueKey('prism-vault-sort')));
    await tester.pumpAndSettle();
    expect(find.text('密码排序'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('prism-vault-sort-titleDescending')),
    );
    await tester.pumpAndSettle();

    expect(find.text('名称 Z-A'), findsOneWidget);
    expect(
      tester.getTopLeft(zuluCard).dy,
      lessThan(tester.getTopLeft(alphaCard).dy),
    );

    await controller.lock();
    await tester.pumpAndSettle();
  });

  testWidgets('unlock card stays vertically centered on a phone', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(375, 812);
    addTearDown(tester.view.reset);

    final controller = _buildController();
    addTearDown(controller.dispose);
    await controller.bootstrap();
    await controller.createVault('master-pass');
    await controller.lock();

    await tester.pumpWidget(CipherbookPrismApp(controller: controller));
    await tester.pumpAndSettle();

    final card = find.byKey(const ValueKey('prism-unlock-card'));
    expect(card, findsOneWidget);
    expect(
      (tester.getCenter(card).dy - tester.view.physicalSize.height / 2).abs(),
      lessThan(2),
    );
  });

  testWidgets('one-tap lock only appears on the dashboard', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(375, 812);
    addTearDown(tester.view.reset);

    final controller = _buildController();
    addTearDown(controller.dispose);
    await controller.bootstrap();
    await controller.createVault('master-pass');

    await tester.pumpWidget(CipherbookPrismApp(controller: controller));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('prism-dashboard-lock')), findsOneWidget);

    await tester.tap(find.text('全部密码').first);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('prism-dashboard-lock')), findsNothing);
    expect(find.byTooltip('锁定密码库'), findsNothing);

    await tester.tap(find.text('工具').last);
    await tester.pumpAndSettle();
    expect(find.text('立即锁定'), findsNothing);

    await controller.lock();
    await tester.pumpAndSettle();
  });

  testWidgets('Prism frontend uses a list-to-detail flow on narrow screens', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(375, 812);
    addTearDown(tester.view.reset);

    final controller = _buildController();
    addTearDown(controller.dispose);
    await controller.bootstrap();
    await controller.createVault('master-pass');
    await controller.addOrUpdateItem(
      title: 'GitHub',
      username: 'alice@example.com',
      password: 'secret-password',
      url: 'https://github.com',
      notes: 'Work account',
      tags: const [],
    );

    await tester.pumpWidget(CipherbookPrismApp(controller: controller));
    await tester.pumpAndSettle();

    await tester.tap(find.text('全部密码').first);
    await tester.pumpAndSettle();
    expect(find.text('GitHub'), findsOneWidget);
    final addPassword = find.byKey(const ValueKey('prism-vault-add-password'));
    expect(addPassword, findsOneWidget);
    expect(
      tester.getBottomRight(addPassword).dx,
      lessThanOrEqualTo(tester.view.physicalSize.width - 16),
    );

    await tester.tap(find.text('GitHub'));
    await tester.pumpAndSettle();
    expect(find.text('返回列表'), findsOneWidget);
    expect(find.text('alice@example.com'), findsWidgets);
    expect(
      find.byKey(const ValueKey('shell-narrow-navigation-dock')),
      findsNothing,
    );
    final scroll = find.byKey(const ValueKey('prism-detail-scroll'));
    final footer = find.byKey(const ValueKey('prism-detail-footer'));
    expect(scroll, findsOneWidget);
    expect(footer, findsOneWidget);
    expect(find.descendant(of: scroll, matching: footer), findsOneWidget);
    final scrollRect = tester.getRect(scroll);
    expect(scrollRect.height.isFinite, isTrue);
    expect(scrollRect.height, greaterThan(0));
    final scrollable = find.descendant(
      of: scroll,
      matching: find.byType(Scrollable),
    );
    final position = tester.state<ScrollableState>(scrollable).position;
    expect(position.maxScrollExtent, greaterThan(0));
    position.jumpTo(position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(
      tester
          .getRect(find.byKey(const ValueKey('prism-detail-metadata-strip')))
          .bottom,
      lessThanOrEqualTo(tester.getRect(footer).top),
    );
    expect(tester.getRect(footer).bottom, lessThanOrEqualTo(scrollRect.bottom));
    expect(
      scrollRect.bottom - tester.getRect(footer).bottom,
      greaterThanOrEqualTo(16),
    );

    await tester.tap(find.text('返回列表'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('shell-narrow-navigation-dock')),
      findsOneWidget,
    );

    await controller.lock();
    await tester.pumpAndSettle();
  });

  testWidgets(
    'Prism frontend completes quick unlock without a build conflict',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1280, 800);
      addTearDown(tester.view.reset);

      final deviceKeyStore = _MemoryDeviceKeyStore(
        supported: true,
        readDelay: const Duration(milliseconds: 200),
      );
      final controller = _buildController(deviceKeyStore: deviceKeyStore);
      addTearDown(controller.dispose);
      await controller.bootstrap();
      await controller.createVault('master-pass');
      await controller.addOrUpdateItem(
        title: 'Quick unlock record',
        username: 'alice@example.com',
        password: 'secret-password',
        url: 'https://example.com',
        notes: '',
        tags: const [],
      );
      await controller.enableQuickUnlock();
      await controller.lock();

      await tester.pumpWidget(CipherbookPrismApp(controller: controller));
      await tester.pumpAndSettle();

      expect(find.text('使用系统认证快速解锁'), findsOneWidget);
      await tester.tap(find.text('使用系统认证快速解锁'));
      await tester.pump();
      expect(find.text('使用系统认证快速解锁'), findsOneWidget);
      await tester.pumpAndSettle();

      expect(find.text('密码库'), findsOneWidget);
      expect(find.text('Quick unlock record'), findsOneWidget);

      await controller.lock();
      await tester.pumpAndSettle();
    },
  );

  testWidgets('Prism frontend locks when the app enters background', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 800);
    addTearDown(tester.view.reset);
    addTearDown(() {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    });

    final controller = _buildController();
    addTearDown(controller.dispose);
    await controller.bootstrap();
    await controller.createVault('master-pass');

    await tester.pumpWidget(CipherbookPrismApp(controller: controller));
    await tester.pumpAndSettle();
    expect(find.text('仪表盘'), findsWidgets);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await tester.pump();
    expect(controller.isUnlocked, isFalse);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('输入主密码'), findsOneWidget);
    expect(find.text('仪表盘'), findsNothing);
  });

  testWidgets('auto-lock duration can be changed from tools', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 800);
    addTearDown(tester.view.reset);

    final controller = _buildController();
    addTearDown(controller.dispose);
    await controller.bootstrap();
    await controller.createVault('master-pass');

    await tester.pumpWidget(CipherbookPrismApp(controller: controller));
    await tester.pumpAndSettle();
    await tester.tap(find.text('工具'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('prism-auto-lock-setting')));
    await tester.pumpAndSettle();
    expect(find.text('自动锁定'), findsWidgets);

    await tester.tap(find.byKey(const ValueKey('prism-auto-lock-fiveMinutes')));
    await tester.pumpAndSettle();

    expect(controller.autoLockPreset, AutoLockPreset.fiveMinutes);
    expect(find.text('5 分钟'), findsOneWidget);
    await controller.lock();
    await tester.pumpAndSettle();
  });

  testWidgets('sync workspace uses a centered readable width', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 800);
    addTearDown(tester.view.reset);

    final controller = _buildController();
    addTearDown(controller.dispose);
    await controller.bootstrap();
    await controller.createVault('master-pass');

    await tester.pumpWidget(CipherbookPrismApp(controller: controller));
    await tester.pumpAndSettle();
    await tester.tap(find.text('设备同步').first);
    await tester.pumpAndSettle();

    final content = find.byKey(const ValueKey('prism-sync-content'));
    expect(content, findsOneWidget);
    expect(tester.getSize(content).width, lessThanOrEqualTo(760));
    expect(find.byKey(const ValueKey('prism-sync-primary')), findsOneWidget);
    expect(find.byKey(const ValueKey('prism-sync-secondary')), findsOneWidget);
    expect(find.byKey(const ValueKey('prism-sync-all')), findsNothing);
    expect(tester.takeException(), isNull);
    await controller.lock();
    await tester.pumpAndSettle();
  });

  testWidgets('discovered LAN devices expose password-verified sync', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(375, 812);
    addTearDown(tester.view.reset);

    final controller = _DiscoveredSyncController();
    addTearDown(controller.dispose);
    await controller.bootstrap();
    await controller.createVault('master-pass');

    await tester.pumpWidget(CipherbookPrismApp(controller: controller));
    await tester.pumpAndSettle();
    await tester.tap(find.text('设备同步').last);
    await tester.pumpAndSettle();

    expect(find.text('测试平板'), findsOneWidget);
    final syncButton = find.byKey(const ValueKey('prism-sync-all'));
    _expectMinHitTarget(tester, syncButton);
    await tester.ensureVisible(syncButton);
    await tester.tap(syncButton);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('prism-sync-password-dialog')),
      findsOneWidget,
    );
    await tester.enterText(
      find.byKey(const ValueKey('prism-sync-password-field')),
      'master-pass',
    );
    await tester.tap(find.byKey(const ValueKey('prism-sync-password-confirm')));
    await tester.pumpAndSettle();

    expect(controller.submittedPassword, 'master-pass');
    expect(
      find.byKey(const ValueKey('prism-sync-password-dialog')),
      findsNothing,
    );
    expect(find.text('同步成功：测试通知'), findsOneWidget);

    await controller.lock();
    await tester.pumpAndSettle();
  });

  testWidgets('Prism password rows drag directly into categories', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 800);
    addTearDown(tester.view.reset);

    final controller = _buildController();
    addTearDown(controller.dispose);
    await controller.bootstrap();
    await controller.createVault('master-pass');
    await controller.addCategory('工作');
    await controller.addOrUpdateItem(
      title: 'Alpha',
      username: 'alice',
      password: 'pw',
      url: '',
      notes: '',
      tags: const [],
    );

    await tester.pumpWidget(CipherbookPrismApp(controller: controller));
    await tester.pumpAndSettle();
    await _showCategories(tester);

    final category = controller.vaultData.categories.single;
    final item = controller.vaultData.activeItems.single;
    final source = find.byKey(ValueKey('prism-password-drag-${item.id}'));
    final handle = find.byKey(
      ValueKey('prism-password-drag-handle-${item.id}'),
    );
    expect(source, findsOneWidget);
    expect(handle, findsOneWidget);
    expect(find.byKey(const ValueKey('prism-category-organize')), findsNothing);

    Future<void> dragPasswordTo(Key targetKey) async {
      final target = find.byKey(targetKey);
      final start = tester.getCenter(source);
      final gesture = await tester.startGesture(start);
      await tester.pump(const Duration(milliseconds: 600));
      await gesture.moveBy(const Offset(24, 0));
      await tester.pump();
      await gesture.moveTo(tester.getCenter(target));
      await tester.pump(const Duration(milliseconds: 100));
      await gesture.up();
      await tester.pumpAndSettle();
    }

    await dragPasswordTo(ValueKey('prism-category-drop-${category.id}'));
    expect(controller.vaultData.activeItems.single.folder, category.id);
    expect(find.byType(CipherbookVaultPage), findsNothing);

    await dragPasswordTo(const ValueKey('prism-category-drop-uncategorized'));
    expect(controller.vaultData.activeItems.single.folder, isEmpty);
    expect(find.byType(CipherbookVaultPage), findsNothing);
    expect(source, findsOneWidget);
    expect(handle, findsOneWidget);

    expect(
      find.byKey(ValueKey('prism-category-more-${category.id}')),
      findsNothing,
    );
    await tester.tap(
      find.byKey(ValueKey('prism-category-drop-${category.id}')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('prism-category-action-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('prism-category-menu-rename')));
    await tester.pumpAndSettle();
    expect(find.text('查看密码'), findsNothing);
    expect(find.text('重命名'), findsOneWidget);
    expect(find.text('删除'), findsOneWidget);
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();

    await controller.lock();
    await tester.pumpAndSettle();
  });

  testWidgets('category selection filters passwords without leaving the page', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 800);
    addTearDown(tester.view.reset);

    final controller = _buildController();
    addTearDown(controller.dispose);
    await controller.bootstrap();
    await controller.createVault('master-pass');
    await controller.addCategory('工作');
    await controller.addCategory('个人');
    for (final title in ['Alpha', 'Beta', 'Gamma']) {
      await controller.addOrUpdateItem(
        title: title,
        username: '',
        password: 'pw',
        url: '',
        notes: '',
        tags: const [],
      );
    }

    final work = controller.vaultData.categories.singleWhere(
      (category) => category.name == '工作',
    );
    final personal = controller.vaultData.categories.singleWhere(
      (category) => category.name == '个人',
    );
    final alpha = controller.vaultData.activeItems.singleWhere(
      (item) => item.title == 'Alpha',
    );
    final beta = controller.vaultData.activeItems.singleWhere(
      (item) => item.title == 'Beta',
    );
    await controller.assignItemToCategory(
      itemId: alpha.id,
      categoryId: work.id,
    );
    await controller.assignItemToCategory(
      itemId: beta.id,
      categoryId: personal.id,
    );

    await tester.pumpWidget(CipherbookPrismApp(controller: controller));
    await tester.pumpAndSettle();
    await _showCategories(tester);

    await tester.tap(find.byKey(ValueKey('prism-category-drop-${work.id}')));
    await tester.pumpAndSettle();

    expect(find.byType(CipherbookVaultPage), findsNothing);
    expect(_categoryListItem('Alpha'), findsOneWidget);
    expect(_categoryListItem('Beta'), findsNothing);
    expect(_categoryListItem('Gamma'), findsNothing);
    expect(find.text('共 1 条'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('prism-category-all-passwords')),
    );
    await tester.pumpAndSettle();
    expect(_categoryListItem('Alpha'), findsOneWidget);
    expect(_categoryListItem('Beta'), findsOneWidget);
    expect(_categoryListItem('Gamma'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('prism-category-drop-uncategorized')),
    );
    await tester.pumpAndSettle();
    expect(_categoryListItem('Alpha'), findsNothing);
    expect(_categoryListItem('Beta'), findsNothing);
    expect(_categoryListItem('Gamma'), findsOneWidget);
    expect(find.text('共 1 条'), findsOneWidget);
    expect(find.byType(CipherbookVaultPage), findsNothing);

    await controller.lock();
    await tester.pumpAndSettle();
  });

  testWidgets('category search works across all passwords and one category', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 800);
    addTearDown(tester.view.reset);

    final controller = _buildController();
    addTearDown(controller.dispose);
    await controller.bootstrap();
    await controller.createVault('master-pass');
    await controller.addCategory('工作');
    for (final title in ['Alpha', 'Beta', 'Gamma']) {
      await controller.addOrUpdateItem(
        title: title,
        username: '',
        password: 'pw',
        url: '',
        notes: '',
        tags: const [],
      );
    }
    final work = controller.vaultData.categories.single;
    final alpha = controller.vaultData.activeItems.singleWhere(
      (item) => item.title == 'Alpha',
    );
    await controller.assignItemToCategory(
      itemId: alpha.id,
      categoryId: work.id,
    );

    await tester.pumpWidget(CipherbookPrismApp(controller: controller));
    await tester.pumpAndSettle();
    await _showCategories(tester);

    final search = find.byKey(const ValueKey('prism-category-password-search'));
    expect(
      find.byKey(const ValueKey('prism-category-all-passwords')),
      findsOneWidget,
    );

    await tester.enterText(search, 'beta');
    await tester.pumpAndSettle();
    expect(_categoryListItem('Alpha'), findsNothing);
    expect(_categoryListItem('Beta'), findsOneWidget);
    expect(_categoryListItem('Gamma'), findsNothing);
    expect(find.text('1 条结果'), findsOneWidget);

    await tester.tap(find.byKey(ValueKey('prism-category-drop-${work.id}')));
    await tester.pumpAndSettle();
    expect(find.text('没有匹配的密码'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('prism-category-detail-empty')),
      findsOneWidget,
    );

    await tester.enterText(search, 'a');
    await tester.pumpAndSettle();
    expect(_categoryListItem('Alpha'), findsOneWidget);
    expect(_categoryListItem('Beta'), findsNothing);
    expect(_categoryListItem('Gamma'), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey('prism-category-all-passwords')),
    );
    await tester.pumpAndSettle();
    expect(_categoryListItem('Alpha'), findsOneWidget);
    expect(_categoryListItem('Beta'), findsOneWidget);
    expect(_categoryListItem('Gamma'), findsOneWidget);
    expect(find.text('3 条结果'), findsOneWidget);

    await tester.tap(find.byTooltip('清除搜索'));
    await tester.pumpAndSettle();
    expect(find.text('未分类 2 · 共 3'), findsOneWidget);

    await controller.lock();
    await tester.pumpAndSettle();
  });

  testWidgets('categories page can sort categories and passwords', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 800);
    addTearDown(tester.view.reset);

    final controller = _buildController();
    addTearDown(controller.dispose);
    await controller.bootstrap();
    await controller.createVault('master-pass');
    await controller.addCategory('Beta');
    await controller.addCategory('Alpha');
    await controller.addOrUpdateItem(
      title: 'Aardvark',
      username: '',
      password: 'pw',
      url: '',
      notes: '',
      tags: const [],
    );
    await controller.addOrUpdateItem(
      title: 'Zulu',
      username: '',
      password: 'pw',
      url: '',
      notes: '',
      tags: const [],
    );
    final beta = controller.vaultData.categories.singleWhere(
      (category) => category.name == 'Beta',
    );
    final alpha = controller.vaultData.categories.singleWhere(
      (category) => category.name == 'Alpha',
    );
    final aardvark = controller.vaultData.activeItems.singleWhere(
      (item) => item.title == 'Aardvark',
    );
    final zulu = controller.vaultData.activeItems.singleWhere(
      (item) => item.title == 'Zulu',
    );
    await controller.assignItemToCategory(
      itemId: aardvark.id,
      categoryId: beta.id,
    );
    await controller.assignItemToCategory(itemId: zulu.id, categoryId: beta.id);

    await tester.pumpWidget(CipherbookPrismApp(controller: controller));
    await tester.pumpAndSettle();
    await tester.tap(find.text('分类').last);
    await tester.pumpAndSettle();

    final betaCard = find.byKey(ValueKey('prism-category-drop-${beta.id}'));
    final alphaCard = find.byKey(ValueKey('prism-category-drop-${alpha.id}'));
    final sortMenu = find.byKey(const ValueKey('prism-category-sort-menu'));
    expect(
      tester.getTopLeft(betaCard).dx,
      lessThan(tester.getTopLeft(alphaCard).dx),
    );
    expect(
      tester
          .getSize(find.byKey(const ValueKey('prism-category-password-search')))
          .width,
      greaterThanOrEqualTo(240),
    );
    final createCategory = find.byKey(
      const ValueKey('prism-category-add-primary'),
    );
    expect(
      find.descendant(of: createCategory, matching: find.text('新建分类')),
      findsOneWidget,
    );
    expect(tester.getSize(createCategory).height, greaterThanOrEqualTo(44));
    expect(
      find.descendant(of: sortMenu, matching: find.text('名称 A-Z')),
      findsOneWidget,
    );

    await tester.tap(sortMenu);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('prism-category-order-sort')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('prism-category-order-nameAscending')),
    );
    await tester.pumpAndSettle();

    await tester.tap(sortMenu);
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('prism-category-order-sort')),
        matching: find.text('名称 A-Z'),
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(alphaCard).dx,
      lessThan(tester.getTopLeft(betaCard).dx),
    );

    final aardvarkRow = find.byKey(
      ValueKey('prism-password-row-${aardvark.id}'),
    );
    final zuluRow = find.byKey(ValueKey('prism-password-row-${zulu.id}'));
    expect(
      tester.getTopLeft(aardvarkRow).dy,
      lessThan(tester.getTopLeft(zuluRow).dy),
    );

    await tester.tap(sortMenu);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('prism-category-password-sort')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(
        const ValueKey('prism-category-password-sort-titleDescending'),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.descendant(of: sortMenu, matching: find.text('名称 Z-A')),
      findsOneWidget,
    );
    await tester.tap(sortMenu);
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('prism-category-password-sort')),
        matching: find.text('名称 Z-A'),
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(zuluRow).dy,
      lessThan(tester.getTopLeft(aardvarkRow).dy),
    );

    await controller.lock();
    await tester.pumpAndSettle();
  });

  testWidgets('category page keeps password creation on all passwords', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 800);
    addTearDown(tester.view.reset);

    final controller = _buildController();
    addTearDown(controller.dispose);
    await controller.bootstrap();
    await controller.createVault('master-pass');
    await controller.addCategory('工作');
    final category = controller.vaultData.categories.single;

    await tester.pumpWidget(CipherbookPrismApp(controller: controller));
    await tester.pumpAndSettle();
    await tester.tap(find.text('分类').last);
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(ValueKey('prism-category-drop-${category.id}')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('prism-category-add-password')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('prism-empty-category-add')),
      findsNothing,
    );
    expect(find.text('在当前分类新增密码'), findsNothing);

    await _showAllPasswords(tester);
    expect(
      find.byKey(const ValueKey('prism-vault-add-password')),
      findsOneWidget,
    );

    await controller.lock();
    await tester.pumpAndSettle();
  });

  testWidgets('category chips are password drop targets, not drag sources', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
    });
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 800);
    addTearDown(tester.view.reset);

    final controller = _buildController();
    addTearDown(controller.dispose);
    await controller.bootstrap();
    await controller.createVault('master-pass');
    await controller.addCategory('工作');
    await controller.addCategory('个人');
    await controller.addCategory('财务');

    await tester.pumpWidget(CipherbookPrismApp(controller: controller));
    await tester.pumpAndSettle();
    await _showCategories(tester);

    for (final category in controller.vaultData.categories) {
      expect(
        find.byKey(ValueKey('prism-category-drop-${category.id}')),
        findsOneWidget,
      );
      expect(
        find.byKey(ValueKey('prism-category-reorder-${category.id}')),
        findsNothing,
      );
      expect(
        find.byKey(ValueKey('prism-category-drag-handle-${category.id}')),
        findsNothing,
      );
    }

    expect(controller.vaultData.categories.map((item) => item.name), [
      '工作',
      '个人',
      '财务',
    ]);
    debugDefaultTargetPlatformOverride = null;
    await controller.lock();
    await tester.pumpAndSettle();
  });

  testWidgets('category password opens details and can move categories', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 800);
    addTearDown(tester.view.reset);

    final controller = _buildController();
    addTearDown(controller.dispose);
    await controller.bootstrap();
    await controller.createVault('master-pass');
    await controller.addCategory('工作');
    await controller.addCategory('个人');
    await controller.addOrUpdateItem(
      title: 'Alpha',
      username: 'alice@example.com',
      password: 'pw',
      url: 'https://example.com',
      notes: 'Work account',
      tags: const [],
    );
    final categories = controller.vaultData.categories;
    final work = categories.singleWhere((category) => category.name == '工作');
    final personal = categories.singleWhere(
      (category) => category.name == '个人',
    );
    final item = controller.vaultData.activeItems.single;
    await controller.assignItemToCategory(itemId: item.id, categoryId: work.id);

    await tester.pumpWidget(CipherbookPrismApp(controller: controller));
    await tester.pumpAndSettle();
    await tester.tap(find.text('分类').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(ValueKey('prism-password-title-${item.id}')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('prism-category-item-details')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('prism-category-detail-category')),
          )
          .data,
      '工作',
    );
    expect(find.text('https://example.com'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('prism-category-detail-metadata-updated')),
      findsOneWidget,
    );
    expect(find.byType(CipherbookVaultPage), findsNothing);

    final moveButton = find.byKey(const ValueKey('prism-category-detail-move'));
    final detailScroll = find.byKey(
      const ValueKey('prism-category-detail-scroll'),
    );
    if (detailScroll.evaluate().isNotEmpty) {
      await tester.scrollUntilVisible(
        moveButton,
        200,
        scrollable: find.descendant(
          of: detailScroll,
          matching: find.byType(Scrollable),
        ),
      );
    }
    await tester.pumpAndSettle();
    await tester.tap(moveButton);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('prism-category-detail-move-picker')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(ValueKey('prism-category-detail-move-${personal.id}')),
    );
    await tester.pumpAndSettle();

    expect(controller.vaultData.activeItems.single.folder, personal.id);
    expect(
      find.byKey(const ValueKey('prism-category-item-details')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('prism-category-detail-category')),
          )
          .data,
      '个人',
    );
    expect(find.byType(CipherbookVaultPage), findsNothing);

    await controller.lock();
    await tester.pumpAndSettle();
  });

  testWidgets('desktop category rows select details and edit action', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 800);
    addTearDown(tester.view.reset);

    final controller = _buildController();
    addTearDown(controller.dispose);
    await controller.bootstrap();
    await controller.createVault('master-pass');
    await controller.addCategory('工作');
    for (final title in ['Alpha', 'Beta']) {
      await controller.addOrUpdateItem(
        title: title,
        username: '$title@example.com',
        password: 'pw-$title',
        url: 'https://example.com/$title',
        notes: '',
        tags: const [],
        categoryId: controller.vaultData.categories.single.id,
      );
    }
    final beta = controller.vaultData.activeItems.singleWhere(
      (item) => item.title == 'Beta',
    );

    await tester.pumpWidget(CipherbookPrismApp(controller: controller));
    await tester.pumpAndSettle();
    await _showCategories(tester);

    final betaTitle = find.byKey(ValueKey('prism-password-title-${beta.id}'));
    await tester.tap(betaTitle);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('prism-category-detail-title')),
          )
          .data,
      'Beta',
    );
    await tester.tap(find.byKey(ValueKey('prism-password-open-${beta.id}')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('prism-password-editor')), findsOneWidget);
    final titleField = tester.widget<TextField>(
      find.byKey(const ValueKey('prism-password-editor-title')),
    );
    expect(titleField.controller?.text, 'Beta');
    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();

    await controller.lock();
    await tester.pumpAndSettle();
  });

  testWidgets('locking closes mobile category details and clears passwords', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(375, 812);
    addTearDown(tester.view.reset);

    const secret = 'category-detail-secret';
    final controller = _buildController();
    addTearDown(controller.dispose);
    await controller.bootstrap();
    await controller.createVault('master-pass');
    await controller.addCategory('工作');
    final category = controller.vaultData.categories.single;
    await controller.addOrUpdateItem(
      title: '分类敏感详情',
      username: 'alice@example.com',
      password: secret,
      url: '',
      notes: '',
      tags: const [],
      categoryId: category.id,
    );
    final item = controller.vaultData.activeItems.single;

    await tester.pumpWidget(CipherbookPrismApp(controller: controller));
    await tester.pumpAndSettle();
    await tester.tap(find.text('分类').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('prism-password-title-${item.id}')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('prism-category-detail-page')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey('prism-category-detail-password-visibility')),
    );
    await tester.pumpAndSettle();
    expect(find.text(secret), findsOneWidget);

    await controller.lock();
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('prism-category-item-details')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('prism-category-detail-page')),
      findsNothing,
    );
    expect(find.text(secret), findsNothing);
    expect(find.text('输入主密码'), findsOneWidget);
    expect(
      tester
          .widgetList<EditableText>(find.byType(EditableText))
          .any((field) => field.controller.text.contains(secret)),
      isFalse,
    );
  });

  testWidgets('locking disposes password editor and drops unsaved input', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 800);
    addTearDown(tester.view.reset);

    const title = '未保存的敏感条目';
    const secret = 'editor-secret-must-not-return';
    final controller = _buildController();
    addTearDown(controller.dispose);
    await controller.bootstrap();
    await controller.createVault('master-pass');

    await tester.pumpWidget(CipherbookPrismApp(controller: controller));
    await tester.pumpAndSettle();
    await tester.tap(find.text('全部密码').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('prism-vault-add-password')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('prism-password-editor-title')),
      title,
    );
    await tester.enterText(
      find.byKey(const ValueKey('prism-password-editor-username')),
      'editor@example.com',
    );
    await tester.enterText(
      find.byKey(const ValueKey('prism-password-editor-password')),
      secret,
    );
    await tester.pump();

    await controller.lock();
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('prism-password-editor')), findsNothing);
    expect(find.text(title), findsNothing);
    expect(find.text(secret), findsNothing);
    expect(
      tester
          .widgetList<EditableText>(find.byType(EditableText))
          .any((field) => field.controller.text.contains(secret)),
      isFalse,
    );

    await controller.unlock('master-pass');
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('prism-password-editor')), findsNothing);
    expect(find.text(title), findsNothing);
    expect(find.text(secret), findsNothing);
    expect(controller.vaultData.activeItems, isEmpty);

    await controller.lock();
    await tester.pumpAndSettle();
  });

  testWidgets('Windows category page groups passwords with direct drag', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
    });
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 800);
    addTearDown(tester.view.reset);

    final controller = _buildController();
    addTearDown(controller.dispose);
    await controller.bootstrap();
    await controller.createVault('master-pass');
    await controller.addCategory('工作');
    await controller.addOrUpdateItem(
      title: 'Alpha',
      username: 'alice',
      password: 'pw',
      url: '',
      notes: '',
      tags: const [],
    );

    await tester.pumpWidget(CipherbookPrismApp(controller: controller));
    await tester.pumpAndSettle();
    await tester.tap(find.text('分类').first);
    await tester.pumpAndSettle();

    final category = controller.vaultData.categories.single;
    final item = controller.vaultData.activeItems.single;
    final source = find.byKey(ValueKey('prism-password-drag-${item.id}'));
    final handle = find.byKey(
      ValueKey('prism-password-drag-handle-${item.id}'),
    );
    final target = find.byKey(ValueKey('prism-category-drop-${category.id}'));
    final uncategorized = find.byKey(
      const ValueKey('prism-category-drop-uncategorized'),
    );
    expect(
      tester.getSize(target).height,
      closeTo(tester.getSize(uncategorized).height, 0.1),
    );
    final addButton = find.byKey(const ValueKey('prism-category-add-primary'));
    expect(tester.getTopRight(addButton).dx, lessThanOrEqualTo(1264));
    expect(source, findsOneWidget);
    expect(handle, findsOneWidget);
    expect(find.byKey(const ValueKey('prism-category-organize')), findsNothing);

    final start = tester.getCenter(source);
    final gesture = await tester.startGesture(
      start,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await gesture.moveBy(const Offset(24, 0));
    await tester.pump();
    await gesture.moveTo(tester.getCenter(target));
    await tester.pump(const Duration(milliseconds: 100));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(controller.vaultData.activeItems.single.folder, category.id);
    expect(find.byType(CipherbookVaultPage), findsNothing);
    expect(source, findsOneWidget);
    expect(handle, findsOneWidget);

    debugDefaultTargetPlatformOverride = null;
    await controller.lock();
    await tester.pumpAndSettle();
  });

  testWidgets('Windows narrow category tabs keep long-press drag', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
    });
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(700, 820);
    addTearDown(tester.view.reset);

    final controller = _buildController();
    addTearDown(controller.dispose);
    await controller.bootstrap();
    await controller.createVault('master-pass');
    await controller.addCategory('工作');
    await controller.addOrUpdateItem(
      title: 'Alpha',
      username: 'alice',
      password: 'pw',
      url: '',
      notes: '',
      tags: const [],
    );

    await tester.pumpWidget(CipherbookPrismApp(controller: controller));
    await tester.pumpAndSettle();
    await _showCategories(tester);

    final category = controller.vaultData.categories.single;
    final item = controller.vaultData.activeItems.single;
    final source = find.byKey(ValueKey('prism-password-drag-${item.id}'));
    final handle = find.byKey(
      ValueKey('prism-password-drag-handle-${item.id}'),
    );
    expect(
      find.byKey(const ValueKey('prism-category-workbench')),
      findsOneWidget,
    );
    expect(find.text('Alpha'), findsOneWidget);
    expect(source, findsOneWidget);
    expect(handle, findsNothing);
    expect(find.byTooltip('长按拖动密码到分类'), findsNothing);

    final gesture = await tester.startGesture(
      tester.getCenter(source),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
    expect(find.byKey(const ValueKey('prism-category-tabs')), findsOneWidget);

    final target = find.byKey(ValueKey('prism-category-drop-${category.id}'));
    expect(target, findsOneWidget);
    await gesture.moveTo(tester.getCenter(target));
    await tester.pump(const Duration(milliseconds: 100));
    final highlightedSurface = tester.widget<PressSurface>(
      find.descendant(of: target, matching: find.byType(PressSurface)).first,
    );
    expect(
      highlightedSurface.fill,
      tester.element(target).colorScheme.primaryContainer,
    );
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 100));

    expect(controller.vaultData.activeItems.single.folder, category.id);
    expect(find.text('已移动到“工作”'), findsOneWidget);
    expect(find.byKey(const ValueKey('prism-category-tabs')), findsOneWidget);

    debugDefaultTargetPlatformOverride = null;
    await controller.lock();
    await tester.pumpAndSettle();
  });

  testWidgets('Windows narrow category menu exposes category management', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
    });
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(375, 812);
    addTearDown(tester.view.reset);

    final controller = _buildController();
    addTearDown(controller.dispose);
    await controller.bootstrap();
    await controller.createVault('master-pass');
    await controller.addCategory('工作');
    final category = controller.vaultData.categories.single;

    await tester.pumpWidget(CipherbookPrismApp(controller: controller));
    await tester.pumpAndSettle();
    await _showCategories(tester);

    final menuButton = find.byKey(const ValueKey('prism-category-action-menu'));
    expect(menuButton, findsOneWidget);
    expect(tester.getSize(menuButton).height, greaterThanOrEqualTo(40));

    await tester.tap(menuButton);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('prism-category-management-menu')),
      findsOneWidget,
    );

    final addAction = tester.widget<PressSurface>(
      find.byKey(const ValueKey('prism-category-menu-add')),
    );
    final renameAction = tester.widget<PressSurface>(
      find.byKey(const ValueKey('prism-category-menu-rename')),
    );
    final deleteAction = tester.widget<PressSurface>(
      find.byKey(const ValueKey('prism-category-menu-delete')),
    );
    expect(addAction.onPressed, isNotNull);
    expect(renameAction.onPressed, isNull);
    expect(deleteAction.onPressed, isNull);
    expect(
      find.byKey(const ValueKey('prism-category-menu-sort')),
      findsNothing,
    );

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(ValueKey('prism-category-drop-${category.id}')),
    );
    await tester.pumpAndSettle();
    await tester.tap(menuButton);
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<PressSurface>(
            find.byKey(const ValueKey('prism-category-menu-rename')),
          )
          .onPressed,
      isNotNull,
    );
    expect(
      tester
          .widget<PressSurface>(
            find.byKey(const ValueKey('prism-category-menu-delete')),
          )
          .onPressed,
      isNotNull,
    );

    debugDefaultTargetPlatformOverride = null;
    await controller.lock();
    await tester.pumpAndSettle();
  });

  testWidgets('empty category keeps view-all navigation without password add', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(375, 812);
    addTearDown(tester.view.reset);

    final controller = _buildController();
    addTearDown(controller.dispose);
    await controller.bootstrap();
    await controller.createVault('master-pass');
    await controller.addCategory('归档');
    final category = controller.vaultData.categories.single;

    await tester.pumpWidget(CipherbookPrismApp(controller: controller));
    await tester.pumpAndSettle();
    await _showCategories(tester);
    await tester.tap(
      find.byKey(ValueKey('prism-category-drop-${category.id}')),
    );
    await tester.pumpAndSettle();

    expect(find.text('这个分类还没有密码'), findsOneWidget);
    final addPassword = find.byKey(const ValueKey('prism-empty-category-add'));
    final allPasswords = find.byKey(const ValueKey('prism-empty-category-all'));
    expect(addPassword, findsNothing);
    expect(allPasswords, findsOneWidget);
    expect(find.text('可将密码拖入此分类'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('prism-category-add-password')),
      findsNothing,
    );

    await tester.tap(allPasswords);
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<PressSurface>(
            find
                .descendant(
                  of: find.byKey(
                    const ValueKey('prism-category-all-passwords'),
                  ),
                  matching: find.byType(PressSurface),
                )
                .first,
          )
          .selected,
      isTrue,
    );
    expect(
      find.byKey(const ValueKey('prism-empty-category-add')),
      findsNothing,
    );

    await controller.lock();
    await tester.pumpAndSettle();
  });

  testWidgets('category tabs group passwords on a narrow phone', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(375, 812);
    addTearDown(tester.view.reset);

    final controller = _buildController();
    addTearDown(controller.dispose);
    await controller.bootstrap();
    await controller.createVault('master-pass');
    await controller.addCategory('工作');
    await controller.addOrUpdateItem(
      title: 'Alpha',
      username: 'alice',
      password: 'pw',
      url: '',
      notes: '',
      tags: const [],
    );
    final category = controller.vaultData.categories.single;
    final item = controller.vaultData.activeItems.single;
    await controller.assignItemToCategory(
      itemId: item.id,
      categoryId: category.id,
    );

    await tester.pumpWidget(CipherbookPrismApp(controller: controller));
    await tester.pumpAndSettle();
    await tester.tap(find.text('分类').last);
    await tester.pumpAndSettle();

    final primaryAction = find.byKey(
      const ValueKey('prism-category-add-primary'),
    );
    final tabs = find.byKey(const ValueKey('prism-category-tabs'));
    final categoryRow = find.byKey(
      ValueKey('prism-category-drop-${category.id}'),
    );
    final search = find.byKey(const ValueKey('prism-category-password-search'));
    final sortMenu = find.byKey(const ValueKey('prism-category-sort-menu'));
    expect(primaryAction, findsOneWidget);
    expect(tabs, findsOneWidget);
    expect(
      find.byKey(const ValueKey('prism-category-directory')),
      findsNothing,
    );
    expect(categoryRow, findsOneWidget);
    expect(
      find.byKey(const ValueKey('prism-category-add-password')),
      findsNothing,
    );
    expect(search, findsOneWidget);
    expect(sortMenu, findsOneWidget);
    expect(
      find.byKey(const ValueKey('prism-category-order-sort')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('prism-category-password-sort')),
      findsNothing,
    );
    expect(tester.getSize(categoryRow).height, 44);
    expect(
      tester.getTopLeft(tabs).dy,
      greaterThan(tester.getBottomLeft(primaryAction).dy),
    );
    expect(
      tester.getTopLeft(search).dy,
      greaterThan(tester.getBottomLeft(tabs).dy),
    );
    expect(
      find.byKey(ValueKey('prism-password-drag-${item.id}')),
      findsOneWidget,
    );

    await tester.tap(categoryRow);
    await tester.pumpAndSettle();
    expect(find.text('Alpha'), findsOneWidget);
    expect(
      tester
          .widget<PressSurface>(
            find
                .descendant(
                  of: categoryRow,
                  matching: find.byType(PressSurface),
                )
                .first,
          )
          .selected,
      isTrue,
    );
    expect(tester.takeException(), isNull);

    await controller.lock();
    await tester.pumpAndSettle();
  });

  testWidgets('category management stays in place and creates categories', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 800);
    addTearDown(tester.view.reset);

    final controller = _buildController();
    addTearDown(controller.dispose);
    await controller.bootstrap();
    await controller.createVault('master-pass');
    await controller.addCategory('钱包');

    await tester.pumpWidget(CipherbookPrismApp(controller: controller));
    await tester.pumpAndSettle();
    await tester.tap(find.text('分类').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('钱包'));
    await tester.pumpAndSettle();
    expect(find.byType(CipherbookVaultPage), findsNothing);

    await tester.tap(find.text('未分类'));
    await tester.pumpAndSettle();
    expect(find.byType(CipherbookVaultPage), findsNothing);
    expect(controller.vaultData.categories, hasLength(1));

    await tester.tap(find.byKey(const ValueKey('prism-category-add-primary')));
    await tester.pumpAndSettle();
    expect(find.byType(InputDialog), findsOneWidget);
    await tester.enterText(
      find.descendant(
        of: find.byType(InputDialog),
        matching: find.byType(EditableText),
      ),
      '工作',
    );
    await tester.tap(find.text('提交'));
    await tester.pumpAndSettle();

    expect(
      controller.vaultData.categories.map((category) => category.name),
      containsAll(['钱包', '工作']),
    );
    await controller.lock();
    await tester.pumpAndSettle();
  });

  testWidgets('security check rows use the same spacing', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 800);
    addTearDown(tester.view.reset);

    final controller = _buildController();
    addTearDown(controller.dispose);
    await controller.bootstrap();
    await controller.createVault('master-pass');
    for (final (title, password) in [
      ('Repeat A1', '1111'),
      ('Repeat A2', '1111'),
      ('Repeat B1', '2222'),
      ('Repeat B2', '2222'),
    ]) {
      await controller.addOrUpdateItem(
        title: title,
        username: '',
        password: password,
        url: '',
        notes: '',
        tags: const [],
      );
    }
    final weakIds = controller.vaultData.activeItems
        .where((item) => item.title.startsWith('Repeat'))
        .map((item) => item.id)
        .toList();

    await tester.pumpWidget(CipherbookPrismApp(controller: controller));
    await tester.pumpAndSettle();
    await tester.tap(find.text('密码检查').first);
    await tester.pumpAndSettle();

    final repeatedA = find.byKey(const ValueKey('prism-repeated-row-0'));
    final repeatedB = find.byKey(const ValueKey('prism-repeated-row-1'));
    final weakA = find.byKey(ValueKey('prism-weak-row-${weakIds[0]}'));
    final weakB = find.byKey(ValueKey('prism-weak-row-${weakIds[1]}'));
    expect(repeatedA, findsOneWidget);
    expect(repeatedB, findsOneWidget);
    expect(weakA, findsOneWidget);
    expect(weakB, findsOneWidget);

    final repeatedGap =
        tester.getTopLeft(repeatedB).dy - tester.getBottomLeft(repeatedA).dy;
    final weakGap =
        tester.getTopLeft(weakB).dy - tester.getBottomLeft(weakA).dy;
    expect(repeatedGap, closeTo(8, 0.1));
    expect(weakGap, closeTo(repeatedGap, 0.1));
    expect(tester.getSize(weakA).height, tester.getSize(repeatedA).height);

    await controller.lock();
    await tester.pumpAndSettle();
  });

  testWidgets(
    'dashboard recent item opens the exact selected record on desktop',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      addTearDown(() {
        debugDefaultTargetPlatformOverride = null;
      });
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1280, 800);
      addTearDown(tester.view.reset);

      final controller = _buildController();
      addTearDown(controller.dispose);
      await controller.bootstrap();
      await controller.createVault('master-pass');
      for (final title in ['最早记录', '目标记录', '最新记录']) {
        await controller.addOrUpdateItem(
          title: title,
          username: '$title@example.com',
          password: 'pw',
          url: '',
          notes: '',
          tags: const [],
        );
      }
      final selected = controller.vaultData.activeItems.singleWhere(
        (item) => item.title == '目标记录',
      );

      await tester.pumpWidget(CipherbookPrismApp(controller: controller));
      await tester.pumpAndSettle();

      final recentRow = find.byKey(
        ValueKey('prism-dashboard-recent-item-${selected.id}'),
      );
      expect(recentRow, findsOneWidget);
      await tester.tap(recentRow);
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(CipherbookVaultPage)),
      );
      expect(container.read(vaultQueryProvider).selectedItemId, selected.id);
      expect(find.byKey(ValueKey(selected.id)), findsOneWidget);
      final selectedRow = find.byKey(
        ValueKey('prism-vault-entry-${selected.id}'),
      );
      expect(
        tester
            .widget<Card>(
              find
                  .descendant(of: selectedRow, matching: find.byType(Card))
                  .first,
            )
            .isSelected,
        isTrue,
      );

      debugDefaultTargetPlatformOverride = null;
      await controller.lock();
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'dashboard recent item opens the exact selected record on mobile',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(375, 812);
      addTearDown(tester.view.reset);

      final controller = _buildController();
      addTearDown(controller.dispose);
      await controller.bootstrap();
      await controller.createVault('master-pass');
      for (final title in ['最早记录', '目标记录', '最新记录']) {
        await controller.addOrUpdateItem(
          title: title,
          username: '$title@example.com',
          password: 'pw',
          url: '',
          notes: '',
          tags: const [],
        );
      }
      final selected = controller.vaultData.activeItems.singleWhere(
        (item) => item.title == '目标记录',
      );

      await tester.pumpWidget(CipherbookPrismApp(controller: controller));
      await tester.pumpAndSettle();

      final recentRow = find.byKey(
        ValueKey('prism-dashboard-recent-item-${selected.id}'),
      );
      await tester.ensureVisible(recentRow);
      await tester.pumpAndSettle();
      await tester.tap(recentRow);
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(CipherbookVaultPage)),
      );
      expect(container.read(vaultQueryProvider).selectedItemId, selected.id);
      expect(
        find.byKey(const ValueKey('prism-vault-detail-card')),
        findsOneWidget,
      );
      expect(find.byKey(ValueKey(selected.id)), findsOneWidget);
      expect(find.text('返回列表'), findsOneWidget);

      await controller.lock();
      await tester.pumpAndSettle();
    },
  );

  testWidgets('Windows controls and tablet navigation meet hit target rules', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
    });
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(768, 900);
    addTearDown(tester.view.reset);

    final controller = _buildController();
    addTearDown(controller.dispose);
    await controller.bootstrap();
    await controller.createVault('master-pass');
    await controller.addCategory('工作');
    await controller.addOrUpdateItem(
      title: 'Alpha',
      username: 'alice',
      password: 'pw',
      url: '',
      notes: '',
      tags: const [],
    );

    await tester.pumpWidget(CipherbookPrismApp(controller: controller));
    await tester.pumpAndSettle();

    final sidebar = find.byType(NavigationSidebar);
    expect(sidebar, findsOneWidget);
    expect(
      find.descendant(of: sidebar, matching: find.text('密码检查')),
      findsOneWidget,
    );
    _expectMinHitTarget(tester, find.byKey(const ValueKey('仪表盘')));
    _expectMinHitTarget(
      tester,
      find.byKey(const ValueKey('prism-dashboard-add-password')),
    );
    _expectMinHitTarget(
      tester,
      find.byKey(const ValueKey('prism-dashboard-lock')),
    );

    tester.view.physicalSize = const Size(1280, 800);
    await tester.pumpAndSettle();
    await _showCategories(tester);
    _expectMinHitTarget(
      tester,
      find.byKey(const ValueKey('prism-category-add-primary')),
    );
    _expectMinHitTarget(
      tester,
      find.byKey(const ValueKey('prism-category-action-menu')),
    );
    _expectMinHitTarget(
      tester,
      find.byKey(const ValueKey('prism-category-all-passwords')),
    );
    expect(find.byKey(const ValueKey('prism-category-organize')), findsNothing);
    _expectMinHitTarget(
      tester,
      find.byKey(const ValueKey('prism-category-sort-menu')),
    );
    _expectMinHitTarget(
      tester,
      find.byKey(const ValueKey('prism-category-detail-edit')),
    );

    await _showAllPasswords(tester);
    _expectMinHitTarget(
      tester,
      find.byKey(const ValueKey('prism-vault-add-password')),
    );
    _expectMinHitTarget(tester, find.byKey(const ValueKey('prism-vault-sort')));
    _expectMinHitTarget(
      tester,
      find.byKey(const ValueKey('prism-vault-filter-all')),
    );
    _expectMinHitTarget(
      tester,
      find.byKey(const ValueKey('prism-detail-favorite')),
    );
    _expectMinHitTarget(
      tester,
      find.byKey(const ValueKey('prism-detail-copy-password')),
    );

    debugDefaultTargetPlatformOverride = null;
    await controller.lock();
    await tester.pumpAndSettle();
  });

  testWidgets('Prism quick unlock reports an unavailable key cleanly', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 800);
    addTearDown(tester.view.reset);

    final deviceKeyStore = _MemoryDeviceKeyStore(supported: true);
    final controller = _buildController(deviceKeyStore: deviceKeyStore);
    addTearDown(controller.dispose);
    await controller.bootstrap();
    await controller.createVault('master-pass');
    await controller.enableQuickUnlock();
    deviceKeyStore.storedBytes = null;
    await controller.lock();

    await tester.pumpWidget(CipherbookPrismApp(controller: controller));
    await tester.pumpAndSettle();
    await tester.tap(find.text('使用系统认证快速解锁'));
    await tester.pumpAndSettle();

    expect(find.text('快速解锁密钥不可用。'), findsOneWidget);
    expect(find.textContaining('Bad state:'), findsNothing);
  });
}

Future<void> _showCategories(WidgetTester tester) async {
  final shell = find.byType(ResponsiveShell);
  expect(shell, findsOneWidget);
  ProviderScope.containerOf(tester.element(shell))
      .read(currentShellDestinationProvider.notifier)
      .go(CipherbookDestinationId.categories);
  await tester.pumpAndSettle();
}

Future<void> _showAllPasswords(WidgetTester tester) async {
  final shell = find.byType(ResponsiveShell);
  expect(shell, findsOneWidget);
  ProviderScope.containerOf(tester.element(shell))
      .read(currentShellDestinationProvider.notifier)
      .go(CipherbookDestinationId.vault);
  await tester.pumpAndSettle();
}

void _expectMinHitTarget(WidgetTester tester, Finder finder) {
  expect(finder, findsOneWidget);
  final size = tester.getSize(finder);
  expect(size.height, greaterThanOrEqualTo(44), reason: '$finder: $size');
  expect(size.width, greaterThanOrEqualTo(44), reason: '$finder: $size');
}

VaultController _buildController({DeviceKeyStore? deviceKeyStore}) {
  return VaultController(
    repository: _MemoryVaultRepository(),
    cryptoService: _FastCryptoService(),
    importExportService: _NoopImportExportService(),
    deviceKeyStore: deviceKeyStore ?? _MemoryDeviceKeyStore(),
    passwordGeneratorService: PasswordGeneratorService(random: Random(1)),
    clipboardService: _MemoryClipboardService(),
  );
}

class _DiscoveredSyncController extends VaultController {
  _DiscoveredSyncController()
    : super(
        repository: _MemoryVaultRepository(),
        cryptoService: _FastCryptoService(),
        importExportService: _NoopImportExportService(),
        deviceKeyStore: _MemoryDeviceKeyStore(),
        passwordGeneratorService: PasswordGeneratorService(random: Random(1)),
        clipboardService: _MemoryClipboardService(),
      );

  String? submittedPassword;
  int _completionRevision = 0;
  String? _completionMessage;

  @override
  int get lanSyncCompletionRevision => _completionRevision;

  @override
  String? get lanSyncCompletionMessage => _completionMessage;

  @override
  List<LanSyncPeer> get lanSyncPeers => const [
    LanSyncPeer(
      address: '192.168.1.20',
      port: 45822,
      deviceName: '测试平板',
      vaultId: 'test-vault',
      revision: 1,
      deviceId: 'test-device',
    ),
  ];

  @override
  Future<VaultOperationResult> syncLanWithPassword(String password) async {
    submittedPassword = password;
    _completionMessage = '同步成功：测试通知';
    _completionRevision++;
    notifyListeners();
    return const VaultOperationResult.success();
  }
}

class _FastCryptoService extends CryptoService {
  @override
  Future<Uint8List> deriveKekBytes(String password, KdfConfig kdf) async {
    final source = utf8.encode(password);
    final result = Uint8List(32);
    for (var index = 0; index < result.length; index++) {
      result[index] = source[index % source.length];
    }
    return result;
  }
}

class _MemoryVaultRepository extends VaultRepository {
  EncryptedVaultDocument? document;

  @override
  Future<bool> exists() async => document != null;

  @override
  Future<VaultLoadResult> inspect() async => document == null
      ? const VaultLoadResult(state: VaultStorageState.absent)
      : VaultLoadResult(
          state: VaultStorageState.available,
          document: document,
          rawBytes: document!.encode(),
        );

  @override
  Future<EncryptedVaultDocument?> load() async => document;

  @override
  Future<Uint8List?> loadRaw() async => document?.encode();

  @override
  Future<void> save(EncryptedVaultDocument next) async {
    document = next;
  }

  @override
  Future<void> importRaw(Uint8List bytes) async {
    document = EncryptedVaultDocument.decode(bytes);
  }
}

class _MemoryDeviceKeyStore implements DeviceKeyStore {
  _MemoryDeviceKeyStore({
    this.supported = false,
    this.readDelay = Duration.zero,
  });

  final bool supported;
  final Duration readDelay;
  Uint8List? storedBytes;

  @override
  Future<void> clear() async {
    storedBytes = null;
  }

  @override
  Future<bool> isSupported() async => supported;

  @override
  Future<bool> hasWrappedDekCache() async => storedBytes != null;

  @override
  Future<Uint8List?> readWrappedDek() async {
    if (readDelay > Duration.zero) {
      await Future<void>.delayed(readDelay);
    }
    return storedBytes;
  }

  @override
  Future<void> storeWrappedDek(Uint8List wrappedDekBytes) async {
    storedBytes = Uint8List.fromList(wrappedDekBytes);
  }
}

class _NoopImportExportService extends ImportExportService {
  @override
  Future<String?> pickImportPath() async => null;

  @override
  Future<Uint8List> readFile(String path) async => Uint8List(0);

  @override
  Future<String?> pickExportPath() async => null;

  @override
  Future<void> writeFile(String path, Uint8List bytes) async {}
}

class _MemoryClipboardService extends ClipboardService {
  @override
  Future<void> copyText(
    String text, {
    Duration clearAfter = const Duration(seconds: 30),
  }) async {}
}
