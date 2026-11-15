import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prism_shell/prism_shell.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';

import '../../models/vault_models.dart';
import '../bridge/vault_controller_provider.dart';
import '../shared/cipherbook_page_scaffold.dart';
import '../shell/cipherbook_navigation.dart';
import '../theme/cipherbook_glyphs.dart';
import '../theme/cipherbook_visual_tokens.dart';
import '../vault/vault_item_editor.dart';
import '../vault/vault_query.dart';
import 'dashboard_metrics.dart';

class CipherbookDashboardPage extends ConsumerWidget {
  const CipherbookDashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(vaultControllerProvider);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final data = controller.vaultData;
        final metrics = DashboardMetrics.fromVaultData(data);
        final syncLabel = controller.lanSyncHost != null
            ? '已开启'
            : controller.lanSyncPeers.isNotEmpty
            ? '${controller.lanSyncPeers.length} 台'
            : '待连接';
        final peerCount = controller.lanSyncPeers.length;
        final addPasswordAction = FilledButton.icon(
          key: const ValueKey('prism-dashboard-add-password'),
          onPressed: controller.busy
              ? null
              : () => unawaited(
                  showCipherbookItemEditor(
                    context: context,
                    controller: controller,
                  ),
                ),
          icon: const GlyphIcon(VaultGlyphs.add),
          label: const Text('新增密码'),
          style: ButtonStyle.from(
            backgroundColor: CipherbookVisualTokens.accent,
            foregroundColor: context.colorScheme.onPrimary,
            padding: const EdgeInsets.symmetric(
              horizontal: CipherbookVisualTokens.space12,
            ),
            minimumSize: const Size(0, CipherbookVisualTokens.controlHeight),
          ),
        );
        final lockAction = IconButton(
          key: const ValueKey('prism-dashboard-lock'),
          onPressed: () {
            unawaited(controller.lock());
          },
          tooltip: '锁定密码库',
          icon: const GlyphIcon(VaultGlyphs.vault),
          style: ButtonStyle.from(
            backgroundColor: CipherbookVisualTokens.surfaceMuted,
            foregroundColor: context.colorScheme.onSurface,
          ),
        );
        return CipherbookPageScaffold(
          body: LayoutBuilder(
            builder: (context, constraints) {
              final padding = CipherbookVisualTokens.pagePadding(
                constraints.maxWidth,
              );
              return ListView(
                padding: padding,
                children: [
                  _DashboardSummary(
                    metrics: metrics,
                    syncLabel: syncLabel,
                    peerCount: peerCount,
                    onOpenVault: () => openVault(context, ref),
                    onOpenSecurity: () {
                      ShellNavigationScope.navigationOf(
                        context,
                      ).select(CipherbookDestinationId.security);
                    },
                    onOpenSync: () {
                      ShellNavigationScope.navigationOf(
                        context,
                      ).select(CipherbookDestinationId.sync);
                    },
                    headerActions: [lockAction],
                  ),
                  const SizedBox(height: CipherbookVisualTokens.space24),
                  _DashboardLowerSection(
                    data: data,
                    metrics: metrics,
                    addPasswordAction: addPasswordAction,
                    onOpenCategories: () {
                      ShellNavigationScope.navigationOf(
                        context,
                      ).select(CipherbookDestinationId.categories);
                    },
                    onOpenTools: () {
                      ShellNavigationScope.navigationOf(
                        context,
                      ).select(CipherbookDestinationId.tools);
                    },
                    onOpenVault: (filter, {categoryId, selectedItemId}) {
                      openVault(
                        context,
                        ref,
                        filter: filter,
                        categoryId: categoryId,
                        selectedItemId: selectedItemId,
                      );
                    },
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

class _DashboardSummary extends StatelessWidget {
  const _DashboardSummary({
    required this.metrics,
    required this.syncLabel,
    required this.peerCount,
    required this.onOpenVault,
    required this.onOpenSecurity,
    required this.onOpenSync,
    this.headerActions = const [],
  });

  final DashboardMetrics metrics;
  final String syncLabel;
  final int peerCount;
  final VoidCallback onOpenVault;
  final VoidCallback onOpenSecurity;
  final VoidCallback onOpenSync;
  final List<Widget> headerActions;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 680;
        final dividerGap = wide
            ? CipherbookVisualTokens.space24
            : CipherbookVisualTokens.space16;
        final vault = _VaultSummaryGroup(
          metrics: metrics,
          onPressed: onOpenVault,
          headerActions: headerActions,
          contentPadding: EdgeInsets.fromLTRB(
            0,
            CipherbookVisualTokens.space8,
            wide ? dividerGap : 0,
            CipherbookVisualTokens.space8,
          ),
        );
        final security = _SecuritySummaryGroup(
          metrics: metrics,
          onPressed: onOpenSecurity,
          contentPadding: EdgeInsets.fromLTRB(
            wide ? dividerGap : 0,
            CipherbookVisualTokens.space8,
            dividerGap,
            CipherbookVisualTokens.space8,
          ),
        );
        final sync = _SyncSummaryGroup(
          label: syncLabel,
          peerCount: peerCount,
          onPressed: onOpenSync,
          contentPadding: EdgeInsets.fromLTRB(
            dividerGap,
            CipherbookVisualTokens.space8,
            0,
            CipherbookVisualTokens.space8,
          ),
        );
        if (wide) {
          return SizedBox(
            height: headerActions.isEmpty ? 94 : 126,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(flex: 2, child: vault),
                const _SummaryVerticalDivider(),
                Expanded(child: security),
                const _SummaryVerticalDivider(),
                Expanded(child: sync),
              ],
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            vault,
            const _SummaryHorizontalDivider(),
            SizedBox(
              height: 96,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: security),
                  const _SummaryVerticalDivider(),
                  Expanded(child: sync),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _VaultSummaryGroup extends StatelessWidget {
  const _VaultSummaryGroup({
    required this.metrics,
    required this.onPressed,
    required this.contentPadding,
    this.headerActions = const [],
  });

  final DashboardMetrics metrics;
  final VoidCallback onPressed;
  final EdgeInsets contentPadding;
  final List<Widget> headerActions;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '${metrics.activeCount}',
              style: AppTextStyle.title2
                  .of(context, emphasized: true)
                  .copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
            ),
            const SizedBox(width: CipherbookVisualTokens.space8),
            Padding(
              padding: const EdgeInsets.only(
                bottom: CipherbookVisualTokens.space4,
              ),
              child: Text(
                '条密码',
                style: AppTextStyle.footnote
                    .of(context)
                    .copyWith(color: colorScheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
        const SizedBox(height: CipherbookVisualTokens.space4),
        Wrap(
          spacing: CipherbookVisualTokens.space16,
          runSpacing: CipherbookVisualTokens.space4,
          children: [
            _InlineStat(label: '收藏', value: metrics.favoriteCount),
            _InlineStat(label: '分类', value: metrics.categoryCount),
            _InlineStat(label: 'TOTP', value: metrics.totpCount),
            Text(
              metrics.lastUpdatedAt == null
                  ? '暂无记录'
                  : '更新 ${_formatDate(metrics.lastUpdatedAt!)}',
              style: AppTextStyle.caption1
                  .of(context)
                  .copyWith(color: colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ],
    );
    final content = Padding(
      padding: contentPadding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 2,
            height: 64,
            decoration: BoxDecoration(
              color: CipherbookVisualTokens.accent,
              borderRadius: BorderRadius.circular(1),
            ),
          ),
          const SizedBox(width: CipherbookVisualTokens.space12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(
                right: headerActions.isEmpty
                    ? 0
                    : CipherbookVisualTokens.controlHeight +
                          CipherbookVisualTokens.space8,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const _SummaryHeader(title: '密码库', actionLabel: ''),
                  const SizedBox(height: CipherbookVisualTokens.space8),
                  details,
                ],
              ),
            ),
          ),
        ],
      ),
    );
    return _DashboardFocusTarget(
      key: const ValueKey('prism-dashboard-focus-summary-vault'),
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          PressRegion(
            key: const ValueKey('prism-dashboard-summary-vault'),
            onTap: onPressed,
            shape: AppShape.all(CipherbookVisualTokens.radiusControl),
            overlay: PressRegion.hoverOverlay,
            child: content,
          ),
          if (headerActions.isNotEmpty)
            Positioned(
              top: CipherbookVisualTokens.space8,
              right: CipherbookVisualTokens.space8,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: headerActions,
              ),
            ),
        ],
      ),
    );
  }
}

class _SecuritySummaryGroup extends StatelessWidget {
  const _SecuritySummaryGroup({
    required this.metrics,
    required this.onPressed,
    required this.contentPadding,
  });

  final DashboardMetrics metrics;
  final VoidCallback onPressed;
  final EdgeInsets contentPadding;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return _DashboardFocusTarget(
      key: const ValueKey('prism-dashboard-focus-summary-security'),
      child: PressRegion(
        key: const ValueKey('prism-dashboard-summary-security'),
        onTap: onPressed,
        shape: AppShape.all(CipherbookVisualTokens.radiusControl),
        overlay: PressRegion.hoverOverlay,
        child: Padding(
          padding: contentPadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const _SummaryHeader(title: '密码检查', actionLabel: '查看'),
              const SizedBox(height: CipherbookVisualTokens.space12),
              Row(
                children: [
                  Expanded(
                    child: _DashboardFigure(
                      value: '${metrics.repeatedGroups.length}',
                      label: '组重复',
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 34,
                    color: colorScheme.outlineVariant,
                  ),
                  const SizedBox(width: CipherbookVisualTokens.space16),
                  Expanded(
                    child: _DashboardFigure(
                      value: '${metrics.weakCount}',
                      label: '条弱密码',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SyncSummaryGroup extends StatelessWidget {
  const _SyncSummaryGroup({
    required this.label,
    required this.peerCount,
    required this.onPressed,
    required this.contentPadding,
  });

  final String label;
  final int peerCount;
  final VoidCallback onPressed;
  final EdgeInsets contentPadding;

  @override
  Widget build(BuildContext context) {
    return _DashboardFocusTarget(
      key: const ValueKey('prism-dashboard-focus-summary-sync'),
      child: PressRegion(
        key: const ValueKey('prism-dashboard-summary-sync'),
        onTap: onPressed,
        shape: AppShape.all(CipherbookVisualTokens.radiusControl),
        overlay: PressRegion.hoverOverlay,
        child: Padding(
          padding: contentPadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const _SummaryHeader(title: '设备同步', actionLabel: '连接'),
              const SizedBox(height: CipherbookVisualTokens.space12),
              Text(
                label,
                key: const ValueKey('prism-dashboard-sync-status'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.listSubtitleStyle,
              ),
              const SizedBox(height: CipherbookVisualTokens.space4),
              Text(
                peerCount == 0 ? '尚未发现其他设备' : '已发现 $peerCount 台设备',
                style: context.listCaptionStyle,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SummaryHeader extends StatelessWidget {
  const _SummaryHeader({required this.title, required this.actionLabel});

  final String title;
  final String actionLabel;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyle.footnote.of(context, emphasized: true),
          ),
        ),
        if (actionLabel.isNotEmpty) ...[
          Text(
            actionLabel,
            style: AppTextStyle.caption1
                .of(context, emphasized: true)
                .copyWith(color: colorScheme.primary),
          ),
          const SizedBox(width: CipherbookVisualTokens.space4),
          GlyphIcon(
            Glyphs.chevronForward,
            size: 14,
            color: colorScheme.primary,
          ),
        ],
      ],
    );
  }
}

class _SummaryHorizontalDivider extends StatelessWidget {
  const _SummaryHorizontalDivider();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: CipherbookVisualTokens.space12),
      child: Divider(height: 1, thickness: 1),
    );
  }
}

class _SummaryVerticalDivider extends StatelessWidget {
  const _SummaryVerticalDivider();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 1,
      child: ColoredBox(color: context.colorScheme.outlineVariant),
    );
  }
}

class _DashboardFigure extends StatelessWidget {
  const _DashboardFigure({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: AppTextStyle.title2
              .of(context, emphasized: true)
              .copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
        ),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyle.caption1
              .of(context)
              .copyWith(color: context.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _InlineStat extends StatelessWidget {
  const _InlineStat({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 6,
      children: [
        Text(
          '$value',
          style: AppTextStyle.subheadline
              .of(context, emphasized: true)
              .copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
        ),
        Text(
          label,
          style: AppTextStyle.footnote
              .of(context)
              .copyWith(color: context.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _MetricSummaryBar extends StatelessWidget {
  const _MetricSummaryBar({required this.metrics, required this.onOpenVault});

  final DashboardMetrics metrics;
  final ValueChanged<VaultListFilter> onOpenVault;

  @override
  Widget build(BuildContext context) {
    final entries = <({String title, String value, VaultListFilter filter})>[
      (
        title: '全部密码',
        value: '${metrics.activeCount}',
        filter: VaultListFilter.all,
      ),
      (
        title: '收藏',
        value: '${metrics.favoriteCount}',
        filter: VaultListFilter.favorites,
      ),
      (
        title: '重复密码',
        value: '${metrics.repeatedGroups.length}',
        filter: VaultListFilter.repeated,
      ),
      (
        title: '弱密码',
        value: '${metrics.weakCount}',
        filter: VaultListFilter.weak,
      ),
      (
        title: 'TOTP',
        value: '${metrics.totpCount}',
        filter: VaultListFilter.totp,
      ),
      (
        title: '回收站',
        value: '${metrics.deletedCount}',
        filter: VaultListFilter.deleted,
      ),
    ];
    final colorScheme = context.colorScheme;
    return SizedBox(
      key: const ValueKey('prism-dashboard-metric-summary'),
      height: CipherbookVisualTokens.dashboardRowHeight,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var index = 0; index < entries.length; index++) ...[
            if (index > 0)
              SizedBox(
                width: 1,
                height: 16,
                child: ColoredBox(color: colorScheme.outlineVariant),
              ),
            Expanded(
              child: _DashboardFocusTarget(
                child: PressRegion(
                  key: ValueKey(
                    'prism-dashboard-metric-${entries[index].filter.name}',
                  ),
                  onTap: () => onOpenVault(entries[index].filter),
                  shape: AppShape.all(CipherbookVisualTokens.radiusControl),
                  overlay: PressRegion.hoverOverlay,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Flexible(
                        child: Text(
                          entries[index].title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyle.caption1
                              .of(context)
                              .copyWith(color: colorScheme.onSurfaceVariant),
                        ),
                      ),
                      const SizedBox(width: CipherbookVisualTokens.space8),
                      Text(
                        entries[index].value,
                        style: AppTextStyle.footnote
                            .of(context, emphasized: true)
                            .copyWith(
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DashboardLowerSection extends StatelessWidget {
  const _DashboardLowerSection({
    required this.data,
    required this.metrics,
    required this.addPasswordAction,
    required this.onOpenCategories,
    required this.onOpenTools,
    required this.onOpenVault,
  });

  final VaultData data;
  final DashboardMetrics metrics;
  final Widget addPasswordAction;
  final VoidCallback onOpenCategories;
  final VoidCallback onOpenTools;
  final void Function(
    VaultListFilter filter, {
    String? categoryId,
    String? selectedItemId,
  })
  onOpenVault;

  @override
  Widget build(BuildContext context) {
    final recent = data.activeItems.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final recentItems = recent.take(6).toList();
    final categories = data.categories.toList()
      ..sort((a, b) => a.sortIndex.compareTo(b.sortIndex));

    return LayoutBuilder(
      builder: (context, constraints) {
        final recentCard = _DashboardListCard(
          title: '最近修改',
          action: addPasswordAction,
          child: recentItems.isEmpty
              ? const _EmptyDashboardText('还没有密码记录')
              : Column(
                  children: _separatedDashboardRows([
                    for (final item in recentItems)
                      _RecentItemRow(
                        item: item,
                        categoryName: data.categoryById(item.folder)?.name,
                        onPressed: () => onOpenVault(
                          VaultListFilter.all,
                          selectedItemId: item.id,
                        ),
                      ),
                  ]),
                ),
        );
        final categoryLimit = metrics.uncategorizedCount > 0 ? 3 : 4;
        final categoryRows = <Widget>[
          for (final category in categories.take(categoryLimit))
            _CategoryCountRow(
              id: category.id,
              name: category.name,
              count: data.activeItems
                  .where((item) => item.folder == category.id)
                  .length,
              onPressed: () => onOpenVault(
                VaultListFilter.category,
                categoryId: category.id,
              ),
            ),
          if (metrics.uncategorizedCount > 0)
            _CategoryCountRow(
              id: '',
              name: '未分类',
              count: metrics.uncategorizedCount,
              onPressed: () =>
                  onOpenVault(VaultListFilter.category, categoryId: ''),
            ),
        ];
        final categoriesCard = _DashboardListCard(
          key: const ValueKey('prism-dashboard-categories-card'),
          title: '分类分布',
          child: categoryRows.isEmpty
              ? const _EmptyDashboardText('还没有分类数据')
              : Column(children: _separatedDashboardRows(categoryRows)),
        );
        final shortcutsCard = _DashboardListCard(
          key: const ValueKey('prism-dashboard-shortcuts-card'),
          title: '快捷入口',
          child: Column(
            children: _separatedDashboardRows([
              _DashboardShortcutRow(title: '管理分类', onPressed: onOpenCategories),
              _DashboardShortcutRow(title: '设置与工具', onPressed: onOpenTools),
            ]),
          ),
        );
        final metricSummary = _MetricSummaryBar(
          metrics: metrics,
          onOpenVault: (filter) => onOpenVault(filter),
        );
        if (constraints.maxWidth < 780) {
          final showMetricSummary = constraints.maxWidth >= 600;
          return Column(
            children: [
              KeyedSubtree(
                key: const ValueKey('prism-dashboard-recent-card'),
                child: recentCard,
              ),
              if (showMetricSummary) ...[
                const SizedBox(height: CipherbookVisualTokens.space24),
                metricSummary,
              ],
              const SizedBox(height: CipherbookVisualTokens.space24),
              categoriesCard,
              const SizedBox(height: CipherbookVisualTokens.space24),
              shortcutsCard,
            ],
          );
        }
        return Column(
          children: [
            SizedBox(
              height: CipherbookVisualTokens.dashboardCardLaneHeight,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    flex: 2,
                    child: KeyedSubtree(
                      key: const ValueKey('prism-dashboard-recent-card'),
                      child: recentCard,
                    ),
                  ),
                  const SizedBox(width: CipherbookVisualTokens.space24),
                  Expanded(
                    child: Column(
                      children: [
                        Expanded(flex: 2, child: categoriesCard),
                        const SizedBox(height: CipherbookVisualTokens.space24),
                        Expanded(child: shortcutsCard),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: CipherbookVisualTokens.space24),
            metricSummary,
          ],
        );
      },
    );
  }
}

class _DashboardListCard extends StatelessWidget {
  const _DashboardListCard({
    super.key,
    required this.title,
    required this.child,
    this.action,
  });

  final String title;
  final Widget child;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Card(
      inert: true,
      radius: CipherbookVisualTokens.radiusPanel,
      shape: AppShape.all(
        CipherbookVisualTokens.radiusPanel,
      ).copyWith(side: CipherbookVisualTokens.borderSide),
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              CipherbookVisualTokens.space16,
              CipherbookVisualTokens.space12,
              CipherbookVisualTokens.space16,
              CipherbookVisualTokens.space8,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      title,
                      style: AppTextStyle.headline.of(
                        context,
                        emphasized: true,
                      ),
                    ),
                  ),
                ),
                if (action case final action?) ...[
                  const SizedBox(width: CipherbookVisualTokens.space8),
                  action,
                ],
              ],
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class _RecentItemRow extends StatelessWidget {
  const _RecentItemRow({
    required this.item,
    required this.categoryName,
    required this.onPressed,
  });

  final VaultItem item;
  final String? categoryName;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final subtitle = [
      if (item.username.trim().isNotEmpty) item.username,
      if ((categoryName ?? '').trim().isNotEmpty) categoryName!,
    ].join(' · ');
    return _DashboardFocusTarget(
      key: ValueKey('prism-dashboard-focus-recent-${item.id}'),
      child: _dashboardRowPressRegion(
        key: ValueKey('prism-dashboard-recent-item-${item.id}'),
        onTap: onPressed,
        child: Row(
          children: [
            _EntryInitial(title: item.title),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    item.title.isEmpty ? '未命名' : item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyle.subheadline.of(
                      context,
                      emphasized: true,
                    ),
                  ),
                  if (subtitle.isNotEmpty)
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyle.footnote
                          .of(context)
                          .copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                ],
              ),
            ),
            GlyphIcon(
              Glyphs.chevronForward,
              size: 16,
              color: colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

class _DashboardShortcutRow extends StatelessWidget {
  const _DashboardShortcutRow({required this.title, required this.onPressed});

  final String title;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return _DashboardFocusTarget(
      child: _dashboardRowPressRegion(
        key: ValueKey('prism-dashboard-shortcut-$title'),
        onTap: onPressed,
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyle.footnote.of(context, emphasized: true),
              ),
            ),
            GlyphIcon(
              Glyphs.chevronForward,
              size: 14,
              color: colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryCountRow extends StatelessWidget {
  const _CategoryCountRow({
    required this.id,
    required this.name,
    required this.count,
    required this.onPressed,
  });

  final String id;
  final String name;
  final int count;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return _DashboardFocusTarget(
      child: _dashboardRowPressRegion(
        key: ValueKey(
          'prism-dashboard-category-${id.isEmpty ? 'uncategorized' : id}',
        ),
        onTap: onPressed,
        child: Row(
          children: [
            Expanded(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyle.subheadline.of(context),
              ),
            ),
            Text(
              '$count',
              style: AppTextStyle.footnote
                  .of(context, emphasized: true)
                  .copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

Widget _dashboardRowPressRegion({
  Key? key,
  required VoidCallback onTap,
  required Widget child,
}) {
  return PressRegion(
    key: key,
    onTap: onTap,
    shape: AppShape.all(CipherbookVisualTokens.radiusControl),
    overlay: PressRegion.hoverOverlay,
    child: SizedBox(
      width: double.infinity,
      height: CipherbookVisualTokens.dashboardRowHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: CipherbookVisualTokens.space16,
        ),
        child: child,
      ),
    ),
  );
}

class _DashboardFocusTarget extends StatelessWidget {
  const _DashboardFocusTarget({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return FocusRing(
      shape: AppShape.all(CipherbookVisualTokens.radiusControl),
      child: child,
    );
  }
}

class _EntryInitial extends StatelessWidget {
  const _EntryInitial({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final normalized = title.trim();
    return Container(
      width: 34,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: AppRadius.sm,
      ),
      child: Text(
        normalized.isEmpty ? '?' : normalized.characters.first.toUpperCase(),
        style: AppTextStyle.footnote
            .of(context, emphasized: true)
            .copyWith(color: colorScheme.onSurfaceVariant),
      ),
    );
  }
}

class _EmptyDashboardText extends StatelessWidget {
  const _EmptyDashboardText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Center(
        child: Text(
          text,
          style: AppTextStyle.subheadline
              .of(context)
              .copyWith(color: context.colorScheme.onSurfaceVariant),
        ),
      ),
    );
  }
}

List<Widget> _separatedDashboardRows(List<Widget> rows) {
  return [
    for (var index = 0; index < rows.length; index++) ...[
      if (index > 0) const Divider(height: 1, thickness: 1),
      rows[index],
    ],
  ];
}

String _formatDate(DateTime value) {
  final local = value.toLocal();
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$month-$day $hour:$minute';
}
