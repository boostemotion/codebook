import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:cipherbook/models/vault_models.dart';
import 'package:cipherbook/presentation/app/cipherbook_destinations.dart';
import 'package:cipherbook/presentation/app/cipherbook_ui_localizations.dart';
import 'package:cipherbook/presentation/bridge/vault_controller_provider.dart';
import 'package:cipherbook/presentation/categories/categories_page.dart';
import 'package:cipherbook/presentation/shell/cipherbook_navigation.dart';
import 'package:cipherbook/presentation/shell/cipherbook_shell_chrome.dart';
import 'package:cipherbook/presentation/theme/cipherbook_visual_tokens.dart';
import 'package:cipherbook/presentation/vault/vault_page.dart';
import 'package:cipherbook/services/clipboard_service.dart';
import 'package:cipherbook/services/crypto_service.dart';
import 'package:cipherbook/services/device_key_store.dart';
import 'package:cipherbook/services/import_export_service.dart';
import 'package:cipherbook/services/password_generator_service.dart';
import 'package:cipherbook/services/vault_repository.dart';
import 'package:cipherbook/state/vault_controller.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_shell/prism_shell.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';

const _captureKey = ValueKey('password-inspector-capture');
const _screenshotDirectory =
    'docs/design/frontend-v2/password-detail-2026-11-14/screenshots';
const _copyVisualSettle = Duration(milliseconds: 220);
const _populatedItemId = 'inspector-github';
const _sparseItemId = 'inspector-sparse';
const _walletItemId = 'inspector-bank';
const _walletRelatedItemIds = [
  'inspector-crypto',
  'inspector-insurance',
  'inspector-reserve',
  'inspector-card',
];

void main() {
  setUpAll(() async {
    final bytes = await File(r'C:\Windows\Fonts\Deng.ttf').readAsBytes();
    final data = ByteData.sublistView(bytes);
    final loader = FontLoader('Deng')..addFont(Future<ByteData>.value(data));
    await loader.load();
  });

  testWidgets('captures the shared password inspector across breakpoints', (
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
    await _showDestination(tester, CipherbookDestinationId.vault);
    await _selectItem(tester, _walletItemId, pageType: CipherbookVaultPage);
    _expectDocumentInspector(
      tester,
      'prism-detail',
      populated: true,
      hasRelated: true,
    );
    _expectActionTargets(tester, 'prism-detail');
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('prism-detail-notes-section')),
        matching: find.textContaining('日常收支与自动扣款'),
      ),
      findsOneWidget,
    );
    expect(find.text('未发现重复'), findsOneWidget);
    expect(find.text('TOTP 已配置'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _capture('all-passwords-populated-1440.png');

    await _showDestination(tester, CipherbookDestinationId.categories);
    await _selectItem(
      tester,
      _walletItemId,
      pageType: CipherbookCategoriesPage,
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('prism-category-detail-title')),
          )
          .data,
      '储蓄账户',
    );
    await _capture('categories-populated-1440.png');
    _expectDocumentInspector(
      tester,
      'prism-category-detail',
      populated: true,
      hasRelated: true,
    );

    await _showDestination(tester, CipherbookDestinationId.vault);
    await _selectItem(tester, _sparseItemId, pageType: CipherbookVaultPage);
    _expectDocumentInspector(
      tester,
      'prism-detail',
      populated: false,
      hasRelated: false,
    );
    expect(find.text('未设置'), findsNothing);
    expect(find.text('暂无备注'), findsOneWidget);
    expect(find.byKey(const ValueKey('prism-detail-open-url')), findsNothing);
    expect(find.byKey(const ValueKey('prism-detail-totp-value')), findsNothing);
    await _capture('all-passwords-sparse-1440.png');

    await _setSize(tester, const Size(1280, 800));
    await _showDestination(tester, CipherbookDestinationId.vault);
    await _selectItem(tester, _walletItemId, pageType: CipherbookVaultPage);
    await _expectShortWideInspector(tester, 'prism-detail');
    final allPasswordsDetail1280 = tester.getRect(
      find.byKey(const ValueKey('prism-vault-detail-card')),
    );

    await _showDestination(tester, CipherbookDestinationId.categories);
    await _selectItem(
      tester,
      _walletItemId,
      pageType: CipherbookCategoriesPage,
    );
    await _expectShortWideInspector(tester, 'prism-category-detail');
    _expectSameDetailRect(
      allPasswordsDetail1280,
      tester.getRect(find.byKey(const ValueKey('prism-category-item-details'))),
    );

    await _setSize(tester, const Size(768, 900));
    await _leaveCategoryDetail(tester);
    await _showDestination(tester, CipherbookDestinationId.vault);
    await _selectItem(tester, _walletItemId, pageType: CipherbookVaultPage);
    _expectNarrowDetail(tester, 'prism-detail');
    _expectNoAppNavigation(tester);
    await _expectToolbarScrollTail(tester, 'prism-detail');
    await _revealRelatedContext(tester, 'prism-detail');
    await _capture('all-passwords-detail-768.png');
    _expectDetailNavigation(tester, 'prism-detail');
    final allPasswordsDetail768 = tester.getRect(
      find.byKey(const ValueKey('prism-vault-detail-card')),
    );
    await _leaveAllPasswordsDetail(tester);

    await _showDestination(tester, CipherbookDestinationId.categories);
    await _selectItem(
      tester,
      _walletItemId,
      pageType: CipherbookCategoriesPage,
    );
    _expectNarrowDetail(tester, 'prism-category-detail');
    _expectNoAppNavigation(tester);
    await _expectToolbarScrollTail(tester, 'prism-category-detail');
    await _revealRelatedContext(tester, 'prism-category-detail');
    await _capture('categories-detail-768.png');
    _expectDetailNavigation(tester, 'prism-category-detail');
    _expectSameDetailRect(
      allPasswordsDetail768,
      tester.getRect(find.byKey(const ValueKey('prism-category-item-details'))),
    );
    await _leaveCategoryDetail(tester);

    await _setSize(tester, const Size(375, 812));
    await _showDestination(tester, CipherbookDestinationId.vault);
    await _selectItem(tester, _walletItemId, pageType: CipherbookVaultPage);
    _expectNarrowDetail(tester, 'prism-detail');
    _expectNoAppNavigation(tester);
    await _expectToolbarScrollTail(tester, 'prism-detail');
    await _revealRelatedContext(tester, 'prism-detail');
    await _capture('all-passwords-detail-375.png');
    final allPasswordsDetail375 = tester.getRect(
      find.byKey(const ValueKey('prism-vault-detail-card')),
    );
    await _leaveAllPasswordsDetail(tester);

    await _showDestination(tester, CipherbookDestinationId.categories);
    await _selectItem(
      tester,
      _walletItemId,
      pageType: CipherbookCategoriesPage,
    );
    _expectNarrowDetail(tester, 'prism-category-detail');
    _expectNoAppNavigation(tester);
    await _expectToolbarScrollTail(tester, 'prism-category-detail');
    await _revealRelatedContext(tester, 'prism-category-detail');
    await _capture('categories-detail-375.png');
    _expectSameDetailRect(
      allPasswordsDetail375,
      tester.getRect(find.byKey(const ValueKey('prism-category-item-details'))),
    );
    await _leaveCategoryDetail(tester);

    await _showDestination(tester, CipherbookDestinationId.vault);
    await _selectItem(tester, _sparseItemId, pageType: CipherbookVaultPage);
    _expectNarrowDetail(
      tester,
      'prism-detail',
      populated: false,
      hasRelated: false,
    );
    expect(find.text('暂无备注'), findsOneWidget);
    await _capture('all-passwords-sparse-375.png');

    await controller.lock();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('captures an isolated All Passwords state at 1024', (
    tester,
  ) async {
    final controller = await _pumpInspectorApp(tester, const Size(1024, 900));

    await _showDestination(tester, CipherbookDestinationId.vault);
    await _selectItem(tester, _walletItemId, pageType: CipherbookVaultPage);
    _expectAllPasswordsPageIdentity(tester);
    _expectSingleColumnInspector(tester, 'prism-detail', hasRelated: true);
    _expectReadableCredentialValues(tester, 'prism-detail');
    await _expectToolbarScrollTail(
      tester,
      'prism-detail',
      expectScrollable: true,
    );
    await _revealRelatedContext(tester, 'prism-detail');
    _expectAllPasswordsPageIdentity(tester);
    await _capture('all-passwords-populated-1024.png');

    await controller.lock();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('captures an isolated Categories state at 1024', (tester) async {
    final controller = await _pumpInspectorApp(tester, const Size(1024, 900));

    await _showDestination(tester, CipherbookDestinationId.categories);
    await _selectItem(
      tester,
      _walletItemId,
      pageType: CipherbookCategoriesPage,
    );
    _expectCategoriesPageIdentity(tester, selectedTitle: '储蓄账户');
    _expectSingleColumnInspector(
      tester,
      'prism-category-detail',
      hasRelated: true,
    );
    _expectReadableCredentialValues(tester, 'prism-category-detail');
    await _expectToolbarScrollTail(
      tester,
      'prism-category-detail',
      expectScrollable: true,
    );
    await _revealRelatedContext(tester, 'prism-category-detail');
    _expectCategoriesPageIdentity(tester, selectedTitle: '储蓄账户');
    await _capture('categories-populated-1024.png');

    await controller.lock();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('1024 explicit navigation keeps page identity', (tester) async {
    final controller = await _pumpInspectorApp(tester, const Size(1024, 900));

    await _showDestination(tester, CipherbookDestinationId.categories);
    _expectCategoriesPageIdentity(tester);
    await _showDestination(tester, CipherbookDestinationId.vault);
    _expectAllPasswordsPageIdentity(tester);
    await _showDestination(tester, CipherbookDestinationId.categories);
    _expectCategoriesPageIdentity(tester);

    await controller.lock();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    debugDefaultTargetPlatformOverride = null;
  });

  for (final copyCase
      in <
        ({
          Size size,
          String entry,
          String control,
          String feedback,
          String message,
          String visibleTextOwner,
          String? activeText,
          String? inactiveText,
          bool compactCheck,
          bool successBackground,
          bool successGlyph,
          String? fieldName,
          String? labelSlot,
          bool scrollToToolbar,
          String? screenshot,
        })
      >[
        (
          size: const Size(1440, 900),
          entry: 'top password action',
          control: 'copy-password',
          feedback: 'inline-copy-header-password',
          message: '已复制密码',
          visibleTextOwner: 'copy-password',
          activeText: '已复制',
          inactiveText: '复制密码',
          compactCheck: false,
          successBackground: true,
          successGlyph: false,
          fieldName: null,
          labelSlot: 'copy-password-label',
          scrollToToolbar: false,
          screenshot: 'all-passwords-inline-copy-1440.png',
        ),
        (
          size: const Size(1440, 900),
          entry: 'account row action',
          control: 'copy-username',
          feedback: 'inline-copy-username',
          message: '已复制账号',
          visibleTextOwner: 'credential-username',
          activeText: '已复制',
          inactiveText: '账号',
          compactCheck: false,
          successBackground: false,
          successGlyph: true,
          fieldName: '账号',
          labelSlot: null,
          scrollToToolbar: false,
          screenshot: 'all-passwords-inline-copy-account-row-1440.png',
        ),
        (
          size: const Size(1440, 900),
          entry: 'password row action',
          control: 'copy-password-field',
          feedback: 'inline-copy-password',
          message: '已复制密码',
          visibleTextOwner: 'credential-password',
          activeText: '已复制',
          inactiveText: '密码',
          compactCheck: false,
          successBackground: false,
          successGlyph: true,
          fieldName: '密码',
          labelSlot: null,
          scrollToToolbar: false,
          screenshot: null,
        ),
        (
          size: const Size(1440, 900),
          entry: 'toolbar account action',
          control: 'shortcut-copy-username',
          feedback: 'inline-copy-toolbar-username',
          message: '已复制账号',
          visibleTextOwner: 'shortcut-copy-username',
          activeText: '已复制',
          inactiveText: '账号',
          compactCheck: false,
          successBackground: false,
          successGlyph: true,
          fieldName: null,
          labelSlot: 'shortcut-copy-username-label',
          scrollToToolbar: true,
          screenshot: null,
        ),
        (
          size: const Size(1440, 900),
          entry: 'toolbar password action',
          control: 'shortcut-copy-password',
          feedback: 'inline-copy-toolbar-password',
          message: '已复制密码',
          visibleTextOwner: 'shortcut-copy-password',
          activeText: '已复制',
          inactiveText: '密码',
          compactCheck: false,
          successBackground: false,
          successGlyph: true,
          fieldName: null,
          labelSlot: 'shortcut-copy-password-label',
          scrollToToolbar: true,
          screenshot: null,
        ),
        (
          size: const Size(375, 812),
          entry: 'top password action',
          control: 'copy-password',
          feedback: 'inline-copy-header-password',
          message: '已复制密码',
          visibleTextOwner: 'copy-password',
          activeText: null,
          inactiveText: null,
          compactCheck: true,
          successBackground: true,
          successGlyph: false,
          fieldName: null,
          labelSlot: null,
          scrollToToolbar: false,
          screenshot: 'all-passwords-inline-copy-375.png',
        ),
        (
          size: const Size(375, 812),
          entry: 'account row action',
          control: 'copy-username',
          feedback: 'inline-copy-username',
          message: '已复制账号',
          visibleTextOwner: 'credential-username',
          activeText: '已复制',
          inactiveText: '账号',
          compactCheck: false,
          successBackground: false,
          successGlyph: true,
          fieldName: '账号',
          labelSlot: null,
          scrollToToolbar: false,
          screenshot: 'all-passwords-inline-copy-account-row-375.png',
        ),
        (
          size: const Size(375, 812),
          entry: 'password row action',
          control: 'copy-password-field',
          feedback: 'inline-copy-password',
          message: '已复制密码',
          visibleTextOwner: 'credential-password',
          activeText: '已复制',
          inactiveText: '密码',
          compactCheck: false,
          successBackground: false,
          successGlyph: true,
          fieldName: '密码',
          labelSlot: null,
          scrollToToolbar: false,
          screenshot: null,
        ),
        (
          size: const Size(375, 812),
          entry: 'toolbar account action',
          control: 'shortcut-copy-username',
          feedback: 'inline-copy-toolbar-username',
          message: '已复制账号',
          visibleTextOwner: 'shortcut-copy-username',
          activeText: '已复制',
          inactiveText: '账号',
          compactCheck: false,
          successBackground: false,
          successGlyph: true,
          fieldName: null,
          labelSlot: 'shortcut-copy-username-label',
          scrollToToolbar: true,
          screenshot: null,
        ),
        (
          size: const Size(375, 812),
          entry: 'toolbar password action',
          control: 'shortcut-copy-password',
          feedback: 'inline-copy-toolbar-password',
          message: '已复制密码',
          visibleTextOwner: 'shortcut-copy-password',
          activeText: '已复制',
          inactiveText: '密码',
          compactCheck: false,
          successBackground: false,
          successGlyph: true,
          fieldName: null,
          labelSlot: 'shortcut-copy-password-label',
          scrollToToolbar: true,
          screenshot: null,
        ),
      ]) {
    final viewport =
        '${copyCase.size.width.toInt()}x${copyCase.size.height.toInt()}';
    testWidgets('inline copy feedback is stable for ${copyCase.entry} at '
        '$viewport', (tester) async {
      final controller = await _pumpInspectorApp(tester, copyCase.size);
      const prefix = 'prism-detail';
      final control = find.byKey(ValueKey('$prefix-${copyCase.control}'));
      final feedback = find.byKey(ValueKey('$prefix-${copyCase.feedback}'));
      final visibleTextOwner = find.byKey(
        ValueKey('$prefix-${copyCase.visibleTextOwner}'),
      );
      final labelSlot = copyCase.labelSlot == null
          ? null
          : find.byKey(ValueKey('$prefix-${copyCase.labelSlot}'));

      await _showDestination(tester, CipherbookDestinationId.vault);
      await _selectItem(tester, _walletItemId, pageType: CipherbookVaultPage);
      if (copyCase.scrollToToolbar) {
        await _expectToolbarScrollTail(tester, prefix);
      }
      expect(control.hitTestable(), findsOneWidget);

      final controlRect = tester.getRect(control);
      final labelSlotRect = labelSlot == null
          ? null
          : tester.getRect(labelSlot);
      final layoutBeforeCopy = _inspectorLayout(tester, prefix);
      final scrollPosition = _inspectorScrollPosition(tester, prefix);
      final offsetBeforeCopy = scrollPosition.pixels;
      final extentBeforeCopy = scrollPosition.maxScrollExtent;

      await tester.tap(control);
      await tester.pump();
      await tester.pump(_copyVisualSettle);
      _expectInlineCopyActive(
        tester,
        control: control,
        feedback: feedback,
        message: copyCase.message,
        visibleTextOwner: visibleTextOwner,
        activeText: copyCase.activeText,
        compactCheck: copyCase.compactCheck,
        successBackground: copyCase.successBackground,
        successGlyph: copyCase.successGlyph,
        fieldName: copyCase.fieldName,
      );
      if (copyCase.successBackground) {
        await _expectRenderedControlFill(
          tester,
          control,
          expected: CipherbookVisualTokens.success,
        );
      }
      _expectNoFloatingCopyFeedback(tester, prefix);
      _expectInspectorLayoutUnchanged(tester, prefix, layoutBeforeCopy);
      expect(tester.getRect(control), controlRect);
      expect(tester.getRect(feedback), controlRect);
      if (labelSlot != null) {
        expect(tester.getRect(labelSlot), labelSlotRect);
      }
      expect(scrollPosition.pixels, offsetBeforeCopy);
      expect(scrollPosition.maxScrollExtent, extentBeforeCopy);
      final activeFocus = FocusManager.instance.primaryFocus;

      if (copyCase.screenshot case final screenshot?) {
        await _capture(screenshot);
      }

      await tester.pump(const Duration(milliseconds: 1579));
      _expectInlineCopyActive(
        tester,
        control: control,
        feedback: feedback,
        message: copyCase.message,
        visibleTextOwner: visibleTextOwner,
        activeText: copyCase.activeText,
        compactCheck: copyCase.compactCheck,
        successBackground: copyCase.successBackground,
        successGlyph: copyCase.successGlyph,
        fieldName: copyCase.fieldName,
      );
      expect(tester.getRect(control), controlRect);
      if (labelSlot != null) {
        expect(tester.getRect(labelSlot), labelSlotRect);
      }
      expect(FocusManager.instance.primaryFocus, same(activeFocus));

      await tester.pump(const Duration(milliseconds: 1));
      _expectInlineCopyInactive(
        tester,
        control: control,
        feedback: feedback,
        visibleTextOwner: visibleTextOwner,
        activeText: copyCase.activeText,
        inactiveText: copyCase.inactiveText,
        successBackground: copyCase.successBackground,
        fieldName: copyCase.fieldName,
      );
      if (copyCase.successBackground) {
        await tester.pump(_copyVisualSettle);
        await _expectRenderedControlFill(
          tester,
          control,
          expected: CipherbookVisualTokens.accent,
        );
      }
      _expectInspectorLayoutUnchanged(tester, prefix, layoutBeforeCopy);
      expect(tester.getRect(control), controlRect);
      if (labelSlot != null) {
        expect(tester.getRect(labelSlot), labelSlotRect);
      }
      expect(scrollPosition.pixels, offsetBeforeCopy);
      expect(scrollPosition.maxScrollExtent, extentBeforeCopy);
      expect(FocusManager.instance.primaryFocus, same(activeFocus));

      await controller.lock();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      debugDefaultTargetPlatformOverride = null;
    });
  }

  testWidgets('repeating inline copy feedback restarts its timer', (
    tester,
  ) async {
    final controller = await _pumpInspectorApp(tester, const Size(1440, 900));
    const prefix = 'prism-detail';
    final control = find.byKey(const ValueKey('prism-detail-copy-password'));
    final feedback = find.byKey(
      const ValueKey('prism-detail-inline-copy-header-password'),
    );

    await _showDestination(tester, CipherbookDestinationId.vault);
    await _selectItem(tester, _walletItemId, pageType: CipherbookVaultPage);
    final controlRect = tester.getRect(control);
    final layoutBeforeCopy = _inspectorLayout(tester, prefix);

    await tester.tap(control);
    await tester.pump();
    await tester.pump(_copyVisualSettle);
    _expectInlineCopyActive(
      tester,
      control: control,
      feedback: feedback,
      message: '已复制密码',
      visibleTextOwner: control,
      activeText: '已复制',
      compactCheck: false,
      successBackground: true,
      successGlyph: false,
      fieldName: null,
    );

    await tester.pump(const Duration(milliseconds: 680));
    await tester.tap(control);
    await tester.pump();
    await tester.pump(_copyVisualSettle);
    _expectInlineCopyActive(
      tester,
      control: control,
      feedback: feedback,
      message: '已复制密码',
      visibleTextOwner: control,
      activeText: '已复制',
      compactCheck: false,
      successBackground: true,
      successGlyph: false,
      fieldName: null,
    );

    await tester.pump(const Duration(milliseconds: 680));
    _expectInlineCopyActive(
      tester,
      control: control,
      feedback: feedback,
      message: '已复制密码',
      visibleTextOwner: control,
      activeText: '已复制',
      compactCheck: false,
      successBackground: true,
      successGlyph: false,
      fieldName: null,
    );
    await tester.pump(const Duration(milliseconds: 899));
    _expectInlineCopyActive(
      tester,
      control: control,
      feedback: feedback,
      message: '已复制密码',
      visibleTextOwner: control,
      activeText: '已复制',
      compactCheck: false,
      successBackground: true,
      successGlyph: false,
      fieldName: null,
    );
    await tester.pump(const Duration(milliseconds: 1));
    _expectInlineCopyInactive(
      tester,
      control: control,
      feedback: feedback,
      visibleTextOwner: control,
      activeText: '已复制',
      inactiveText: '复制密码',
      successBackground: true,
      fieldName: null,
    );
    _expectInspectorLayoutUnchanged(tester, prefix, layoutBeforeCopy);
    expect(tester.getRect(control), controlRect);
    _expectNoFloatingCopyFeedback(tester, prefix);

    await controller.lock();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('related entries switch detail selection in both page paths', (
    tester,
  ) async {
    final controller = await _pumpInspectorApp(tester, const Size(1440, 900));

    await _showDestination(tester, CipherbookDestinationId.vault);
    await _selectItem(tester, _walletItemId, pageType: CipherbookVaultPage);
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('prism-detail-title')))
          .data,
      '储蓄账户',
    );
    await tester.tap(
      find.byKey(const ValueKey('prism-detail-related-inspector-card')),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('prism-detail-title')))
          .data,
      '家庭信用卡',
    );

    await _showDestination(tester, CipherbookDestinationId.categories);
    await _selectItem(
      tester,
      _walletItemId,
      pageType: CipherbookCategoriesPage,
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('prism-category-detail-title')),
          )
          .data,
      '储蓄账户',
    );
    await tester.tap(
      find.byKey(
        const ValueKey('prism-category-detail-related-inspector-card'),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('prism-category-detail-title')),
          )
          .data,
      '家庭信用卡',
    );
    expect(find.byType(CipherbookCategoriesPage), findsOneWidget);

    await controller.lock();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('narrow category related selection stays in the detail page', (
    tester,
  ) async {
    final controller = await _pumpInspectorApp(tester, const Size(768, 1024));

    await _showDestination(tester, CipherbookDestinationId.categories);
    await _selectItem(
      tester,
      _walletItemId,
      pageType: CipherbookCategoriesPage,
    );
    expect(
      find.byKey(const ValueKey('prism-category-detail-page')),
      findsOneWidget,
    );
    await _revealRelatedContext(tester, 'prism-category-detail');
    await tester.tap(
      find.byKey(
        const ValueKey('prism-category-detail-related-inspector-card'),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('prism-category-detail-page')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('prism-category-detail-title')),
          )
          .data,
      '家庭信用卡',
    );
    await tester.tap(find.byKey(const ValueKey('prism-category-detail-back')));
    await tester.pumpAndSettle();

    await controller.lock();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('rechecks the shared inspector at 1024x768', (tester) async {
    final controller = await _pumpInspectorApp(tester, const Size(1024, 768));

    await _showDestination(tester, CipherbookDestinationId.vault);
    await _selectItem(tester, _walletItemId, pageType: CipherbookVaultPage);
    _expectSingleColumnInspector(tester, 'prism-detail');
    await _expectToolbarScrollTail(tester, 'prism-detail');

    await _showDestination(tester, CipherbookDestinationId.categories);
    await _selectItem(
      tester,
      _walletItemId,
      pageType: CipherbookCategoriesPage,
    );
    _expectSingleColumnInspector(tester, 'prism-category-detail');
    await _expectToolbarScrollTail(tester, 'prism-category-detail');

    await controller.lock();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('rechecks the shared inspector at 768x1024', (tester) async {
    final controller = await _pumpInspectorApp(tester, const Size(768, 1024));

    await _showDestination(tester, CipherbookDestinationId.vault);
    await _selectItem(tester, _walletItemId, pageType: CipherbookVaultPage);
    _expectNarrowDetail(tester, 'prism-detail');
    _expectNoAppNavigation(tester);
    await _expectToolbarScrollTail(tester, 'prism-detail');
    final allPasswordsRect = tester.getRect(
      find.byKey(const ValueKey('prism-vault-detail-card')),
    );
    await _leaveAllPasswordsDetail(tester);

    await _showDestination(tester, CipherbookDestinationId.categories);
    await _selectItem(
      tester,
      _walletItemId,
      pageType: CipherbookCategoriesPage,
    );
    _expectNarrowDetail(tester, 'prism-category-detail');
    _expectNoAppNavigation(tester);
    await _expectToolbarScrollTail(tester, 'prism-category-detail');
    _expectSameDetailRect(
      allPasswordsRect,
      tester.getRect(find.byKey(const ValueKey('prism-category-item-details'))),
    );
    await _leaveCategoryDetail(tester);

    await controller.lock();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    debugDefaultTargetPlatformOverride = null;
  });
}

Map<String, Rect> _inspectorLayout(WidgetTester tester, String prefix) {
  const suffixes = [
    'header',
    'credentials-section',
    'credential-username',
    'credential-password',
    'username-value',
    'password-value',
    'notes-section',
    'metadata-strip',
    'related-section',
    'footer',
    'copy-password',
    'copy-username',
    'copy-password-field',
    'shortcut-copy-username',
    'shortcut-copy-password',
  ];
  return {
    for (final suffix in suffixes)
      suffix: tester.getRect(find.byKey(ValueKey('$prefix-$suffix'))),
  };
}

void _expectInspectorLayoutUnchanged(
  WidgetTester tester,
  String prefix,
  Map<String, Rect> expected,
) {
  for (final entry in expected.entries) {
    expect(
      tester.getRect(find.byKey(ValueKey('$prefix-${entry.key}'))),
      entry.value,
      reason: '${entry.key} shifted after copy feedback appeared',
    );
  }
}

ScrollPosition _inspectorScrollPosition(WidgetTester tester, String prefix) {
  final scrollable = find.descendant(
    of: find.byKey(ValueKey('$prefix-scroll')),
    matching: find.byType(Scrollable),
  );
  expect(scrollable, findsOneWidget);
  return tester.state<ScrollableState>(scrollable).position;
}

void _expectInlineCopyActive(
  WidgetTester tester, {
  required Finder control,
  required Finder feedback,
  required String message,
  required Finder visibleTextOwner,
  required String? activeText,
  required bool compactCheck,
  required bool successBackground,
  required bool successGlyph,
  required String? fieldName,
}) {
  expect(control, findsOneWidget);
  expect(feedback, findsOneWidget);
  final semantics = tester.widget<Semantics>(feedback);
  expect(semantics.properties.liveRegion, isTrue);
  expect(semantics.properties.label, message);
  final check = find.descendant(
    of: control,
    matching: find.byWidgetPredicate(
      (widget) => widget is GlyphIcon && identical(widget.glyph, Glyphs.check),
    ),
  );
  expect(check, findsOneWidget);
  if (successGlyph) {
    expect(
      tester.widget<GlyphIcon>(check).color,
      CipherbookVisualTokens.success,
    );
  }
  if (compactCheck) {
    expect(tester.getSize(check), const Size(26, 26));
    expect(
      tester.getCenter(check).dx,
      closeTo(tester.getCenter(control).dx, 0.5),
    );
    expect(
      tester.getCenter(check).dy,
      closeTo(tester.getCenter(control).dy, 0.5),
    );
    expect(
      find.descendant(of: control, matching: find.text('已复制')),
      findsNothing,
    );
  }
  expect(
    find.descendant(
      of: control,
      matching: find.byWidgetPredicate(
        (widget) => widget is GlyphIcon && identical(widget.glyph, Glyphs.copy),
      ),
    ),
    findsNothing,
  );
  if (activeText != null) {
    final successText = find.descendant(
      of: visibleTextOwner,
      matching: find.text(activeText),
    );
    expect(successText, findsOneWidget);
    expect(find.text(activeText), findsOneWidget);
    expect(
      tester.widget<Text>(successText).style?.color,
      successBackground
          ? tester.element(control).colorScheme.onPrimary
          : CipherbookVisualTokens.success,
    );
    if (fieldName != null) {
      final neutralFieldName = find.descendant(
        of: visibleTextOwner,
        matching: find.text(fieldName),
      );
      expect(neutralFieldName, findsOneWidget);
      expect(
        tester.widget<Text>(neutralFieldName).style?.color,
        tester.element(control).colorScheme.onSurfaceVariant,
      );
      final separation =
          tester.getRect(successText).left -
          tester.getRect(neutralFieldName).right;
      expect(separation, greaterThanOrEqualTo(CipherbookVisualTokens.space8));
    }
  } else {
    expect(find.text('已复制'), findsNothing);
  }
  if (successBackground) {
    final surface = find.descendant(
      of: control,
      matching: find.byType(PressSurface),
    );
    expect(surface, findsOneWidget);
    expect(
      tester.widget<PressSurface>(surface).fill,
      CipherbookVisualTokens.success,
    );
    expect(
      _resolvedCopyBackground(tester, control),
      CipherbookVisualTokens.success,
    );
  }
}

void _expectInlineCopyInactive(
  WidgetTester tester, {
  required Finder control,
  required Finder feedback,
  required Finder visibleTextOwner,
  required String? activeText,
  required String? inactiveText,
  required bool successBackground,
  required String? fieldName,
}) {
  expect(control, findsOneWidget);
  expect(feedback, findsOneWidget);
  final semantics = tester.widget<Semantics>(feedback);
  expect(semantics.properties.liveRegion, isFalse);
  expect(semantics.properties.label, isNull);
  expect(
    find.descendant(
      of: control,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is GlyphIcon && identical(widget.glyph, Glyphs.check),
      ),
    ),
    findsNothing,
  );
  expect(
    find.descendant(
      of: control,
      matching: find.byWidgetPredicate(
        (widget) => widget is GlyphIcon && identical(widget.glyph, Glyphs.copy),
      ),
    ),
    findsOneWidget,
  );
  if (activeText != null) {
    expect(
      find.descendant(of: visibleTextOwner, matching: find.text(activeText)),
      findsNothing,
    );
    expect(find.text(activeText), findsNothing);
  }
  if (inactiveText != null) {
    expect(
      find.descendant(of: visibleTextOwner, matching: find.text(inactiveText)),
      findsOneWidget,
    );
  }
  if (fieldName != null) {
    final neutralFieldName = find.descendant(
      of: visibleTextOwner,
      matching: find.text(fieldName),
    );
    expect(neutralFieldName, findsOneWidget);
    expect(
      tester.widget<Text>(neutralFieldName).style?.color,
      tester.element(control).colorScheme.onSurfaceVariant,
    );
  }
  if (successBackground) {
    expect(
      _resolvedCopyBackground(tester, control),
      CipherbookVisualTokens.accent,
    );
  }
}

Color? _resolvedCopyBackground(WidgetTester tester, Finder control) {
  final filledButton = find.descendant(
    of: control,
    matching: find.byType(FilledButton),
  );
  if (filledButton.evaluate().isNotEmpty) {
    return tester
        .widget<FilledButton>(filledButton)
        .style
        ?.backgroundColor
        ?.resolve(<WidgetState>{});
  }
  final iconButton = find.descendant(
    of: control,
    matching: find.byType(IconButton),
  );
  expect(iconButton, findsOneWidget);
  return tester
      .widget<IconButton>(iconButton)
      .style
      ?.backgroundColor
      ?.resolve(<WidgetState>{});
}

Future<void> _expectRenderedControlFill(
  WidgetTester tester,
  Finder control, {
  required Color expected,
}) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_captureKey),
  );
  expect(boundary.debugNeedsPaint, isFalse);

  final rect = tester.getRect(control);
  final sample = Offset(rect.center.dx, rect.top + 6);
  final pixel = await tester.runAsync(() async {
    final image = await boundary.toImage();
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      expect(bytes, isNotNull);
      final x = sample.dx.floor();
      final y = sample.dy.floor();
      expect(x, inInclusiveRange(0, image.width - 1));
      expect(y, inInclusiveRange(0, image.height - 1));
      final offset = (y * image.width + x) * 4;
      return Color.fromARGB(
        bytes!.getUint8(offset + 3),
        bytes.getUint8(offset),
        bytes.getUint8(offset + 1),
        bytes.getUint8(offset + 2),
      );
    } finally {
      image.dispose();
    }
  });
  expect(pixel, isNotNull);
  final distance = <int>[
    (pixel!.r * 255).round() - (expected.r * 255).round(),
    (pixel.g * 255).round() - (expected.g * 255).round(),
    (pixel.b * 255).round() - (expected.b * 255).round(),
  ].map((channel) => channel.abs());
  expect(
    distance,
    everyElement(lessThanOrEqualTo(2)),
    reason: 'Rendered control fill $pixel did not match $expected at $sample.',
  );
}

void _expectNoFloatingCopyFeedback(WidgetTester tester, String prefix) {
  expect(find.byKey(ValueKey('$prefix-copy-feedback')), findsNothing);
  expect(find.byKey(ValueKey('$prefix-copy-feedback-semantics')), findsNothing);
  expect(find.text('已复制账号'), findsNothing);
  expect(find.text('已复制密码'), findsNothing);
  expect(
    find.byWidgetPredicate(
      (widget) => widget.runtimeType.toString() == 'SnackBar',
    ),
    findsNothing,
  );
}

Future<VaultController> _pumpInspectorApp(
  WidgetTester tester,
  Size size,
) async {
  debugDefaultTargetPlatformOverride = TargetPlatform.windows;
  addTearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
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
  return controller;
}

void _expectAllPasswordsPageIdentity(WidgetTester tester) {
  _expectActiveDestination(tester, CipherbookDestinationId.vault);
  _expectShellPage(tester, 1);
  _expectVisibleControl(tester, 'prism-vault-filters');
  const filters = {
    'all': '全部',
    'favorites': '收藏',
    'repeated': '重复',
    'weak': '弱密码',
    'totp': 'TOTP',
    'deleted': '回收',
  };
  for (final entry in filters.entries) {
    final filter = entry.key;
    final label = entry.value;
    final finder = find.byKey(ValueKey('prism-vault-filter-$filter'));
    _expectVisibleControl(tester, 'prism-vault-filter-$filter');
    expect(
      find.descendant(of: finder, matching: find.text(label)),
      findsOneWidget,
    );
  }
  for (final key in [
    'prism-vault-search',
    'prism-vault-sort',
    'prism-vault-list-pane',
    'prism-vault-detail-pane',
    'prism-detail-copy-password',
  ]) {
    _expectVisibleControl(tester, key);
  }
  for (final key in [
    'prism-category-workbench',
    'prism-category-add-primary',
    'prism-category-list-pane',
    'prism-category-password-search',
    'prism-security-metric-repeated',
    'prism-security-metric-weak',
  ]) {
    _expectHiddenControl(tester, key);
  }
}

void _expectCategoriesPageIdentity(
  WidgetTester tester, {
  String? selectedTitle,
}) {
  _expectActiveDestination(tester, CipherbookDestinationId.categories);
  _expectShellPage(tester, 2);
  for (final key in [
    'prism-category-workbench',
    'prism-category-add-primary',
    'prism-category-all-passwords',
    'prism-category-list-pane',
    'prism-category-password-search',
    'prism-category-password-list',
    'prism-category-detail-pane',
    'prism-category-item-details',
  ]) {
    _expectVisibleControl(tester, key);
  }
  expect(
    find.descendant(
      of: find.byKey(const ValueKey('prism-category-add-primary')),
      matching: find.text('新建分类'),
    ),
    findsOneWidget,
  );
  if (selectedTitle != null) {
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('prism-category-detail-title')),
          )
          .data,
      selectedTitle,
    );
  }
  for (final key in [
    'prism-vault-filters',
    'prism-vault-filter-all',
    'prism-vault-search',
    'prism-vault-sort',
    'prism-vault-list-pane',
    'prism-vault-detail-pane',
    'prism-security-metric-repeated',
    'prism-security-metric-weak',
  ]) {
    _expectHiddenControl(tester, key);
  }
}

void _expectActiveDestination(WidgetTester tester, String destination) {
  final shell = find.byType(ResponsiveShell);
  expect(shell, findsOneWidget);
  expect(
    ProviderScope.containerOf(
      tester.element(shell),
    ).read(currentShellDestinationProvider),
    destination,
  );
}

void _expectShellPage(WidgetTester tester, int page) {
  final finder = find.byType(PageView);
  expect(finder, findsOneWidget);
  final pageView = tester.widget<PageView>(finder);
  expect(pageView.controller, isNotNull);
  expect(pageView.controller!.page, closeTo(page.toDouble(), 0.01));
}

void _expectVisibleControl(WidgetTester tester, String key) {
  final finder = find.byKey(ValueKey(key));
  expect(finder, findsOneWidget);
  expect(finder.hitTestable(), findsOneWidget);
}

void _expectHiddenControl(WidgetTester tester, String key) {
  expect(find.byKey(ValueKey(key)).hitTestable(), findsNothing);
}

void _expectDocumentInspector(
  WidgetTester tester,
  String prefix, {
  required bool populated,
  bool hasRelated = true,
}) {
  final surface = find.byKey(_surfaceKey(prefix));
  expect(surface, findsOneWidget);
  expect(tester.widget(surface), isNot(isA<Card>()));
  expect(find.ancestor(of: surface, matching: find.byType(Card)), findsNothing);
  expect(find.byKey(ValueKey('$prefix-document-content')), findsOneWidget);
  expect(find.byKey(ValueKey('$prefix-single-column')), findsNothing);
  expect(find.byKey(ValueKey('$prefix-scroll')), findsOneWidget);
  expect(find.byKey(ValueKey('$prefix-credential-grid')), findsOneWidget);
  expect(find.byKey(ValueKey('$prefix-metadata-strip')), findsOneWidget);
  expect(find.byKey(ValueKey('$prefix-main-column')), findsNothing);
  expect(find.byKey(ValueKey('$prefix-side-column')), findsNothing);
  expect(find.byKey(ValueKey('$prefix-security-section')), findsNothing);
  expect(find.byKey(ValueKey('$prefix-organization-section')), findsNothing);
  expect(find.byKey(ValueKey('$prefix-activity-section')), findsNothing);

  for (final key in ['strength', 'reuse', 'totp', 'updated']) {
    expect(find.byKey(ValueKey('$prefix-metadata-$key')), findsOneWidget);
  }
  expect(find.byKey(ValueKey('$prefix-metadata-category')), findsNothing);

  final surfaceRect = tester.getRect(surface);
  final header = tester.getRect(find.byKey(ValueKey('$prefix-header')));
  expect(header.top, closeTo(surfaceRect.top, 0.5));
  _expectDesktopPaneFill(tester, prefix);
  _expectToolbarFollowsDocument(
    tester,
    prefix,
    hasWebsite: populated,
    hasRelated: hasRelated,
  );
  _expectPinnedScrollbar(tester, prefix);
  _expectHeaderActionsAligned(tester, prefix);
  _expectCredentialGrid(
    tester,
    prefix,
    columns: 2,
    includeOptionalFields: populated,
  );

  final notes = find.byKey(ValueKey('$prefix-notes-section'));
  final scroll = find.byKey(ValueKey('$prefix-scroll'));
  expect(tester.getSize(notes).height, lessThan(tester.getSize(scroll).height));
  final metadataTop = tester
      .getRect(find.byKey(ValueKey('$prefix-metadata-strip')))
      .top;
  expect(tester.getRect(notes).bottom, lessThan(metadataTop));
  if (populated) {
    final noteContent = find.byKey(ValueKey('$prefix-notes-content'));
    expect(noteContent, findsOneWidget);
    expect(tester.getSize(noteContent).height, greaterThan(24));
    expect(find.byKey(ValueKey('$prefix-notes-empty')), findsNothing);
  } else {
    expect(find.byKey(ValueKey('$prefix-notes-empty')), findsOneWidget);
    expect(find.byKey(ValueKey('$prefix-notes-content')), findsNothing);
    expect(tester.getSize(notes).height, lessThan(64));
  }
}

ValueKey<String> _surfaceKey(String prefix) {
  return ValueKey(
    prefix == 'prism-detail'
        ? 'prism-vault-detail-card'
        : 'prism-category-item-details',
  );
}

void _expectCredentialGrid(
  WidgetTester tester,
  String prefix, {
  required int columns,
  bool includeOptionalFields = true,
}) {
  final fields = [
    find.byKey(ValueKey('$prefix-credential-username')),
    find.byKey(ValueKey('$prefix-credential-password')),
    if (includeOptionalFields) ...[
      find.byKey(ValueKey('$prefix-credential-url')),
      find.byKey(ValueKey('$prefix-credential-totp')),
    ],
  ];
  for (final field in fields) {
    expect(field, findsOneWidget);
  }

  if (columns == 1) {
    for (var index = 1; index < fields.length; index++) {
      final previous = tester.getRect(fields[index - 1]);
      final current = tester.getRect(fields[index]);
      expect(current.left, closeTo(previous.left, 0.5));
      expect(current.right, closeTo(previous.right, 0.5));
      expect(current.top, greaterThanOrEqualTo(previous.bottom));
    }
    return;
  }

  for (var index = 0; index < fields.length; index += 2) {
    final left = tester.getRect(fields[index]);
    final right = tester.getRect(fields[index + 1]);
    expect(right.top, closeTo(left.top, 0.5));
    expect(right.height, closeTo(left.height, 0.5));
    expect(right.left, greaterThan(left.right));
  }
}

void _expectSingleColumnInspector(
  WidgetTester tester,
  String prefix, {
  bool hasRelated = true,
}) {
  expect(find.byKey(ValueKey('$prefix-single-column')), findsOneWidget);
  expect(find.byKey(ValueKey('$prefix-document-content')), findsNothing);
  expect(find.byKey(ValueKey('$prefix-main-column')), findsNothing);
  expect(find.byKey(ValueKey('$prefix-side-column')), findsNothing);
  expect(find.byKey(ValueKey('$prefix-scroll')), findsOneWidget);
  expect(find.byKey(ValueKey('$prefix-footer')), findsOneWidget);
  expect(find.byKey(ValueKey('$prefix-metadata-strip')), findsOneWidget);
  _expectHeaderActionsAligned(tester, prefix);
  _expectCredentialGrid(tester, prefix, columns: 1);
  _expectToolbarFollowsDocument(
    tester,
    prefix,
    hasWebsite: true,
    hasRelated: hasRelated,
  );
  _expectPinnedScrollbar(tester, prefix);
}

void _expectDesktopPaneFill(WidgetTester tester, String prefix) {
  final pane = tester.getRect(
    find.byKey(
      ValueKey(
        prefix == 'prism-detail'
            ? 'prism-vault-detail-pane'
            : 'prism-category-detail-pane',
      ),
    ),
  );
  final surface = tester.getRect(
    find.byKey(
      ValueKey(
        prefix == 'prism-detail'
            ? 'prism-vault-detail-card'
            : 'prism-category-item-details',
      ),
    ),
  );
  expect(surface.top - pane.top, closeTo(12, 0.5));
  expect(pane.bottom - surface.bottom, closeTo(20, 0.5));
}

void _expectToolbarFollowsDocument(
  WidgetTester tester,
  String prefix, {
  required bool hasWebsite,
  required bool hasRelated,
}) {
  final wideColumns = find
      .byKey(ValueKey('$prefix-document-content'))
      .evaluate()
      .isNotEmpty;
  final documentKey = ValueKey(
    wideColumns ? '$prefix-document-content' : '$prefix-single-column',
  );
  final documentFinder = find.byKey(documentKey);
  final document = tester.widget<Column>(documentFinder);
  expect(document.mainAxisSize, MainAxisSize.min);
  expect(document.mainAxisAlignment, MainAxisAlignment.start);
  expect(document.children.whereType<Spacer>(), isEmpty);
  expect(document.children.whereType<Flexible>(), isEmpty);

  final scroll = find.byKey(ValueKey('$prefix-scroll'));
  final metadata = find.byKey(ValueKey('$prefix-metadata-strip'));
  final toolbar = find.byKey(ValueKey('$prefix-footer'));
  expect(scroll, findsOneWidget);
  expect(metadata, findsOneWidget);
  expect(toolbar, findsOneWidget);
  expect(find.descendant(of: scroll, matching: toolbar), findsOneWidget);

  _expectQuietMetadata(tester, prefix, documentFinder);
  _expectLightweightToolbar(tester, prefix, hasWebsite: hasWebsite);
  _expectCategoryPlacement(tester, prefix);
  _expectRelatedSection(
    tester,
    prefix,
    hasRelated: hasRelated,
    wideColumns: wideColumns,
  );

  final notes = find.byKey(ValueKey('$prefix-notes-section'));
  expect(tester.getRect(notes).bottom, lessThan(tester.getRect(metadata).top));
  final related = find.byKey(ValueKey('$prefix-related-section'));
  final tail = hasRelated ? related : metadata;
  expect(tester.getRect(tail).bottom, lessThan(tester.getRect(toolbar).top));
  expect(
    tester.getRect(toolbar).top - tester.getRect(tail).bottom,
    closeTo(CipherbookVisualTokens.space20, 0.5),
  );
}

void _expectCategoryPlacement(WidgetTester tester, String prefix) {
  final header = find.byKey(ValueKey('$prefix-header'));
  final metadata = find.byKey(ValueKey('$prefix-metadata-strip'));
  final move = find.byKey(ValueKey('$prefix-move'));
  final category = find.byKey(ValueKey('$prefix-category'));
  expect(find.descendant(of: header, matching: move), findsOneWidget);
  expect(find.descendant(of: metadata, matching: move), findsNothing);
  expect(find.descendant(of: header, matching: category), findsOneWidget);
  expect(tester.widget<Text>(category).data, isNotEmpty);
  expect(tester.getSize(move).height, closeTo(44, 0.5));
  final itemType = find.descendant(of: header, matching: find.text('登录密码'));
  expect(itemType, findsOneWidget);
  expect(
    tester.getCenter(category).dy,
    closeTo(tester.getCenter(itemType).dy, 0.5),
  );
}

void _expectRelatedSection(
  WidgetTester tester,
  String prefix, {
  required bool hasRelated,
  required bool wideColumns,
}) {
  final section = find.byKey(ValueKey('$prefix-related-section'));
  if (!hasRelated) {
    expect(section, findsNothing);
    return;
  }

  expect(section, findsOneWidget);
  expect(
    find.descendant(of: section, matching: find.text('同分类')),
    findsOneWidget,
  );
  expect(
    find.descendant(of: section, matching: find.byType(PressSurface)),
    findsNWidgets(4),
  );
  expect(find.byKey(ValueKey('$prefix-related-$_walletItemId')), findsNothing);

  final rows = [
    for (final id in _walletRelatedItemIds)
      find.byKey(ValueKey('$prefix-related-$id')),
  ];
  for (var index = 0; index < rows.length; index++) {
    expect(rows[index], findsOneWidget);
    expect(
      find.byKey(
        ValueKey('$prefix-related-summary-${_walletRelatedItemIds[index]}'),
      ),
      findsOneWidget,
    );
  }

  final rects = [for (final row in rows) tester.getRect(row)];
  if (wideColumns) {
    expect(rects[0].top, closeTo(rects[1].top, 0.5));
    expect(rects[2].top, closeTo(rects[3].top, 0.5));
    expect(rects[0].top, lessThan(rects[2].top));
    expect(rects[1].left, greaterThan(rects[0].left));
  } else {
    for (var index = 1; index < rects.length; index++) {
      expect(rects[index].top, greaterThanOrEqualTo(rects[index - 1].bottom));
      expect(rects[index].left, closeTo(rects.first.left, 0.5));
    }
  }
}

void _expectQuietMetadata(WidgetTester tester, String prefix, Finder document) {
  final metadata = find.byKey(ValueKey('$prefix-metadata-strip'));
  for (final type in [Container, DecoratedBox, ColoredBox, Card]) {
    expect(
      find.descendant(of: metadata, matching: find.byType(type)),
      findsNothing,
    );
  }
  expect(_hasContainerAncestorBefore(tester, metadata, document), isFalse);
}

bool _hasContainerAncestorBefore(
  WidgetTester tester,
  Finder child,
  Finder boundary,
) {
  final boundaryElement = tester.element(boundary);
  var foundContainer = false;
  var reachedBoundary = false;
  tester.element(child).visitAncestorElements((ancestor) {
    if (identical(ancestor, boundaryElement)) {
      reachedBoundary = true;
      return false;
    }
    if (ancestor.widget is Container ||
        ancestor.widget is DecoratedBox ||
        ancestor.widget is ColoredBox ||
        ancestor.widget is Card) {
      foundContainer = true;
      return false;
    }
    return true;
  });
  expect(reachedBoundary, isTrue);
  return foundContainer;
}

void _expectLightweightToolbar(
  WidgetTester tester,
  String prefix, {
  required bool hasWebsite,
}) {
  final toolbar = find.byKey(ValueKey('$prefix-footer'));
  final rule = find.byKey(ValueKey('$prefix-toolbar-rule'));
  expect(rule, findsOneWidget);
  expect(
    find.descendant(of: toolbar, matching: find.byType(ColoredBox)),
    findsOneWidget,
  );
  for (final type in [Container, DecoratedBox, Card]) {
    expect(
      find.descendant(of: toolbar, matching: find.byType(type)),
      findsNothing,
    );
  }

  final ruleRect = tester.getRect(rule);
  final toolbarRect = tester.getRect(toolbar);
  expect(ruleRect.top, closeTo(toolbarRect.top, 0.5));
  expect(ruleRect.width, closeTo(toolbarRect.width, 0.5));
  expect(ruleRect.height, closeTo(1, 0.5));
  expect(
    tester
        .widget<ColoredBox>(
          find.descendant(of: rule, matching: find.byType(ColoredBox)),
        )
        .color,
    tester.element(toolbar).colorScheme.outlineVariant,
  );

  final shortcutKeys = [
    'copy-username',
    'copy-password',
    if (hasWebsite) 'open-url',
  ];
  for (final key in shortcutKeys) {
    expect(find.byKey(ValueKey('$prefix-shortcut-$key')), findsOneWidget);
  }
  expect(find.byKey(ValueKey('$prefix-shortcut-edit')), findsNothing);
  expect(find.byKey(ValueKey('$prefix-edit')), findsOneWidget);
  expect(
    find.descendant(of: toolbar, matching: find.byType(TextButton)),
    findsNWidgets(shortcutKeys.length),
  );

  final labels = tester
      .widgetList<Text>(
        find.descendant(of: toolbar, matching: find.byType(Text)),
      )
      .map((text) => text.data)
      .whereType<String>()
      .toList();
  expect(labels, ['账号', '密码', if (hasWebsite) '网址']);
}

void _expectPinnedScrollbar(WidgetTester tester, String prefix) {
  final scrollbar = tester.widget<Scrollbar>(
    find.byKey(ValueKey('$prefix-scrollbar')),
  );
  expect(scrollbar.thumbVisibility, isTrue);
}

Future<void> _expectToolbarScrollTail(
  WidgetTester tester,
  String prefix, {
  bool expectScrollable = false,
}) async {
  final scroll = find.byKey(ValueKey('$prefix-scroll'));
  final scrollRect = tester.getRect(scroll);
  expect(scrollRect.height.isFinite, isTrue);
  expect(scrollRect.height, greaterThan(0));
  final scrollable = find.descendant(
    of: scroll,
    matching: find.byType(Scrollable),
  );
  expect(scrollable, findsOneWidget);
  final position = tester.state<ScrollableState>(scrollable).position;
  expect(position.viewportDimension, closeTo(scrollRect.height, 0.5));
  expect(position.maxScrollExtent, greaterThanOrEqualTo(0));
  if (expectScrollable) {
    expect(position.maxScrollExtent, greaterThan(0));
  }
  position.jumpTo(position.maxScrollExtent);
  await tester.pumpAndSettle();

  final toolbar = find.byKey(ValueKey('$prefix-footer'));
  final metadata = find.byKey(ValueKey('$prefix-metadata-strip'));
  expect(
    tester.getRect(metadata).bottom,
    lessThan(tester.getRect(toolbar).top),
  );
  expect(tester.getRect(toolbar).bottom, lessThanOrEqualTo(scrollRect.bottom));
  expect(
    scrollRect.bottom - tester.getRect(toolbar).bottom,
    greaterThanOrEqualTo(CipherbookVisualTokens.space16),
  );
  expect(tester.takeException(), isNull);
}

Future<void> _revealRelatedContext(WidgetTester tester, String prefix) async {
  final section = find.byKey(ValueKey('$prefix-related-section'));
  expect(section, findsOneWidget);
  final scroll = find.byKey(ValueKey('$prefix-scroll'));
  expect(scroll, findsOneWidget);
  final scrollable = find.descendant(
    of: scroll,
    matching: find.byType(Scrollable),
  );
  expect(scrollable, findsOneWidget);
  final position = tester.state<ScrollableState>(scrollable).position;
  position.jumpTo(position.maxScrollExtent);
  await tester.pumpAndSettle();
  expect(section.hitTestable(), findsOneWidget);
}

Future<void> _expectShortWideInspector(
  WidgetTester tester,
  String prefix, {
  bool hasRelated = true,
}) async {
  final document = find.byKey(ValueKey('$prefix-document-content'));
  final singleColumn = find.byKey(ValueKey('$prefix-single-column'));
  final columns = document.evaluate().isNotEmpty ? 2 : 1;
  if (columns == 2) {
    expect(singleColumn, findsNothing);
  } else {
    expect(singleColumn, findsOneWidget);
  }
  expect(find.byKey(ValueKey('$prefix-main-column')), findsNothing);
  expect(find.byKey(ValueKey('$prefix-side-column')), findsNothing);
  expect(find.byKey(ValueKey('$prefix-metadata-strip')), findsOneWidget);
  _expectCredentialGrid(tester, prefix, columns: columns);
  _expectDesktopPaneFill(tester, prefix);
  _expectToolbarFollowsDocument(
    tester,
    prefix,
    hasWebsite: true,
    hasRelated: hasRelated,
  );
  _expectPinnedScrollbar(tester, prefix);
  await _expectToolbarScrollTail(tester, prefix);
}

void _expectNarrowDetail(
  WidgetTester tester,
  String prefix, {
  bool populated = true,
  bool hasRelated = true,
}) {
  expect(find.byKey(ValueKey('$prefix-title')), findsOneWidget);
  expect(find.byKey(ValueKey('$prefix-copy-password')), findsOneWidget);
  expect(find.byKey(ValueKey('$prefix-scroll')), findsOneWidget);
  expect(find.byKey(ValueKey('$prefix-footer')), findsOneWidget);
  expect(find.byKey(ValueKey('$prefix-metadata-strip')), findsOneWidget);
  _expectHeaderActionsAligned(tester, prefix);
  expect(find.byKey(ValueKey('$prefix-single-column')), findsOneWidget);
  expect(find.byKey(ValueKey('$prefix-document-content')), findsNothing);
  _expectToolbarFollowsDocument(
    tester,
    prefix,
    hasWebsite: populated,
    hasRelated: hasRelated,
  );
  expect(
    find.ancestor(
      of: find.byKey(_surfaceKey(prefix)),
      matching: find.byType(Card),
    ),
    findsNothing,
  );
  _expectCredentialGrid(
    tester,
    prefix,
    columns: 1,
    includeOptionalFields: populated,
  );
  final cardKey = prefix == 'prism-detail'
      ? const ValueKey('prism-vault-detail-card')
      : const ValueKey('prism-category-item-details');
  final viewport =
      tester.view.physicalSize.width / tester.view.devicePixelRatio;
  final card = tester.getRect(find.byKey(cardKey));
  expect(card.left, greaterThanOrEqualTo(0));
  expect(card.right, lessThanOrEqualTo(viewport));
  expect(tester.takeException(), isNull);
}

void _expectDetailNavigation(WidgetTester tester, String prefix) {
  final back = find.byKey(
    ValueKey(
      prefix == 'prism-detail'
          ? 'prism-vault-detail-back'
          : 'prism-category-detail-back',
    ),
  );
  expect(back, findsOneWidget);
  expect(
    find.descendant(of: back, matching: find.text('返回列表')),
    findsOneWidget,
  );
  expect(find.text('密码详情'), findsNothing);
  expect(tester.getSize(back).height, greaterThanOrEqualTo(44));
}

void _expectNoAppNavigation(WidgetTester tester) {
  expect(find.byType(NavigationSidebar), findsNothing);
  expect(
    find.byKey(const ValueKey('shell-narrow-navigation-dock')),
    findsNothing,
  );
}

void _expectReadableCredentialValues(WidgetTester tester, String prefix) {
  final username = find.byKey(ValueKey('$prefix-username-value'));
  final url = find.byKey(ValueKey('$prefix-url-value'));
  expect(username, findsOneWidget);
  expect(url, findsOneWidget);
  expect(tester.getSize(username).width, greaterThan(140));
  expect(tester.getSize(url).width, greaterThan(100));
  expect(
    _renderedLineCount(
      tester.renderObject<RenderParagraph>(username),
      tester.widget<Text>(username).data!,
    ),
    1,
  );
  expect(
    _renderedLineCount(
      tester.renderObject<RenderParagraph>(url),
      tester.widget<Text>(url).data!,
    ),
    lessThanOrEqualTo(2),
  );
}

int _renderedLineCount(RenderParagraph paragraph, String text) {
  final boxes = paragraph.getBoxesForSelection(
    TextSelection(baseOffset: 0, extentOffset: text.length),
  );
  return boxes.map((box) => box.top.round()).toSet().length;
}

void _expectSameDetailRect(Rect first, Rect second) {
  expect(second.left, closeTo(first.left, 0.5));
  expect(second.top, closeTo(first.top, 0.5));
  expect(second.width, closeTo(first.width, 0.5));
  expect(second.height, closeTo(first.height, 0.5));
}

void _expectActionTargets(WidgetTester tester, String prefix) {
  for (final action in ['favorite', 'copy-password', 'edit']) {
    final finder = find.byKey(ValueKey('$prefix-$action'));
    expect(finder, findsOneWidget);
    expect(tester.getSize(finder).height, greaterThanOrEqualTo(44));
  }
  final move = find.byKey(ValueKey('$prefix-move'));
  expect(move, findsOneWidget);
  expect(tester.getSize(move).height, greaterThanOrEqualTo(44));
  for (final shortcut in ['copy-username', 'copy-password', 'open-url']) {
    final finder = find.byKey(ValueKey('$prefix-shortcut-$shortcut'));
    expect(finder, findsOneWidget);
    expect(tester.getSize(finder).height, greaterThanOrEqualTo(44));
  }
  expect(find.byKey(ValueKey('$prefix-shortcut-edit')), findsNothing);
}

void _expectHeaderActionsAligned(WidgetTester tester, String prefix) {
  final actions = [
    for (final action in ['favorite', 'copy-password', 'edit'])
      find.byKey(ValueKey('$prefix-$action')),
  ];
  final compactRow = find.byKey(ValueKey('$prefix-header-actions'));
  final expectsCompactRow =
      tester.getSize(find.byKey(ValueKey('$prefix-header'))).width < 600;
  expect(compactRow, expectsCompactRow ? findsOneWidget : findsNothing);
  if (expectsCompactRow) {
    for (final action in actions) {
      final iconButton = tester.widget<IconButton>(
        find.descendant(of: action, matching: find.byType(IconButton)),
      );
      expect(iconButton.tooltip, isNotEmpty);
    }
  }
  final rects = [for (final action in actions) tester.getRect(action)];
  for (final rect in rects) {
    expect(rect.width, greaterThanOrEqualTo(44));
    expect(rect.height, greaterThanOrEqualTo(44));
  }
  for (final rect in rects.skip(1)) {
    expect(rect.top, closeTo(rects.first.top, 0.5));
    expect(rect.bottom, closeTo(rects.first.bottom, 0.5));
  }
}

Future<void> _selectItem(
  WidgetTester tester,
  String itemId, {
  required Type pageType,
}) async {
  final page = find.byType(pageType);
  expect(page, findsOneWidget);
  Finder inPage(Finder finder) => find.descendant(of: page, matching: finder);
  if (pageType == CipherbookVaultPage &&
      inPage(find.byKey(ValueKey(itemId))).evaluate().isNotEmpty) {
    return;
  }
  if (pageType == CipherbookCategoriesPage &&
      (find
              .byKey(ValueKey('prism-category-item-details-$itemId'))
              .evaluate()
              .isNotEmpty ||
          find
              .byKey(ValueKey('prism-category-detail-$itemId'))
              .evaluate()
              .isNotEmpty)) {
    return;
  }
  final title = inPage(find.byKey(ValueKey('prism-password-title-$itemId')));
  final visibleTitle = title.hitTestable();
  if (visibleTitle.evaluate().isNotEmpty) {
    await tester.tap(visibleTitle.first);
    await tester.pumpAndSettle();
    return;
  }
  final vaultEntry = inPage(find.byKey(ValueKey('prism-vault-entry-$itemId')));
  final passwordDrag = inPage(
    find.byKey(ValueKey('prism-password-drag-$itemId')),
  );
  final passwordRow = inPage(
    find.byKey(ValueKey('prism-password-row-$itemId')),
  );
  final candidates = pageType == CipherbookVaultPage
      ? [vaultEntry, passwordDrag, passwordRow]
      : [passwordDrag, passwordRow, vaultEntry];
  final listScope = pageType == CipherbookVaultPage
      ? inPage(find.byKey(const ValueKey('prism-vault-list-pane')))
      : inPage(find.byKey(const ValueKey('prism-category-password-list')));
  final verticalScrollable = find.descendant(
    of: listScope,
    matching: find.byWidgetPredicate(
      (widget) =>
          widget is Scrollable &&
          (widget.axisDirection == AxisDirection.down ||
              widget.axisDirection == AxisDirection.up),
    ),
  );
  if (verticalScrollable.evaluate().isNotEmpty) {
    for (final candidate in candidates) {
      if (candidate.evaluate().isNotEmpty) {
        break;
      }
      await tester.scrollUntilVisible(
        candidate,
        220,
        scrollable: verticalScrollable.first,
      );
      await tester.pumpAndSettle();
      if (candidate.evaluate().isNotEmpty) {
        break;
      }
    }
  }

  Finder? target;
  for (final candidate in candidates) {
    if (candidate.evaluate().isEmpty) {
      continue;
    }
    await tester.ensureVisible(candidate);
    await tester.pumpAndSettle();
    final visible = candidate.hitTestable();
    if (visible.evaluate().isNotEmpty) {
      target = visible.first;
      break;
    }
  }
  expect(target, isNotNull);
  await tester.tap(target!);
  await tester.pumpAndSettle();
}

Future<void> _leaveAllPasswordsDetail(WidgetTester tester) async {
  final back = find.byKey(const ValueKey('prism-vault-detail-back'));
  if (back.evaluate().isEmpty) {
    return;
  }
  await tester.tap(back);
  await tester.pumpAndSettle();
}

Future<void> _leaveCategoryDetail(WidgetTester tester) async {
  final back = find.byKey(const ValueKey('prism-category-detail-back'));
  if (back.evaluate().isEmpty) {
    return;
  }
  await tester.tap(back);
  await tester.pumpAndSettle();
}

Future<void> _showDestination(WidgetTester tester, String destination) async {
  final shell = find.byType(ResponsiveShell);
  expect(shell, findsOneWidget);
  ProviderScope.containerOf(
    tester.element(shell),
  ).read(currentShellDestinationProvider.notifier).go(destination);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pumpAndSettle();
}

Future<void> _setSize(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  await tester.pumpAndSettle();
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pumpAndSettle();
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
          child: const _ScreenshotShell(),
        ),
      ),
    );
  }
}

class _ScreenshotShell extends ConsumerWidget {
  const _ScreenshotShell();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailShellHidden = ref.watch(passwordDetailShellHiddenProvider);
    return ResponsiveShell(
      initialDestinationId: CipherbookDestinationId.dashboard,
      destinations: cipherbookDestinationsOf(context),
      navigationVisible: !detailShellHidden,
    );
  }
}

VaultController _buildController() {
  return VaultController(
    repository: _MemoryVaultRepository(),
    cryptoService: _FastCryptoService(vaultData: _inspectorVaultData()),
    importExportService: _NoopImportExportService(),
    deviceKeyStore: _MemoryDeviceKeyStore(),
    passwordGeneratorService: PasswordGeneratorService(random: Random(7)),
    clipboardService: _MemoryClipboardService(),
  );
}

VaultData _inspectorVaultData() {
  final createdAt = DateTime(2026, 10, 3, 9, 12);
  final updatedAt = DateTime(2026, 11, 14, 18, 42);
  final categories = [
    VaultCategory(
      id: 'inspector-work',
      name: '工作',
      createdAt: createdAt,
      updatedAt: updatedAt,
      sortIndex: 0,
    ),
    VaultCategory(
      id: 'inspector-personal',
      name: '个人',
      createdAt: createdAt,
      updatedAt: updatedAt,
      sortIndex: 1,
    ),
    VaultCategory(
      id: 'inspector-finance',
      name: '财务',
      createdAt: createdAt,
      updatedAt: updatedAt,
      sortIndex: 2,
    ),
  ];
  final items = [
    VaultItem(
      id: _populatedItemId,
      title: 'GitHub',
      username: 'developer@example.test',
      password: 'CorrectHorseBatteryStaple!42',
      url: 'https://github.com/settings/security',
      notes:
          '生产发布账号。仅用于发布流程和紧急回滚。\n\n'
          '轮换周期：90 天。恢复代码保存在离线介质中，不在设备上保留副本。',
      tags: const ['开发', '生产'],
      totpSecret: 'JBSWY3DPEHPK3PXP',
      createdAt: createdAt,
      updatedAt: updatedAt,
      folder: 'inspector-work',
      favorite: true,
    ),
    VaultItem(
      id: 'inspector-cloud',
      title: '云控制台',
      username: 'ops@example.test',
      password: 'CorrectHorseBatteryStaple!42',
      url: 'https://console.example.test',
      notes: '',
      tags: const ['运维'],
      createdAt: createdAt,
      updatedAt: updatedAt.subtract(const Duration(hours: 2)),
      folder: 'inspector-work',
    ),
    VaultItem(
      id: 'inspector-bank',
      title: '储蓄账户',
      username: 'finance@example.test',
      password: 'banking-only-password-84',
      url: 'https://bank.example.test',
      notes:
          '日常收支与自动扣款。\n\n'
          '大额操作使用独立设备确认，恢复信息保存在离线介质中。',
      tags: const ['财务'],
      totpSecret: 'wallet-bank-totp-secret',
      createdAt: createdAt,
      updatedAt: updatedAt.subtract(const Duration(hours: 5)),
      folder: 'inspector-finance',
    ),
    VaultItem(
      id: 'inspector-card',
      title: '家庭信用卡',
      username: 'cards@example.test',
      password: 'wallet-card-password',
      url: 'https://cards.example.test',
      notes: '',
      tags: const ['财务'],
      createdAt: createdAt,
      updatedAt: updatedAt.subtract(const Duration(hours: 6)),
      folder: 'inspector-finance',
    ),
    VaultItem(
      id: 'inspector-broker',
      title: '证券账户',
      username: 'broker@example.test',
      password: 'wallet-broker-password',
      url: 'https://broker.example.test',
      notes: '',
      tags: const ['财务'],
      createdAt: createdAt,
      updatedAt: updatedAt.subtract(const Duration(hours: 7)),
      folder: 'inspector-finance',
    ),
    VaultItem(
      id: 'inspector-insurance',
      title: '保险账户',
      username: 'insurance@example.test',
      password: 'wallet-insurance-password',
      url: 'https://insurance.example.test',
      notes: '',
      tags: const ['财务'],
      createdAt: createdAt,
      updatedAt: updatedAt.subtract(const Duration(hours: 8)),
      folder: 'inspector-finance',
    ),
    VaultItem(
      id: 'inspector-reserve',
      title: '备用储蓄',
      username: 'reserve@example.test',
      password: 'wallet-reserve-password',
      url: 'https://reserve.example.test',
      notes: '',
      tags: const ['财务'],
      createdAt: createdAt,
      updatedAt: updatedAt.subtract(const Duration(hours: 9)),
      folder: 'inspector-finance',
    ),
    VaultItem(
      id: 'inspector-crypto',
      title: '交易平台',
      username: 'trading@example.test',
      password: 'wallet-trading-password',
      url: 'https://trading.example.test',
      notes: '',
      tags: const ['财务'],
      createdAt: createdAt,
      updatedAt: updatedAt.subtract(const Duration(hours: 10)),
      folder: 'inspector-finance',
    ),
    VaultItem(
      id: 'inspector-travel',
      title: '旅行证件',
      username: 'travel@example.test',
      password: 'travel-documents-password-72',
      url: '',
      notes: '',
      tags: const ['个人'],
      createdAt: createdAt,
      updatedAt: updatedAt.subtract(const Duration(days: 2)),
      folder: 'inspector-personal',
    ),
    VaultItem(
      id: _sparseItemId,
      title: '临时入口',
      username: 'temporary',
      password: 'pw',
      url: '',
      notes: '',
      tags: const [],
      createdAt: createdAt,
      updatedAt: updatedAt.subtract(const Duration(days: 7)),
      folder: '',
    ),
  ];
  return VaultData(items: items, categories: categories, updatedAt: updatedAt);
}

class _FastCryptoService extends CryptoService {
  _FastCryptoService({required this.vaultData});

  final VaultData vaultData;

  @override
  Future<EncryptedVaultDocument> createVault({
    required String password,
    VaultData? vaultData,
  }) {
    return super.createVault(password: password, vaultData: this.vaultData);
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
