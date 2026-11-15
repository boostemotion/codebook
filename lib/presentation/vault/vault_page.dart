import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';

import '../../models/vault_models.dart';
import '../../state/vault_controller.dart';
import '../bridge/vault_controller_provider.dart';
import '../dashboard/dashboard_metrics.dart';
import '../shell/cipherbook_shell_chrome.dart';
import '../shared/cipherbook_page_scaffold.dart';
import '../shared/password_detail_navigation.dart';
import '../shared/password_inspector.dart';
import '../shared/password_list_row.dart';
import '../shared/sort_picker.dart';
import '../theme/cipherbook_glyphs.dart';
import '../theme/cipherbook_visual_tokens.dart';
import 'vault_item_editor.dart';
import 'vault_query.dart';
import 'vault_sort.dart';

class CipherbookVaultPage extends ConsumerStatefulWidget {
  const CipherbookVaultPage({super.key});

  @override
  ConsumerState<CipherbookVaultPage> createState() =>
      _CipherbookVaultPageState();
}

class _CipherbookVaultPageState extends ConsumerState<CipherbookVaultPage> {
  late final TextEditingController _searchController;
  String? _selectedItemId;
  bool _mobileDetailOpen = false;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(
      text: ref.read(vaultQueryProvider).search,
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(vaultControllerProvider);
    final query = ref.watch(vaultQueryProvider);
    final sortPreferences = ref.watch(vaultSortProvider);
    ref.listen<VaultQuery>(vaultQueryProvider, (previous, next) {
      if (_searchController.text != next.search) {
        _searchController.value = TextEditingValue(
          text: next.search,
          selection: TextSelection.collapsed(offset: next.search.length),
        );
      }
      if (previous?.selectedItemId != next.selectedItemId &&
          next.selectedItemId != null) {
        setState(() {
          _selectedItemId = next.selectedItemId;
          _mobileDetailOpen = true;
        });
        ref
            .read(passwordDetailShellHiddenProvider.notifier)
            .setHidden(CipherbookDetailLayout.usesListDetail(context));
      } else if (previous?.filter != next.filter ||
          previous?.categoryId != next.categoryId) {
        setState(() {
          _selectedItemId = null;
          _mobileDetailOpen = false;
        });
        ref.read(passwordDetailShellHiddenProvider.notifier).setHidden(false);
      }
    });

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final data = controller.vaultData;
        final metrics = DashboardMetrics.fromVaultData(data);
        final repeatedIds = {
          for (final group in metrics.repeatedGroups)
            for (final item in group.items) item.id,
        };
        final weakIds = metrics.weakItems.map((item) => item.id).toSet();
        final items = filterVaultItems(
          data,
          query,
          repeatedItemIds: repeatedIds,
          weakItemIds: weakIds,
          sort: sortPreferences.allPasswords,
        );
        final selectedItem = _selectedItem(items);
        final addPasswordAction = IconButton(
          key: const ValueKey('prism-vault-add-password'),
          onPressed: controller.busy
              ? null
              : () => unawaited(
                  showCipherbookItemEditor(
                    context: context,
                    controller: controller,
                    initialCategoryId: query.categoryId,
                  ),
                ),
          tooltip: '新增密码',
          icon: const GlyphIcon(VaultGlyphs.add),
          style: ButtonStyle.from(
            backgroundColor: CipherbookVisualTokens.accent,
            foregroundColor: context.colorScheme.onPrimary,
          ),
        );
        return CipherbookPageScaffold(
          body: LayoutBuilder(
            builder: (context, _) {
              final wide = !CipherbookDetailLayout.usesListDetail(context);
              if (!wide && _mobileDetailOpen && selectedItem != null) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    PasswordDetailNavigation(
                      backButtonKey: const ValueKey('prism-vault-detail-back'),
                      onBack: () {
                        setState(() {
                          _mobileDetailOpen = false;
                        });
                        ref
                            .read(passwordDetailShellHiddenProvider.notifier)
                            .setHidden(false);
                      },
                    ),
                    Expanded(
                      child: PasswordDetailFrame(
                        child: _VaultItemDetailPanel(
                          key: ValueKey(selectedItem.id),
                          controller: controller,
                          item: selectedItem,
                          onEdit: () =>
                              unawaited(_editItem(controller, selectedItem)),
                          onSelected: (item) =>
                              _selectItem(item, openMobileDetail: true),
                        ),
                      ),
                    ),
                  ],
                );
              }

              final listPanel = _VaultListPanel(
                controller: controller,
                query: query,
                items: items,
                sortLabel: sortPreferences.allPasswords.labelFor(
                  deleted: query.filter == VaultListFilter.deleted,
                ),
                selectedItemId: selectedItem?.id,
                searchController: _searchController,
                addAction: addPasswordAction,
                onSearchChanged: (value) {
                  ref.read(vaultQueryProvider.notifier).setSearch(value);
                },
                onFilterChanged: (filter) {
                  ref
                      .read(vaultQueryProvider.notifier)
                      .setFilter(
                        filter,
                        categoryId: filter == VaultListFilter.category
                            ? query.categoryId
                            : null,
                      );
                },
                onSort: () => unawaited(_chooseAllPasswordsSort(query.filter)),
                onSelected: (item) =>
                    _selectItem(item, openMobileDetail: !wide),
              );
              if (!wide) {
                return listPanel;
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(width: 460, child: listPanel),
                  Container(
                    width: 1,
                    color: context.colorScheme.outlineVariant,
                  ),
                  Expanded(
                    key: const ValueKey('prism-vault-detail-pane'),
                    child: selectedItem == null
                        ? const _VaultDetailEmptyState()
                        : _VaultInspectorFrame(
                            child: _VaultItemDetailPanel(
                              key: ValueKey(selectedItem.id),
                              controller: controller,
                              item: selectedItem,
                              onEdit: () => unawaited(
                                _editItem(controller, selectedItem),
                              ),
                              onSelected: (item) =>
                                  _selectItem(item, openMobileDetail: false),
                            ),
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

  VaultItem? _selectedItem(List<VaultItem> items) {
    if (items.isEmpty) {
      return null;
    }
    final id = _selectedItemId;
    if (id != null) {
      for (final item in items) {
        if (item.id == id) {
          return item;
        }
      }
      return null;
    }
    return items.first;
  }

  void _selectItem(VaultItem item, {required bool openMobileDetail}) {
    setState(() {
      _selectedItemId = item.id;
      _mobileDetailOpen = openMobileDetail;
    });
    ref
        .read(passwordDetailShellHiddenProvider.notifier)
        .setHidden(openMobileDetail);
  }

  Future<void> _editItem(VaultController controller, VaultItem item) async {
    final saved = await showCipherbookItemEditor(
      context: context,
      controller: controller,
      item: item,
    );
    if (saved && mounted) {
      setState(() {
        _selectedItemId = item.id;
      });
    }
  }

  Future<void> _chooseAllPasswordsSort(VaultListFilter filter) async {
    final selected = ref.read(vaultSortProvider).allPasswords;
    final choice = await showSortPicker<VaultItemSort>(
      context: context,
      title: '密码排序',
      selected: selected,
      choices: [
        for (final sort in VaultItemSort.values)
          SortChoice(
            value: sort,
            label: sort.labelFor(deleted: filter == VaultListFilter.deleted),
            key: ValueKey('prism-vault-sort-${sort.name}'),
          ),
      ],
    );
    if (choice != null && mounted) {
      ref.read(vaultSortProvider.notifier).setAllPasswords(choice);
    }
  }
}

class _VaultListPanel extends StatelessWidget {
  const _VaultListPanel({
    required this.controller,
    required this.query,
    required this.items,
    required this.sortLabel,
    required this.selectedItemId,
    required this.searchController,
    required this.addAction,
    required this.onSearchChanged,
    required this.onFilterChanged,
    required this.onSort,
    required this.onSelected,
  });

  final VaultController controller;
  final VaultQuery query;
  final List<VaultItem> items;
  final String sortLabel;
  final String? selectedItemId;
  final TextEditingController searchController;
  final Widget? addAction;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<VaultListFilter> onFilterChanged;
  final VoidCallback onSort;
  final ValueChanged<VaultItem> onSelected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final filters = <(VaultListFilter, String)>[
      (VaultListFilter.all, '全部'),
      (VaultListFilter.favorites, '收藏'),
      (VaultListFilter.repeated, '重复'),
      (VaultListFilter.weak, '弱密码'),
      (VaultListFilter.totp, 'TOTP'),
      (VaultListFilter.deleted, '回收'),
      if (query.filter == VaultListFilter.category)
        (VaultListFilter.category, '分类'),
    ];
    return Padding(
      key: const ValueKey('prism-vault-list-pane'),
      padding: const EdgeInsets.fromLTRB(
        CipherbookVisualTokens.space16,
        CipherbookVisualTokens.space12,
        CipherbookVisualTokens.space16,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _VaultFilterBar(
            key: const ValueKey('prism-vault-filters'),
            filters: filters,
            selected: query.filter,
            onSelected: onFilterChanged,
          ),
          const SizedBox(height: CipherbookVisualTokens.space8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('prism-vault-search'),
                  controller: searchController,
                  onChanged: onSearchChanged,
                  style: AppTextStyle.subheadline.of(context),
                  decoration: InputDecoration(
                    hintText: '搜索标题、账号、网址或备注',
                    prefixIcon: const GlyphIcon(Glyphs.search),
                    isDense: true,
                    filled: true,
                    fillColor: CipherbookVisualTokens.surface,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: CipherbookVisualTokens.space12,
                      vertical: CipherbookVisualTokens.space12,
                    ),
                    border: AppInputBorder(
                      borderRadius: CipherbookVisualTokens.controlRadius,
                      borderSide: CipherbookVisualTokens.borderSide,
                    ),
                    enabledBorder: AppInputBorder(
                      borderRadius: CipherbookVisualTokens.controlRadius,
                      borderSide: CipherbookVisualTokens.strongBorderSide,
                    ),
                    focusedBorder: AppInputBorder(
                      borderRadius: CipherbookVisualTokens.controlRadius,
                      borderSide: CipherbookVisualTokens.accentBorderSide,
                    ),
                  ),
                ),
              ),
              if (addAction case final action?) ...[
                const SizedBox(width: CipherbookVisualTokens.space8),
                action,
              ],
            ],
          ),
          const SizedBox(height: CipherbookVisualTokens.space8),
          Row(
            children: [
              Text(
                '${items.length} 条',
                style: AppTextStyle.footnote
                    .of(context)
                    .copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
              ),
              const Spacer(),
              TextButton.icon(
                key: const ValueKey('prism-vault-sort'),
                onPressed: onSort,
                icon: const GlyphIcon(Glyphs.sort),
                label: Text(sortLabel),
                style: ButtonStyle.from(
                  foregroundColor: colorScheme.onSurfaceVariant,
                  minimumSize: const Size(
                    0,
                    CipherbookVisualTokens.controlHeight,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: CipherbookVisualTokens.space8,
                  ),
                  tapTargetSize: TapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
          const SizedBox(height: CipherbookVisualTokens.space4),
          Expanded(
            child: items.isEmpty
                ? _VaultListEmptyState(
                    searching: query.search.trim().isNotEmpty,
                  )
                : ScrollConfiguration(
                    behavior: const ScrollBehavior(),
                    child: ListView.separated(
                      itemCount: items.length,
                      padding: const EdgeInsets.only(bottom: 20),
                      separatorBuilder: (_, __) => const SizedBox(
                        height: CipherbookPasswordRowMetrics.rowGap,
                      ),
                      itemBuilder: (context, index) {
                        final item = items[index];
                        final categoryName = controller.vaultData
                            .categoryById(item.folder)
                            ?.name;
                        return _VaultEntryCard(
                          key: ValueKey('prism-vault-entry-${item.id}'),
                          item: item,
                          categoryName: categoryName,
                          selected: item.id == selectedItemId,
                          onPressed: () => onSelected(item),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _VaultFilterBar extends StatelessWidget {
  const _VaultFilterBar({
    super.key,
    required this.filters,
    required this.selected,
    required this.onSelected,
  });

  final List<(VaultListFilter, String)> filters;
  final VaultListFilter selected;
  final ValueChanged<VaultListFilter> onSelected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final compact = ViewScope.sizeOf(context).width < 760;
    final height = compact
        ? CipherbookVisualTokens.mobileControlHeight
        : CipherbookVisualTokens.controlHeight;
    final width = compact ? 52.0 : 64.0;
    final gap = compact
        ? const SizedBox(width: 6)
        : const SizedBox(width: CipherbookVisualTokens.space8);
    return SizedBox(
      height: height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: filters.length,
        separatorBuilder: (_, _) => gap,
        itemBuilder: (context, index) {
          final (filter, label) = filters[index];
          final active = selected == filter;
          return SizedBox(
            width: width,
            child: PressSurface(
              key: ValueKey('prism-vault-filter-${filter.name}'),
              fill: active
                  ? CipherbookVisualTokens.accent
                  : CipherbookVisualTokens.surfaceMuted,
              shape: AppShape.full,
              side: active
                  ? BorderSide.none
                  : CipherbookVisualTokens.borderSide,
              foreground: active
                  ? colorScheme.onPrimary
                  : colorScheme.onSurface,
              padding: const EdgeInsets.symmetric(
                horizontal: CipherbookVisualTokens.space4,
              ),
              minimum: BoxConstraints(minHeight: height),
              tapTarget: Size.zero,
              selected: active,
              onPressed: () => onSelected(filter),
              child: Center(
                child: Text(
                  label,
                  maxLines: 1,
                  style: AppTextStyle.footnote.of(context, emphasized: active),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _VaultEntryCard extends StatelessWidget {
  const _VaultEntryCard({
    super.key,
    required this.item,
    required this.categoryName,
    required this.selected,
    required this.onPressed,
  });

  final VaultItem item;
  final String? categoryName;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return CipherbookPasswordRow(
      item: item,
      categoryName: categoryName,
      onPressed: onPressed,
      onTrailingPressed: onPressed,
      selected: selected,
    );
  }
}

class _VaultInspectorFrame extends StatelessWidget {
  const _VaultInspectorFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        CipherbookVisualTokens.space20,
        CipherbookVisualTokens.space12,
        CipherbookVisualTokens.space20,
        CipherbookVisualTokens.space20,
      ),
      child: Align(
        alignment: MediaQuery.sizeOf(context).width >= 1200
            ? Alignment.center
            : Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1000),
          child: child,
        ),
      ),
    );
  }
}

class _VaultItemDetailPanel extends StatelessWidget {
  const _VaultItemDetailPanel({
    super.key,
    required this.controller,
    required this.item,
    required this.onEdit,
    required this.onSelected,
  });

  final VaultController controller;
  final VaultItem item;
  final VoidCallback? onEdit;
  final ValueChanged<VaultItem> onSelected;

  @override
  Widget build(BuildContext context) {
    return PasswordInspector(
      controller: controller,
      item: item,
      cardKey: const ValueKey('prism-vault-detail-card'),
      keyPrefix: 'prism-detail',
      onEdit: onEdit,
      onSelectItem: onSelected,
    );
  }
}

class _VaultDetailEmptyState extends StatelessWidget {
  const _VaultDetailEmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        '选择一条密码查看详情',
        style: AppTextStyle.subheadline
            .of(context)
            .copyWith(color: context.colorScheme.onSurfaceVariant),
      ),
    );
  }
}

class _VaultListEmptyState extends StatelessWidget {
  const _VaultListEmptyState({required this.searching});

  final bool searching;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(CipherbookVisualTokens.space24),
        child: Text(
          searching ? '没有匹配的密码' : '当前筛选下没有密码',
          textAlign: TextAlign.center,
          style: AppTextStyle.subheadline
              .of(context, emphasized: true)
              .copyWith(color: context.colorScheme.onSurfaceVariant),
        ),
      ),
    );
  }
}
