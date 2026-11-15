import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cipherbook/models/vault_models.dart';
import 'package:cipherbook/presentation/app/cipherbook_destinations.dart';
import 'package:cipherbook/presentation/app/cipherbook_ui_localizations.dart';
import 'package:cipherbook/presentation/bridge/vault_controller_provider.dart';
import 'package:cipherbook/presentation/dashboard/dashboard_page.dart';
import 'package:cipherbook/presentation/shell/cipherbook_navigation.dart';
import 'package:cipherbook/presentation/theme/cipherbook_visual_tokens.dart';
import 'package:cipherbook/presentation/unlock/vault_unlock_page.dart';
import 'package:cipherbook/services/clipboard_service.dart';
import 'package:cipherbook/services/crypto_service.dart';
import 'package:cipherbook/services/device_key_store.dart';
import 'package:cipherbook/services/import_export_service.dart';
import 'package:cipherbook/services/password_generator_service.dart';
import 'package:cipherbook/services/vault_repository.dart';
import 'package:cipherbook/state/vault_controller.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_shell/prism_shell.dart';
import 'package:prism_ui/prism_ui.dart';

const _captureKey = ValueKey('vault-index-visual-refresh-capture');
const _screenshotDirectory =
    '../docs/design/frontend-v2/visual-refresh-2026-11-14/screenshots';

void main() {
  setUpAll(() async {
    final bytes = await File(r'C:\Windows\Fonts\Deng.ttf').readAsBytes();
    final data = ByteData.sublistView(bytes);
    final loader = FontLoader('Deng')..addFont(Future<ByteData>.value(data));
    await loader.load();
  });

  testWidgets('captures the Vault Index responsive breakpoints', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
    });
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final controller = _buildController();
    addTearDown(controller.dispose);
    await controller.bootstrap();
    await controller.createVault('synthetic-only-password');

    await tester.pumpWidget(
      RepaintBoundary(
        key: _captureKey,
        child: _ScreenshotApp(controller: controller),
      ),
    );
    await tester.pumpAndSettle();

    await _setSize(tester, const Size(1440, 900));
    await _showDestination(tester, CipherbookDestinationId.dashboard);
    expect(
      find.byKey(const ValueKey('prism-dashboard-add-password')),
      findsOneWidget,
    );
    _expectDashboardActionsDoNotOverlap(tester);
    _expectDashboardSyncStatusSecondary(tester);
    expect(
      find.descendant(
        of: find.byType(CipherbookDashboardPage),
        matching: find.text('打开'),
      ),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('prism-dashboard-metric-summary')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(CipherbookDashboardPage),
        matching: find.byType(Card),
      ),
      findsNWidgets(3),
    );
    final theme = Theme.of(tester.element(find.byType(ResponsiveShell)));
    expect(theme.colorScheme.surface, CipherbookVisualTokens.bgApp);
    await _capture(tester, 'desktop-dashboard-1440.png');
    expect(
      _contrastRatio(
        CipherbookVisualTokens.accent,
        CipherbookVisualTokens.surface,
      ),
      greaterThanOrEqualTo(3),
    );
    final summaryFocus = find.byKey(
      const ValueKey('prism-dashboard-focus-summary-vault'),
    );
    await _focusWithin(
      tester,
      find.byKey(const ValueKey('prism-dashboard-summary-vault')),
    );
    _expectVisibleFocusRing(tester, summaryFocus);
    await _capture(tester, 'qa-dashboard-focus-summary-1440.png');

    final recentItems = controller.vaultData.activeItems.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final focusedRecent = recentItems.first;
    await _focusWithin(
      tester,
      find.byKey(ValueKey('prism-dashboard-recent-item-${focusedRecent.id}')),
    );
    _expectVisibleFocusRing(
      tester,
      find.byKey(ValueKey('prism-dashboard-focus-recent-${focusedRecent.id}')),
    );
    await _capture(tester, 'qa-dashboard-focus-recent-1440.png');

    final longTitleItem = controller.vaultData.activeItems.singleWhere(
      (item) => item.id == 'synthetic-item-2',
    );
    await _focusWithin(
      tester,
      find.byKey(ValueKey('prism-dashboard-recent-item-${longTitleItem.id}')),
    );
    _expectVisibleFocusRing(
      tester,
      find.byKey(ValueKey('prism-dashboard-focus-recent-${longTitleItem.id}')),
    );
    await _capture(tester, 'qa-dashboard-focus-long-title-1440.png');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();

    await _showDestination(tester, CipherbookDestinationId.vault);
    expect(find.byType(Chip), findsNothing);
    expect(
      find.byKey(const ValueKey('prism-vault-filter-all')),
      findsOneWidget,
    );
    await _capture(tester, 'desktop-vault-1440.png');
    final vaultFilterTop = tester
        .getTopLeft(find.byKey(const ValueKey('prism-vault-filters')))
        .dy;
    final vaultListWidth = tester
        .getSize(find.byKey(const ValueKey('prism-vault-list-pane')))
        .width;
    final vaultDetailPane = find.byKey(
      const ValueKey('prism-vault-detail-pane'),
    );
    final vaultDetailCard = find.byKey(
      const ValueKey('prism-vault-detail-card'),
    );
    final vaultDetailGutter =
        tester.getTopLeft(vaultDetailCard).dx -
        tester.getTopLeft(vaultDetailPane).dx;
    final vaultDetailTopGutter =
        tester.getTopLeft(vaultDetailCard).dy -
        tester.getTopLeft(vaultDetailPane).dy;

    await _showDestination(tester, CipherbookDestinationId.categories);
    expect(
      find.byKey(const ValueKey('prism-category-workbench')),
      findsOneWidget,
    );
    _expectCategoryCreateAction(tester);
    _expectCategoryCapsulesFullyVisible(tester, controller);
    _expectCategoryPageTitle(tester, visible: false);
    expect(
      find.byKey(const ValueKey('prism-category-add-password')),
      findsNothing,
    );
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('prism-category-rail'))).dy,
      closeTo(vaultFilterTop, 0.1),
    );
    expect(
      tester
          .getSize(find.byKey(const ValueKey('prism-category-list-pane')))
          .width,
      closeTo(vaultListWidth, 0.1),
    );
    expect(
      tester
              .getTopLeft(
                find.byKey(const ValueKey('prism-category-item-details')),
              )
              .dx -
          tester
              .getTopLeft(
                find.byKey(const ValueKey('prism-category-detail-pane')),
              )
              .dx,
      closeTo(vaultDetailGutter, 0.1),
    );
    expect(
      tester
              .getTopLeft(
                find.byKey(const ValueKey('prism-category-item-details')),
              )
              .dy -
          tester
              .getTopLeft(
                find.byKey(const ValueKey('prism-category-detail-pane')),
              )
              .dy,
      closeTo(vaultDetailTopGutter, 0.1),
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('prism-category-workbench')),
        matching: find.text('新增密码'),
      ),
      findsNothing,
    );
    await _capture(tester, 'desktop-categories-1440.png');

    await _showDestination(tester, CipherbookDestinationId.security);
    _expectSecurityPageHeader(tester, visible: false);
    _expectSecurityMetricsAligned(tester, stacked: false);
    await _capture(tester, 'desktop-security-1440.png');

    await _setSize(tester, const Size(1024, 900));
    await _showDestination(tester, CipherbookDestinationId.dashboard);
    _expectDashboardActionsDoNotOverlap(tester);
    await _capture(tester, 'desktop-dashboard-1024.png');
    await _showDestination(tester, CipherbookDestinationId.vault);
    await _capture(tester, 'desktop-vault-1024.png');
    await _showDestination(tester, CipherbookDestinationId.categories);
    _expectCategoryCreateAction(tester);
    _expectCategoryCapsulesFullyVisible(tester, controller);
    _expectCategoryPageTitle(tester, visible: false);
    _expectDesktopCategoryDocumentSkeleton(tester);
    await _capture(tester, 'desktop-categories-1024.png');
    await _showDestination(tester, CipherbookDestinationId.security);
    _expectSecurityPageHeader(tester, visible: false);
    _expectSecurityMetricsAligned(tester, stacked: false);
    await _capture(tester, 'desktop-security-1024.png');

    await _setSize(tester, const Size(768, 900));
    await _showDestination(tester, CipherbookDestinationId.dashboard);
    _expectDashboardActionsDoNotOverlap(tester);
    final sidebar = find.byType(NavigationSidebar);
    expect(sidebar, findsOneWidget);
    expect(
      find.descendant(of: sidebar, matching: find.text('密码检查')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('prism-dashboard-metric-summary')),
      findsNothing,
    );
    await _capture(tester, 'tablet-dashboard-768.png');

    await _showDestination(tester, CipherbookDestinationId.vault);
    await _capture(tester, 'tablet-vault-768.png');

    await _showDestination(tester, CipherbookDestinationId.categories);
    _expectCategoryCreateAction(tester);
    _expectCategoryCapsulesFullyVisible(tester, controller);
    _expectCategoryPageTitle(tester, visible: true);
    await _capture(tester, 'tablet-categories-768.png');
    await tester.tap(
      find.byKey(const ValueKey('prism-category-drop-synthetic-category-work')),
    );
    await tester.pumpAndSettle();
    expect(find.text('GitHub'), findsOneWidget);
    expect(find.text('旅行证件'), findsNothing);
    await _capture(tester, 'tablet-categories-selected-768.png');
    await tester.tap(
      find.byKey(const ValueKey('prism-category-all-passwords')),
    );
    await tester.pumpAndSettle();
    await _showDestination(tester, CipherbookDestinationId.security);
    _expectSecurityPageHeader(tester, visible: true);
    _expectSecurityMetricsAligned(tester, stacked: true);
    await _capture(tester, 'tablet-security-768.png');

    await _setSize(tester, const Size(375, 812));
    await _showDestination(tester, CipherbookDestinationId.dashboard);
    _expectDashboardActionsDoNotOverlap(tester);
    _expectDashboardSyncStatusSecondary(tester);
    expect(
      find.byKey(const ValueKey('prism-dashboard-metric-summary')),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byType(CipherbookDashboardPage),
        matching: find.byType(Card),
      ),
      findsNWidgets(3),
    );
    final recentCard = find.byKey(
      const ValueKey('prism-dashboard-recent-card'),
    );
    expect(recentCard, findsOneWidget);
    expect(tester.getTopLeft(recentCard).dy, lessThanOrEqualTo(400));
    final mobileRecentItems = controller.vaultData.activeItems.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    for (final item in mobileRecentItems.take(3)) {
      final row = find.byKey(
        ValueKey('prism-dashboard-recent-item-${item.id}'),
      );
      expect(row, findsOneWidget);
      expect(tester.getBottomLeft(row).dy, lessThanOrEqualTo(752));
    }
    await _capture(tester, 'mobile-dashboard-375.png');

    await _showDestination(tester, CipherbookDestinationId.vault);
    await _capture(tester, 'mobile-vault-375.png');

    await _showDestination(tester, CipherbookDestinationId.tools);
    expect(find.byKey(const ValueKey('prism-tools-security')), findsOneWidget);
    await _capture(tester, 'mobile-tools-375.png');
    await tester.tap(find.byKey(const ValueKey('prism-tools-security')));
    await tester.pumpAndSettle();
    expect(find.text('基础弱密码'), findsWidgets);
    _expectSecurityPageHeader(tester, visible: true);
    _expectSecurityMetricsAligned(tester, stacked: true);
    await _capture(tester, 'mobile-security-375.png');

    await _showDestination(tester, CipherbookDestinationId.categories);
    expect(
      find.byKey(const ValueKey('shell-narrow-navigation-dock')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('prism-category-add-primary')),
      findsOneWidget,
    );
    _expectCategoryCreateAction(tester);
    _expectCategoryCapsulesFullyVisible(tester, controller);
    _expectCategoryPageTitle(tester, visible: true);
    expect(
      find.byKey(const ValueKey('prism-category-add-password')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('prism-category-tabs')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('prism-category-directory')),
      findsNothing,
    );
    expect(
      tester
          .getSize(find.byKey(const ValueKey('prism-category-all-passwords')))
          .height,
      44,
    );
    final passwordList = find.byKey(
      const ValueKey('prism-category-password-list'),
    );
    final dashboardNavigationLabel = find.text('仪表盘').last;
    expect(
      tester.getBottomLeft(passwordList).dy,
      lessThanOrEqualTo(tester.getTopLeft(dashboardNavigationLabel).dy),
    );
    await _capture(tester, 'mobile-categories-375.png');
    await tester.tap(
      find.byKey(const ValueKey('prism-category-drop-synthetic-category-work')),
    );
    await tester.pumpAndSettle();
    expect(find.text('GitHub'), findsOneWidget);
    expect(find.text('旅行证件'), findsNothing);
    final selectedWorkItem = controller.vaultData.activeItems.firstWhere(
      (item) => item.title == 'GitHub',
    );
    final selectedMetadata = tester
        .widget<Text>(
          find.byKey(
            ValueKey('prism-password-metadata-${selectedWorkItem.id}'),
          ),
        )
        .data!;
    expect(selectedMetadata, contains('example.test/0'));
    expect(selectedMetadata, isNot(contains('https://')));
    expect(selectedMetadata, isNot(contains('工作')));
    await _capture(tester, 'mobile-categories-selected-375.png');

    await controller.lock();
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      RepaintBoundary(
        key: _captureKey,
        child: _ScreenshotApp(controller: controller, showUnlock: true),
      ),
    );
    await tester.pumpAndSettle();

    await _setSize(tester, const Size(1024, 900));
    await _capture(tester, 'desktop-unlock-1024.png');

    await _setSize(tester, const Size(1440, 900));
    expect(find.byKey(const ValueKey('prism-unlock-card')), findsNothing);
    await _capture(tester, 'desktop-unlock-1440.png');

    await _setSize(tester, const Size(375, 812));
    expect(find.byKey(const ValueKey('prism-unlock-card')), findsOneWidget);
    await _capture(tester, 'mobile-unlock-375.png');

    expect(tester.takeException(), isNull);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('security summary keeps one grid with populated metrics', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
    });
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final controller = _buildController(
      initialVaultData: _populatedSecurityVaultData(),
    );
    addTearDown(controller.dispose);
    await controller.bootstrap();
    await controller.createVault('synthetic-only-password');

    await tester.pumpWidget(
      RepaintBoundary(
        key: _captureKey,
        child: _ScreenshotApp(controller: controller),
      ),
    );
    await tester.pumpAndSettle();

    await _setSize(tester, const Size(1440, 900));
    await _showDestination(tester, CipherbookDestinationId.security);
    _expectSecurityPageHeader(tester, visible: false);
    _expectSecurityMetricsAligned(tester, stacked: false);
    await _capture(tester, 'desktop-security-populated-1440.png');

    await _setSize(tester, const Size(768, 900));
    await _showDestination(tester, CipherbookDestinationId.security);
    _expectSecurityPageHeader(tester, visible: true);
    _expectSecurityMetricsAligned(tester, stacked: true);
    await _capture(tester, 'tablet-security-populated-768.png');

    await _setSize(tester, const Size(375, 812));
    await _showDestination(tester, CipherbookDestinationId.tools);
    await tester.tap(find.byKey(const ValueKey('prism-tools-security')));
    await tester.pumpAndSettle();
    _expectSecurityPageHeader(tester, visible: true);
    _expectSecurityMetricsAligned(tester, stacked: true);
    await _capture(tester, 'mobile-security-populated-375.png');

    await controller.lock();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('dashboard hover regions fill their interactive bounds', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
    });
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final controller = _buildController();
    addTearDown(controller.dispose);
    await controller.bootstrap();
    await controller.createVault('synthetic-only-password');

    await tester.pumpWidget(
      RepaintBoundary(
        key: _captureKey,
        child: _ScreenshotApp(controller: controller),
      ),
    );
    await tester.pumpAndSettle();
    await _setSize(tester, const Size(1074, 900));
    await _showDestination(tester, CipherbookDestinationId.dashboard);

    final recentItem = controller.vaultData.activeItems.first;
    final firstCategory = controller.vaultData.categories.first;
    final regions = <(Finder, Finder)>[
      (
        find.byKey(const ValueKey('prism-dashboard-focus-summary-vault')),
        find.byKey(const ValueKey('prism-dashboard-summary-vault')),
      ),
      (
        find.byKey(const ValueKey('prism-dashboard-focus-summary-security')),
        find.byKey(const ValueKey('prism-dashboard-summary-security')),
      ),
      (
        find.byKey(const ValueKey('prism-dashboard-focus-summary-sync')),
        find.byKey(const ValueKey('prism-dashboard-summary-sync')),
      ),
      (
        find.byKey(ValueKey('prism-dashboard-focus-recent-${recentItem.id}')),
        find.byKey(ValueKey('prism-dashboard-recent-item-${recentItem.id}')),
      ),
    ];
    for (final (interactive, region) in regions) {
      expect(tester.getRect(region), tester.getRect(interactive));
    }
    final vaultBounds = tester.getRect(
      find.byKey(const ValueKey('prism-dashboard-summary-vault')),
    );
    final securityBounds = tester.getRect(
      find.byKey(const ValueKey('prism-dashboard-summary-security')),
    );
    final syncBounds = tester.getRect(
      find.byKey(const ValueKey('prism-dashboard-summary-sync')),
    );
    expect(securityBounds.left, vaultBounds.right + 1);
    expect(syncBounds.left, securityBounds.right + 1);
    for (final region in [
      find.byKey(ValueKey('prism-dashboard-recent-item-${recentItem.id}')),
      find.byKey(ValueKey('prism-dashboard-category-${firstCategory.id}')),
      find.byKey(const ValueKey('prism-dashboard-shortcut-管理分类')),
      find.byKey(const ValueKey('prism-dashboard-shortcut-设置与工具')),
      find.byKey(const ValueKey('prism-dashboard-metric-all')),
    ]) {
      expect(
        tester.getSize(region).height,
        CipherbookVisualTokens.dashboardRowHeight,
      );
    }

    final recentCard = find.byKey(
      const ValueKey('prism-dashboard-recent-card'),
    );
    final categoriesCard = find.byKey(
      const ValueKey('prism-dashboard-categories-card'),
    );
    final shortcutsCard = find.byKey(
      const ValueKey('prism-dashboard-shortcuts-card'),
    );
    final recentRegion = find.byKey(
      ValueKey('prism-dashboard-recent-item-${recentItem.id}'),
    );
    final categoryRegion = find.byKey(
      ValueKey('prism-dashboard-category-${firstCategory.id}'),
    );
    final shortcutRegion = find.byKey(
      const ValueKey('prism-dashboard-shortcut-管理分类'),
    );
    expect(tester.getRect(recentRegion).left, tester.getRect(recentCard).left);
    expect(
      tester.getRect(recentRegion).right,
      tester.getRect(recentCard).right,
    );
    expect(
      tester.getRect(categoryRegion).left,
      tester.getRect(categoriesCard).left,
    );
    expect(
      tester.getRect(categoryRegion).right,
      tester.getRect(categoriesCard).right,
    );
    expect(
      tester.getRect(shortcutRegion).left,
      tester.getRect(shortcutsCard).left,
    );
    expect(
      tester.getRect(shortcutRegion).right,
      tester.getRect(shortcutsCard).right,
    );
    final hover = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await hover.addPointer(location: Offset.zero);
    await hover.moveTo(tester.getCenter(recentRegion));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await hover.removePointer();
    await controller.lock();
    await tester.pumpAndSettle();
    debugDefaultTargetPlatformOverride = null;
  });
}

void _expectDashboardActionsDoNotOverlap(WidgetTester tester) {
  final addAction = find.byKey(const ValueKey('prism-dashboard-add-password'));
  final lockAction = find.byKey(const ValueKey('prism-dashboard-lock'));
  expect(addAction, findsOneWidget);
  expect(lockAction, findsOneWidget);
  expect(
    find.descendant(of: addAction, matching: find.text('新增密码')),
    findsOneWidget,
  );

  final addRect = tester.getRect(addAction);
  final lockRect = tester.getRect(lockAction);
  expect(addRect.height, greaterThanOrEqualTo(44));
  expect(addRect.width, greaterThan(44));
  final horizontalGap = max(
    lockRect.left - addRect.right,
    addRect.left - lockRect.right,
  );
  final verticalGap = max(
    lockRect.top - addRect.bottom,
    addRect.top - lockRect.bottom,
  );
  expect(
    addRect.overlaps(lockRect) ||
        (horizontalGap < CipherbookVisualTokens.space8 &&
            verticalGap < CipherbookVisualTokens.space8),
    isFalse,
  );

  final viewport = Size(
    tester.view.physicalSize.width / tester.view.devicePixelRatio,
    tester.view.physicalSize.height / tester.view.devicePixelRatio,
  );
  for (final actionRect in [addRect, lockRect]) {
    expect(actionRect.left, greaterThanOrEqualTo(0));
    expect(actionRect.top, greaterThanOrEqualTo(0));
    expect(actionRect.right, lessThanOrEqualTo(viewport.width));
    expect(actionRect.bottom, lessThanOrEqualTo(viewport.height));
  }
}

void _expectCategoryCreateAction(WidgetTester tester) {
  final primaryAction = find.byKey(
    const ValueKey('prism-category-add-primary'),
  );
  final actionMenu = find.byKey(const ValueKey('prism-category-action-menu'));
  expect(primaryAction, findsOneWidget);
  expect(
    find.descendant(of: primaryAction, matching: find.text('新建分类')),
    findsOneWidget,
  );
  final primaryRect = tester.getRect(primaryAction);
  expect(primaryRect.height, greaterThanOrEqualTo(44));
  expect(primaryRect.width, greaterThan(44));
  expect(actionMenu, findsOneWidget);
  expect(
    tester.getRect(actionMenu).left - primaryRect.right,
    greaterThanOrEqualTo(CipherbookVisualTokens.space8),
  );
}

void _expectCategoryPageTitle(WidgetTester tester, {required bool visible}) {
  final title = find.byKey(const ValueKey('prism-category-page-title'));
  if (!visible) {
    expect(title, findsNothing);
    return;
  }
  expect(title, findsOneWidget);
  expect(tester.widget<Text>(title).data, '分类');
}

void _expectCategoryCapsulesFullyVisible(
  WidgetTester tester,
  VaultController controller,
) {
  final rail = find.byKey(const ValueKey('prism-category-rail'));
  final tabs = find.byKey(const ValueKey('prism-category-tabs'));
  final container = rail.evaluate().isNotEmpty ? rail : tabs;
  expect(container, findsOneWidget);
  expect(
    find.byKey(const ValueKey('prism-category-rail-scroll')),
    findsNothing,
  );
  expect(
    find.byKey(const ValueKey('prism-category-tabs-scroll')),
    findsNothing,
  );
  final containerRect = tester.getRect(container);
  expect(
    containerRect.height,
    greaterThan(CipherbookVisualTokens.controlHeight),
  );
  final capsules = <Finder>[
    find.byKey(const ValueKey('prism-category-all-passwords')),
    for (final category in controller.vaultData.categories)
      find.byKey(ValueKey('prism-category-drop-${category.id}')),
    find.byKey(const ValueKey('prism-category-drop-uncategorized')),
  ];
  for (final capsule in capsules) {
    expect(capsule, findsOneWidget);
    final rect = tester.getRect(capsule);
    expect(rect.height, CipherbookVisualTokens.controlHeight);
    expect(rect.left, greaterThanOrEqualTo(containerRect.left - 0.1));
    expect(rect.top, greaterThanOrEqualTo(containerRect.top - 0.1));
    expect(rect.right, lessThanOrEqualTo(containerRect.right + 0.1));
    expect(rect.bottom, lessThanOrEqualTo(containerRect.bottom + 0.1));
  }
}

void _expectDashboardSyncStatusSecondary(WidgetTester tester) {
  final status = find.byKey(const ValueKey('prism-dashboard-sync-status'));
  final pressRegion = find.byKey(
    const ValueKey('prism-dashboard-summary-sync'),
  );
  expect(status, findsOneWidget);
  expect(pressRegion, findsOneWidget);
  expect(find.descendant(of: pressRegion, matching: status), findsOneWidget);

  final statusText = tester.widget<Text>(status);
  expect(statusText.data, '待连接');
  expect(statusText.style?.fontSize, 15);
  expect(statusText.style?.fontWeight, FontWeight.w400);
  expect(
    statusText.style?.color,
    tester.element(status).colorScheme.onSurfaceVariant,
  );
}

void _expectDesktopCategoryDocumentSkeleton(WidgetTester tester) {
  final listPane = find.byKey(const ValueKey('prism-category-list-pane'));
  final detailPane = find.byKey(const ValueKey('prism-category-detail-pane'));
  final detailCard = find.byKey(const ValueKey('prism-category-item-details'));
  expect(listPane, findsOneWidget);
  expect(detailPane, findsOneWidget);
  expect(detailCard, findsOneWidget);
  expect(tester.getSize(listPane).width, 460);
  expect(
    tester.getTopLeft(detailCard).dx - tester.getTopLeft(detailPane).dx,
    closeTo(CipherbookVisualTokens.space20, 0.1),
  );
  expect(
    tester.getTopLeft(detailCard).dy - tester.getTopLeft(detailPane).dy,
    closeTo(CipherbookVisualTokens.space12, 0.1),
  );
  expect(
    find.ancestor(of: detailCard, matching: find.byType(Card)),
    findsNothing,
  );
  expect(tester.widget(detailCard), isA<Column>());
  expect(
    find.byKey(const ValueKey('prism-category-detail-credential-grid')),
    findsOneWidget,
  );
  expect(
    find.byKey(const ValueKey('prism-category-detail-metadata-strip')),
    findsOneWidget,
  );
}

void _expectSecurityMetricsAligned(
  WidgetTester tester, {
  required bool stacked,
}) {
  final repeated = find.byKey(const ValueKey('prism-security-metric-repeated'));
  final weak = find.byKey(const ValueKey('prism-security-metric-weak'));
  expect(repeated, findsOneWidget);
  expect(weak, findsOneWidget);

  final repeatedRect = tester.getRect(repeated);
  final weakRect = tester.getRect(weak);
  expect(weakRect.width, closeTo(repeatedRect.width, 0.1));
  expect(weakRect.height, closeTo(repeatedRect.height, 0.1));
  if (stacked) {
    expect(weakRect.left, closeTo(repeatedRect.left, 0.1));
    expect(weakRect.top, greaterThan(repeatedRect.bottom));
  } else {
    expect(weakRect.top, closeTo(repeatedRect.top, 0.1));
    expect(weakRect.left, greaterThan(repeatedRect.right));
  }

  final repeatedTexts = find.descendant(
    of: repeated,
    matching: find.byType(Text),
  );
  final weakTexts = find.descendant(of: weak, matching: find.byType(Text));
  expect(repeatedTexts, findsNWidgets(3));
  expect(weakTexts, findsNWidgets(3));
  final repeatedTitle = repeatedTexts.at(0);
  final repeatedValue = repeatedTexts.at(1);
  final repeatedDetail = repeatedTexts.at(2);
  final weakTitle = weakTexts.at(0);
  final weakValue = weakTexts.at(1);
  final weakDetail = weakTexts.at(2);
  expect(
    tester.getTopLeft(weakTitle).dy - weakRect.top,
    closeTo(tester.getTopLeft(repeatedTitle).dy - repeatedRect.top, 0.1),
  );
  expect(
    tester.getTopLeft(weakValue).dy - weakRect.top,
    closeTo(tester.getTopLeft(repeatedValue).dy - repeatedRect.top, 0.1),
  );
  expect(
    tester.getTopLeft(weakDetail).dy - weakRect.top,
    closeTo(tester.getTopLeft(repeatedDetail).dy - repeatedRect.top, 0.1),
  );
  expect(
    tester.getTopLeft(weakTitle).dx - weakRect.left,
    closeTo(tester.getTopLeft(repeatedTitle).dx - repeatedRect.left, 0.1),
  );
  expect(
    tester.getTopLeft(weakValue).dx - weakRect.left,
    closeTo(tester.getTopLeft(repeatedValue).dx - repeatedRect.left, 0.1),
  );

  final repeatedCard = tester.widget<Card>(
    find.descendant(of: repeated, matching: find.byType(Card)).first,
  );
  final weakCard = tester.widget<Card>(
    find.descendant(of: weak, matching: find.byType(Card)).first,
  );
  expect(repeatedCard.shape, weakCard.shape);
}

void _expectSecurityPageHeader(WidgetTester tester, {required bool visible}) {
  final title = find.byKey(const ValueKey('prism-security-page-title'));
  final scopeLabel = find.byKey(const ValueKey('prism-security-scope-label'));
  final scopeTitle = find.byKey(const ValueKey('prism-security-scope-title'));
  if (!visible) {
    expect(title, findsNothing);
    expect(scopeLabel, findsNothing);
    expect(scopeTitle, findsNothing);
    return;
  }

  expect(title, findsOneWidget);
  expect(scopeLabel, findsOneWidget);
  expect(scopeTitle, findsOneWidget);
  final titleText = tester.widget<Text>(title);
  final scopeLabelText = tester.widget<Text>(scopeLabel);
  final scopeTitleText = tester.widget<Text>(scopeTitle);
  expect(titleText.data, '密码检查');
  expect(scopeLabelText.data, '当前范围');
  expect(scopeTitleText.data, '全部密码');
  expect(titleText.style?.fontSize, 15);
  expect(titleText.style?.fontWeight, FontWeight.w600);
  expect(scopeLabelText.style?.fontSize, 12);
  expect(scopeLabelText.style?.fontWeight, FontWeight.w600);
  expect(scopeTitleText.style?.fontSize, 20);
  expect(scopeTitleText.style?.fontWeight, FontWeight.w700);

  final repeated = find.byKey(const ValueKey('prism-security-metric-repeated'));
  expect(repeated, findsOneWidget);
  expect(
    tester.getTopLeft(repeated).dy - tester.getBottomLeft(scopeTitle).dy,
    closeTo(CipherbookVisualTokens.space24, 0.1),
  );
}

Future<void> _showDestination(WidgetTester tester, String destination) async {
  final shellContext = tester.element(find.byType(ResponsiveShell));
  ProviderScope.containerOf(
    shellContext,
  ).read(currentShellDestinationProvider.notifier).go(destination);
  await tester.pumpAndSettle();
}

Future<void> _setSize(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  await tester.pumpAndSettle();
}

Future<void> _capture(WidgetTester tester, String fileName) async {
  expect(tester.takeException(), isNull);
  await expectLater(
    find.byKey(_captureKey),
    matchesGoldenFile('$_screenshotDirectory/$fileName'),
  );
}

Future<void> _focusWithin(WidgetTester tester, Finder target) async {
  final targetElement = tester.element(target);
  for (var index = 0; index < 96; index++) {
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    final focusContext = FocusManager.instance.primaryFocus?.context;
    if (focusContext == null) {
      continue;
    }
    var found = identical(focusContext, targetElement);
    focusContext.visitAncestorElements((element) {
      if (identical(element, targetElement)) {
        found = true;
        return false;
      }
      return true;
    });
    if (found) {
      return;
    }
  }
  fail('Could not focus $target');
}

void _expectVisibleFocusRing(WidgetTester tester, Finder focusTarget) {
  expect(focusTarget, findsOneWidget);
  final decorated = tester.widget<DecoratedBox>(
    find.descendant(of: focusTarget, matching: find.byType(DecoratedBox)).first,
  );
  final decoration = decorated.decoration as ShapeDecoration;
  final side = (decoration.shape as OutlinedBorder).side;
  final colorScheme = Theme.of(tester.element(focusTarget)).colorScheme;
  expect(side.color, colorScheme.primary);
  expect(side.width, 2);
}

double _contrastRatio(Color foreground, Color background) {
  final lighter = foreground.computeLuminance() > background.computeLuminance()
      ? foreground.computeLuminance()
      : background.computeLuminance();
  final darker = foreground.computeLuminance() > background.computeLuminance()
      ? background.computeLuminance()
      : foreground.computeLuminance();
  return (lighter + 0.05) / (darker + 0.05);
}

class _ScreenshotApp extends StatelessWidget {
  const _ScreenshotApp({required this.controller, this.showUnlock = false});

  final VaultController controller;
  final bool showUnlock;

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      overrides: [
        vaultControllerProvider.overrideWithValue(controller),
        initialShellSettingsProvider.overrideWithValue(
          const ShellSettings(
            themeMode: ThemeMode.dark,
            seedColor: CipherbookVisualTokens.accent,
            liquidGlass: false,
            sidebarExpanded: true,
            floatingNavigationBar: true,
            compactDensity: false,
            fontFamily: 'Deng',
            locale: 'zh_CN',
          ),
        ),
      ],
      child: FrontendShellApp(
        title: 'Cipherbook',
        supportedLocales: const [Locale('zh', 'CN')],
        localizationsDelegates: const [
          CipherbookUiLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        desktopTopInset: 0,
        themeBuilder: cipherbookPrismTheme,
        home: ButtonTheme(
          data: CipherbookVisualTokens.buttonTheme,
          child: showUnlock
              ? const VaultUnlockPage()
              : Builder(
                  builder: (context) => ResponsiveShell(
                    initialDestinationId: CipherbookDestinationId.dashboard,
                    destinations: cipherbookDestinationsOf(context),
                  ),
                ),
        ),
      ),
    );
  }
}

VaultController _buildController({VaultData? initialVaultData}) {
  return VaultController(
    repository: _MemoryVaultRepository(),
    cryptoService: _FastCryptoService(
      initialVaultData: initialVaultData ?? _syntheticVaultData(),
    ),
    importExportService: _NoopImportExportService(),
    deviceKeyStore: _MemoryDeviceKeyStore(),
    passwordGeneratorService: PasswordGeneratorService(random: Random(7)),
    clipboardService: _MemoryClipboardService(),
  );
}

class _FastCryptoService extends CryptoService {
  _FastCryptoService({required this.initialVaultData});

  final VaultData initialVaultData;

  @override
  Future<EncryptedVaultDocument> createVault({
    required String password,
    VaultData? vaultData,
  }) {
    return super.createVault(password: password, vaultData: initialVaultData);
  }

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

VaultData _syntheticVaultData() {
  final updatedAt = DateTime(2026, 11, 14, 14, 25);
  final categories = [
    VaultCategory(
      id: 'synthetic-category-work',
      name: '工作',
      createdAt: updatedAt,
      updatedAt: updatedAt,
      sortIndex: 0,
    ),
    VaultCategory(
      id: 'synthetic-category-personal',
      name: '个人',
      createdAt: updatedAt,
      updatedAt: updatedAt,
      sortIndex: 1,
    ),
    VaultCategory(
      id: 'synthetic-category-finance',
      name: '财务',
      createdAt: updatedAt,
      updatedAt: updatedAt,
      sortIndex: 2,
    ),
    VaultCategory(
      id: 'synthetic-category-archive',
      name: '归档',
      createdAt: updatedAt,
      updatedAt: updatedAt,
      sortIndex: 3,
    ),
  ];
  final categoryIds = {
    for (final category in categories) category.name: category.id,
  };
  const entries = [
    ('GitHub', 'builder@example.test', '工作'),
    ('云控制台', 'ops@example.test', '工作'),
    ('企业邮箱与跨区域账号恢复备份中心', 'hello@example.test', '工作'),
    ('旅行证件', 'travel@example.test', '个人'),
    ('储蓄账户', 'finance@example.test', '财务'),
    ('家庭 NAS', 'home@example.test', null),
    ('待整理服务', 'service@example.test', null),
  ];
  final items = [
    for (final (index, entry) in entries.indexed)
      VaultItem(
        id: 'synthetic-item-$index',
        title: entry.$1,
        username: entry.$2,
        password: 'synthetic-only-$index',
        url: 'https://example.test/$index',
        notes: '',
        tags: const [],
        createdAt: updatedAt,
        updatedAt: updatedAt,
        folder: entry.$3 == null ? '' : categoryIds[entry.$3]!,
        favorite: index == 0,
        totpSecret: index == 2 ? 'SYNTHETICONLYSECRET' : null,
      ),
  ];
  return VaultData(items: items, categories: categories, updatedAt: updatedAt);
}

VaultData _populatedSecurityVaultData() {
  final updatedAt = DateTime(2026, 11, 14, 14, 25);
  VaultItem item(String id, String title, String password) {
    return VaultItem(
      id: id,
      title: title,
      username: '$id@example.test',
      password: password,
      url: 'https://$id.example.test',
      notes: '',
      tags: const [],
      createdAt: updatedAt,
      updatedAt: updatedAt,
    );
  }

  return VaultData(
    items: [
      item('reused-a', '重复账号 A', 'synthetic-shared-password'),
      item('reused-b', '重复账号 B', 'synthetic-shared-password'),
      item('weak-a', '基础弱密码 A', '12345678'),
      item('unique-a', '独立强密码', 'synthetic-unique-password'),
    ],
    updatedAt: updatedAt,
  );
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
  Uint8List? storedBytes;

  @override
  Future<void> clear() async {
    storedBytes = null;
  }

  @override
  Future<bool> hasWrappedDekCache() async => storedBytes != null;

  @override
  Future<bool> isSupported() async => false;

  @override
  Future<Uint8List?> readWrappedDek() async => storedBytes;

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
