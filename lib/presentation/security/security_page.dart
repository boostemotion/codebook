import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';

import '../bridge/vault_controller_provider.dart';
import '../dashboard/dashboard_metrics.dart';
import '../shared/cipherbook_page_scaffold.dart';
import '../shell/cipherbook_navigation.dart';
import '../theme/cipherbook_visual_tokens.dart';
import '../vault/vault_query.dart';

const _securityRowGap = 8.0;
const _securityRowPadding = EdgeInsets.symmetric(horizontal: 14, vertical: 11);
const _securityMetricCardHeight = 120.0;
const _securityMetricTitleSlot = 18.0;
const _securityMetricValueSlot = 30.0;
const _securityMetricDetailSlot = 18.0;

class CipherbookSecurityPage extends ConsumerWidget {
  const CipherbookSecurityPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(vaultControllerProvider);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final metrics = DashboardMetrics.fromVaultData(controller.vaultData);
        return CipherbookPageScaffold(
          body: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 760;
              return ListView(
                padding: EdgeInsets.fromLTRB(
                  CipherbookVisualTokens.space16,
                  compact
                      ? CipherbookVisualTokens.space12
                      : CipherbookVisualTokens.space16,
                  CipherbookVisualTokens.space16,
                  CipherbookVisualTokens.space32,
                ),
                children: [
                  if (compact) ...[
                    const _SecurityPageHeader(),
                    const SizedBox(height: CipherbookVisualTokens.space24),
                  ],
                  _SecuritySummary(
                    repeatedGroups: metrics.repeatedGroups.length,
                    repeatedAccounts: metrics.repeatedAccountCount,
                    weakCount: metrics.weakCount,
                    onOpenRepeated: () => openVault(
                      context,
                      ref,
                      filter: VaultListFilter.repeated,
                    ),
                    onOpenWeak: () =>
                        openVault(context, ref, filter: VaultListFilter.weak),
                  ),
                  const SizedBox(height: CipherbookVisualTokens.space8),
                  Card(
                    inert: true,
                    shape: AppShape.all(
                      CipherbookVisualTokens.radiusPanel,
                    ).copyWith(side: CipherbookVisualTokens.borderSide),
                    padding: const EdgeInsets.all(
                      CipherbookVisualTokens.space16,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '重复密码',
                          style: AppTextStyle.headline.of(
                            context,
                            emphasized: true,
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (metrics.repeatedGroups.isEmpty)
                          const _SecurityEmptyRow('没有发现重复密码')
                        else
                          for (
                            var index = 0;
                            index < metrics.repeatedGroups.length;
                            index++
                          )
                            Padding(
                              padding: const EdgeInsets.only(
                                bottom: _securityRowGap,
                              ),
                              child: _RepeatedPasswordRow(
                                key: ValueKey('prism-repeated-row-$index'),
                                groupNumber: index + 1,
                                titles: metrics.repeatedGroups[index].items
                                    .map(
                                      (item) => item.title.isEmpty
                                          ? '未命名'
                                          : item.title,
                                    )
                                    .toList(),
                                onPressed: () => openVault(
                                  context,
                                  ref,
                                  filter: VaultListFilter.repeated,
                                ),
                              ),
                            ),
                      ],
                    ),
                  ),
                  const SizedBox(height: CipherbookVisualTokens.space8),
                  Card(
                    inert: true,
                    shape: AppShape.all(
                      CipherbookVisualTokens.radiusPanel,
                    ).copyWith(side: CipherbookVisualTokens.borderSide),
                    padding: const EdgeInsets.all(
                      CipherbookVisualTokens.space16,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '基础弱密码',
                          style: AppTextStyle.headline.of(
                            context,
                            emphasized: true,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '空密码、少于 8 位或纯数字',
                          style: AppTextStyle.footnote
                              .of(context)
                              .copyWith(
                                color: context.colorScheme.onSurfaceVariant,
                              ),
                        ),
                        const SizedBox(height: 12),
                        if (metrics.weakItems.isEmpty)
                          const _SecurityEmptyRow('没有发现符合基础规则的弱密码')
                        else
                          for (final item in metrics.weakItems.take(8))
                            Padding(
                              padding: const EdgeInsets.only(
                                bottom: _securityRowGap,
                              ),
                              child: _WeakPasswordRow(
                                key: ValueKey('prism-weak-row-${item.id}'),
                                title: item.title.isEmpty ? '未命名' : item.title,
                                username: item.username,
                                onPressed: () => openVault(
                                  context,
                                  ref,
                                  filter: VaultListFilter.weak,
                                ),
                              ),
                            ),
                      ],
                    ),
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

class _SecurityPageHeader extends StatelessWidget {
  const _SecurityPageHeader();

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(
            key: const ValueKey('prism-security-page-title'),
            '密码检查',
            style: AppTextStyle.subheadline.of(context, emphasized: true),
          ),
        ),
        const SizedBox(height: CipherbookVisualTokens.space12),
        Text(
          key: const ValueKey('prism-security-scope-label'),
          '当前范围',
          style: AppTextStyle.caption1
              .of(context)
              .copyWith(
                fontSize: 12,
                height: 16 / 12,
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(height: CipherbookVisualTokens.space4),
        Text(
          key: const ValueKey('prism-security-scope-title'),
          '全部密码',
          style: AppTextStyle.custom(
            context,
            size: 20,
            leading: 26,
            weight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _SecuritySummary extends StatelessWidget {
  const _SecuritySummary({
    required this.repeatedGroups,
    required this.repeatedAccounts,
    required this.weakCount,
    required this.onOpenRepeated,
    required this.onOpenWeak,
  });

  final int repeatedGroups;
  final int repeatedAccounts;
  final int weakCount;
  final VoidCallback onOpenRepeated;
  final VoidCallback onOpenWeak;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cards = [
          _SecurityMetricCard(
            key: const ValueKey('prism-security-metric-repeated'),
            title: '重复密码',
            value: '$repeatedGroups 组',
            detail: '$repeatedAccounts 个账号',
            onPressed: onOpenRepeated,
          ),
          _SecurityMetricCard(
            key: const ValueKey('prism-security-metric-weak'),
            title: '基础弱密码',
            value: '$weakCount',
            detail: '条弱密码',
            onPressed: onOpenWeak,
          ),
        ];
        if (constraints.maxWidth < 620) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              cards.first,
              const SizedBox(height: CipherbookVisualTokens.space8),
              cards.last,
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: cards.first),
            const SizedBox(width: CipherbookVisualTokens.space8),
            Expanded(child: cards.last),
          ],
        );
      },
    );
  }
}

class _SecurityMetricCard extends StatelessWidget {
  const _SecurityMetricCard({
    super.key,
    required this.title,
    required this.value,
    required this.detail,
    required this.onPressed,
  });

  final String title;
  final String value;
  final String detail;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _securityMetricCardHeight,
      child: Card(
        onPressed: onPressed,
        shape: AppShape.all(
          CipherbookVisualTokens.radiusPanel,
        ).copyWith(side: CipherbookVisualTokens.borderSide),
        padding: const EdgeInsets.all(CipherbookVisualTokens.space16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: _securityMetricTitleSlot,
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyle.footnote
                      .of(context)
                      .copyWith(color: context.colorScheme.onSurfaceVariant),
                ),
              ),
            ),
            const Spacer(),
            SizedBox(
              height: _securityMetricValueSlot,
              child: Align(
                alignment: AlignmentDirectional.bottomStart,
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyle.title2
                      .of(context, emphasized: true)
                      .copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                ),
              ),
            ),
            SizedBox(
              height: _securityMetricDetailSlot,
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyle.footnote
                      .of(context)
                      .copyWith(color: context.colorScheme.onSurfaceVariant),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RepeatedPasswordRow extends StatelessWidget {
  const _RepeatedPasswordRow({
    super.key,
    required this.groupNumber,
    required this.titles,
    required this.onPressed,
  });

  final int groupNumber;
  final List<String> titles;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Card(
      onPressed: onPressed,
      shape: AppShape.all(
        CipherbookVisualTokens.radiusControl,
      ).copyWith(side: CipherbookVisualTokens.borderSide),
      padding: _securityRowPadding,
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: context.colorScheme.errorContainer,
              border: Border.all(color: context.colorScheme.error),
              borderRadius: CipherbookVisualTokens.controlRadius,
            ),
            child: Text(
              '$groupNumber',
              style: AppTextStyle.footnote
                  .of(context, emphasized: true)
                  .copyWith(color: context.colorScheme.onErrorContainer),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              titles.join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          GlyphIcon(
            Glyphs.chevronForward,
            size: 16,
            color: context.colorScheme.onSurfaceVariant,
          ),
        ],
      ),
    );
  }
}

class _WeakPasswordRow extends StatelessWidget {
  const _WeakPasswordRow({
    super.key,
    required this.title,
    required this.username,
    required this.onPressed,
  });

  final String title;
  final String username;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Card(
      onPressed: onPressed,
      shape: AppShape.all(
        CipherbookVisualTokens.radiusControl,
      ).copyWith(side: CipherbookVisualTokens.borderSide),
      padding: _securityRowPadding,
      child: Row(
        children: [
          Container(
            width: 2,
            height: 32,
            decoration: BoxDecoration(
              color: context.colorScheme.error,
              borderRadius: BorderRadius.circular(1),
            ),
          ),
          const SizedBox(width: CipherbookVisualTokens.space12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title),
                if (username.trim().isNotEmpty)
                  Text(
                    username,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyle.footnote
                        .of(context)
                        .copyWith(color: context.colorScheme.onSurfaceVariant),
                  ),
              ],
            ),
          ),
          GlyphIcon(
            Glyphs.chevronForward,
            size: 16,
            color: context.colorScheme.onSurfaceVariant,
          ),
        ],
      ),
    );
  }
}

class _SecurityEmptyRow extends StatelessWidget {
  const _SecurityEmptyRow(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: Text(
          text,
          style: AppTextStyle.footnote
              .of(context)
              .copyWith(color: context.colorScheme.onSurfaceVariant),
        ),
      ),
    );
  }
}
