import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';

import '../../models/vault_models.dart';
import '../shared/password_list_row.dart';
import '../theme/cipherbook_visual_tokens.dart';
import 'category_workbench_tokens.dart';

class _DoubleTapActivator extends StatefulWidget {
  const _DoubleTapActivator({required this.onDoubleTap, required this.child});

  final VoidCallback onDoubleTap;
  final Widget child;

  @override
  State<_DoubleTapActivator> createState() => _DoubleTapActivatorState();
}

class _DoubleTapActivatorState extends State<_DoubleTapActivator> {
  static const _maxDelay = Duration(milliseconds: 360);
  static const _maxDistance = 24.0;

  Duration? _lastTapAt;
  Offset? _lastTapPosition;
  bool _activationPending = false;

  void _handlePointerDown(PointerDownEvent event) {
    final now = event.timeStamp;
    final lastTapAt = _lastTapAt;
    final lastTapPosition = _lastTapPosition;
    _activationPending =
        lastTapAt != null &&
        now - lastTapAt <= _maxDelay &&
        lastTapPosition != null &&
        (event.position - lastTapPosition).distance <= _maxDistance;
    _lastTapAt = now;
    _lastTapPosition = event.position;
  }

  void _handlePointerUp(PointerUpEvent event) {
    if (!_activationPending) {
      return;
    }
    _activationPending = false;
    _lastTapAt = null;
    _lastTapPosition = null;
    widget.onDoubleTap();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _handlePointerDown,
      onPointerUp: _handlePointerUp,
      child: widget.child,
    );
  }
}

class _SixDotDragHandle extends StatelessWidget {
  const _SixDotDragHandle({super.key, required this.color, this.size = 18});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(size: Size.square(size), painter: _SixDotPainter(color));
  }
}

class _SixDotPainter extends CustomPainter {
  const _SixDotPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final radius = size.shortestSide * 0.07;
    for (final x in const [0.34, 0.66]) {
      for (final y in const [0.28, 0.5, 0.72]) {
        canvas.drawCircle(
          Offset(size.width * x, size.height * y),
          radius,
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_SixDotPainter oldDelegate) => oldDelegate.color != color;
}

typedef CategoryAssignCallback =
    Future<void> Function(
      VaultItem item,
      String? categoryId,
      String? categoryName,
    );

bool _wrapIntermediateSearchActions(BuildContext context) {
  final width = MediaQuery.sizeOf(context).width;
  return width >= 430 && width < 600;
}

class CategoryWorkbench extends StatelessWidget {
  const CategoryWorkbench({
    super.key,
    required this.categories,
    required this.categoryCounts,
    required this.uncategorizedCount,
    required this.selectedCategoryId,
    required this.title,
    required this.items,
    required this.totalCount,
    required this.categoryNames,
    required this.busy,
    required this.searching,
    required this.showingAll,
    required this.selectedItemId,
    required this.detailsPane,
    required this.categorySortLabel,
    required this.passwordSortLabel,
    required this.searchController,
    required this.dragging,
    required this.dropFeedback,
    this.inlineActions = const [],
    required this.onSearchChanged,
    required this.onClearSearch,
    required this.onCategorySort,
    required this.onPasswordSort,
    required this.onAllSelected,
    required this.onCategorySelected,
    required this.onUncategorizedSelected,
    required this.onItemSelected,
    required this.onItemDetails,
    required this.onItemEdit,
    required this.onAssign,
    required this.onDragStarted,
    required this.onDragEnded,
  });

  final List<VaultCategory> categories;
  final Map<String, int> categoryCounts;
  final int uncategorizedCount;
  final String? selectedCategoryId;
  final String title;
  final List<VaultItem> items;
  final int totalCount;
  final Map<String, String> categoryNames;
  final bool busy;
  final bool searching;
  final bool showingAll;
  final String? selectedItemId;
  final Widget detailsPane;
  final String categorySortLabel;
  final String passwordSortLabel;
  final TextEditingController searchController;
  final bool dragging;
  final String? dropFeedback;
  final List<Widget> inlineActions;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onClearSearch;
  final VoidCallback onCategorySort;
  final VoidCallback onPasswordSort;
  final VoidCallback onAllSelected;
  final ValueChanged<String> onCategorySelected;
  final VoidCallback onUncategorizedSelected;
  final ValueChanged<VaultItem> onItemSelected;
  final ValueChanged<VaultItem> onItemDetails;
  final ValueChanged<VaultItem> onItemEdit;
  final CategoryAssignCallback onAssign;
  final VoidCallback onDragStarted;
  final VoidCallback onDragEnded;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final useRail =
            constraints.maxWidth >= CategoryWorkbenchTokens.railBreakpoint;
        if (!useRail) {
          return _NarrowCategoryWorkbench(
            categories: categories,
            categoryCounts: categoryCounts,
            uncategorizedCount: uncategorizedCount,
            selectedCategoryId: selectedCategoryId,
            title: title,
            items: items,
            totalCount: totalCount,
            categoryNames: categoryNames,
            busy: busy,
            searching: searching,
            showingAll: showingAll,
            selectedItemId: selectedItemId,
            categorySortLabel: categorySortLabel,
            passwordSortLabel: passwordSortLabel,
            searchController: searchController,
            dropFeedback: dropFeedback,
            inlineActions: inlineActions,
            onSearchChanged: onSearchChanged,
            onClearSearch: onClearSearch,
            onCategorySort: onCategorySort,
            onPasswordSort: onPasswordSort,
            onAllSelected: onAllSelected,
            onCategorySelected: onCategorySelected,
            onUncategorizedSelected: onUncategorizedSelected,
            onItemSelected: onItemDetails,
            onAssign: onAssign,
            onDragStarted: onDragStarted,
            onDragEnded: onDragEnded,
          );
        }

        final colorScheme = context.colorScheme;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              key: const ValueKey('prism-category-list-pane'),
              width: 460,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _CategoryRail(
                    categories: categories,
                    categoryCounts: categoryCounts,
                    uncategorizedCount: uncategorizedCount,
                    selectedCategoryId: selectedCategoryId,
                    totalCount: totalCount,
                    busy: busy,
                    onAllSelected: onAllSelected,
                    onCategorySelected: onCategorySelected,
                    onUncategorizedSelected: onUncategorizedSelected,
                    onAssign: onAssign,
                  ),
                  Expanded(
                    child: _PasswordsWorkspace(
                      items: items,
                      totalCount: totalCount,
                      uncategorizedCount: uncategorizedCount,
                      categoryNames: categoryNames,
                      busy: busy,
                      searching: searching,
                      showingAll: showingAll,
                      selectedItemId: selectedItemId,
                      searchController: searchController,
                      dragging: dragging,
                      dropFeedback: dropFeedback,
                      directDragEnabled: true,
                      inlineActions: inlineActions,
                      categorySortLabel: categorySortLabel,
                      passwordSortLabel: passwordSortLabel,
                      onSearchChanged: onSearchChanged,
                      onClearSearch: onClearSearch,
                      onCategorySort: onCategorySort,
                      onPasswordSort: onPasswordSort,
                      onAllSelected: onAllSelected,
                      onItemSelected: onItemSelected,
                      onItemEdit: onItemEdit,
                      onDragStarted: onDragStarted,
                      onDragEnded: onDragEnded,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              width: 1,
              child: ColoredBox(color: colorScheme.outlineVariant),
            ),
            Expanded(
              key: const ValueKey('prism-category-detail-pane'),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  CategoryWorkbenchTokens.space20,
                  CategoryWorkbenchTokens.space12,
                  CategoryWorkbenchTokens.space20,
                  CategoryWorkbenchTokens.space20,
                ),
                child: Align(
                  alignment: MediaQuery.sizeOf(context).width >= 1200
                      ? Alignment.center
                      : Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1000),
                    child: detailsPane,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _CategoryRail extends StatelessWidget {
  const _CategoryRail({
    required this.categories,
    required this.categoryCounts,
    required this.uncategorizedCount,
    required this.selectedCategoryId,
    required this.totalCount,
    required this.busy,
    required this.onAllSelected,
    required this.onCategorySelected,
    required this.onUncategorizedSelected,
    required this.onAssign,
  });

  final List<VaultCategory> categories;
  final Map<String, int> categoryCounts;
  final int uncategorizedCount;
  final String? selectedCategoryId;
  final int totalCount;
  final bool busy;
  final VoidCallback onAllSelected;
  final ValueChanged<String> onCategorySelected;
  final VoidCallback onUncategorizedSelected;
  final CategoryAssignCallback onAssign;

  @override
  Widget build(BuildContext context) {
    final tabs = <Widget>[
      for (var index = 0; index < categories.length + 2; index++)
        if (index == 0)
          _CompactCategoryTab(
            key: const ValueKey('prism-category-all-passwords'),
            label: '全部密码',
            count: totalCount,
            selected: selectedCategoryId == null,
            enabled: !busy,
            onPressed: onAllSelected,
          )
        else if (index == categories.length + 1)
          _CompactCategoryTab(
            key: const ValueKey('prism-category-drop-uncategorized'),
            label: '未分类',
            count: uncategorizedCount,
            selected: selectedCategoryId == '',
            enabled: !busy,
            onPressed: onUncategorizedSelected,
            onWillAccept: (item) => item.folder.isNotEmpty,
            onDrop: (item) => unawaited(onAssign(item, null, '未分类')),
          )
        else
          _CompactCategoryTab(
            key: ValueKey('prism-category-drop-${categories[index - 1].id}'),
            label: categories[index - 1].name,
            count: categoryCounts[categories[index - 1].id] ?? 0,
            selected: selectedCategoryId == categories[index - 1].id,
            enabled: !busy,
            onPressed: () => onCategorySelected(categories[index - 1].id),
            onWillAccept: (item) => item.folder != categories[index - 1].id,
            onDrop: (item) => unawaited(
              onAssign(
                item,
                categories[index - 1].id,
                categories[index - 1].name,
              ),
            ),
          ),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        CategoryWorkbenchTokens.space16,
        CategoryWorkbenchTokens.space12,
        CategoryWorkbenchTokens.space16,
        0,
      ),
      child: Wrap(
        key: const ValueKey('prism-category-rail'),
        spacing: CategoryWorkbenchTokens.space8,
        runSpacing: CategoryWorkbenchTokens.space8,
        children: tabs,
      ),
    );
  }
}

class _NarrowCategoryWorkbench extends StatelessWidget {
  const _NarrowCategoryWorkbench({
    required this.categories,
    required this.categoryCounts,
    required this.uncategorizedCount,
    required this.selectedCategoryId,
    required this.title,
    required this.items,
    required this.totalCount,
    required this.categoryNames,
    required this.busy,
    required this.searching,
    required this.showingAll,
    required this.selectedItemId,
    required this.categorySortLabel,
    required this.passwordSortLabel,
    required this.searchController,
    required this.dropFeedback,
    required this.inlineActions,
    required this.onSearchChanged,
    required this.onClearSearch,
    required this.onCategorySort,
    required this.onPasswordSort,
    required this.onAllSelected,
    required this.onCategorySelected,
    required this.onUncategorizedSelected,
    required this.onItemSelected,
    required this.onAssign,
    required this.onDragStarted,
    required this.onDragEnded,
  });

  final List<VaultCategory> categories;
  final Map<String, int> categoryCounts;
  final int uncategorizedCount;
  final String? selectedCategoryId;
  final String title;
  final List<VaultItem> items;
  final int totalCount;
  final Map<String, String> categoryNames;
  final bool busy;
  final bool searching;
  final bool showingAll;
  final String? selectedItemId;
  final String categorySortLabel;
  final String passwordSortLabel;
  final TextEditingController searchController;
  final String? dropFeedback;
  final List<Widget> inlineActions;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onClearSearch;
  final VoidCallback onCategorySort;
  final VoidCallback onPasswordSort;
  final VoidCallback onAllSelected;
  final ValueChanged<String> onCategorySelected;
  final VoidCallback onUncategorizedSelected;
  final ValueChanged<VaultItem> onItemSelected;
  final CategoryAssignCallback onAssign;
  final VoidCallback onDragStarted;
  final VoidCallback onDragEnded;

  @override
  Widget build(BuildContext context) {
    final itemCount = items.length;
    final colorScheme = context.colorScheme;
    final floatingNavigationInset = ViewScope.isMobileOf(context)
        ? CategoryWorkbenchTokens.space16
        : 0.0;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        CategoryWorkbenchTokens.space16,
        CategoryWorkbenchTokens.space12,
        CategoryWorkbenchTokens.space16,
        floatingNavigationInset,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    key: const ValueKey('prism-category-page-title'),
                    '分类',
                    style: AppTextStyle.subheadline.of(
                      context,
                      emphasized: true,
                    ),
                  ),
                ),
              ),
              if (inlineActions.isNotEmpty) ...[
                const SizedBox(width: CategoryWorkbenchTokens.space8),
                ...inlineActions,
              ],
            ],
          ),
          const SizedBox(height: CategoryWorkbenchTokens.space8),
          _CompactCategoryTabs(
            categories: categories,
            categoryCounts: categoryCounts,
            uncategorizedCount: uncategorizedCount,
            selectedCategoryId: selectedCategoryId,
            totalCount: totalCount,
            busy: busy,
            onAllSelected: onAllSelected,
            onCategorySelected: onCategorySelected,
            onUncategorizedSelected: onUncategorizedSelected,
            onAssign: onAssign,
          ),
          const SizedBox(height: CategoryWorkbenchTokens.space16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
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
                    const SizedBox(height: CategoryWorkbenchTokens.space4),
                    Semantics(
                      header: true,
                      child: Text(
                        key: const ValueKey('prism-category-selection-title'),
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyle.custom(
                          context,
                          size: 20,
                          leading: 26,
                          weight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: CategoryWorkbenchTokens.space8),
              Text(
                key: const ValueKey('prism-category-selection-count'),
                _countLabel(
                  itemCount: itemCount,
                  totalCount: totalCount,
                  uncategorizedCount: uncategorizedCount,
                  showingAll: showingAll,
                  searching: searching,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyle.footnote
                    .of(context)
                    .copyWith(color: colorScheme.onSurfaceVariant),
              ),
              const SizedBox(width: CategoryWorkbenchTokens.space8),
              _SortMenuButton(
                key: const ValueKey('prism-category-sort-menu'),
                categorySortLabel: categorySortLabel,
                passwordSortLabel: passwordSortLabel,
                enabled: !busy,
                onCategorySort: onCategorySort,
                onPasswordSort: onPasswordSort,
              ),
            ],
          ),
          const SizedBox(height: CategoryWorkbenchTokens.space8),
          _PasswordSearchField(
            controller: searchController,
            onChanged: onSearchChanged,
          ),
          if (dropFeedback case final feedback?) ...[
            const SizedBox(height: CategoryWorkbenchTokens.space8),
            _DropFeedback(message: feedback),
          ],
          const SizedBox(height: CategoryWorkbenchTokens.space8),
          Expanded(
            child: _PasswordList(
              items: items,
              totalCount: totalCount,
              uncategorizedCount: uncategorizedCount,
              categoryNames: categoryNames,
              busy: busy,
              searching: searching,
              showingAll: showingAll,
              selectedItemId: selectedItemId,
              directDragEnabled: false,
              longPressDragEnabled: true,
              showActionButton: false,
              horizontalPadding: 0,
              onClearSearch: onClearSearch,
              onAllSelected: onAllSelected,
              onSelected: onItemSelected,
              onActivated: onItemSelected,
              onDragStarted: onDragStarted,
              onDragEnded: onDragEnded,
            ),
          ),
        ],
      ),
    );
  }
}

class _CompactCategoryTabs extends StatelessWidget {
  const _CompactCategoryTabs({
    required this.categories,
    required this.categoryCounts,
    required this.uncategorizedCount,
    required this.selectedCategoryId,
    required this.totalCount,
    required this.busy,
    required this.onAllSelected,
    required this.onCategorySelected,
    required this.onUncategorizedSelected,
    required this.onAssign,
  });

  final List<VaultCategory> categories;
  final Map<String, int> categoryCounts;
  final int uncategorizedCount;
  final String? selectedCategoryId;
  final int totalCount;
  final bool busy;
  final VoidCallback onAllSelected;
  final ValueChanged<String> onCategorySelected;
  final VoidCallback onUncategorizedSelected;
  final CategoryAssignCallback onAssign;

  @override
  Widget build(BuildContext context) {
    final rowCount = categories.length + 2;
    Widget tabForIndex(int index) {
      if (index == 0) {
        return _CompactCategoryTab(
          key: const ValueKey('prism-category-all-passwords'),
          label: '全部密码',
          count: totalCount,
          selected: selectedCategoryId == null,
          enabled: !busy,
          onPressed: onAllSelected,
        );
      }
      if (index == rowCount - 1) {
        return _CompactCategoryTab(
          key: const ValueKey('prism-category-drop-uncategorized'),
          label: '未分类',
          count: uncategorizedCount,
          selected: selectedCategoryId == '',
          enabled: !busy,
          onPressed: onUncategorizedSelected,
          onWillAccept: (item) => item.folder.isNotEmpty,
          onDrop: (item) => unawaited(onAssign(item, null, '未分类')),
        );
      }
      final category = categories[index - 1];
      return _CompactCategoryTab(
        key: ValueKey('prism-category-drop-${category.id}'),
        label: category.name,
        count: categoryCounts[category.id] ?? 0,
        selected: selectedCategoryId == category.id,
        enabled: !busy,
        onPressed: () => onCategorySelected(category.id),
        onWillAccept: (item) => item.folder != category.id,
        onDrop: (item) => unawaited(onAssign(item, category.id, category.name)),
      );
    }

    return Wrap(
      key: const ValueKey('prism-category-tabs'),
      spacing: CategoryWorkbenchTokens.space8,
      runSpacing: CategoryWorkbenchTokens.space8,
      children: [
        for (var index = 0; index < rowCount; index++) tabForIndex(index),
      ],
    );
  }
}

class _CompactCategoryTab extends StatefulWidget {
  const _CompactCategoryTab({
    super.key,
    required this.label,
    required this.count,
    required this.selected,
    required this.enabled,
    required this.onPressed,
    this.onWillAccept,
    this.onDrop,
  });

  final String label;
  final int count;
  final bool selected;
  final bool enabled;
  final VoidCallback onPressed;
  final bool Function(VaultItem item)? onWillAccept;
  final ValueChanged<VaultItem>? onDrop;

  @override
  State<_CompactCategoryTab> createState() => _CompactCategoryTabState();
}

class _CompactCategoryTabState extends State<_CompactCategoryTab> {
  bool _dragOver = false;

  @override
  Widget build(BuildContext context) {
    final acceptsDrop =
        widget.onWillAccept != null && widget.onDrop != null && widget.enabled;
    if (!acceptsDrop) {
      return _buildTab(context, dragOver: false);
    }
    return DragTarget<VaultItem>(
      onWillAcceptWithDetails: (details) =>
          widget.enabled && widget.onWillAccept!(details.data),
      onMove: (_) {
        if (!_dragOver) {
          setState(() => _dragOver = true);
        }
      },
      onLeave: (_) {
        if (_dragOver) {
          setState(() => _dragOver = false);
        }
      },
      onAcceptWithDetails: (details) {
        setState(() => _dragOver = false);
        widget.onDrop!(details.data);
      },
      builder: (context, candidateData, rejectedData) =>
          _buildTab(context, dragOver: _dragOver),
    );
  }

  Widget _buildTab(BuildContext context, {required bool dragOver}) {
    final colorScheme = context.colorScheme;
    final highlighted = widget.selected || dragOver;
    return ConstrainedBox(
      constraints: const BoxConstraints(
        minWidth: CategoryWorkbenchTokens.compactTabMinWidth,
      ),
      child: PressSurface(
        fill: dragOver
            ? colorScheme.primaryContainer
            : widget.selected
            ? CipherbookVisualTokens.accent
            : CipherbookVisualTokens.surfaceMuted,
        shape: AppShape.full,
        side: widget.selected || dragOver
            ? BorderSide.none
            : CipherbookVisualTokens.borderSide,
        foreground: widget.selected
            ? colorScheme.onPrimary
            : colorScheme.onSurface,
        padding: const EdgeInsets.symmetric(
          horizontal: CategoryWorkbenchTokens.space12,
        ),
        minimum: const BoxConstraints(
          minHeight: CategoryWorkbenchTokens.compactTabHeight,
        ),
        tapTarget: Size.zero,
        onPressed: widget.enabled ? widget.onPressed : null,
        selected: highlighted,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              key: ValueKey('prism-category-label-${widget.label}'),
              widget.label,
              maxLines: 1,
              softWrap: false,
              style: AppTextStyle.footnote
                  .of(context, emphasized: widget.selected)
                  .copyWith(
                    fontSize: CategoryWorkbenchTokens.categoryFontSize,
                    color: widget.selected
                        ? colorScheme.onPrimary
                        : colorScheme.onSurface,
                  ),
            ),
            const SizedBox(width: CategoryWorkbenchTokens.space8),
            Text(
              key: ValueKey('prism-category-tab-count-${widget.label}'),
              '${widget.count}',
              style: AppTextStyle.caption1
                  .of(context)
                  .copyWith(
                    fontSize: CategoryWorkbenchTokens.metadataFontSize,
                    fontWeight: FontWeight.w600,
                    color: widget.selected
                        ? colorScheme.onPrimary.withValues(alpha: 0.78)
                        : colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PasswordsWorkspace extends StatelessWidget {
  const _PasswordsWorkspace({
    required this.items,
    required this.totalCount,
    required this.uncategorizedCount,
    required this.categoryNames,
    required this.busy,
    required this.searching,
    required this.showingAll,
    required this.selectedItemId,
    required this.searchController,
    required this.dragging,
    required this.dropFeedback,
    required this.directDragEnabled,
    required this.inlineActions,
    required this.categorySortLabel,
    required this.passwordSortLabel,
    required this.onSearchChanged,
    required this.onClearSearch,
    required this.onCategorySort,
    required this.onPasswordSort,
    required this.onAllSelected,
    required this.onItemSelected,
    required this.onItemEdit,
    required this.onDragStarted,
    required this.onDragEnded,
  });

  final List<VaultItem> items;
  final int totalCount;
  final int uncategorizedCount;
  final Map<String, String> categoryNames;
  final bool busy;
  final bool searching;
  final bool showingAll;
  final String? selectedItemId;
  final TextEditingController searchController;
  final bool dragging;
  final String? dropFeedback;
  final bool directDragEnabled;
  final List<Widget> inlineActions;
  final String categorySortLabel;
  final String passwordSortLabel;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onClearSearch;
  final VoidCallback onCategorySort;
  final VoidCallback onPasswordSort;
  final VoidCallback onAllSelected;
  final ValueChanged<VaultItem> onItemSelected;
  final ValueChanged<VaultItem> onItemEdit;
  final VoidCallback onDragStarted;
  final VoidCallback onDragEnded;

  @override
  Widget build(BuildContext context) {
    final countLabel = _countLabel(
      itemCount: items.length,
      totalCount: totalCount,
      uncategorizedCount: uncategorizedCount,
      showingAll: showingAll,
      searching: searching,
    );
    final colorScheme = context.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            CipherbookPasswordRowMetrics.listHorizontalPadding,
            CategoryWorkbenchTokens.space8,
            CipherbookPasswordRowMetrics.listHorizontalPadding,
            0,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (inlineActions.isNotEmpty &&
                  _wrapIntermediateSearchActions(context))
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _PasswordSearchField(
                      controller: searchController,
                      onChanged: onSearchChanged,
                    ),
                    const SizedBox(height: CategoryWorkbenchTokens.space8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Wrap(
                        spacing: 0,
                        runSpacing: CategoryWorkbenchTokens.space8,
                        children: inlineActions,
                      ),
                    ),
                  ],
                )
              else
                Row(
                  children: [
                    Expanded(
                      child: _PasswordSearchField(
                        controller: searchController,
                        onChanged: onSearchChanged,
                      ),
                    ),
                    if (inlineActions.isNotEmpty) ...[
                      const SizedBox(width: CategoryWorkbenchTokens.space8),
                      ...inlineActions,
                    ],
                  ],
                ),
              const SizedBox(height: CategoryWorkbenchTokens.space8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      key: const ValueKey('prism-category-range-count'),
                      countLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyle.footnote
                          .of(context)
                          .copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                  ),
                  const SizedBox(width: CategoryWorkbenchTokens.space8),
                  _SortMenuButton(
                    key: const ValueKey('prism-category-sort-menu'),
                    categorySortLabel: categorySortLabel,
                    passwordSortLabel: passwordSortLabel,
                    enabled: !busy,
                    onCategorySort: onCategorySort,
                    onPasswordSort: onPasswordSort,
                  ),
                ],
              ),
              if (dropFeedback case final feedback?) ...[
                const SizedBox(height: CategoryWorkbenchTokens.space8),
                _DropFeedback(message: feedback),
              ] else if (dragging) ...[
                const SizedBox(height: CategoryWorkbenchTokens.space8),
                const _DragGuide(),
              ],
            ],
          ),
        ),
        const SizedBox(height: CategoryWorkbenchTokens.space4),
        Expanded(
          child: _PasswordList(
            items: items,
            totalCount: totalCount,
            uncategorizedCount: uncategorizedCount,
            categoryNames: categoryNames,
            busy: busy,
            searching: searching,
            showingAll: showingAll,
            selectedItemId: selectedItemId,
            directDragEnabled: directDragEnabled,
            longPressDragEnabled: false,
            showActionButton: true,
            horizontalPadding:
                CipherbookPasswordRowMetrics.listHorizontalPadding,
            onClearSearch: onClearSearch,
            onAllSelected: onAllSelected,
            onSelected: onItemSelected,
            onActivated: onItemEdit,
            onDragStarted: onDragStarted,
            onDragEnded: onDragEnded,
          ),
        ),
      ],
    );
  }
}

enum _SortMenuAction { category, password }

class _SortMenuButton extends StatelessWidget {
  const _SortMenuButton({
    super.key,
    required this.categorySortLabel,
    required this.passwordSortLabel,
    required this.enabled,
    required this.onCategorySort,
    required this.onPasswordSort,
  });

  final String categorySortLabel;
  final String passwordSortLabel;
  final bool enabled;
  final VoidCallback onCategorySort;
  final VoidCallback onPasswordSort;

  Future<void> _openMenu(BuildContext context) async {
    final action = await showFloatingDialog<_SortMenuAction>(
      context: context,
      child: Builder(
        builder: (dialogContext) {
          void choose(_SortMenuAction action) {
            Navigator.of(dialogContext).pop(action);
          }

          return AlertDialog(
            key: const ValueKey('prism-category-sort-dialog'),
            title: '排序',
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('取消'),
              ),
            ],
            child: SizedBox(
              width: 300,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _SortMenuRow(
                    key: const ValueKey('prism-category-order-sort'),
                    label: '分类顺序',
                    value: categorySortLabel,
                    onPressed: () => choose(_SortMenuAction.category),
                  ),
                  const SizedBox(height: CategoryWorkbenchTokens.space4),
                  _SortMenuRow(
                    key: const ValueKey('prism-category-password-sort'),
                    label: '密码顺序',
                    value: passwordSortLabel,
                    onPressed: () => choose(_SortMenuAction.password),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    if (action == _SortMenuAction.category) {
      onCategorySort();
    } else if (action == _SortMenuAction.password) {
      onPasswordSort();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '排序：分类 $categorySortLabel，密码 $passwordSortLabel',
      child: TextButton(
        key: const ValueKey('prism-category-sort-summary'),
        onPressed: enabled ? () => _openMenu(context) : null,
        style: const ButtonStyle(
          minimumSize: Size(0, CategoryWorkbenchTokens.touchTargetMin),
          padding: EdgeInsets.symmetric(
            horizontal: CategoryWorkbenchTokens.space8,
          ),
          tapTargetSize: TapTargetSize.shrinkWrap,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              passwordSortLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyle.footnote.of(context, emphasized: true),
            ),
            const SizedBox(width: CategoryWorkbenchTokens.space4),
            const GlyphIcon(Glyphs.chevronDown, size: 14),
          ],
        ),
      ),
    );
  }
}

class _SortMenuRow extends StatelessWidget {
  const _SortMenuRow({
    super.key,
    required this.label,
    required this.value,
    required this.onPressed,
  });

  final String label;
  final String value;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return SizedBox(
      height: CategoryWorkbenchTokens.touchTargetMin,
      child: PressSurface(
        fill: Colors.transparent,
        shape: AppShape.all(CategoryWorkbenchTokens.rowRadius),
        foreground: colorScheme.onSurface,
        padding: const EdgeInsets.symmetric(
          horizontal: CategoryWorkbenchTokens.space12,
        ),
        minimum: const BoxConstraints(
          minHeight: CategoryWorkbenchTokens.touchTargetMin,
        ),
        tapTarget: Size.zero,
        onPressed: onPressed,
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: AppTextStyle.footnote.of(context, emphasized: true),
              ),
            ),
            const SizedBox(width: CategoryWorkbenchTokens.space8),
            Flexible(
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
                style: AppTextStyle.caption1
                    .of(context)
                    .copyWith(color: colorScheme.onSurfaceVariant),
              ),
            ),
            const SizedBox(width: CategoryWorkbenchTokens.space4),
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

class _PasswordSearchField extends StatelessWidget {
  const _PasswordSearchField({
    required this.controller,
    required this.onChanged,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final border = AppInputBorder(
      borderRadius: CipherbookVisualTokens.controlRadius,
      borderSide: CipherbookVisualTokens.borderSide,
    );
    return TextField(
      key: const ValueKey('prism-category-password-search'),
      controller: controller,
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: '搜索名称、账号、网址或备注',
        hintMaxLines: 1,
        isDense: true,
        filled: true,
        fillColor: CipherbookVisualTokens.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: CategoryWorkbenchTokens.space12,
          vertical: CategoryWorkbenchTokens.space12,
        ),
        prefixIcon: const GlyphIcon(Glyphs.search),
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(
                onPressed: () {
                  controller.clear();
                  onChanged('');
                },
                tooltip: '清除搜索',
                icon: const GlyphIcon(Glyphs.close),
                padding: EdgeInsets.zero,
                style: const ButtonStyle(
                  minimumSize: Size.square(
                    CategoryWorkbenchTokens.touchTargetMin,
                  ),
                  maximumSize: Size.square(
                    CategoryWorkbenchTokens.touchTargetMin,
                  ),
                  tapTargetSize: TapTargetSize.shrinkWrap,
                ),
              ),
        border: border,
        enabledBorder: border.copyWith(
          borderSide: CipherbookVisualTokens.strongBorderSide,
        ),
        disabledBorder: border,
        focusedBorder: border.copyWith(
          borderSide: CipherbookVisualTokens.accentBorderSide,
        ),
      ),
    );
  }
}

class _PasswordList extends StatelessWidget {
  const _PasswordList({
    required this.items,
    required this.totalCount,
    required this.uncategorizedCount,
    required this.categoryNames,
    required this.busy,
    required this.searching,
    required this.showingAll,
    required this.selectedItemId,
    required this.directDragEnabled,
    required this.longPressDragEnabled,
    required this.showActionButton,
    required this.horizontalPadding,
    required this.onClearSearch,
    required this.onAllSelected,
    required this.onSelected,
    required this.onActivated,
    required this.onDragStarted,
    required this.onDragEnded,
  });

  final List<VaultItem> items;
  final int totalCount;
  final int uncategorizedCount;
  final Map<String, String> categoryNames;
  final bool busy;
  final bool searching;
  final bool showingAll;
  final String? selectedItemId;
  final bool directDragEnabled;
  final bool longPressDragEnabled;
  final bool showActionButton;
  final double horizontalPadding;
  final VoidCallback onClearSearch;
  final VoidCallback onAllSelected;
  final ValueChanged<VaultItem> onSelected;
  final ValueChanged<VaultItem> onActivated;
  final VoidCallback onDragStarted;
  final VoidCallback onDragEnded;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return _PasswordsEmptyState(
        searching: searching,
        showingAll: showingAll,
        onClearSearch: onClearSearch,
        onAllSelected: onAllSelected,
      );
    }
    return ListView.separated(
      key: const ValueKey('prism-category-password-list'),
      padding: EdgeInsets.fromLTRB(
        horizontalPadding,
        CategoryWorkbenchTokens.space8,
        horizontalPadding,
        CategoryWorkbenchTokens.space20,
      ),
      itemCount: items.length,
      separatorBuilder: (context, index) =>
          const SizedBox(height: CipherbookPasswordRowMetrics.rowGap),
      itemBuilder: (context, index) {
        final item = items[index];
        return _PasswordDragRow(
          item: item,
          categoryName: showingAll ? categoryNames[item.folder] : null,
          selected: selectedItemId == item.id,
          enabled: !busy,
          directDragEnabled: directDragEnabled,
          longPressDragEnabled: longPressDragEnabled,
          showActionButton: showActionButton,
          onPressed: busy ? null : () => onSelected(item),
          onActivated: busy ? null : () => onActivated(item),
          onDragStarted: onDragStarted,
          onDragEnded: onDragEnded,
        );
      },
    );
  }
}

class _PasswordDragRow extends StatelessWidget {
  const _PasswordDragRow({
    required this.item,
    required this.categoryName,
    required this.selected,
    required this.enabled,
    required this.directDragEnabled,
    required this.longPressDragEnabled,
    required this.showActionButton,
    required this.onPressed,
    required this.onActivated,
    required this.onDragStarted,
    required this.onDragEnded,
  });

  final VaultItem item;
  final String? categoryName;
  final bool selected;
  final bool enabled;
  final bool directDragEnabled;
  final bool longPressDragEnabled;
  final bool showActionButton;
  final VoidCallback? onPressed;
  final VoidCallback? onActivated;
  final VoidCallback onDragStarted;
  final VoidCallback onDragEnded;

  @override
  Widget build(BuildContext context) {
    final dragSupported = directDragEnabled || longPressDragEnabled;
    final row = CipherbookPasswordRow(
      item: item,
      categoryName: categoryName,
      stripUrlScheme: true,
      selected: selected,
      onPressed: onPressed,
      onTrailingPressed: onActivated,
      trailingKey: showActionButton
          ? ValueKey('prism-password-open-${item.id}')
          : null,
      trailingTooltip: showActionButton ? '编辑密码' : '查看详情',
      leading: directDragEnabled
          ? _SixDotDragHandle(
              key: ValueKey('prism-password-drag-handle-${item.id}'),
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              size: 18,
            )
          : null,
      leadingTooltip: directDragEnabled ? '拖动密码到分类' : null,
    );
    final interactiveRow = onActivated == null
        ? row
        : _DoubleTapActivator(onDoubleTap: onActivated!, child: row);
    final rowKey = ValueKey('prism-password-row-${item.id}');
    if (!dragSupported || !enabled) {
      return KeyedSubtree(key: rowKey, child: interactiveRow);
    }
    final feedback = Directionality(
      textDirection: Directionality.of(context),
      child: _PasswordDragFeedback(item: item, categoryName: categoryName),
    );
    if (longPressDragEnabled) {
      return KeyedSubtree(
        key: rowKey,
        child: LongPressDraggable<VaultItem>(
          key: ValueKey('prism-password-drag-${item.id}'),
          data: item,
          maxSimultaneousDrags: 1,
          dragAnchorStrategy: pointerDragAnchorStrategy,
          onDragStarted: onDragStarted,
          onDragEnd: (_) => onDragEnded(),
          feedback: feedback,
          childWhenDragging: Opacity(opacity: 0.35, child: interactiveRow),
          child: interactiveRow,
        ),
      );
    }
    return KeyedSubtree(
      key: rowKey,
      child: Draggable<VaultItem>(
        key: ValueKey('prism-password-drag-${item.id}'),
        data: item,
        maxSimultaneousDrags: 1,
        dragAnchorStrategy: pointerDragAnchorStrategy,
        onDragStarted: onDragStarted,
        onDragEnd: (_) => onDragEnded(),
        feedback: feedback,
        childWhenDragging: Opacity(opacity: 0.35, child: interactiveRow),
        child: interactiveRow,
      ),
    );
  }
}

class _PasswordDragFeedback extends StatelessWidget {
  const _PasswordDragFeedback({required this.item, required this.categoryName});

  final VaultItem item;
  final String? categoryName;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 300,
      child: CipherbookPasswordRow(
        item: item,
        categoryName: categoryName,
        stripUrlScheme: true,
        onPressed: null,
        showTrailing: false,
      ),
    );
  }
}

class _PasswordsEmptyState extends StatelessWidget {
  const _PasswordsEmptyState({
    required this.searching,
    required this.showingAll,
    required this.onClearSearch,
    required this.onAllSelected,
  });

  final bool searching;
  final bool showingAll;
  final VoidCallback onClearSearch;
  final VoidCallback onAllSelected;

  @override
  Widget build(BuildContext context) {
    final title = searching
        ? '没有匹配的密码'
        : showingAll
        ? '还没有密码'
        : '这个分类还没有密码';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(CategoryWorkbenchTokens.space24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              textAlign: TextAlign.center,
              style: AppTextStyle.subheadline.of(context, emphasized: true),
            ),
            if (searching) ...[
              const SizedBox(height: CategoryWorkbenchTokens.space12),
              TextButton(onPressed: onClearSearch, child: const Text('清除搜索')),
            ] else if (!showingAll) ...[
              const SizedBox(height: CategoryWorkbenchTokens.space12),
              TextButton(
                key: const ValueKey('prism-empty-category-all'),
                onPressed: onAllSelected,
                child: const Text('查看全部密码'),
              ),
              const SizedBox(height: CategoryWorkbenchTokens.space8),
              Text(
                '可将密码拖入此分类',
                textAlign: TextAlign.center,
                style: AppTextStyle.caption1
                    .of(context)
                    .copyWith(
                      fontSize: CategoryWorkbenchTokens.metadataFontSize,
                      color: context.colorScheme.onSurface.withValues(
                        alpha: CategoryWorkbenchTokens.metadataOpacity,
                      ),
                    ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DragGuide extends StatelessWidget {
  const _DragGuide();

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        border: Border.all(color: colorScheme.primary),
        borderRadius: AppRadius.all(CategoryWorkbenchTokens.rowRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: CategoryWorkbenchTokens.space12,
          vertical: CategoryWorkbenchTokens.space8,
        ),
        child: Row(
          children: [
            _SixDotDragHandle(color: colorScheme.primary, size: 16),
            const SizedBox(width: CategoryWorkbenchTokens.space8),
            Expanded(
              child: Text(
                '拖到左侧分类',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyle.caption1
                    .of(context, emphasized: true)
                    .copyWith(color: colorScheme.primary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DropFeedback extends StatelessWidget {
  const _DropFeedback({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        border: Border.all(color: colorScheme.outlineVariant),
        borderRadius: AppRadius.all(CategoryWorkbenchTokens.rowRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: CategoryWorkbenchTokens.space12,
          vertical: CategoryWorkbenchTokens.space8,
        ),
        child: Row(
          children: [
            GlyphIcon(Glyphs.check, size: 16, color: colorScheme.primary),
            const SizedBox(width: CategoryWorkbenchTokens.space8),
            Expanded(
              child: Text(
                message,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyle.caption1
                    .of(context, emphasized: true)
                    .copyWith(color: colorScheme.onSurface),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _countLabel({
  required int itemCount,
  required int totalCount,
  required int uncategorizedCount,
  required bool showingAll,
  required bool searching,
}) {
  if (searching) {
    return '$itemCount 条结果';
  }
  if (showingAll) {
    return '未分类 $uncategorizedCount · 共 $totalCount';
  }
  return '共 $itemCount 条';
}
