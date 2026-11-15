import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cipherbook/models/vault_models.dart';
import 'package:cipherbook/presentation/app/cipherbook_destinations.dart';
import 'package:cipherbook/presentation/app/cipherbook_ui_localizations.dart';
import 'package:cipherbook/presentation/bridge/vault_controller_provider.dart';
import 'package:cipherbook/presentation/shell/cipherbook_navigation.dart';
import 'package:cipherbook/presentation/theme/cipherbook_visual_tokens.dart';
import 'package:cipherbook/services/clipboard_service.dart';
import 'package:cipherbook/services/crypto_service.dart';
import 'package:cipherbook/services/device_key_store.dart';
import 'package:cipherbook/services/import_export_service.dart';
import 'package:cipherbook/services/password_generator_service.dart';
import 'package:cipherbook/services/vault_repository.dart';
import 'package:cipherbook/state/vault_controller.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_ui/prism_ui.dart';
import 'package:prism_shell/prism_shell.dart';

const _captureKey = ValueKey('category-workbench-capture');
const _screenshotDirectory =
    'docs/design/frontend-v2/category-workbench-v2/screenshots';

void main() {
  setUpAll(() async {
    final bytes = await File(r'C:\Windows\Fonts\Deng.ttf').readAsBytes();
    final data = ByteData.sublistView(bytes);
    final loader = FontLoader('Deng')..addFont(Future<ByteData>.value(data));
    await loader.load();
  });

  testWidgets('captures synthetic category workbench breakpoints', (
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

    final categories = {
      for (final category in controller.vaultData.categories)
        category.name: category,
    };

    await tester.pumpWidget(
      RepaintBoundary(
        key: _captureKey,
        child: _ScreenshotApp(controller: controller),
      ),
    );
    await tester.pumpAndSettle();
    await _showCategories(tester);
    expect(
      find.byKey(const ValueKey('prism-category-workbench')),
      findsOneWidget,
    );

    await _setSize(tester, const Size(1440, 900));
    expect(
      tester
          .getTopLeft(find.byKey(const ValueKey('prism-category-workbench')))
          .dy,
      lessThanOrEqualTo(1),
    );
    expect(find.byType(AppBar), findsNothing);
    final categoryLabel = tester.widget<Text>(
      find.byKey(const ValueKey('prism-category-label-全部密码')),
    );
    expect(categoryLabel.style?.fontSize, 13);
    final firstItem = controller.vaultData.activeItems.first;
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('prism-category-detail-title')),
          )
          .data,
      firstItem.title,
    );
    final passwordTitle = tester.widget<Text>(
      find.byKey(ValueKey('prism-password-title-${firstItem.id}')),
    );
    final passwordMetadata = tester.widget<Text>(
      find.byKey(ValueKey('prism-password-metadata-${firstItem.id}')),
    );
    expect(passwordTitle.style?.fontSize, 15);
    expect(passwordMetadata.style?.fontSize, 13);
    final selectedRow = find.byKey(
      const ValueKey('prism-category-all-passwords'),
    );
    final selectedSurface = tester.widget<PressSurface>(
      find.descendant(of: selectedRow, matching: find.byType(PressSurface)),
    );
    final selectedContext = tester.element(selectedRow);
    expect(selectedSurface.fill, selectedContext.colorScheme.primary);
    final categoryRail = find.byKey(const ValueKey('prism-category-rail'));
    expect(categoryRail, findsOneWidget);
    _expectCategoryCapsulesFullyVisible(
      tester,
      container: categoryRail,
      categories: categories.values,
    );
    _expectCategoryCreateAction(tester);
    expect(
      find.byKey(const ValueKey('prism-category-page-title')),
      findsNothing,
    );
    expect(find.text('分类 · ${categories.length}'), findsNothing);
    expect(find.byKey(const ValueKey('prism-category-organize')), findsNothing);
    expect(
      find.byKey(const ValueKey('prism-category-add-primary')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('prism-category-add')), findsNothing);
    expect(
      find.byKey(const ValueKey('prism-category-list-pane')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('prism-category-detail-pane')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('prism-category-item-details')),
      findsOneWidget,
    );
    final moveButton = find.byKey(const ValueKey('prism-category-detail-move'));
    expect(moveButton, findsOneWidget);
    expect(tester.getSize(moveButton).height, greaterThanOrEqualTo(44));
    expect(
      find.byKey(const ValueKey('prism-category-detail-metadata-updated')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('prism-category-detail-edit')),
      findsOneWidget,
    );
    final editButton = tester.widget<OutlinedButton>(
      find.byKey(const ValueKey('prism-category-detail-edit')),
    );
    expect(
      editButton.style?.foregroundColor?.resolve(const <WidgetState>{}),
      tester
          .element(find.byKey(const ValueKey('prism-category-detail-edit')))
          .colorScheme
          .onSurface,
    );
    expect(
      find.byKey(const ValueKey('prism-category-detail-copy-username')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('prism-category-detail-copy-password')),
      findsOneWidget,
    );
    final allPasswordRow = find.byKey(
      const ValueKey('prism-category-all-passwords'),
    );
    final firstCategoryRow = find.byKey(
      ValueKey('prism-category-drop-${categories.values.first.id}'),
    );
    expect(
      tester.getTopLeft(firstCategoryRow).dx -
          tester.getTopRight(allPasswordRow).dx,
      closeTo(CipherbookVisualTokens.space8, 0.1),
    );
    expect(tester.getSize(allPasswordRow).height, 44);
    final categorySearch = find.byKey(
      const ValueKey('prism-category-password-search'),
    );
    expect(
      tester.getTopLeft(allPasswordRow).dx,
      closeTo(tester.getTopLeft(categorySearch).dx, 0.1),
      reason:
          'Category capsules must share the all-passwords page left gutter.',
    );
    expect(
      tester.getTopLeft(categorySearch).dy -
          tester.getBottomLeft(categoryRail).dy,
      closeTo(8, 0.1),
    );
    final detailPane = find.byKey(const ValueKey('prism-category-detail-pane'));
    final detailCard = find.byKey(
      const ValueKey('prism-category-item-details'),
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
    expect(
      tester.getTopLeft(detailCard).dx - tester.getTopLeft(detailPane).dx,
      closeTo(CipherbookVisualTokens.space20, 0.1),
    );
    expect(
      (tester.getCenter(detailCard).dy - tester.getCenter(detailPane).dy).abs(),
      lessThan(8),
    );
    expect(
      tester.getSize(detailCard).height,
      lessThan(tester.getSize(detailPane).height),
    );
    await _capture('desktop-1440.png');

    final savings = controller.vaultData.activeItems.singleWhere(
      (item) => item.title == '储蓄账户',
    );
    await tester.tap(
      find.byKey(ValueKey('prism-password-title-${savings.id}')),
    );
    await tester.pumpAndSettle();
    final detailTitle = tester.widget<Text>(
      find.byKey(const ValueKey('prism-category-detail-title')),
    );
    expect(detailTitle.data, '储蓄账户');
    final selectedPasswordRow = find.byKey(
      ValueKey('prism-password-row-${savings.id}'),
    );
    final selectedPasswordCard = tester.widget<Card>(
      find
          .descendant(of: selectedPasswordRow, matching: find.byType(Card))
          .first,
    );
    expect(selectedPasswordCard.isSelected, isTrue);
    expect(
      tester
          .widget<Text>(
            find.byKey(ValueKey('prism-password-title-${savings.id}')),
          )
          .style
          ?.color,
      tester.element(selectedPasswordRow).colorScheme.primary,
    );
    expect(find.text('synthetic-only-4'), findsNothing);
    await _capture('desktop-detail-1440.png');

    final emptyCategory = categories['归档']!;
    final emptyCategoryTab = find.byKey(
      ValueKey('prism-category-drop-${emptyCategory.id}'),
    );
    expect(emptyCategoryTab, findsOneWidget);
    await tester.tap(emptyCategoryTab);
    await tester.pumpAndSettle();
    expect(find.text('这个分类还没有密码'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('prism-category-detail-empty')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('prism-category-detail-empty-title')),
          )
          .data,
      '归档',
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('prism-category-detail-empty-count')),
          )
          .data,
      '0 条',
    );
    expect(
      find.byKey(const ValueKey('prism-category-detail-empty-hint')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('prism-category-detail-empty-message')),
          )
          .data,
      '分类为空',
    );
    final emptyCard = find.byKey(const ValueKey('prism-category-detail-empty'));
    final emptyCardWidget = tester.widget<Card>(emptyCard);
    expect(
      emptyCardWidget.shape,
      AppShape.all(CipherbookVisualTokens.radiusPanel).copyWith(
        side: BorderSide(
          color: tester.element(emptyCard).colorScheme.outlineVariant,
        ),
      ),
    );
    expect(
      tester.getTopLeft(emptyCard).dx - tester.getTopLeft(detailPane).dx,
      closeTo(CipherbookVisualTokens.space20, 0.1),
    );
    await _capture('empty-category-1440.png');
    await tester.tap(
      find.byKey(const ValueKey('prism-category-all-passwords')),
    );
    await tester.pumpAndSettle();

    await _setSize(tester, const Size(1024, 900));
    await _showCategories(tester);
    expect(
      find.byKey(const ValueKey('prism-category-add-primary')),
      findsOneWidget,
    );
    _expectCategoryCreateAction(tester);
    _expectCategoryCapsulesFullyVisible(
      tester,
      container: find.byKey(const ValueKey('prism-category-rail')),
      categories: categories.values,
    );
    expect(find.byKey(const ValueKey('prism-category-add')), findsNothing);
    expect(
      tester
          .getSize(find.byKey(const ValueKey('prism-category-add-primary')))
          .height,
      greaterThanOrEqualTo(44),
    );
    expect(
      find.byKey(const ValueKey('prism-category-detail-pane')),
      findsOneWidget,
    );
    final compactListWidth = tester
        .getSize(find.byKey(const ValueKey('prism-category-list-pane')))
        .width;
    final compactDetailWidth = tester
        .getSize(find.byKey(const ValueKey('prism-category-detail-pane')))
        .width;
    expect(compactListWidth, 460);
    expect(compactDetailWidth, greaterThanOrEqualTo(232));
    expect(tester.takeException(), isNull);

    await _setSize(tester, const Size(768, 900));
    await _showCategories(tester);
    _expectNarrowHeader(tester, categories.values);
    expect(
      find.byKey(const ValueKey('prism-category-detail-pane')),
      findsNothing,
    );
    await _capture('tablet-768.png');

    await _setSize(tester, const Size(375, 812));
    await _showCategories(tester);
    _expectNarrowHeader(tester, categories.values);
    _expectPasswordListClearsNavigation(tester);
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('prism-category-selection-count')),
          )
          .data,
      '未分类 2 · 共 7',
    );
    await _capture('mobile-375.png');

    await tester.tap(
      find.byKey(ValueKey('prism-password-drag-${firstItem.id}')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('prism-category-item-details')),
      findsOneWidget,
    );
    final detailPage = find.byKey(const ValueKey('prism-category-detail-page'));
    expect(detailPage, findsOneWidget);
    expect(tester.getTopLeft(detailPage), Offset.zero);
    expect(tester.getSize(detailPage), const Size(375, 812));
    expect(
      find.byKey(const ValueKey('prism-category-detail-back')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('prism-category-detail-scroll')),
      findsOneWidget,
    );
    expect(find.text('synthetic-only-0'), findsNothing);
    expect(
      find.byKey(const ValueKey('prism-category-detail-move')),
      findsOneWidget,
    );
    await _capture('mobile-detail-375.png');
    await tester.tap(find.byKey(const ValueKey('prism-category-detail-back')));
    await tester.pumpAndSettle();
    expect(detailPage, findsNothing);

    await tester.tap(
      find.byKey(ValueKey('prism-password-drag-${firstItem.id}')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('prism-category-detail-edit')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('prism-password-editor')), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    await controller.lock();
    await tester.pumpAndSettle();
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('captures compact Windows categories at 484x953', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
    });
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final controller = _buildController(
      initialVaultData: _compactWindowsVaultData(),
    );
    addTearDown(controller.dispose);
    await controller.bootstrap();
    await controller.createVault('synthetic-only-password');
    final categories = {
      for (final category in controller.vaultData.categories)
        category.name: category,
    };

    await tester.pumpWidget(
      RepaintBoundary(
        key: _captureKey,
        child: _ScreenshotApp(controller: controller),
      ),
    );
    await tester.pumpAndSettle();
    await _setSize(tester, const Size(484, 953));
    await _showCategories(tester);

    _expectNarrowHeader(tester, categories.values);
    _expectIntermediateCompactLayout(tester);
    _expectPasswordListClearsNavigation(tester);
    final allPasswords = tester.widget<Text>(
      find.byKey(const ValueKey('prism-category-label-全部密码')),
    );
    expect(allPasswords.data, '全部密码');
    expect(allPasswords.overflow, isNot(TextOverflow.ellipsis));
    expect(allPasswords.softWrap, isFalse);
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('prism-category-tab-count-全部密码')),
          )
          .data,
      '70',
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('prism-category-selection-count')),
          )
          .data,
      '未分类 40 · 共 70',
    );
    await _capture('windows-484x953.png');

    await _scrollPasswordListToEnd(tester);
    _expectPasswordListClearsNavigation(tester, expectLastRowVisible: true);
    await _capture('windows-484x953-list-end.png');

    await controller.lock();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    debugDefaultTargetPlatformOverride = null;
  });
}

Future<void> _showCategories(WidgetTester tester) async {
  if (find.byType(ResponsiveShell).evaluate().isNotEmpty) {
    final shellContext = tester.element(find.byType(ResponsiveShell));
    ProviderScope.containerOf(shellContext)
        .read(currentShellDestinationProvider.notifier)
        .go(CipherbookDestinationId.categories);
  }
  await tester.pumpAndSettle();
  expect(
    find.byKey(const ValueKey('prism-category-workbench')),
    findsOneWidget,
  );
}

Future<void> _setSize(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  await tester.pumpAndSettle();
}

void _expectNarrowHeader(
  WidgetTester tester,
  Iterable<VaultCategory> categories,
) {
  final primaryAction = find.byKey(
    const ValueKey('prism-category-add-primary'),
  );
  final actionMenu = find.byKey(const ValueKey('prism-category-action-menu'));
  final tabs = find.byKey(const ValueKey('prism-category-tabs'));
  final allPasswords = find.byKey(
    const ValueKey('prism-category-all-passwords'),
  );
  final search = find.byKey(const ValueKey('prism-category-password-search'));
  final sortMenu = find.byKey(const ValueKey('prism-category-sort-menu'));
  expect(find.byKey(const ValueKey('prism-category-add')), findsNothing);
  expect(find.byKey(const ValueKey('prism-category-organize')), findsNothing);
  expect(primaryAction, findsOneWidget);
  expect(tabs, findsOneWidget);
  _expectCategoryCreateAction(tester);
  final pageTitle = find.byKey(const ValueKey('prism-category-page-title'));
  expect(pageTitle, findsOneWidget);
  expect(tester.widget<Text>(pageTitle).data, '分类');
  expect(find.byKey(const ValueKey('prism-category-directory')), findsNothing);
  expect(allPasswords, findsOneWidget);
  expect(tester.getSize(allPasswords).height, 44);
  expect(
    find.byKey(const ValueKey('prism-category-add-password')),
    findsNothing,
  );
  expect(actionMenu, findsOneWidget);
  expect(
    tester.getSize(actionMenu).height,
    greaterThanOrEqualTo(CipherbookVisualTokens.controlHeight),
  );
  expect(search, findsOneWidget);
  expect(sortMenu, findsOneWidget);
  expect(find.byKey(const ValueKey('prism-category-order-sort')), findsNothing);
  expect(
    find.byKey(const ValueKey('prism-category-password-sort')),
    findsNothing,
  );
  expect(
    tester.getTopLeft(search).dy,
    greaterThan(tester.getBottomLeft(tabs).dy),
  );
  final pageTitleRect = tester.getRect(pageTitle);
  expect(
    tester.getRect(primaryAction).center.dy,
    closeTo(pageTitleRect.center.dy, 0.1),
  );
  expect(
    tester.getRect(actionMenu).center.dy,
    closeTo(pageTitleRect.center.dy, 0.1),
  );
  expect(
    tester.getRect(primaryAction).bottom,
    lessThan(tester.getRect(tabs).top),
  );
  _expectCategoryCapsulesFullyVisible(
    tester,
    container: tabs,
    categories: categories,
  );
  final tabLabel = tester.widget<Text>(
    find.byKey(const ValueKey('prism-category-label-全部密码')),
  );
  final tabCount = tester.widget<Text>(
    find.byKey(const ValueKey('prism-category-tab-count-全部密码')),
  );
  final selectionTitle = tester.widget<Text>(
    find.byKey(const ValueKey('prism-category-selection-title')),
  );
  final selectionCount = tester.widget<Text>(
    find.byKey(const ValueKey('prism-category-selection-count')),
  );
  expect(tabLabel.style?.fontSize, 13);
  expect(tabLabel.style?.fontWeight, FontWeight.w600);
  expect(tabCount.style?.fontSize, 13);
  expect(tabCount.style?.fontWeight, FontWeight.w600);
  expect(selectionTitle.style?.fontSize, 20);
  expect(selectionTitle.style?.fontWeight, FontWeight.w700);
  expect(selectionCount.style?.fontSize, 13);
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
  final menuRect = tester.getRect(actionMenu);
  expect(menuRect.left - primaryRect.right, greaterThanOrEqualTo(8));
}

void _expectCategoryCapsulesFullyVisible(
  WidgetTester tester, {
  required Finder container,
  required Iterable<VaultCategory> categories,
}) {
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
    for (final category in categories)
      find.byKey(ValueKey('prism-category-drop-${category.id}')),
    find.byKey(const ValueKey('prism-category-drop-uncategorized')),
  ];
  for (final capsule in capsules) {
    expect(capsule, findsOneWidget);
    final rect = tester.getRect(capsule);
    expect(rect.height, 44);
    expect(rect.left, greaterThanOrEqualTo(containerRect.left - 0.1));
    expect(rect.top, greaterThanOrEqualTo(containerRect.top - 0.1));
    expect(rect.right, lessThanOrEqualTo(containerRect.right + 0.1));
    expect(rect.bottom, lessThanOrEqualTo(containerRect.bottom + 0.1));
  }
  for (final label in [
    '全部密码',
    for (final category in categories) category.name,
    '未分类',
  ]) {
    final labelText = tester.widget<Text>(
      find.byKey(ValueKey('prism-category-label-$label')),
    );
    expect(labelText.overflow, isNot(TextOverflow.ellipsis));
    expect(labelText.softWrap, isFalse);
  }
}

void _expectIntermediateCompactLayout(WidgetTester tester) {
  final title = find.byKey(const ValueKey('prism-category-page-title'));
  final tabs = find.byKey(const ValueKey('prism-category-tabs'));
  final search = find.byKey(const ValueKey('prism-category-password-search'));
  final primaryAction = find.byKey(
    const ValueKey('prism-category-add-primary'),
  );
  final actionMenu = find.byKey(const ValueKey('prism-category-action-menu'));
  expect(title, findsOneWidget);
  expect(tester.getRect(title).bottom, lessThan(tester.getRect(tabs).top));
  final searchRect = tester.getRect(search);
  final primaryRect = tester.getRect(primaryAction);
  final menuRect = tester.getRect(actionMenu);
  final titleRect = tester.getRect(title);
  final tabsRect = tester.getRect(tabs);
  final viewportWidth =
      tester.view.physicalSize.width / tester.view.devicePixelRatio;
  expect(searchRect.width, closeTo(viewportWidth - 32, 0.1));
  expect(searchRect.top, greaterThan(tabsRect.bottom));
  expect(primaryRect.center.dy, closeTo(titleRect.center.dy, 0.1));
  expect(menuRect.center.dy, closeTo(titleRect.center.dy, 0.1));
  expect(primaryRect.bottom, lessThan(tabsRect.top));
  expect(primaryRect.height, greaterThanOrEqualTo(44));
  expect(menuRect.height, greaterThanOrEqualTo(44));
  expect(menuRect.left - primaryRect.right, greaterThanOrEqualTo(8));
}

void _expectPasswordListClearsNavigation(
  WidgetTester tester, {
  bool expectLastRowVisible = false,
}) {
  final list = find.byKey(const ValueKey('prism-category-password-list'));
  final navigation = find.byKey(const ValueKey('shell-narrow-navigation-dock'));
  expect(list, findsOneWidget);
  expect(navigation, findsOneWidget);
  final listRect = tester.getRect(list);
  final navigationRect = tester.getRect(navigation);
  expect(listRect.bottom, lessThanOrEqualTo(navigationRect.top - 16));

  if (!expectLastRowVisible) {
    return;
  }
  final rows = _visiblePasswordRows(tester);
  expect(rows, isNotEmpty);
  final lastRow = rows.reduce(
    (current, candidate) =>
        candidate.bottom > current.bottom ? candidate : current,
  );
  expect(lastRow.bottom, lessThanOrEqualTo(listRect.bottom));
  expect(lastRow.bottom, lessThan(navigationRect.top));
}

Future<void> _scrollPasswordListToEnd(WidgetTester tester) async {
  final list = find.byKey(const ValueKey('prism-category-password-list'));
  final scrollable = find.descendant(
    of: list,
    matching: find.byType(Scrollable),
  );
  expect(scrollable, findsOneWidget);
  final position = tester.state<ScrollableState>(scrollable).position;
  position.jumpTo(position.maxScrollExtent);
  await tester.pumpAndSettle();
}

List<Rect> _visiblePasswordRows(WidgetTester tester) {
  final rows = find.byWidgetPredicate((widget) {
    final key = widget.key;
    return key is ValueKey<String> &&
        key.value.startsWith('prism-password-drag-');
  });
  return [
    for (final element in rows.evaluate())
      tester.getRect(find.byWidget(element.widget)),
  ];
}

Future<void> _capture(String fileName) async {
  await expectLater(
    find.byKey(_captureKey),
    matchesGoldenFile('../$_screenshotDirectory/$fileName'),
  );
}

class _ScreenshotApp extends StatelessWidget {
  const _ScreenshotApp({required this.controller});

  final VaultController controller;

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
          child: Builder(
            builder: (context) => ResponsiveShell(
              initialDestinationId: CipherbookDestinationId.categories,
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

VaultData _compactWindowsVaultData() {
  final updatedAt = DateTime(2026, 11, 14, 20, 25);
  final categories = [
    VaultCategory(
      id: 'compact-wallet',
      name: '钱包',
      createdAt: updatedAt,
      updatedAt: updatedAt,
      sortIndex: 0,
    ),
    VaultCategory(
      id: 'compact-server',
      name: '服务器',
      createdAt: updatedAt,
      updatedAt: updatedAt,
      sortIndex: 1,
    ),
    VaultCategory(
      id: 'compact-mail',
      name: '邮箱',
      createdAt: updatedAt,
      updatedAt: updatedAt,
      sortIndex: 2,
    ),
  ];
  final items = <VaultItem>[];
  var itemIndex = 0;
  void addItems(String label, String folder, int count) {
    for (var index = 0; index < count; index++) {
      final itemNumber = itemIndex + 1;
      items.add(
        VaultItem(
          id: 'compact-item-$itemIndex',
          title: '$label $itemNumber',
          username: 'synthetic-$itemNumber@example.test',
          password: 'synthetic-only-password',
          url: 'https://example.test/$itemNumber',
          notes: '',
          tags: const [],
          createdAt: updatedAt,
          updatedAt: updatedAt,
          folder: folder,
        ),
      );
      itemIndex++;
    }
  }

  addItems('钱包账户', 'compact-wallet', 17);
  addItems('服务器', 'compact-server', 7);
  addItems('邮箱', 'compact-mail', 6);
  addItems('未分类账户', '', 40);
  return VaultData(items: items, categories: categories, updatedAt: updatedAt);
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
    ('邮箱', 'hello@example.test', '工作'),
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
      ),
  ];
  return VaultData(items: items, categories: categories, updatedAt: updatedAt);
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
