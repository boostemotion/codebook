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
import '../shared/sort_picker.dart';
import '../theme/cipherbook_glyphs.dart';
import '../theme/cipherbook_visual_tokens.dart';
import '../vault/vault_item_editor.dart';
import '../vault/vault_sort.dart';
import 'category_item_details_dialog.dart';
import 'category_item_details_inspector.dart';
import 'category_workbench.dart';
import 'category_workbench_tokens.dart';

class CipherbookCategoriesPage extends ConsumerStatefulWidget {
  const CipherbookCategoriesPage({super.key});

  @override
  ConsumerState<CipherbookCategoriesPage> createState() =>
      _CipherbookCategoriesPageState();
}

class _CipherbookCategoriesPageState
    extends ConsumerState<CipherbookCategoriesPage> {
  late final TextEditingController _searchController;
  String? _selectedCategoryId;
  String? _selectedItemId;
  String _searchQuery = '';
  String? _draggingItemId;
  String? _dropFeedback;
  Timer? _feedbackTimer;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
  }

  @override
  void dispose() {
    _feedbackTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(vaultControllerProvider);
    final sortPreferences = ref.watch(vaultSortProvider);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final data = controller.vaultData;
        final metrics = DashboardMetrics.fromVaultData(data);
        final categories = data.categories.toList();
        final items = data.activeItems.toList();
        sortVaultItems(items, sortPreferences.categoryPasswords);
        final categoryCounts = {
          for (final category in categories)
            category.id: items
                .where((item) => item.folder == category.id)
                .length,
        };
        sortVaultCategories(
          categories,
          sortPreferences.categories,
          categoryCounts,
        );
        final categoryNames = {
          for (final category in categories) category.id: category.name,
        };
        final selectedCategoryId =
            _selectedCategoryId == null ||
                _selectedCategoryId!.isEmpty ||
                categoryNames.containsKey(_selectedCategoryId)
            ? _selectedCategoryId
            : null;
        final categoryItems = switch (selectedCategoryId) {
          null => items,
          '' =>
            items
                .where(
                  (item) =>
                      item.folder.isEmpty ||
                      !categoryNames.containsKey(item.folder),
                )
                .toList(),
          final categoryId =>
            items.where((item) => item.folder == categoryId).toList(),
        };
        final normalizedSearch = _searchQuery.trim().toLowerCase();
        final visibleItems = normalizedSearch.isEmpty
            ? categoryItems
            : categoryItems
                  .where((item) => _itemMatchesSearch(item, normalizedSearch))
                  .toList();
        final title = switch (selectedCategoryId) {
          null => '全部密码',
          '' => '未分类',
          final categoryId => categoryNames[categoryId] ?? '分类',
        };
        final selectedItem =
            visibleItems
                .where((item) => item.id == _selectedItemId)
                .firstOrNull ??
            visibleItems.firstOrNull;
        final emptyCountLabel = normalizedSearch.isNotEmpty
            ? '${visibleItems.length} 条结果'
            : '${categoryItems.length} 条';
        final emptyMessage = normalizedSearch.isNotEmpty
            ? '无搜索结果'
            : selectedCategoryId == null
            ? '密码库为空'
            : selectedCategoryId.isEmpty
            ? '暂无未分类密码'
            : '分类为空';
        final emptyHint = normalizedSearch.isNotEmpty
            ? '调整搜索关键词后再试'
            : selectedCategoryId == null
            ? '密码会按分类显示在这里'
            : selectedCategoryId.isEmpty
            ? '未归类的密码会显示在这里'
            : '可将密码拖入此分类';
        final detailsPane = selectedItem == null
            ? CategoryItemDetailsEmpty(
                title: title,
                countLabel: emptyCountLabel,
                message: emptyMessage,
                hint: emptyHint,
              )
            : CategoryItemDetailsInspector(
                key: ValueKey('prism-category-item-details-${selectedItem.id}'),
                controller: controller,
                item: selectedItem,
                onSelectItem: _selectItem,
                onEdit: () => unawaited(_editItem(controller, selectedItem)),
              );
        final createCategoryAction = FilledButton.icon(
          key: const ValueKey('prism-category-add-primary'),
          onPressed: controller.busy
              ? null
              : () => unawaited(_createCategory(controller)),
          icon: const GlyphIcon(VaultGlyphs.add),
          label: const Text('新建分类'),
          style: ButtonStyle.from(
            backgroundColor: CipherbookVisualTokens.accent,
            foregroundColor: context.colorScheme.onPrimary,
            padding: const EdgeInsets.symmetric(
              horizontal: CipherbookVisualTokens.space12,
            ),
            minimumSize: const Size(0, CipherbookVisualTokens.controlHeight),
          ),
        );
        final categoryMenuAction = IconButton(
          key: const ValueKey('prism-category-action-menu'),
          onPressed: controller.busy
              ? null
              : () => unawaited(
                  _showCategoryManagementMenu(
                    controller,
                    categories,
                    selectedCategoryId,
                  ),
                ),
          tooltip: '分类管理',
          icon: const GlyphIcon(Glyphs.more),
          iconSize: 20,
          style: ButtonStyle.from(
            backgroundColor: CipherbookVisualTokens.surfaceMuted,
            foregroundColor: context.colorScheme.onSurface,
          ),
        );
        final actions = <Widget>[
          createCategoryAction,
          const SizedBox(width: CipherbookVisualTokens.space8),
          categoryMenuAction,
        ];
        return CipherbookPageScaffold(
          body: CategoryWorkbench(
            key: const ValueKey('prism-category-workbench'),
            categories: categories,
            categoryCounts: categoryCounts,
            uncategorizedCount: metrics.uncategorizedCount,
            selectedCategoryId: selectedCategoryId,
            title: title,
            items: visibleItems,
            totalCount: items.length,
            categoryNames: categoryNames,
            busy: controller.busy,
            searching: normalizedSearch.isNotEmpty,
            showingAll: selectedCategoryId == null,
            selectedItemId: selectedItem?.id,
            detailsPane: detailsPane,
            categorySortLabel: sortPreferences.categories.label,
            passwordSortLabel: sortPreferences.categoryPasswords.label,
            searchController: _searchController,
            dragging: _draggingItemId != null,
            dropFeedback: _dropFeedback,
            inlineActions: actions,
            onSearchChanged: _setSearchQuery,
            onClearSearch: _clearSearch,
            onCategorySort: () => unawaited(_chooseCategorySort()),
            onPasswordSort: () => unawaited(_chooseCategoryPasswordSort()),
            onAllSelected: _selectAllPasswords,
            onCategorySelected: _selectCategory,
            onUncategorizedSelected: _selectUncategorized,
            onItemSelected: _selectItem,
            onItemDetails: (item) =>
                unawaited(_showItemDetails(controller, item)),
            onItemEdit: (item) => unawaited(_editItem(controller, item)),
            onAssign: (item, categoryId, categoryName) => _assignItem(
              controller: controller,
              item: item,
              categoryId: categoryId,
              categoryName: categoryName,
            ),
            onDragStarted: _startDragging,
            onDragEnded: _stopDragging,
          ),
        );
      },
    );
  }

  void _selectAllPasswords() {
    setState(() {
      _selectedCategoryId = null;
    });
  }

  void _selectCategory(String categoryId) {
    setState(() {
      _selectedCategoryId = categoryId;
    });
  }

  void _selectUncategorized() {
    setState(() {
      _selectedCategoryId = '';
    });
  }

  void _selectItem(VaultItem item) {
    setState(() {
      _selectedItemId = item.id;
    });
  }

  void _setSearchQuery(String query) {
    setState(() {
      _searchQuery = query;
    });
  }

  void _clearSearch() {
    _searchController.clear();
    _setSearchQuery('');
  }

  void _startDragging() {
    if (_draggingItemId != null) {
      return;
    }
    setState(() {
      _draggingItemId = 'active';
      _dropFeedback = null;
    });
  }

  void _stopDragging() {
    if (_draggingItemId == null) {
      return;
    }
    setState(() {
      _draggingItemId = null;
    });
  }

  Future<void> _assignItem({
    required VaultController controller,
    required VaultItem item,
    required String? categoryId,
    required String? categoryName,
  }) async {
    final result = await controller.assignItemToCategory(
      itemId: item.id,
      categoryId: categoryId,
    );
    if (!mounted) {
      return;
    }
    if (!result.succeeded) {
      await _showFailure(result);
      return;
    }

    _feedbackTimer?.cancel();
    setState(() {
      _draggingItemId = null;
      _dropFeedback = categoryId == null || categoryId.isEmpty
          ? '已移动到未分类'
          : '已移动到“${categoryName ?? '分类'}”';
    });
    _feedbackTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted || _dropFeedback == null) {
        return;
      }
      setState(() {
        _dropFeedback = null;
      });
    });
  }

  Future<void> _chooseCategorySort() async {
    final selected = ref.read(vaultSortProvider).categories;
    final choice = await showSortPicker<VaultCategorySort>(
      context: context,
      title: '分类排序',
      selected: selected,
      choices: [
        for (final sort in VaultCategorySort.values)
          SortChoice(
            value: sort,
            label: sort.label,
            key: ValueKey('prism-category-order-${sort.name}'),
          ),
      ],
    );
    if (choice != null && mounted) {
      ref.read(vaultSortProvider.notifier).setCategories(choice);
    }
  }

  Future<void> _chooseCategoryPasswordSort() async {
    final selected = ref.read(vaultSortProvider).categoryPasswords;
    final choice = await showSortPicker<VaultItemSort>(
      context: context,
      title: '密码排序',
      selected: selected,
      choices: [
        for (final sort in VaultItemSort.values)
          SortChoice(
            value: sort,
            label: sort.label,
            key: ValueKey('prism-category-password-sort-${sort.name}'),
          ),
      ],
    );
    if (choice != null && mounted) {
      ref.read(vaultSortProvider.notifier).setCategoryPasswords(choice);
    }
  }

  Future<void> _showItemDetails(
    VaultController controller,
    VaultItem item,
  ) async {
    ref.read(passwordDetailShellHiddenProvider.notifier).setHidden(true);
    try {
      await showCategoryItemDetails(
        context: context,
        controller: controller,
        item: item,
        onSelected: _selectItem,
        onEdit: (selected) => unawaited(_editItem(controller, selected)),
      );
    } finally {
      if (mounted) {
        ref.read(passwordDetailShellHiddenProvider.notifier).setHidden(false);
      }
    }
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

  Future<void> _createCategory(VaultController controller) async {
    final name = await _promptCategoryName(title: '新建分类');
    if (name == null || !mounted) {
      return;
    }
    final result = await controller.addCategory(name.trim());
    await _showFailure(result);
  }

  Future<void> _showCategoryManagementMenu(
    VaultController controller,
    List<VaultCategory> categories,
    String? selectedCategoryId,
  ) async {
    VaultCategory? selectedCategory;
    if (selectedCategoryId != null && selectedCategoryId.isNotEmpty) {
      for (final category in categories) {
        if (category.id == selectedCategoryId) {
          selectedCategory = category;
          break;
        }
      }
    }
    final action = await showFloatingDialog<_CategoryManagementAction>(
      context: context,
      child: Builder(
        builder: (dialogContext) {
          return AlertDialog(
            key: const ValueKey('prism-category-management-menu'),
            title: '分类管理',
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('取消'),
              ),
            ],
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _CategoryManagementMenuRow(
                  actionKey: const ValueKey('prism-category-menu-add'),
                  label: '新建分类',
                  enabled: !controller.busy,
                  onPressed: () => Navigator.of(
                    dialogContext,
                  ).pop(_CategoryManagementAction.add),
                ),
                _CategoryManagementMenuRow(
                  actionKey: const ValueKey('prism-category-menu-rename'),
                  label: '重命名分类',
                  enabled: !controller.busy && selectedCategory != null,
                  onPressed: () => Navigator.of(
                    dialogContext,
                  ).pop(_CategoryManagementAction.rename),
                ),
                _CategoryManagementMenuRow(
                  actionKey: const ValueKey('prism-category-menu-delete'),
                  label: '删除分类',
                  enabled: !controller.busy && selectedCategory != null,
                  onPressed: () => Navigator.of(
                    dialogContext,
                  ).pop(_CategoryManagementAction.delete),
                ),
              ],
            ),
          );
        },
      ),
    );
    if (!mounted || action == null) {
      return;
    }
    switch (action) {
      case _CategoryManagementAction.add:
        await _createCategory(controller);
        return;
      case _CategoryManagementAction.rename:
      case _CategoryManagementAction.delete:
        final category = selectedCategory;
        if (category != null) {
          await _showCategoryActions(controller, category);
        }
        return;
    }
  }

  Future<void> _showCategoryActions(
    VaultController controller,
    VaultCategory category,
  ) async {
    final itemCount = controller.vaultData.activeItems
        .where((item) => item.folder == category.id)
        .length;
    final action = await showFloatingDialog<_CategoryAction>(
      context: context,
      child: Builder(
        builder: (dialogContext) {
          return AlertDialog(
            key: const ValueKey('prism-category-actions'),
            title: '分类详情',
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  category.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyle.subheadline.of(
                    dialogContext,
                    emphasized: true,
                  ),
                ),
                const SizedBox(height: CategoryWorkbenchTokens.space4),
                Text(
                  '$itemCount 条密码',
                  style: AppTextStyle.footnote
                      .of(dialogContext)
                      .copyWith(
                        color: dialogContext.colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: CategoryWorkbenchTokens.space12),
                SizedBox(
                  width: double.infinity,
                  child: TextButton.icon(
                    key: ValueKey('prism-category-rename-${category.id}'),
                    onPressed: () =>
                        Navigator.of(dialogContext).pop(_CategoryAction.rename),
                    icon: const GlyphIcon(VaultGlyphs.edit),
                    label: const Text('重命名'),
                  ),
                ),
                SizedBox(
                  width: double.infinity,
                  child: TextButton.icon(
                    key: ValueKey('prism-category-delete-${category.id}'),
                    onPressed: () =>
                        Navigator.of(dialogContext).pop(_CategoryAction.delete),
                    icon: GlyphIcon(
                      VaultGlyphs.delete,
                      color: dialogContext.colorScheme.error,
                    ),
                    label: Text(
                      '删除',
                      style: TextStyle(color: dialogContext.colorScheme.error),
                    ),
                  ),
                ),
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: const Text('关闭'),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
    if (!mounted || action == null) {
      return;
    }

    switch (action) {
      case _CategoryAction.rename:
        final name = await _promptCategoryName(
          title: '重命名分类',
          initialName: category.name,
        );
        if (name == null || !mounted) {
          return;
        }
        final result = await controller.renameCategory(
          categoryId: category.id,
          name: name.trim(),
        );
        await _showFailure(result);
        return;
      case _CategoryAction.delete:
        final confirmed = await showFloatingDialog<bool>(
          context: context,
          child: Builder(
            builder: (dialogContext) {
              return AlertDialog(
                title: '删除“${category.name}”？',
                destructive: true,
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(false),
                    child: const Text('取消'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(true),
                    child: const Text('删除'),
                  ),
                ],
                child: Text(
                  itemCount == 0
                      ? '这个分类没有密码，删除后无法恢复。'
                      : '$itemCount 条密码会进入未分类，密码不会被删除。',
                ),
              );
            },
          ),
        );
        if (confirmed != true || !mounted) {
          return;
        }
        final result = await controller.deleteCategory(category.id);
        await _showFailure(result);
        return;
    }
  }

  Future<String?> _promptCategoryName({
    required String title,
    String initialName = '',
  }) {
    return showFloatingDialog<String>(
      context: context,
      child: InputDialog(
        title: title,
        value: initialName,
        labelText: '分类名称',
        selectAll: true,
        maxLength: 40,
        keyboardType: TextInputType.text,
        validator: (value) {
          if (value == null || value.trim().isEmpty) {
            return '请输入分类名称';
          }
          return null;
        },
      ),
    );
  }

  Future<void> _showFailure(VaultOperationResult result) async {
    final error = result.error;
    if (error == null || !mounted) {
      return;
    }
    await showFloatingDialog<void>(
      context: context,
      child: Builder(
        builder: (dialogContext) {
          return AlertDialog(
            title: '操作失败',
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('关闭'),
              ),
            ],
            child: Text(error.toString()),
          );
        },
      ),
    );
  }
}

enum _CategoryAction { rename, delete }

enum _CategoryManagementAction { add, rename, delete }

class _CategoryManagementMenuRow extends StatelessWidget {
  const _CategoryManagementMenuRow({
    required this.actionKey,
    required this.label,
    required this.enabled,
    required this.onPressed,
  });

  final Key actionKey;
  final String label;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return SizedBox(
      height: 44,
      child: PressSurface(
        key: actionKey,
        fill: Colors.transparent,
        shape: AppShape.sm,
        foreground: enabled
            ? colorScheme.onSurface
            : colorScheme.onSurface.withValues(alpha: 0.38),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        minimum: const BoxConstraints(minHeight: 44),
        tapTarget: Size.zero,
        onPressed: enabled ? onPressed : null,
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          child: Text(
            label,
            style: AppTextStyle.footnote.of(context, emphasized: enabled),
          ),
        ),
      ),
    );
  }
}

bool _itemMatchesSearch(VaultItem item, String query) {
  return item.title.toLowerCase().contains(query) ||
      item.username.toLowerCase().contains(query) ||
      item.url.toLowerCase().contains(query) ||
      item.notes.toLowerCase().contains(query) ||
      item.tags.any((tag) => tag.toLowerCase().contains(query));
}
