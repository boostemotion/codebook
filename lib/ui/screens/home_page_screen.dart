import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../../models/bitwarden_bridge_models.dart';
import '../../models/vault_models.dart';
import '../../services/lan_sync_service.dart';
import '../../services/totp_service.dart';
import '../../services/vault_repository.dart';
import '../../state/vault_controller.dart';

const TotpService _totpService = TotpService();
const Color _kDialogBarrierColor = Color(0x4A140A11);
final _GlassPerfBus _glassPerfBus = _GlassPerfBus();

enum _AndroidOverflowAction {
  recycleBin,
  categories,
  importVault,
  lanSync,
  exportVault,
  settings,
}

enum _GlassQualityTier {
  high(1.0, 1.0),
  medium(0.78, 0.76),
  low(0.56, 0.52);

  const _GlassQualityTier(this.blurScale, this.shaderStrength);
  final double blurScale;
  final double shaderStrength;
}

class _GlassPerfBus extends ChangeNotifier {
  _GlassQualityTier _tier = _GlassQualityTier.high;
  Timer? _idleTimer;

  _GlassQualityTier get tier => _tier;

  void reset() {
    _idleTimer?.cancel();
    _idleTimer = null;
    _setTier(_GlassQualityTier.high);
  }

  void pulse({bool heavy = false}) {
    _idleTimer?.cancel();
    _setTier(heavy ? _GlassQualityTier.low : _GlassQualityTier.medium);
    _idleTimer = Timer(
      Duration(milliseconds: heavy ? 360 : 220),
      () => _setTier(_GlassQualityTier.high),
    );
  }

  void _setTier(_GlassQualityTier next) {
    if (_tier == next) {
      return;
    }
    _tier = next;
    notifyListeners();
  }
}

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.controller,
  });

  final VaultController controller;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  final TextEditingController _masterPasswordController =
      TextEditingController();
  final TextEditingController _importPasswordController =
      TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final ScrollController _vaultScrollController = ScrollController();
  final GlobalKey<_VaultViewState> _vaultViewKey = GlobalKey<_VaultViewState>();
  bool _searchKeyboardWasVisible = false;
  bool _wasUnlocked = false;
  bool _canSubmitMasterPassword = false;
  bool _androidSearchOpen = false;
  bool _androidFabExpanded = true;
  String? _androidSelectedCategoryId;

  String _searchQuery = '';
  _SortMode _sortMode = _SortMode.recentlyUpdated;

  @override
  void initState() {
    super.initState();
    _wasUnlocked = widget.controller.isUnlocked;
    WidgetsBinding.instance.addObserver(this);
    widget.controller.addListener(_handleControllerChanged);
    _searchFocusNode.addListener(_handleSearchFocusChanged);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.removeListener(_handleControllerChanged);
    _searchFocusNode.removeListener(_handleSearchFocusChanged);
    _glassPerfBus.reset();
    _vaultScrollController.dispose();
    _masterPasswordController.dispose();
    _importPasswordController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final pickerTemporarilyOwnsFocus = state == AppLifecycleState.inactive &&
        widget.controller.externalUiActive;
    if (pickerTemporarilyOwnsFocus) {
      return;
    }
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _masterPasswordController.clear();
      _importPasswordController.clear();
      _canSubmitMasterPassword = false;
      _searchFocusNode.unfocus();
      unawaited(
        widget.controller.handleAppLifecycle(state),
      );
    }
  }

  void _handleControllerChanged() {
    final isUnlocked = widget.controller.isUnlocked;
    if (_wasUnlocked != isUnlocked) {
      if (!isUnlocked) {
        _masterPasswordController.clear();
        _importPasswordController.clear();
        _canSubmitMasterPassword = false;
        _vaultViewKey.currentState?.clearSensitiveInputs();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !widget.controller.isUnlocked) {
            Navigator.of(context, rootNavigator: true)
                .popUntil((route) => route.isFirst);
          }
        });
      }
      _wasUnlocked = isUnlocked;
    }

    final message = widget.controller.message;
    if (!mounted || message == null || message.isEmpty) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
    widget.controller.clearMessage();
  }

  void _handleSearchFocusChanged() {
    if (!mounted) {
      return;
    }
    _glassPerfBus.pulse();
    setState(() {});
  }

  @override
  void didChangeMetrics() {
    if (!mounted) {
      return;
    }
    final keyboardVisible = View.of(context).viewInsets.bottom > 0;
    if (keyboardVisible) {
      _searchKeyboardWasVisible = true;
      _glassPerfBus.pulse(heavy: true);
      return;
    }
    if (_searchKeyboardWasVisible && _searchFocusNode.hasFocus) {
      _searchFocusNode.unfocus();
    }
    _searchKeyboardWasVisible = false;
  }

  void _focusSearch() {
    if (!widget.controller.isUnlocked) {
      return;
    }
    if (Theme.of(context).platform == TargetPlatform.android) {
      setState(() {
        _androidSearchOpen = true;
      });
    }
    _vaultViewKey.currentState?.showPasswords();
    _searchFocusNode.requestFocus();
  }

  void _closeAndroidSearch() {
    _searchFocusNode.unfocus();
    _searchController.clear();
    setState(() {
      _androidSearchOpen = false;
      _searchQuery = '';
    });
  }

  void _handleEscape() {
    if (_androidSearchOpen) {
      _closeAndroidSearch();
      return;
    }
    if (_searchFocusNode.hasFocus) {
      _searchFocusNode.unfocus();
      return;
    }
    _vaultViewKey.currentState?.showPasswords();
  }

  Widget _buildAndroidScaffold(BuildContext context) {
    final controller = widget.controller;
    if (!controller.isUnlocked) {
      return Stack(
        children: [
          Scaffold(
            appBar: AppBar(title: const Text('密码本')),
            body: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: _LockedView(
                  controller: controller,
                  masterPasswordController: _masterPasswordController,
                  importPasswordController: _importPasswordController,
                  canSubmitMasterPassword: _canSubmitMasterPassword,
                  onLanPair: () => _showLanSyncDialog(
                    context,
                    controller: controller,
                  ),
                  onMasterPasswordChanged: (value) {
                    final canSubmit = value.trim().isNotEmpty;
                    if (canSubmit != _canSubmitMasterPassword) {
                      setState(() {
                        _canSubmitMasterPassword = canSubmit;
                      });
                    }
                  },
                ),
              ),
            ),
          ),
          if (controller.busy)
            const Positioned.fill(
              child: ColoredBox(
                color: Color(0x55000000),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
        ],
      );
    }

    final items = controller.vaultData.activeItems.where((item) {
      if (_searchQuery.isEmpty) {
        return true;
      }
      final haystack = [
        item.title,
        item.username,
        item.url,
        item.notes,
        item.folder,
        item.tags.join(' '),
      ].join(' ').toLowerCase();
      return haystack.contains(_searchQuery);
    }).where((item) {
      if (_androidSelectedCategoryId == null) {
        return true;
      }
      if (_androidSelectedCategoryId!.isEmpty) {
        return item.folder.isEmpty;
      }
      return item.folder == _androidSelectedCategoryId;
    }).toList()
      ..sort((a, b) {
        final byUpdatedAt = b.updatedAt.compareTo(a.updatedAt);
        if (byUpdatedAt != 0) {
          return byUpdatedAt;
        }
        return a.title.toLowerCase().compareTo(b.title.toLowerCase());
      });

    return PopScope(
      canPop: !_androidSearchOpen,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _androidSearchOpen) {
          _closeAndroidSearch();
        }
      },
      child: Listener(
        onPointerDown: (_) => controller.registerActivity(),
        onPointerSignal: (_) => controller.registerActivity(),
        child: Scaffold(
          appBar: AppBar(
            leading: _androidSearchOpen
                ? IconButton(
                    tooltip: '关闭搜索',
                    onPressed: _closeAndroidSearch,
                    icon: const Icon(Icons.arrow_back_rounded),
                  )
                : null,
            title: _androidSearchOpen
                ? TextField(
                    key: const ValueKey('android-search-field'),
                    controller: _searchController,
                    focusNode: _searchFocusNode,
                    autofocus: true,
                    textInputAction: TextInputAction.search,
                    decoration: const InputDecoration(
                      filled: false,
                      fillColor: Colors.transparent,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(vertical: 10),
                      hintText: '搜索条目',
                    ),
                    onChanged: (value) {
                      setState(() {
                        _searchQuery = value.trim().toLowerCase();
                      });
                    },
                  )
                : const Text('密码本'),
            actions: [
              if (!_androidSearchOpen)
                IconButton(
                  tooltip: '搜索',
                  onPressed: _focusSearch,
                  icon: const Icon(Icons.search_rounded),
                ),
              if (!_androidSearchOpen)
                IconButton(
                  tooltip: '设备配对与同步',
                  onPressed: () => _showLanSyncDialog(
                    context,
                    controller: controller,
                  ),
                  icon: const Icon(Icons.sync_rounded),
                ),
              IconButton(
                tooltip: '立即锁定',
                onPressed: controller.lock,
                icon: const Icon(Icons.lock_rounded),
              ),
              PopupMenuButton<_AndroidOverflowAction>(
                key: const ValueKey('android-vault-overflow'),
                tooltip: '更多操作',
                onSelected: (action) => _handleAndroidOverflow(context, action),
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: _AndroidOverflowAction.recycleBin,
                    child: ListTile(
                      leading: Icon(Icons.delete_outline_rounded),
                      title: Text('回收站'),
                    ),
                  ),
                  PopupMenuItem(
                    value: _AndroidOverflowAction.categories,
                    child: ListTile(
                      leading: Icon(Icons.folder_outlined),
                      title: Text('分类管理'),
                    ),
                  ),
                  PopupMenuItem(
                    value: _AndroidOverflowAction.importVault,
                    child: ListTile(
                      leading: Icon(Icons.download_rounded),
                      title: Text('导入'),
                    ),
                  ),
                  PopupMenuItem(
                    value: _AndroidOverflowAction.lanSync,
                    child: ListTile(
                      leading: Icon(Icons.devices_other_rounded),
                      title: Text('设备配对与同步'),
                    ),
                  ),
                  PopupMenuItem(
                    value: _AndroidOverflowAction.exportVault,
                    child: ListTile(
                      leading: Icon(Icons.upload_rounded),
                      title: Text('导出'),
                    ),
                  ),
                  PopupMenuItem(
                    value: _AndroidOverflowAction.settings,
                    child: ListTile(
                      leading: Icon(Icons.settings_rounded),
                      title: Text('设置'),
                    ),
                  ),
                ],
              ),
            ],
          ),
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                child: Text(
                  _searchQuery.isEmpty
                      ? '全部密码  ·  ${items.length}'
                      : '搜索结果  ·  ${items.length}',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ),
              SizedBox(
                height: 48,
                child: ListView(
                  key: const ValueKey('android-category-bar'),
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    _AndroidCategoryChip(
                      key: const ValueKey('android-category-bar-all'),
                      label: '全部',
                      active: _androidSelectedCategoryId == null,
                      onTap: () {
                        setState(() {
                          _androidSelectedCategoryId = null;
                        });
                      },
                    ),
                    _AndroidCategoryChip(
                      key: const ValueKey('android-category-bar-none'),
                      label: '未分类',
                      active: _androidSelectedCategoryId == '',
                      onTap: () {
                        setState(() {
                          _androidSelectedCategoryId = '';
                        });
                      },
                      onItemDropped: (itemId) =>
                          controller.assignItemToCategory(itemId: itemId),
                    ),
                    for (final category in controller.vaultData.categories)
                      _AndroidCategoryChip(
                        key: ValueKey('android-category-bar-${category.id}'),
                        label: category.name,
                        active: _androidSelectedCategoryId == category.id,
                        onTap: () {
                          setState(() {
                            _androidSelectedCategoryId = category.id;
                          });
                        },
                        onItemDropped: (itemId) =>
                            controller.assignItemToCategory(
                          itemId: itemId,
                          categoryId: category.id,
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: items.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _searchQuery.isEmpty
                                  ? Icons.key_outlined
                                  : Icons.search_off_rounded,
                              size: 36,
                              color: Theme.of(context).colorScheme.outline,
                            ),
                            const SizedBox(height: 12),
                            Text(_searchQuery.isEmpty ? '还没有条目' : '没有匹配条目',
                                style: Theme.of(context).textTheme.titleMedium),
                            const SizedBox(height: 4),
                            Text(
                                _searchQuery.isEmpty
                                    ? '添加第一条密码，随时查找'
                                    : '试试其他关键词',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    )),
                          ],
                        ),
                      )
                    : NotificationListener<ScrollNotification>(
                        onNotification: (notification) {
                          if (notification is UserScrollNotification &&
                              notification.direction != ScrollDirection.idle) {
                            final expanded = notification.direction !=
                                ScrollDirection.reverse;
                            if (expanded != _androidFabExpanded) {
                              setState(() {
                                _androidFabExpanded = expanded;
                              });
                            }
                          }
                          return false;
                        },
                        child: ListView.separated(
                          key: const ValueKey('android-vault-list'),
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 96),
                          itemCount: items.length,
                          separatorBuilder: (_, __) => Padding(
                            padding: const EdgeInsets.only(left: 64, right: 8),
                            child: Divider(
                                height: 1,
                                color: Theme.of(context)
                                    .colorScheme
                                    .outlineVariant),
                          ),
                          itemBuilder: (context, index) {
                            final item = items[index];
                            final subtitle = [item.username, item.url]
                                .where((value) => value.trim().isNotEmpty)
                                .join(' · ');
                            final entryTile = Material(
                              key: ValueKey('android-vault-item-${item.id}'),
                              color: Colors.transparent,
                              clipBehavior: Clip.antiAlias,
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                leading: Container(
                                  width: 44,
                                  height: 44,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .secondaryContainer,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    item.title.trim().isEmpty
                                        ? '?'
                                        : item.title
                                            .trim()
                                            .characters
                                            .first
                                            .toUpperCase(),
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSecondaryContainer,
                                          fontWeight: FontWeight.w700,
                                        ),
                                  ),
                                ),
                                title: Text(
                                  item.title.trim().isEmpty
                                      ? '未命名'
                                      : item.title,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleSmall
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: subtitle.isEmpty
                                    ? null
                                    : Text(
                                        subtitle,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                onTap: () => _showItemDetails(
                                  context,
                                  controller: controller,
                                  item: item,
                                ),
                                trailing: PopupMenuButton<String>(
                                  key:
                                      ValueKey('android-entry-menu-${item.id}'),
                                  tooltip: '条目操作',
                                  onSelected: (action) async {
                                    switch (action) {
                                      case 'copy':
                                        controller.copySecret(item.password);
                                        break;
                                      case 'edit':
                                        _showItemEditor(
                                          context,
                                          controller: controller,
                                          item: item,
                                        );
                                        break;
                                      case 'category':
                                        await _showAndroidCategoryPicker(
                                          context,
                                          controller: controller,
                                          item: item,
                                        );
                                        break;
                                      case 'delete':
                                        _confirmDeleteItem(
                                          context,
                                          controller: controller,
                                          item: item,
                                        );
                                        break;
                                    }
                                  },
                                  itemBuilder: (context) => const [
                                    PopupMenuItem(
                                      value: 'copy',
                                      child: ListTile(
                                        leading: Icon(Icons.copy_outlined),
                                        title: Text('复制密码'),
                                      ),
                                    ),
                                    PopupMenuItem(
                                      value: 'edit',
                                      child: ListTile(
                                        leading: Icon(Icons.edit_outlined),
                                        title: Text('编辑'),
                                      ),
                                    ),
                                    PopupMenuItem(
                                      value: 'category',
                                      child: ListTile(
                                        leading: Icon(Icons.folder_outlined),
                                        title: Text('移动到分类'),
                                      ),
                                    ),
                                    PopupMenuItem(
                                      value: 'delete',
                                      child: ListTile(
                                        leading:
                                            Icon(Icons.delete_outline_rounded),
                                        title: Text('移至回收站'),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                            return LongPressDraggable<VaultItem>(
                              key: ValueKey('android-draggable-${item.id}'),
                              data: item,
                              dragAnchorStrategy: pointerDragAnchorStrategy,
                              feedback: _AndroidDraggedEntryCard(
                                item: item,
                                accountInfo: subtitle,
                              ),
                              childWhenDragging: Opacity(
                                opacity: 0.45,
                                child: entryTile,
                              ),
                              child: entryTile,
                            );
                          },
                        ),
                      ),
              ),
            ],
          ),
          floatingActionButton: AnimatedSwitcher(
            duration: const Duration(milliseconds: 160),
            child: _androidFabExpanded
                ? FloatingActionButton.extended(
                    key: const ValueKey('android-vault-fab'),
                    tooltip: '新增条目',
                    onPressed: () =>
                        _showItemEditor(context, controller: controller),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('新增'),
                  )
                : FloatingActionButton(
                    key: const ValueKey('android-vault-fab'),
                    tooltip: '新增条目',
                    onPressed: () =>
                        _showItemEditor(context, controller: controller),
                    child: const Icon(Icons.add_rounded),
                  ),
          ),
        ),
      ),
    );
  }

  Future<void> _handleAndroidOverflow(
    BuildContext context,
    _AndroidOverflowAction action,
  ) async {
    switch (action) {
      case _AndroidOverflowAction.recycleBin:
        await showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          builder: (context) => _RecycleBinSheet(controller: widget.controller),
        );
        return;
      case _AndroidOverflowAction.categories:
        await showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          builder: (_) => _AndroidCategoriesSheet(
            controller: widget.controller,
            onReordered: widget.controller.reorderCategories,
          ),
        );
        return;
      case _AndroidOverflowAction.importVault:
        await showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          builder: (context) =>
              _AndroidImportSheet(controller: widget.controller),
        );
        return;
      case _AndroidOverflowAction.lanSync:
        await _showLanSyncDialog(
          context,
          controller: widget.controller,
        );
        return;
      case _AndroidOverflowAction.exportVault:
        await showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          builder: (context) =>
              _AndroidExportSheet(controller: widget.controller),
        );
        return;
      case _AndroidOverflowAction.settings:
        await showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          builder: (context) =>
              _AndroidSettingsSheet(controller: widget.controller),
        );
        return;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        if (Theme.of(context).platform == TargetPlatform.android) {
          return _buildAndroidScaffold(context);
        }
        return Scaffold(
          extendBody: true,
          body: Listener(
            onPointerDown: (_) => widget.controller.registerActivity(),
            onPointerSignal: (_) => widget.controller.registerActivity(),
            child: Focus(
              autofocus: true,
              onKeyEvent: (_, __) {
                widget.controller.registerActivity();
                return KeyEventResult.ignored;
              },
              child: CallbackShortcuts(
                bindings: {
                  const SingleActivator(LogicalKeyboardKey.keyL, control: true):
                      widget.controller.lock,
                  const SingleActivator(LogicalKeyboardKey.keyF, control: true):
                      _focusSearch,
                  const SingleActivator(LogicalKeyboardKey.keyN, control: true):
                      () => _vaultViewKey.currentState?.showAddItem(),
                  const SingleActivator(LogicalKeyboardKey.escape):
                      _handleEscape,
                },
                child: Stack(
                  children: [
                    const Positioned.fill(child: _GlassBackground()),
                    Positioned.fill(
                      child: SafeArea(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
                          child: widget.controller.isUnlocked
                              ? LayoutBuilder(
                                  builder: (context, constraints) {
                                    return SizedBox(
                                      width: constraints.maxWidth,
                                      height: constraints.maxHeight,
                                      child: _VaultView(
                                        key: _vaultViewKey,
                                        controller: widget.controller,
                                        searchController: _searchController,
                                        searchFocusNode: _searchFocusNode,
                                        isSearchFocused:
                                            _searchFocusNode.hasFocus,
                                        scrollController:
                                            _vaultScrollController,
                                        searchQuery: _searchQuery,
                                        sortMode: _sortMode,
                                        onSearchChanged: (value) {
                                          setState(() {
                                            _searchQuery =
                                                value.trim().toLowerCase();
                                          });
                                        },
                                        onSortModeChanged: (value) {
                                          setState(() {
                                            _sortMode = value;
                                          });
                                        },
                                      ),
                                    );
                                  },
                                )
                              : _LockedView(
                                  controller: widget.controller,
                                  masterPasswordController:
                                      _masterPasswordController,
                                  importPasswordController:
                                      _importPasswordController,
                                  canSubmitMasterPassword:
                                      _canSubmitMasterPassword,
                                  onLanPair: () => _showLanSyncDialog(
                                    context,
                                    controller: widget.controller,
                                  ),
                                  onMasterPasswordChanged: (value) {
                                    final canSubmit = value.trim().isNotEmpty;
                                    if (canSubmit != _canSubmitMasterPassword) {
                                      setState(() {
                                        _canSubmitMasterPassword = canSubmit;
                                      });
                                    }
                                  },
                                ),
                        ),
                      ),
                    ),
                    if (widget.controller.busy)
                      const ColoredBox(
                        color: Color(0x55000000),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _GlassBackground extends StatelessWidget {
  const _GlassBackground();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(color: Color(0xFFF4F5F7));
  }
}

class _LockedView extends StatelessWidget {
  const _LockedView({
    required this.controller,
    required this.masterPasswordController,
    required this.importPasswordController,
    required this.canSubmitMasterPassword,
    required this.onLanPair,
    required this.onMasterPasswordChanged,
  });

  final VaultController controller;
  final TextEditingController masterPasswordController;
  final TextEditingController importPasswordController;
  final bool canSubmitMasterPassword;
  final VoidCallback onLanPair;
  final ValueChanged<String> onMasterPasswordChanged;

  @override
  Widget build(BuildContext context) {
    if (controller.storageState == VaultStorageState.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!controller.canCreateVault &&
        controller.storageState != VaultStorageState.available) {
      return _StorageRepairView(controller: controller);
    }
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          child: _FrostedSurface(
            sigma: 24,
            plainOnAndroid: true,
            padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  controller.hasVault ? '解锁密码本' : '创建密码本',
                  style: Theme.of(context).platform == TargetPlatform.android
                      ? Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          )
                      : Theme.of(context).textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.2,
                          ),
                ),
                const SizedBox(height: 8),
                Text(
                  controller.hasVault
                      ? '输入主密码进入本地加密库。'
                      : '设置主密码后，所有数据会保存在本地加密库中。',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: masterPasswordController,
                  obscureText: true,
                  enableSuggestions: false,
                  autocorrect: false,
                  onChanged: onMasterPasswordChanged,
                  decoration: const InputDecoration(
                    labelText: '主密码',
                    prefixIcon: Icon(Icons.key_rounded),
                  ),
                  onSubmitted: (_) {
                    if (controller.hasVault && !canSubmitMasterPassword) {
                      return;
                    }
                    if (controller.hasVault) {
                      controller.unlock(masterPasswordController.text);
                    } else {
                      controller.createVault(masterPasswordController.text);
                    }
                  },
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: (!controller.hasVault || canSubmitMasterPassword)
                      ? () {
                          if (controller.hasVault) {
                            controller.unlock(masterPasswordController.text);
                          } else {
                            controller
                                .createVault(masterPasswordController.text);
                          }
                        }
                      : null,
                  icon: Icon(
                    controller.hasVault
                        ? Icons.lock_open_rounded
                        : Icons.verified_user_rounded,
                  ),
                  label: Text(controller.hasVault ? '解锁' : '创建密码库'),
                ),
                if (controller.canUseQuickUnlockNow && controller.hasVault) ...[
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: controller.unlockWithQuickUnlock,
                    icon: const Icon(Icons.fingerprint_rounded),
                    label: const Text('快速解锁（系统认证）'),
                  ),
                ],
                if (!controller.hasVault) ...[
                  const SizedBox(height: 20),
                  const Divider(height: 1),
                  const SizedBox(height: 14),
                  TextField(
                    controller: importPasswordController,
                    obscureText: true,
                    enableSuggestions: false,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: '导入文件密码',
                      helperText: '首次使用时，也可以直接导入已有加密备份。',
                      prefixIcon: Icon(Icons.file_open_rounded),
                    ),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final plan = await controller
                          .previewImport(importPasswordController.text);
                      if (plan == null || !context.mounted) {
                        return;
                      }
                      final confirmed = await _showImportSummaryDialog(
                        context,
                        plan.summary,
                      );
                      if (confirmed == true && context.mounted) {
                        await controller.applyImportPlan(plan);
                      }
                    },
                    icon: const Icon(Icons.download_rounded),
                    label: const Text('导入并合并备份'),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: controller.busy ? null : onLanPair,
                    icon: const Icon(Icons.devices_other_rounded),
                    label: const Text('从局域网配对已有密码库'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StorageRepairView extends StatelessWidget {
  const _StorageRepairView({required this.controller});

  final VaultController controller;

  @override
  Widget build(BuildContext context) {
    final canRecover = controller.canRecoverVault;
    final title = canRecover ? '检测到可恢复的密码库' : '密码库需要修复';
    final detail = controller.message ??
        (canRecover
            ? '已验证备份副本。恢复前不会覆盖当前文件。'
            : '无法安全打开本地密码库。为防止覆盖数据，创建和解锁已被禁用。');
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: _FrostedSurface(
          sigma: 24,
          padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.warning_amber_rounded, size: 34),
              const SizedBox(height: 12),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
              ),
              const SizedBox(height: 8),
              Text(detail, textAlign: TextAlign.center),
              if (canRecover) ...[
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: controller.recoverVault,
                  icon: const Icon(Icons.settings_backup_restore_rounded),
                  label: const Text('从验证过的副本恢复'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

enum _VaultTab {
  passwords,
  add,
  importVault,
  exportVault,
  pairing,
  settings,
}

extension on _VaultTab {
  String get label => switch (this) {
        _VaultTab.passwords => '密码',
        _VaultTab.add => '新增',
        _VaultTab.importVault => '导入',
        _VaultTab.exportVault => '导出',
        _VaultTab.pairing => '配对同步',
        _VaultTab.settings => '设置',
      };

  IconData get icon => switch (this) {
        _VaultTab.passwords => Icons.lock_outline_rounded,
        _VaultTab.add => Icons.add_circle_outline_rounded,
        _VaultTab.importVault => Icons.download_rounded,
        _VaultTab.exportVault => Icons.upload_file_rounded,
        _VaultTab.pairing => Icons.sync_rounded,
        _VaultTab.settings => Icons.settings_rounded,
      };
}

class _VaultView extends StatefulWidget {
  const _VaultView({
    super.key,
    required this.controller,
    required this.searchController,
    required this.searchFocusNode,
    required this.isSearchFocused,
    required this.scrollController,
    required this.searchQuery,
    required this.sortMode,
    required this.onSearchChanged,
    required this.onSortModeChanged,
  });

  final VaultController controller;
  final TextEditingController searchController;
  final FocusNode searchFocusNode;
  final bool isSearchFocused;
  final ScrollController scrollController;
  final String searchQuery;
  final _SortMode sortMode;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<_SortMode> onSortModeChanged;

  @override
  State<_VaultView> createState() => _VaultViewState();
}

class _VaultViewState extends State<_VaultView> {
  _VaultTab _tab = _VaultTab.passwords;
  String? _selectedCategoryId;
  final TextEditingController _addTitleController = TextEditingController();
  final TextEditingController _addUsernameController = TextEditingController();
  final TextEditingController _addPasswordController = TextEditingController();
  final TextEditingController _addUrlController = TextEditingController();
  final TextEditingController _addNotesController = TextEditingController();
  final TextEditingController _importPasswordController =
      TextEditingController();
  final TextEditingController _exportPasswordController =
      TextEditingController();
  final TextEditingController _oldPasswordController = TextEditingController();
  final TextEditingController _newPasswordController = TextEditingController();

  ImportPlan? _pendingImportPlan;
  ImportMergeSummary? _importSummary;
  bool _addPasswordObscured = true;
  String? _addSelectedCategoryId;

  @override
  void dispose() {
    _addTitleController.dispose();
    _addUsernameController.dispose();
    _addPasswordController.dispose();
    _addUrlController.dispose();
    _addNotesController.dispose();
    _importPasswordController.dispose();
    _exportPasswordController.dispose();
    _oldPasswordController.dispose();
    _newPasswordController.dispose();
    super.dispose();
  }

  void showAddItem() {
    setState(() {
      _tab = _VaultTab.add;
      _addPasswordObscured = true;
    });
  }

  void clearSensitiveInputs() {
    _addTitleController.clear();
    _addUsernameController.clear();
    _addPasswordController.clear();
    _addUrlController.clear();
    _addNotesController.clear();
    _importPasswordController.clear();
    _exportPasswordController.clear();
    _oldPasswordController.clear();
    _newPasswordController.clear();
    setState(() {
      _addPasswordObscured = true;
      _pendingImportPlan = null;
      _importSummary = null;
    });
  }

  void showPasswords() {
    if (_tab == _VaultTab.passwords) {
      return;
    }
    setState(() {
      _tab = _VaultTab.passwords;
    });
  }

  @override
  Widget build(BuildContext context) {
    final keyboardVisible = MediaQuery.viewInsetsOf(context).bottom > 0;
    final viewportWidth = MediaQuery.sizeOf(context).width;
    final platform = Theme.of(context).platform;
    final isDesktopPlatform = platform == TargetPlatform.windows ||
        platform == TargetPlatform.macOS ||
        platform == TargetPlatform.linux;
    final items = widget.controller.vaultData.activeItems.where((item) {
      if (widget.searchQuery.isEmpty) {
        return true;
      }
      final haystack = [
        item.title,
        item.username,
        item.url,
        item.notes,
        item.folder,
        item.tags.join(' '),
      ].join(' ').toLowerCase();
      return haystack.contains(widget.searchQuery);
    }).toList()
      ..sort((a, b) {
        if (widget.sortMode == _SortMode.alphabetical) {
          return a.title.toLowerCase().compareTo(b.title.toLowerCase());
        }
        final byUpdatedAt = b.updatedAt.compareTo(a.updatedAt);
        if (byUpdatedAt != 0) {
          return byUpdatedAt;
        }
        return a.title.toLowerCase().compareTo(b.title.toLowerCase());
      });

    if (isDesktopPlatform) {
      return LayoutBuilder(
          builder: (context, constraints) => Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _DesktopSidebar(
                    key: const ValueKey('liquid-dock'),
                    activeTab: _tab,
                    compact: constraints.maxWidth < 700,
                    onTabChanged: (tab) {
                      _glassPerfBus.pulse(heavy: true);
                      setState(() {
                        _tab = tab;
                        if (tab == _VaultTab.add) {
                          _addPasswordObscured = true;
                        }
                      });
                    },
                    onLock: widget.controller.lock,
                  ),
                  const SizedBox(width: 1),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _DesktopHeader(
                            tab: _tab,
                            itemCount: items.length,
                            searchController: widget.searchController,
                            searchFocusNode: widget.searchFocusNode,
                            sortMode: widget.sortMode,
                            onSearchChanged: (value) {
                              _glassPerfBus.pulse();
                              widget.onSearchChanged(value);
                            },
                            onClearSearch: () {
                              widget.searchController.clear();
                              widget.onSearchChanged('');
                            },
                            onSortModeChanged: widget.onSortModeChanged,
                          ),
                          const SizedBox(height: 12),
                          Expanded(
                            child: _tab == _VaultTab.passwords
                                ? _buildFilteredPasswordsPage(items, true)
                                : Align(
                                    alignment: Alignment.topLeft,
                                    child: ConstrainedBox(
                                      constraints:
                                          const BoxConstraints(maxWidth: 680),
                                      child: _buildActionPage(context),
                                    ),
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ));
    }

    final shouldHideDock = keyboardVisible ||
        (!isDesktopPlatform &&
            widget.isSearchFocused &&
            _tab == _VaultTab.passwords);
    final dockMaxWidth = double.infinity;
    return Stack(
      children: [
        Positioned.fill(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (isDesktopPlatform && _tab == _VaultTab.passwords)
                Padding(
                  key: const ValueKey('vault-header'),
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        '共 ${items.length} 条',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: const Color(0xA54A373F),
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.2,
                            ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: '立即锁定 (Ctrl+L)',
                        onPressed: () => widget.controller.lock(),
                        icon: const Icon(Icons.lock_rounded),
                      ),
                    ],
                  ),
                ),
              if (_tab == _VaultTab.passwords)
                _SearchField(
                  key: const ValueKey('vault-toolbar'),
                  controller: widget.searchController,
                  focusNode: widget.searchFocusNode,
                  onChanged: (value) {
                    _glassPerfBus.pulse();
                    widget.onSearchChanged(value);
                  },
                  sortMode: widget.sortMode,
                  onClear: () {
                    widget.searchController.clear();
                    _glassPerfBus.pulse();
                    widget.onSearchChanged('');
                  },
                  onSortModeChanged: (value) {
                    _glassPerfBus.pulse();
                    widget.onSortModeChanged(value);
                  },
                )
              else
                _ActionPageTitle(
                  title: _tab.label,
                  subtitle: '切换到页面模式，操作不再使用弹出框',
                ),
              const SizedBox(height: 8),
              Expanded(
                child: _tab == _VaultTab.passwords
                    ? _buildFilteredPasswordsPage(items, isDesktopPlatform)
                    : _buildActionPage(context),
              ),
            ],
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: SafeArea(
            top: false,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: dockMaxWidth.clamp(0, viewportWidth).toDouble(),
                ),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  transitionBuilder: (child, animation) {
                    return SizeTransition(
                      sizeFactor: animation,
                      alignment: Alignment.bottomCenter,
                      child: FadeTransition(opacity: animation, child: child),
                    );
                  },
                  child: shouldHideDock
                      ? const SizedBox.shrink(
                          key: ValueKey('liquid-dock-hidden'))
                      : _BottomActionDock(
                          key: const ValueKey('liquid-dock'),
                          activeIndex: _tab.index,
                          onIndexChanged: (index) {
                            _glassPerfBus.pulse(heavy: true);
                            final tab = _VaultTab.values[index];
                            setState(() {
                              _tab = tab;
                              if (tab == _VaultTab.add) {
                                _addPasswordObscured = true;
                              }
                            });
                          },
                        ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFilteredPasswordsPage(
    List<VaultItem> allFilteredItems,
    bool isDesktopPlatform,
  ) {
    final items = allFilteredItems.where((item) {
      if (_selectedCategoryId == null) {
        return true;
      }
      if (_selectedCategoryId!.isEmpty) {
        return item.folder.isEmpty;
      }
      return item.folder == _selectedCategoryId;
    }).toList();
    return _buildPasswordsPage(items, isDesktopPlatform);
  }

  Widget _buildPasswordsPage(List<VaultItem> items, bool isDesktopPlatform) {
    if (items.isEmpty) {
      return _FrostedSurface(
        key: const ValueKey('vault-empty'),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 22),
        child: Center(
          child: Text(
            widget.searchQuery.isEmpty ? '还没有条目' : '没有匹配条目',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
      );
    }
    final categories = widget.controller.vaultData.categories.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollStartNotification ||
            notification is ScrollUpdateNotification ||
            notification is UserScrollNotification) {
          _glassPerfBus.pulse(heavy: true);
        } else if (notification is ScrollEndNotification) {
          _glassPerfBus.pulse();
        }
        return false;
      },
      child: isDesktopPlatform
          ? LayoutBuilder(
              builder: (context, constraints) {
                final showCategorySidebar = constraints.maxWidth >= 700;
                final vaultList = ListView.separated(
                  key: const ValueKey('vault-list'),
                  controller: widget.scrollController,
                  separatorBuilder: (_, __) => const SizedBox(height: 4),
                  itemCount: items.length,
                  padding: const EdgeInsets.only(
                    bottom: 16,
                    right: 4,
                  ),
                  itemBuilder: (context, index) {
                    final item = items[index];
                    final accountInfo = [
                      item.username.trim(),
                      item.url.trim(),
                    ].where((part) => part.isNotEmpty).join(' · ');
                    final entryCard = _EntryCard(
                      item: item,
                      accountInfo: accountInfo,
                      isDesktop: true,
                      onView: () => _showItemDetails(
                        context,
                        controller: widget.controller,
                        item: item,
                      ),
                      onCopy: () => widget.controller.copySecret(item.password),
                      onEdit: () => _showItemEditor(
                        context,
                        controller: widget.controller,
                        item: item,
                      ),
                      onDelete: () => _confirmDeleteItem(
                        context,
                        controller: widget.controller,
                        item: item,
                      ),
                    );
                    if (!showCategorySidebar) {
                      return RepaintBoundary(child: entryCard);
                    }
                    return RepaintBoundary(
                      child: Draggable<VaultItem>(
                        data: item,
                        dragAnchorStrategy: pointerDragAnchorStrategy,
                        feedback: _DraggedEntryCard(
                          item: item,
                          accountInfo: accountInfo,
                        ),
                        childWhenDragging: Opacity(
                          opacity: 0.45,
                          child: _EntryCard(
                            item: item,
                            accountInfo: accountInfo,
                            isDesktop: true,
                            onView: () {},
                            onCopy: () {},
                            onEdit: () {},
                            onDelete: () {},
                          ),
                        ),
                        child: entryCard,
                      ),
                    );
                  },
                );
                if (!showCategorySidebar) {
                  return vaultList;
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _DesktopCategorySidebar(
                      categories: categories,
                      categoryCounts: {
                        for (final category in categories)
                          category.id: widget.controller.vaultData.activeItems
                              .where((item) => item.folder == category.id)
                              .length,
                      },
                      selectedCategoryId: _selectedCategoryId,
                      totalCount:
                          widget.controller.vaultData.activeItems.length,
                      uncategorizedCount: widget
                          .controller.vaultData.activeItems
                          .where((item) => item.folder.isEmpty)
                          .length,
                      onSelected: (categoryId) {
                        _glassPerfBus.pulse(heavy: true);
                        setState(() {
                          _selectedCategoryId = categoryId;
                        });
                      },
                      onCategoryDropped: (categoryId, itemId) {
                        widget.controller.assignItemToCategory(
                          itemId: itemId,
                          categoryId: categoryId,
                        );
                      },
                      onCategoryAdded: (name) =>
                          widget.controller.addCategory(name),
                      onCategoryRenamed: (categoryId, name) =>
                          widget.controller.renameCategory(
                        categoryId: categoryId,
                        name: name,
                      ),
                      onCategoryDeleted: widget.controller.deleteCategory,
                    ),
                    const SizedBox(width: 16),
                    Expanded(child: vaultList),
                  ],
                );
              },
            )
          : ListView.separated(
              key: const ValueKey('vault-list'),
              controller: widget.scrollController,
              itemCount: items.length,
              padding: const EdgeInsets.fromLTRB(0, 0, 0, 116),
              separatorBuilder: (_, __) => const SizedBox(height: 7),
              itemBuilder: (context, index) {
                final item = items[index];
                final accountInfo = [
                  item.username.trim(),
                  item.url.trim(),
                ].where((part) => part.isNotEmpty).join(' · ');
                return RepaintBoundary(
                  child: _EntryCard(
                    item: item,
                    accountInfo: accountInfo,
                    isDesktop: false,
                    onView: () => _showItemDetails(
                      context,
                      controller: widget.controller,
                      item: item,
                    ),
                    onCopy: () => widget.controller.copySecret(item.password),
                    onEdit: () => _showItemEditor(
                      context,
                      controller: widget.controller,
                      item: item,
                    ),
                    onDelete: () => _confirmDeleteItem(
                      context,
                      controller: widget.controller,
                      item: item,
                    ),
                  ),
                );
              },
            ),
    );
  }

  Widget _buildActionPage(BuildContext context) {
    switch (_tab) {
      case _VaultTab.add:
        return _buildAddPage();
      case _VaultTab.importVault:
        return _buildImportPage();
      case _VaultTab.exportVault:
        return _buildExportPage();
      case _VaultTab.pairing:
        return _buildPairingPage();
      case _VaultTab.settings:
        return _buildSettingsPage();
      case _VaultTab.passwords:
        return const SizedBox.shrink();
    }
  }

  Widget _buildAddPage() {
    return _FrostedSurface(
      key: const ValueKey('vault-page-add'),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      child: SingleChildScrollView(
        child: Column(
          children: [
            TextField(
              controller: _addTitleController,
              decoration: const InputDecoration(labelText: '名称'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _addUsernameController,
              decoration: const InputDecoration(labelText: '账号'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _addPasswordController,
              obscureText: _addPasswordObscured,
              enableSuggestions: false,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: '密码',
                suffixIcon: IconButton(
                  tooltip: _addPasswordObscured ? '显示密码' : '隐藏密码',
                  onPressed: () {
                    setState(() {
                      _addPasswordObscured = !_addPasswordObscured;
                    });
                  },
                  icon: Icon(
                    _addPasswordObscured
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            _PasswordGeneratorControl(
              controller: widget.controller,
              onGenerated: (password) => _addPasswordController.text = password,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _addUrlController,
              decoration: const InputDecoration(labelText: '网址'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _addNotesController,
              maxLines: 4,
              decoration: const InputDecoration(labelText: '备注'),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: _addSelectedCategoryId,
              decoration: const InputDecoration(labelText: '分类'),
              items: [
                const DropdownMenuItem(
                  value: '',
                  child: Text('无分类'),
                ),
                for (final category in widget.controller.vaultData.categories)
                  DropdownMenuItem(
                    value: category.id,
                    child: Text(category.name),
                  ),
              ],
              onChanged: (value) {
                setState(() {
                  _addSelectedCategoryId =
                      value == null || value.isEmpty ? null : value;
                });
              },
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: widget.controller.busy
                    ? null
                    : () async {
                        final result = await widget.controller.addOrUpdateItem(
                          title: _addTitleController.text,
                          username: _addUsernameController.text,
                          password: _addPasswordController.text,
                          url: _addUrlController.text,
                          notes: _addNotesController.text,
                          tags: const [],
                          categoryId: _addSelectedCategoryId,
                        );
                        if (!mounted || !result.succeeded) {
                          return;
                        }
                        _glassPerfBus.pulse(heavy: true);
                        setState(() {
                          _addPasswordObscured = true;
                        });
                        _addTitleController.clear();
                        _addUsernameController.clear();
                        _addPasswordController.clear();
                        _addUrlController.clear();
                        _addNotesController.clear();
                        _addSelectedCategoryId = null;
                      },
                icon: const Icon(Icons.check_rounded),
                label: const Text('保存条目'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImportPage() {
    return _FrostedSurface(
      key: const ValueKey('vault-page-import'),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _importPasswordController,
            obscureText: true,
            decoration: const InputDecoration(labelText: '导入文件密码'),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: widget.controller.busy
                      ? null
                      : () async {
                          final plan = await widget.controller
                              .previewImport(_importPasswordController.text);
                          if (!mounted || plan == null) {
                            return;
                          }
                          setState(() {
                            _pendingImportPlan = plan;
                            _importSummary = plan.summary;
                          });
                        },
                  icon: const Icon(Icons.search_rounded),
                  label: const Text('预览导入'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  onPressed:
                      (_pendingImportPlan == null || widget.controller.busy)
                          ? null
                          : () async {
                              final result =
                                  await widget.controller.applyImportPlan(
                                _pendingImportPlan!,
                              );
                              if (!mounted || !result.succeeded) {
                                return;
                              }
                              setState(() {
                                _pendingImportPlan = null;
                                _importSummary = null;
                              });
                            },
                  icon: const Icon(Icons.download_done_rounded),
                  label: const Text('确认导入'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: widget.controller.busy
                ? null
                : () => _showLanSyncDialog(
                      context,
                      controller: widget.controller,
                    ),
            icon: const Icon(Icons.wifi_tethering_rounded),
            label: const Text('设备配对与同步'),
          ),
          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 14),
          Text(
            '从 Bitwarden 导入',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          Text(
            '支持未加密 JSON 和 CSV。导入前会列出重复候选，是否合并由你确认。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: widget.controller.busy
                ? null
                : () => _startBitwardenImport(
                      context,
                      widget.controller,
                    ),
            icon: const Icon(Icons.compare_arrows_rounded),
            label: const Text('选择 Bitwarden 文件并核验'),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _importSummary == null
                ? const Center(child: Text('先点击“预览导入”，再确认导入'))
                : _ImportSummaryView(summary: _importSummary!),
          ),
        ],
      ),
    );
  }

  Widget _buildExportPage() {
    return _FrostedSurface(
      key: const ValueKey('vault-page-export'),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _exportPasswordController,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: '导出密码（可选）',
              helperText: '留空表示沿用当前密码库加密',
            ),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: widget.controller.busy
                ? null
                : () => widget.controller.exportVault(
                      exportPassword: _exportPasswordController.text,
                    ),
            icon: const Icon(Icons.upload_rounded),
            label: const Text('导出加密备份'),
          ),
          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 14),
          Text(
            '导出到 Bitwarden',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          Text(
            '交换文件包含明文凭据。建议导入 Bitwarden 后立即删除。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: widget.controller.busy
                    ? null
                    : () => _exportToBitwarden(
                          context,
                          widget.controller,
                          BitwardenExchangeFormat.json,
                        ),
                icon: const Icon(Icons.data_object_rounded),
                label: const Text('导出 JSON'),
              ),
              OutlinedButton.icon(
                onPressed: widget.controller.busy
                    ? null
                    : () => _exportToBitwarden(
                          context,
                          widget.controller,
                          BitwardenExchangeFormat.csv,
                        ),
                icon: const Icon(Icons.table_rows_rounded),
                label: const Text('导出 CSV'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: widget.controller.busy
                ? null
                : () => _startBitwardenDeltaExport(
                      context,
                      widget.controller,
                    ),
            icon: const Icon(Icons.rule_rounded),
            label: const Text('核对 Bitwarden 并导出缺失项'),
          ),
          const SizedBox(height: 4),
          Text(
            '先选择 Bitwarden 最新导出作为基线，只导出 Bitwarden 中不存在的本机条目。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (Theme.of(context).platform == TargetPlatform.android) ...[
            const SizedBox(height: 10),
            Text(
              '导出时会弹出文件选择器页面，导出完成后会给出消息提示。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPairingPage() {
    final isAndroid = Theme.of(context).platform == TargetPlatform.android;
    return _FrostedSurface(
      key: const ValueKey('vault-page-pairing'),
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isAndroid ? '在局域网中发现并同步设备' : '设备连接同一局域网并保持解锁，使用共同主密码合并。',
            style: isAndroid
                ? Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800)
                : Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 8),
          if (isAndroid) ...[
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Text(
                '配对后使用同一个主密码共享密码库。设备只在当前局域网内通信，数据仍以加密文件传输。',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFF667085),
                    ),
              ),
            ),
            const SizedBox(height: 14),
          ],
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: widget.controller.busy
                ? null
                : () => _showLanSyncDialog(
                      context,
                      controller: widget.controller,
                    ),
            icon: const Icon(Icons.sync_rounded),
            label: Text(isAndroid ? '打开设备配对' : '设备同步'),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsPage() {
    final enabled = widget.controller.quickUnlockEnabled;
    final supported = widget.controller.quickUnlockSupported;
    return _FrostedSurface(
      key: const ValueKey('vault-page-settings'),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _oldPasswordController,
              obscureText: true,
              decoration: const InputDecoration(labelText: '当前主密码'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _newPasswordController,
              obscureText: true,
              decoration: const InputDecoration(labelText: '新主密码'),
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: widget.controller.busy
                  ? null
                  : () async {
                      final result =
                          await widget.controller.changeMasterPassword(
                        oldPassword: _oldPasswordController.text,
                        newPassword: _newPasswordController.text,
                      );
                      if (mounted && result.succeeded) {
                        _oldPasswordController.clear();
                        _newPasswordController.clear();
                      }
                    },
              icon: const Icon(Icons.key_rounded),
              label: const Text('修改主密码'),
            ),
            const SizedBox(height: 14),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: enabled,
              onChanged: !supported || widget.controller.busy
                  ? null
                  : (value) async {
                      if (value) {
                        await widget.controller.enableQuickUnlock();
                      } else {
                        await widget.controller.disableQuickUnlock();
                      }
                      if (mounted) {
                        setState(() {});
                      }
                    },
              title: const Text('快速解锁'),
              subtitle: Text(
                supported ? '使用系统认证保护会话密钥' : '当前设备不支持',
              ),
            ),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: widget.controller.allowQuickUnlockOnFirstLaunch,
              onChanged: !supported || !enabled || widget.controller.busy
                  ? null
                  : (value) async {
                      await widget.controller
                          .setAllowQuickUnlockOnFirstLaunch(value);
                      if (mounted) {
                        setState(() {});
                      }
                    },
              title: const Text('冷启动直接快速解锁'),
              subtitle: Text(
                !supported
                    ? '当前设备不支持快速解锁'
                    : !enabled
                        ? '请先开启快速解锁'
                        : '启动应用后可直接使用系统认证，无需先输入一次主密码',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionPageTitle extends StatelessWidget {
  const _ActionPageTitle({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return _FrostedSurface(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      borderRadius: BorderRadius.circular(8),
      child: Row(
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              subtitle,
              style: Theme.of(context).textTheme.bodySmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _DesktopSidebar extends StatelessWidget {
  const _DesktopSidebar({
    super.key,
    required this.activeTab,
    required this.compact,
    required this.onTabChanged,
    required this.onLock,
  });

  final _VaultTab activeTab;
  final bool compact;
  final ValueChanged<_VaultTab> onTabChanged;
  final VoidCallback onLock;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: compact ? 64 : 200,
      color: const Color(0xFFFFFFFF),
      padding: EdgeInsets.fromLTRB(compact ? 8 : 12, 16, compact ? 8 : 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.lock_rounded,
                  size: 18,
                  color: Colors.white,
                ),
              ),
              if (!compact) const SizedBox(width: 10),
              if (!compact)
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Cipherbook',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.1,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 20),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                for (final tab in _VaultTab.values)
                  _DesktopSidebarItem(
                    tab: tab,
                    active: tab == activeTab,
                    compact: compact,
                    onTap: () => onTabChanged(tab),
                  ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFE7E9EE)),
          const SizedBox(height: 10),
          Align(
            alignment: compact ? Alignment.center : Alignment.centerLeft,
            child: Tooltip(
              message: '立即锁定 (Ctrl+L)',
              child: TextButton.icon(
                onPressed: onLock,
                icon: const Icon(Icons.lock_outline_rounded, size: 18),
                label: compact ? const SizedBox.shrink() : const Text('锁定'),
                style: TextButton.styleFrom(padding: const EdgeInsets.all(10)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DesktopSidebarItem extends StatelessWidget {
  const _DesktopSidebarItem({
    required this.tab,
    required this.active,
    required this.compact,
    required this.onTap,
  });

  final _VaultTab tab;
  final bool active;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = active
        ? Theme.of(context).colorScheme.primary
        : const Color(0xFF667085);
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Tooltip(
        message: compact ? tab.label : '',
        child: Material(
          color: active
              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.09)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
          child: InkWell(
            borderRadius: BorderRadius.circular(7),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              child: Row(
                children: [
                  Icon(tab.icon, size: 18, color: color),
                  if (!compact) const SizedBox(width: 10),
                  if (!compact)
                    Expanded(
                      child: Text(
                        tab.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: active ? color : const Color(0xFF475467),
                          fontSize: 13,
                          fontWeight:
                              active ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DesktopCategorySidebar extends StatelessWidget {
  const _DesktopCategorySidebar({
    required this.categories,
    required this.categoryCounts,
    required this.selectedCategoryId,
    required this.totalCount,
    required this.uncategorizedCount,
    required this.onSelected,
    required this.onCategoryDropped,
    required this.onCategoryAdded,
    required this.onCategoryRenamed,
    required this.onCategoryDeleted,
  });

  final List<VaultCategory> categories;
  final Map<String, int> categoryCounts;
  final String? selectedCategoryId;
  final int totalCount;
  final int uncategorizedCount;
  final ValueChanged<String?> onSelected;
  final void Function(String categoryId, String itemId) onCategoryDropped;
  final Future<VaultOperationResult> Function(String name) onCategoryAdded;
  final Future<VaultOperationResult> Function(String categoryId, String name)
      onCategoryRenamed;
  final Future<VaultOperationResult> Function(String categoryId)
      onCategoryDeleted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 190,
      child: Column(
        key: const ValueKey('desktop-category-sidebar'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '分类',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                key: const ValueKey('desktop-category-add'),
                tooltip: '新建分类',
                onPressed: () => _showCategoryNameDialog(
                  context,
                  title: '新建分类',
                  onSubmit: onCategoryAdded,
                ),
                icon: const Icon(Icons.add_rounded, size: 18),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 16),
              children: [
                _CategoryDropTile(
                  key: const ValueKey('desktop-category-all'),
                  label: '全部密码',
                  count: totalCount,
                  icon: Icons.all_inbox_rounded,
                  active: selectedCategoryId == null,
                  onTap: () => onSelected(null),
                ),
                _CategoryDropTile(
                  key: const ValueKey('desktop-category-uncategorized'),
                  label: '未分类',
                  count: uncategorizedCount,
                  icon: Icons.inbox_outlined,
                  active: selectedCategoryId == '',
                  onTap: () => onSelected(''),
                  onItemDropped: (itemId) => onCategoryDropped('', itemId),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Divider(height: 1),
                ),
                for (final category in categories)
                  _CategoryDropTile(
                    key: ValueKey('desktop-category-${category.id}'),
                    label: category.name,
                    count: categoryCounts[category.id] ?? 0,
                    icon: Icons.folder_outlined,
                    active: selectedCategoryId == category.id,
                    onTap: () => onSelected(category.id),
                    onItemDropped: (itemId) =>
                        onCategoryDropped(category.id, itemId),
                    onRename: () => _showCategoryNameDialog(
                      context,
                      title: '重命名分类',
                      initialName: category.name,
                      onSubmit: (name) => onCategoryRenamed(category.id, name),
                    ),
                    onDelete: () async {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (dialogContext) => AlertDialog(
                          title: const Text('删除分类？'),
                          content: Text(
                            '“${category.name}”中的密码会移回未分类，密码不会删除。',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () =>
                                  Navigator.of(dialogContext).pop(false),
                              child: const Text('取消'),
                            ),
                            FilledButton(
                              onPressed: () =>
                                  Navigator.of(dialogContext).pop(true),
                              child: const Text('删除分类'),
                            ),
                          ],
                        ),
                      );
                      if (confirmed == true) {
                        await onCategoryDeleted(category.id);
                        onSelected(selectedCategoryId == category.id
                            ? null
                            : selectedCategoryId);
                      }
                    },
                  ),
              ],
            ),
          ),
          Text(
            '拖动密码到分类即可归组',
            style: theme.textTheme.bodySmall?.copyWith(
              color: const Color(0xFF98A2B3),
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryDropTile extends StatefulWidget {
  const _CategoryDropTile({
    super.key,
    required this.label,
    required this.count,
    required this.icon,
    required this.active,
    required this.onTap,
    this.onItemDropped,
    this.onRename,
    this.onDelete,
  });

  final String label;
  final int count;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;
  final ValueChanged<String>? onItemDropped;
  final VoidCallback? onRename;
  final VoidCallback? onDelete;

  @override
  State<_CategoryDropTile> createState() => _CategoryDropTileState();
}

class _CategoryDropTileState extends State<_CategoryDropTile> {
  bool _hovering = false;
  bool _dragging = false;

  Widget _buildTile() {
    final theme = Theme.of(context);
    final activeColor = theme.colorScheme.primary;
    final color = widget.active ? activeColor : const Color(0xFF475467);
    return Container(
      decoration: BoxDecoration(
        color: _dragging
            ? theme.colorScheme.primaryContainer
            : (widget.active
                ? activeColor.withValues(alpha: 0.08)
                : Colors.transparent),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(
          color: _dragging ? activeColor : Colors.transparent,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(7),
          onTap: widget.onTap,
          onHover: (value) {
            if (_hovering != value) {
              setState(() {
                _hovering = value;
              });
            }
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
            child: Row(
              children: [
                Icon(widget.icon, size: 17, color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: color,
                      fontSize: 13,
                      fontWeight:
                          widget.active ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
                if (widget.onRename != null || widget.onDelete != null)
                  if (_hovering)
                    PopupMenuButton<String>(
                      tooltip: '分类操作',
                      icon: const Icon(Icons.more_horiz_rounded, size: 17),
                      onSelected: (action) {
                        if (action == 'rename') widget.onRename?.call();
                        if (action == 'delete') widget.onDelete?.call();
                      },
                      itemBuilder: (context) => const [
                        PopupMenuItem(
                          value: 'rename',
                          child: Text('重命名'),
                        ),
                        PopupMenuItem(
                          value: 'delete',
                          child: Text('删除分类'),
                        ),
                      ],
                    )
                  else
                    Text(
                      '${widget.count}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF98A2B3),
                      ),
                    )
                else
                  Text(
                    '${widget.count}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: const Color(0xFF98A2B3),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dropTarget = DragTarget<VaultItem>(
      onWillAcceptWithDetails: (_) => widget.onItemDropped != null,
      onAcceptWithDetails: (details) =>
          widget.onItemDropped?.call(details.data.id),
      onMove: (_) {
        if (!_dragging) {
          setState(() {
            _dragging = true;
          });
        }
      },
      onLeave: (_) {
        if (_dragging) {
          setState(() {
            _dragging = false;
          });
        }
      },
      builder: (context, candidateData, rejectedData) => _buildTile(),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: dropTarget,
    );
  }
}

Future<void> _showCategoryNameDialog(
  BuildContext context, {
  required String title,
  required Future<VaultOperationResult> Function(String name) onSubmit,
  String initialName = '',
}) async {
  await showDialog<bool>(
    context: context,
    builder: (_) => _CategoryNameDialog(
      title: title,
      initialName: initialName,
      onSubmit: onSubmit,
    ),
  );
}

class _CategoryNameDialog extends StatefulWidget {
  const _CategoryNameDialog({
    required this.title,
    required this.initialName,
    required this.onSubmit,
  });

  final String title;
  final String initialName;
  final Future<VaultOperationResult> Function(String name) onSubmit;

  @override
  State<_CategoryNameDialog> createState() => _CategoryNameDialogState();
}

class _CategoryNameDialogState extends State<_CategoryNameDialog> {
  late final TextEditingController _nameController;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_saving) {
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final result = await widget.onSubmit(_nameController.text);
    if (!mounted) {
      return;
    }
    if (result.succeeded) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _saving = false;
      _error = result.error?.toString();
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        key: const ValueKey('category-name-field'),
        autofocus: true,
        controller: _nameController,
        maxLength: maxVaultTagLength,
        decoration: InputDecoration(
          labelText: '分类名称',
          errorText: _error,
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _saving ? null : _submit,
          child: Text(_saving ? '保存中…' : '保存'),
        ),
      ],
    );
  }
}

class _DesktopHeader extends StatelessWidget {
  const _DesktopHeader({
    required this.tab,
    required this.itemCount,
    required this.searchController,
    required this.searchFocusNode,
    required this.sortMode,
    required this.onSearchChanged,
    required this.onClearSearch,
    required this.onSortModeChanged,
  });

  final _VaultTab tab;
  final int itemCount;
  final TextEditingController searchController;
  final FocusNode searchFocusNode;
  final _SortMode sortMode;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onClearSearch;
  final ValueChanged<_SortMode> onSortModeChanged;

  String get subtitle => switch (tab) {
        _VaultTab.passwords => '$itemCount 条记录',
        _ => '',
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final title = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tab == _VaultTab.passwords ? '密码库' : tab.label,
              style: theme.textTheme.titleLarge?.copyWith(
                color: const Color(0xFF101828),
                fontWeight: FontWeight.w700,
              ),
            ),
            if (subtitle.isNotEmpty) ...[
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF667085),
                ),
              ),
            ],
          ],
        );

        if (tab != _VaultTab.passwords) {
          return Padding(
            key: const ValueKey('vault-header'),
            padding: const EdgeInsets.only(bottom: 1),
            child: title,
          );
        }

        final toolbar = SizedBox(
          width: constraints.maxWidth < 520 ? constraints.maxWidth : 360,
          child: _SearchField(
            key: const ValueKey('vault-toolbar'),
            controller: searchController,
            focusNode: searchFocusNode,
            onChanged: onSearchChanged,
            sortMode: sortMode,
            onClear: onClearSearch,
            onSortModeChanged: onSortModeChanged,
          ),
        );

        if (constraints.maxWidth < 520) {
          return Column(
            key: const ValueKey('vault-header'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              title,
              const SizedBox(height: 12),
              toolbar,
            ],
          );
        }

        return Row(
          key: const ValueKey('vault-header'),
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(child: title),
            const SizedBox(width: 20),
            toolbar,
          ],
        );
      },
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.sortMode,
    required this.onClear,
    required this.onSortModeChanged,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final _SortMode sortMode;
  final VoidCallback onClear;
  final ValueChanged<_SortMode> onSortModeChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _FrostedSurface(
            sigma: 16,
            borderRadius: BorderRadius.circular(8),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            tint: const Color(0x20FFFFFF),
            borderColor: const Color(0xFFD9DEE5),
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              onChanged: onChanged,
              onTapOutside: (_) => focusNode.unfocus(),
              onSubmitted: (_) => focusNode.unfocus(),
              decoration: InputDecoration(
                filled: false,
                fillColor: Colors.transparent,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                prefixIcon: const Icon(Icons.search_rounded),
                hintText: '\u641c\u7d22\u6761\u76ee',
                hintStyle: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF98A2B3),
                ),
                suffixIcon: controller.text.isEmpty
                    ? null
                    : IconButton(
                        onPressed: onClear,
                        icon: const Icon(Icons.close_rounded),
                        tooltip: '\u6e05\u7a7a\u641c\u7d22',
                      ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 11,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        _SortPill(
          mode: sortMode,
          onChanged: onSortModeChanged,
        ),
      ],
    );
  }
}

class _SortPill extends StatelessWidget {
  const _SortPill({
    required this.mode,
    required this.onChanged,
  });

  final _SortMode mode;
  final ValueChanged<_SortMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return _FrostedSurface(
      sigma: 16,
      borderRadius: BorderRadius.circular(8),
      padding: EdgeInsets.zero,
      tint: const Color(0x20FFFFFF),
      borderColor: const Color(0xFFD9DEE5),
      child: Tooltip(
        message: '排序方式',
        child: Semantics(
          button: true,
          label: '排序方式',
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () async {
                _glassPerfBus.pulse();
                final next = await _showSortModePicker(context, mode);
                if (next != null) {
                  onChanged(next);
                }
              },
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      mode.shortLabel,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF475467),
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(
                      Icons.unfold_more_rounded,
                      size: 16,
                      color: Color(0xFF667085),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum _SortMode {
  recentlyUpdated('\u6700\u8fd1\u66f4\u65b0', '\u6700\u8fd1'),
  alphabetical('\u5b57\u6bcd\u6392\u5e8f', '\u5b57\u6bcd');

  const _SortMode(this.label, this.shortLabel);
  final String label;
  final String shortLabel;
}

Future<_SortMode?> _showSortModePicker(
  BuildContext context,
  _SortMode mode,
) {
  return showDialog<_SortMode>(
    context: context,
    builder: (context) {
      Widget option(_SortMode item) {
        final active = item == mode;
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: InkWell(
            borderRadius: BorderRadius.circular(7),
            onTap: () => Navigator.of(context).pop(item),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(7),
                color: active ? const Color(0xFFEFF8FF) : Colors.transparent,
                border: Border.all(
                  color: active
                      ? const Color(0xFFB2DDFF)
                      : const Color(0xFFE4E7EC),
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      item.label,
                      style: TextStyle(
                        fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                        color: const Color(0xFF344054),
                      ),
                    ),
                  ),
                  if (active)
                    const Icon(
                      Icons.check_rounded,
                      size: 18,
                      color: Color(0xFF175CD3),
                    ),
                ],
              ),
            ),
          ),
        );
      }

      return AlertDialog(
        title: const Text('排序方式'),
        contentPadding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            option(_SortMode.recentlyUpdated),
            option(_SortMode.alphabetical),
          ],
        ),
      );
    },
  );
}

class _BottomActionDock extends StatefulWidget {
  const _BottomActionDock({
    super.key,
    required this.activeIndex,
    required this.onIndexChanged,
  });

  final int activeIndex;
  final ValueChanged<int> onIndexChanged;

  @override
  State<_BottomActionDock> createState() => _BottomActionDockState();
}

class _BottomActionDockState extends State<_BottomActionDock>
    with SingleTickerProviderStateMixin {
  int _activeIndex = 0;
  int _fromIndex = 0;
  int _toIndex = 0;
  late final AnimationController _morphController;

  @override
  void initState() {
    super.initState();
    _activeIndex = widget.activeIndex;
    _fromIndex = widget.activeIndex;
    _toIndex = widget.activeIndex;
    _morphController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
  }

  @override
  void didUpdateWidget(covariant _BottomActionDock oldWidget) {
    super.didUpdateWidget(oldWidget);
    _activeIndex = widget.activeIndex;
  }

  @override
  void dispose() {
    _morphController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = _VaultTab.values;

    return _FrostedSurface(
      sigma: 20,
      borderRadius: BorderRadius.circular(10),
      padding: const EdgeInsets.fromLTRB(6, 6, 6, 5),
      tint: const Color(0x1FFFFFFF),
      borderColor: const Color(0xB2FFFFFF),
      shadowColor: const Color(0x2A291B21),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final slotWidth = constraints.maxWidth / items.length;
          final baseWidth = slotWidth - 6;
          return SizedBox(
            height: 58,
            child: Stack(
              children: [
                AnimatedBuilder(
                  animation: _morphController,
                  builder: (context, _) {
                    final t =
                        Curves.easeOutCubic.transform(_morphController.value);
                    final fromLeft = (slotWidth * _fromIndex) + 3;
                    final toLeft = (slotWidth * _toIndex) + 3;
                    final centerLeft = lerpDouble(
                          fromLeft + baseWidth / 2,
                          toLeft + baseWidth / 2,
                          t,
                        ) ??
                        (toLeft + baseWidth / 2);
                    final travel = (_toIndex - _fromIndex).abs().toDouble();
                    final unionWave = math.sin(math.pi * t);
                    final morphWidth = baseWidth +
                        (slotWidth * 0.24 * unionWave * (1 + travel * 0.15));
                    final highlightLeft = centerLeft - morphWidth / 2;

                    return Positioned(
                      left: highlightLeft,
                      top: 2,
                      bottom: 2,
                      width: morphWidth,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          color: Theme.of(context).colorScheme.primaryContainer,
                          border: Border.all(
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ),
                    );
                  },
                ),
                Row(
                  children: [
                    for (var i = 0; i < items.length; i++)
                      Expanded(
                        child: _DockActionButton(
                          icon: items[i].icon,
                          label: items[i].label,
                          active: i == _activeIndex,
                          onTap: () {
                            if (i != _activeIndex) {
                              _fromIndex = _activeIndex;
                              _toIndex = i;
                            } else {
                              _fromIndex = i;
                              _toIndex = i;
                            }
                            _glassPerfBus.pulse(heavy: true);
                            setState(() {
                              _activeIndex = i;
                            });
                            _morphController.forward(from: 0);
                            widget.onIndexChanged(i);
                          },
                        ),
                      ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _DockActionButton extends StatelessWidget {
  const _DockActionButton({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = active ? const Color(0xFF744B5A) : const Color(0xFF302127);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(26),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(height: 2),
              SizedBox(
                width: double.infinity,
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EntryCard extends StatefulWidget {
  const _EntryCard({
    required this.item,
    required this.accountInfo,
    required this.isDesktop,
    required this.onView,
    required this.onCopy,
    required this.onEdit,
    required this.onDelete,
  });

  final VaultItem item;
  final String accountInfo;
  final bool isDesktop;
  final VoidCallback onView;
  final VoidCallback onCopy;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  State<_EntryCard> createState() => _EntryCardState();
}

class _EntryCardState extends State<_EntryCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final desktopSpacing = widget.isDesktop;
    final title = widget.item.title.trim().isEmpty ? '未命名' : widget.item.title;
    final leadingText = title.isEmpty ? '•' : title[0].toUpperCase();
    final subtitleText = widget.accountInfo.isNotEmpty
        ? widget.accountInfo
        : (widget.item.notes.trim().isNotEmpty
            ? widget.item.notes.trim()
            : '点击查看详情');
    if (desktopSpacing) {
      final theme = Theme.of(context);
      return Material(
        color: _hovered ? const Color(0xFFF3F6FA) : Colors.white,
        borderRadius: BorderRadius.circular(6),
        child: MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: InkWell(
            onTap: widget.onView,
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: LayoutBuilder(builder: (context, constraints) {
                final actions = <(IconData, String, VoidCallback)>[
                  (Icons.visibility_outlined, '查看', widget.onView),
                  (Icons.copy_outlined, '复制密码', widget.onCopy),
                  (Icons.edit_outlined, '编辑', widget.onEdit),
                  (Icons.delete_outline, '删除', widget.onDelete),
                ];
                return Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(leadingText,
                          style: TextStyle(
                              color: theme.colorScheme.onPrimaryContainer,
                              fontWeight: FontWeight.w700)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleSmall),
                          if (widget.accountInfo.isNotEmpty)
                            Text(widget.accountInfo,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall),
                        ],
                      ),
                    ),
                    if (constraints.maxWidth < 340)
                      PopupMenuButton<int>(
                        tooltip: '条目操作',
                        icon: const Icon(Icons.more_vert),
                        onSelected: (index) => actions[index].$3(),
                        itemBuilder: (context) => [
                          for (var i = 0; i < actions.length; i++)
                            PopupMenuItem(value: i, child: Text(actions[i].$2)),
                        ],
                      )
                    else
                      for (final action in actions)
                        IconButton(
                          tooltip: action.$2,
                          onPressed: action.$3,
                          icon: Icon(action.$1, size: 18),
                          visualDensity: VisualDensity.compact,
                        ),
                  ],
                );
              }),
            ),
          ),
        ),
      );
    }
    final titleStyle = Theme.of(context).textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w900,
          fontSize: desktopSpacing ? 17 : 19,
          height: desktopSpacing ? 1.02 : 1.0,
          letterSpacing: -0.15,
          color: const Color(0xFF101828),
        );
    final accountStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
          fontWeight: FontWeight.w500,
          fontSize: desktopSpacing ? 11 : 12,
          color: const Color(0xFF667085),
        );

    final tint = desktopSpacing
        ? (_hovered ? const Color(0xFFF8FAFC) : const Color(0xFFFFFFFF))
        : (_hovered ? const Color(0x16F4EBEF) : const Color(0x10EFE4E8));
    final border = desktopSpacing
        ? (_hovered ? const Color(0xFFB2DDFF) : const Color(0xFFE4E7EC))
        : (_hovered ? const Color(0x8FEFE3E8) : const Color(0x73E9DBE1));
    final radius = desktopSpacing ? 8.0 : 14.0;

    return MouseRegion(
      onEnter: widget.isDesktop ? (_) => setState(() => _hovered = true) : null,
      onExit: widget.isDesktop ? (_) => setState(() => _hovered = false) : null,
      child: AnimatedScale(
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOut,
        scale: _hovered ? 1.001 : 1.0,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: desktopSpacing ? 62 : 0),
          child: _FrostedSurface(
            sigma: 10,
            enableBlur: true,
            tint: tint,
            borderColor: border,
            shadowColor: desktopSpacing
                ? (_hovered ? const Color(0x1A110A0E) : const Color(0x160D0609))
                : (_hovered
                    ? const Color(0x16150C10)
                    : const Color(0x120E070A)),
            specularStrength: 0,
            borderRadius: BorderRadius.circular(radius),
            padding: EdgeInsets.fromLTRB(
              desktopSpacing ? 12 : 9,
              desktopSpacing ? 8 : 5,
              desktopSpacing ? 8 : 4,
              desktopSpacing ? 8 : 5,
            ),
            child: desktopSpacing
                ? Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: const Color(0xFFEFF8FF),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFB2DDFF)),
                        ),
                        child: Text(
                          leadingText,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF175CD3),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: titleStyle,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              subtitleText,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: accountStyle,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      _DesktopActionCluster(
                        onView: widget.onView,
                        onCopy: widget.onCopy,
                        onEdit: widget.onEdit,
                        onDelete: widget.onDelete,
                      ),
                    ],
                  )
                : Row(
                    children: [
                      Expanded(
                        child: Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(text: title, style: titleStyle),
                              if (widget.accountInfo.isNotEmpty)
                                TextSpan(
                                  text: '   ${widget.accountInfo}',
                                  style: accountStyle,
                                ),
                            ],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      _MiniActionButton(
                        icon: Icons.visibility_outlined,
                        tooltip: '查看',
                        onTap: widget.onView,
                      ),
                      _MiniActionButton(
                        icon: Icons.copy_outlined,
                        tooltip: '复制密码',
                        onTap: widget.onCopy,
                      ),
                      _MiniActionButton(
                        icon: Icons.edit_outlined,
                        tooltip: '编辑',
                        onTap: widget.onEdit,
                      ),
                      _MiniActionButton(
                        icon: Icons.delete_outline,
                        tooltip: '删除',
                        onTap: widget.onDelete,
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class _DesktopActionCluster extends StatelessWidget {
  const _DesktopActionCluster({
    required this.onView,
    required this.onCopy,
    required this.onEdit,
    required this.onDelete,
  });

  final VoidCallback onView;
  final VoidCallback onCopy;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 96,
      height: 60,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE4E7EC)),
      ),
      child: Column(
        children: [
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: _MiniActionButton(
                    large: true,
                    boxed: true,
                    icon: Icons.visibility_outlined,
                    tooltip: '查看',
                    onTap: onView,
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: _MiniActionButton(
                    large: true,
                    boxed: true,
                    icon: Icons.copy_outlined,
                    tooltip: '复制密码',
                    onTap: onCopy,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: _MiniActionButton(
                    large: true,
                    boxed: true,
                    icon: Icons.edit_outlined,
                    tooltip: '编辑',
                    onTap: onEdit,
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: _MiniActionButton(
                    large: true,
                    boxed: true,
                    icon: Icons.delete_outline,
                    tooltip: '删除',
                    onTap: onDelete,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DraggedEntryCard extends StatelessWidget {
  const _DraggedEntryCard({
    required this.item,
    required this.accountInfo,
  });

  final VaultItem item;
  final String accountInfo;

  @override
  Widget build(BuildContext context) {
    final title = item.title.trim().isEmpty ? '未命名' : item.title;
    final leadingText = title.isEmpty ? '•' : title[0].toUpperCase();
    return Material(
      elevation: 10,
      borderRadius: BorderRadius.circular(8),
      color: Colors.white,
      child: Container(
        width: 260,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFB2DDFF)),
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFFEFF8FF),
                borderRadius: BorderRadius.circular(7),
              ),
              child: Text(
                leadingText,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF175CD3),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF101828),
                    ),
                  ),
                  if (accountInfo.isNotEmpty)
                    Text(
                      accountInfo,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF667085),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniActionButton extends StatefulWidget {
  const _MiniActionButton({
    this.large = false,
    this.boxed = false,
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final bool large;
  final bool boxed;
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  State<_MiniActionButton> createState() => _MiniActionButtonState();
}

class _MiniActionButtonState extends State<_MiniActionButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final platform = Theme.of(context).platform;
    final isDesktopPlatform = platform == TargetPlatform.windows ||
        platform == TargetPlatform.macOS ||
        platform == TargetPlatform.linux;
    final iconSize = widget.large ? 17.0 : 15.0;
    final splashRadius = widget.large ? 18.0 : 14.0;
    final minSize = widget.boxed ? 26.0 : (widget.large ? 29.0 : 24.0);
    final radius = widget.large ? 14.0 : 12.0;
    final padding = widget.boxed ? 2.0 : (widget.large ? 5.0 : 3.0);

    return MouseRegion(
      onEnter:
          isDesktopPlatform ? (_) => setState(() => _hovered = true) : null,
      onExit:
          isDesktopPlatform ? (_) => setState(() => _hovered = false) : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: widget.boxed
              ? (_hovered ? const Color(0xFFEFF8FF) : const Color(0xFFF8FAFC))
              : (_hovered ? const Color(0xFFF2F4F7) : Colors.transparent),
          borderRadius: BorderRadius.circular(radius),
        ),
        child: IconButton(
          onPressed: widget.onTap,
          icon: Icon(widget.icon, color: const Color(0xFF475467)),
          tooltip: widget.tooltip,
          iconSize: iconSize,
          splashRadius: splashRadius,
          visualDensity: VisualDensity.compact,
          constraints: BoxConstraints(minWidth: minSize, minHeight: minSize),
          padding: EdgeInsets.all(padding),
        ),
      ),
    );
  }
}

class _DockPopupEntrance extends StatelessWidget {
  const _DockPopupEntrance({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        final eased = value.clamp(0.0, 1.0);
        final slideY = (1 - eased) * 18;
        final scale = 0.94 + (0.06 * eased);
        return Opacity(
          opacity: eased,
          child: Transform.translate(
            offset: Offset(0, slideY),
            child: Transform.scale(scale: scale, child: child),
          ),
        );
      },
      child: child,
    );
  }
}

Future<T?> _showGlassDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) async {
  _glassPerfBus.pulse(heavy: true);
  final navigator = Navigator.of(context, rootNavigator: true);
  final route = DialogRoute<T>(
    context: context,
    themes: InheritedTheme.capture(from: context, to: navigator.context),
    barrierColor: _kDialogBarrierColor,
    builder: (context) => _DockPopupEntrance(child: builder(context)),
  );
  final result = await navigator.push(route);
  await route.completed;
  _glassPerfBus.pulse();
  return result;
}

class _GlassDialogActionBar extends StatelessWidget {
  const _GlassDialogActionBar({
    required this.children,
  });

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: children,
    );
  }
}

class _GlassDialogButton extends StatelessWidget {
  const _GlassDialogButton({
    required this.label,
    required this.onTap,
    this.primary = false,
    this.destructive = false,
  });

  final String label;
  final VoidCallback? onTap;
  final bool primary;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final foreground = destructive
        ? const Color(0xFF8C3348)
        : (primary ? const Color(0xFF241A1E) : const Color(0xFF6D5660));
    final tint = destructive
        ? const Color(0x22F3C9D4)
        : (primary ? const Color(0x28F7D4E1) : const Color(0x18F7EEF2));
    final border = destructive
        ? const Color(0x88E4B5C3)
        : (primary ? const Color(0x8CD6A7B9) : const Color(0x7ADFD1D8));

    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: _FrostedSurface(
        sigma: 14,
        borderRadius: BorderRadius.circular(8),
        tint: tint,
        borderColor: border,
        shadowColor: const Color(0x140E070A),
        specularStrength: 0,
        padding: EdgeInsets.zero,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              child: Text(
                label,
                style: TextStyle(
                  color: foreground,
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<bool?> _showImportSummaryDialog(
  BuildContext context,
  ImportMergeSummary summary,
) {
  return _showGlassDialog<bool>(
    context: context,
    builder: (context) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      child: _FrostedSurface(
        sigma: 18,
        borderRadius: BorderRadius.circular(24),
        tint: const Color(0x14F7EEF2),
        borderColor: const Color(0x7FE7D9E1),
        shadowColor: const Color(0x22110810),
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 16),
        child: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '导入预览',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: const Color(0xFF241A1E),
                    ),
              ),
              const SizedBox(height: 12),
              _ImportSummaryView(summary: summary),
              const SizedBox(height: 14),
              _GlassDialogActionBar(
                children: [
                  _GlassDialogButton(
                    label: '取消',
                    onTap: () => Navigator.of(context).pop(false),
                  ),
                  _GlassDialogButton(
                    label: '确认导入',
                    primary: true,
                    onTap: () => Navigator.of(context).pop(true),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

Future<void> _startBitwardenImport(
  BuildContext context,
  VaultController controller,
) async {
  final plan = await controller.previewBitwardenImport();
  if (!context.mounted || plan == null) {
    return;
  }
  final decisions = await _showBitwardenImportDialog(context, plan);
  if (!context.mounted || decisions == null) {
    return;
  }
  await controller.applyBitwardenImport(
    plan,
    decisions: decisions,
  );
}

Future<bool> _confirmBitwardenExport(
  BuildContext context,
  BitwardenExchangeFormat format,
) async {
  final label = format.name.toUpperCase();
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('导出 Bitwarden $label？'),
      content: const Text(
        '交换文件包含可直接读取的账号和密码。请只保存到可信位置，并在导入 Bitwarden 后立即删除。',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('继续导出'),
        ),
      ],
    ),
  );
  return confirmed == true;
}

Future<void> _exportToBitwarden(
  BuildContext context,
  VaultController controller,
  BitwardenExchangeFormat format,
) async {
  final confirmed = await _confirmBitwardenExport(context, format);
  if (!context.mounted || !confirmed) {
    return;
  }
  await controller.exportBitwarden(format);
}

Future<bool> _startBitwardenDeltaExport(
  BuildContext context,
  VaultController controller,
) async {
  final plan = await controller.previewBitwardenDeltaExport();
  if (!context.mounted || plan == null) {
    return false;
  }
  final format = await showDialog<BitwardenExchangeFormat>(
    context: context,
    builder: (_) => _BitwardenDeltaExportDialog(plan: plan),
  );
  if (!context.mounted || format == null) {
    return false;
  }
  final confirmed = await _confirmBitwardenExport(context, format);
  if (!context.mounted || !confirmed) {
    return false;
  }
  final result = await controller.exportBitwardenDelta(plan, format);
  return result.succeeded;
}

class _BitwardenDeltaExportDialog extends StatelessWidget {
  const _BitwardenDeltaExportDialog({required this.plan});

  final BitwardenDeltaExportPlan plan;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AlertDialog(
      key: const ValueKey('bitwarden-delta-dialog'),
      title: const Text('Bitwarden 缺失项核对'),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Bitwarden 基线 ${plan.baselineItemCount} 条，'
              'Codebook ${plan.localItemCount} 条，'
              '已匹配 ${plan.matchedItemCount} 条。',
            ),
            const SizedBox(height: 8),
            Text(
              plan.hasMissingItems
                  ? '将只导出 Bitwarden 中不存在的 ${plan.missingItemCount} 条。'
                  : '没有发现需要补充到 Bitwarden 的条目。',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: plan.hasMissingItems
                        ? colors.primary
                        : colors.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 8),
            const Text(
              '此操作不会更新或删除 Bitwarden 已有条目；Bitwarden 中不同的密码需要在对应条目中单独修改。',
            ),
            if (plan.unsupportedItems > 0 ||
                plan.duplicateCodebookCount > 0 ||
                plan.warnings.isNotEmpty) ...[
              const SizedBox(height: 8),
              if (plan.unsupportedItems > 0)
                Text(
                  '基线中有 ${plan.unsupportedItems} 条未支持项目，未参与匹配。',
                  style: TextStyle(color: colors.error),
                ),
              if (plan.duplicateCodebookCount > 0)
                Text(
                  'Codebook 中有 ${plan.duplicateCodebookCount} 条完全相同记录，仅导出一次。',
                ),
              for (final warning in plan.warnings) Text(warning),
            ],
            if (plan.hasMissingItems) ...[
              const SizedBox(height: 12),
              const Text('缺失条目：'),
              const SizedBox(height: 4),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 220),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerLowest,
                    border: Border.all(color: colors.outlineVariant),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    itemCount: plan.missingItems.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final item = plan.missingItems[index];
                      final subtitle = item.kind == VaultItemKind.secureNote
                          ? '安全笔记'
                          : (item.username.isEmpty ? '登录项' : item.username);
                      return ListTile(
                        dense: true,
                        leading: Icon(
                          item.kind == VaultItemKind.secureNote
                              ? Icons.note_outlined
                              : Icons.login_rounded,
                          size: 20,
                        ),
                        title: Text(
                          item.title.isEmpty ? '（未命名条目）' : item.title,
                        ),
                        subtitle: Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        if (plan.hasMissingItems) ...[
          OutlinedButton(
            onPressed: () =>
                Navigator.of(context).pop(BitwardenExchangeFormat.csv),
            child: const Text('导出缺失 CSV'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(context).pop(BitwardenExchangeFormat.json),
            child: const Text('导出缺失 JSON'),
          ),
        ],
      ],
    );
  }
}

Future<Map<String, BitwardenImportAction>?> _showBitwardenImportDialog(
  BuildContext context,
  BitwardenImportPlan plan,
) {
  return showDialog<Map<String, BitwardenImportAction>>(
    context: context,
    builder: (context) => _BitwardenImportDialog(plan: plan),
  );
}

class _BitwardenImportDialog extends StatefulWidget {
  const _BitwardenImportDialog({required this.plan});

  final BitwardenImportPlan plan;

  @override
  State<_BitwardenImportDialog> createState() => _BitwardenImportDialogState();
}

class _BitwardenImportDialogState extends State<_BitwardenImportDialog> {
  late final Map<String, BitwardenImportAction> _decisions = {
    for (final review in widget.plan.reviews)
      review.importedItem.id: BitwardenImportAction.keepBoth,
  };

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final compact = size.width < 600;
    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: compact ? 12 : 28,
        vertical: 20,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 720,
          maxHeight: size.height * 0.88,
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            compact ? 16 : 22,
            20,
            compact ? 16 : 22,
            14,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.compare_arrows_rounded),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '核验 Bitwarden 导入',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    tooltip: '取消',
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '可导入 ${widget.plan.incomingItems} 条，'
                '发现 ${widget.plan.reviews.length} 条需要人工核验的候选。',
              ),
              if (widget.plan.unsupportedItems > 0) ...[
                const SizedBox(height: 6),
                Text(
                  '另有 ${widget.plan.unsupportedItems} 条未支持项目不会导入。',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              if (widget.plan.reusedPasswordCount > 0) ...[
                const SizedBox(height: 6),
                Text(
                  '检测到 ${widget.plan.reusedPasswordCount} 条与本机其他账号复用密码；'
                  '这只会提示，不会合并条目。',
                ),
              ],
              for (final warning in widget.plan.warnings) ...[
                const SizedBox(height: 6),
                Text(warning),
              ],
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 10),
              if (widget.plan.reviews.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  child: Text(
                    widget.plan.incomingItems == 0
                        ? '文件中没有可导入的登录项或安全笔记。'
                        : '没有发现重复候选，全部条目将作为新记录导入。',
                  ),
                )
              else ...[
                Text(
                  '软件只提供候选，不会自动删除或覆盖。默认两边都保留。',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: widget.plan.reviews.length,
                    separatorBuilder: (_, __) => const Divider(height: 18),
                    itemBuilder: (context, index) {
                      final review = widget.plan.reviews[index];
                      return _BitwardenReviewTile(
                        review: review,
                        action: _decisions[review.importedItem.id] ??
                            BitwardenImportAction.keepBoth,
                        onChanged: (action) {
                          setState(() {
                            _decisions[review.importedItem.id] = action;
                          });
                        },
                      );
                    },
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: widget.plan.incomingItems == 0
                        ? null
                        : () => Navigator.of(context).pop(_decisions),
                    icon: const Icon(Icons.download_done_rounded),
                    label: const Text('按选择导入'),
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

class _BitwardenReviewTile extends StatelessWidget {
  const _BitwardenReviewTile({
    required this.review,
    required this.action,
    required this.onChanged,
  });

  final BitwardenImportReview review;
  final BitwardenImportAction action;
  final ValueChanged<BitwardenImportAction> onChanged;

  @override
  Widget build(BuildContext context) {
    final imported = review.importedItem;
    final local = review.localItem;
    final aliases = review.sharedAliases
        .map(_displayAlias)
        .where((value) => value.isNotEmpty)
        .toSet()
        .join('、');
    final label = imported.kind == VaultItemKind.secureNote
        ? switch (review.kind) {
            BitwardenImportMatchKind.exactDuplicate => '疑似重复笔记',
            BitwardenImportMatchKind.passwordConflict => '笔记标题相同，内容不同',
            BitwardenImportMatchKind.possibleDuplicate => '笔记可能相关',
          }
        : switch (review.kind) {
            BitwardenImportMatchKind.exactDuplicate => '疑似重复',
            BitwardenImportMatchKind.passwordConflict => '账号可能相同，密码不同',
            BitwardenImportMatchKind.possibleDuplicate => '可能相关',
          };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                imported.title.isEmpty ? '（未命名导入项）' : imported.title,
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color:
                        review.kind == BitwardenImportMatchKind.passwordConflict
                            ? Theme.of(context).colorScheme.error
                            : Theme.of(context).colorScheme.primary,
                  ),
            ),
          ],
        ),
        const SizedBox(height: 5),
        Text('导入项账号：${imported.username.isEmpty ? '（空）' : imported.username}'),
        Text(
            '本机候选：${local.title} · ${local.username.isEmpty ? '（空）' : local.username}'),
        if (aliases.isNotEmpty) Text('共同账号信息：$aliases'),
        if (review.hasAmbiguousMatches)
          Text(
            '另有 ${review.equallyRankedMatchCount - 1} 个同强度本机候选，'
            '无法安全判断应替换哪一条。',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        Text(
          '判断依据：${review.reason}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            ChoiceChip(
              label: const Text('两边都保留'),
              selected: action == BitwardenImportAction.keepBoth,
              onSelected: (_) => onChanged(BitwardenImportAction.keepBoth),
            ),
            ChoiceChip(
              label: const Text('用导入项替换本机'),
              selected: action == BitwardenImportAction.useImported &&
                  !review.hasAmbiguousMatches,
              onSelected: review.hasAmbiguousMatches
                  ? null
                  : (_) => onChanged(BitwardenImportAction.useImported),
            ),
            ChoiceChip(
              label: const Text('不导入这一条'),
              selected: action == BitwardenImportAction.keepLocal,
              onSelected: (_) => onChanged(BitwardenImportAction.keepLocal),
            ),
          ],
        ),
      ],
    );
  }

  String _displayAlias(String alias) {
    final separator = alias.indexOf(':');
    return separator < 0 ? alias : alias.substring(separator + 1);
  }
}

class _PasswordGeneratorControl extends StatefulWidget {
  const _PasswordGeneratorControl(
      {required this.controller, required this.onGenerated});

  final VaultController controller;
  final ValueChanged<String> onGenerated;

  @override
  State<_PasswordGeneratorControl> createState() =>
      _PasswordGeneratorControlState();
}

class _PasswordGeneratorControlState extends State<_PasswordGeneratorControl> {
  int _length = 20;

  @override
  Widget build(BuildContext context) => Wrap(
        alignment: WrapAlignment.end,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        children: [
          DropdownButton<int>(
            value: _length,
            underline: const SizedBox.shrink(),
            borderRadius: BorderRadius.circular(12),
            items: [
              for (final length in [16, 20, 24, 32])
                DropdownMenuItem(value: length, child: Text('$length 位'))
            ],
            onChanged: (value) {
              if (value != null) setState(() => _length = value);
            },
          ),
          TextButton.icon(
            onPressed: () => widget.onGenerated(
                widget.controller.generatePassword(length: _length)),
            icon: const Icon(Icons.password_outlined, size: 18),
            label: const Text('生成密码'),
          ),
        ],
      );
}

Future<void> _showAndroidItemEditor(
  BuildContext context, {
  required VaultController controller,
  VaultItem? item,
}) async {
  final titleController = TextEditingController(text: item?.title ?? '');
  final usernameController = TextEditingController(text: item?.username ?? '');
  final passwordController = TextEditingController(text: item?.password ?? '');
  final urlController = TextEditingController(text: item?.url ?? '');
  final notesController = TextEditingController(text: item?.notes ?? '');
  String? androidSelectedCategoryId =
      item == null || item.folder.isEmpty ? null : item.folder;
  var obscurePassword = true;
  var saving = false;

  final navigator = Navigator.of(context);
  final route = ModalBottomSheetRoute<void>(
    capturedThemes:
        InheritedTheme.capture(from: context, to: navigator.context),
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    modalBarrierColor: Theme.of(context).bottomSheetTheme.modalBarrierColor,
    isScrollControlled: true,
    builder: (sheetContext) => StatefulBuilder(
      builder: (context, setSheetState) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.88,
          minChildSize: 0.55,
          maxChildSize: 0.96,
          builder: (context, scrollController) => SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
              ),
              child: ListView(
                controller: scrollController,
                children: [
                  Text(
                    item == null ? '新增条目' : '编辑条目',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: titleController,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(labelText: '名称'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: usernameController,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(labelText: '账号'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: passwordController,
                    obscureText: obscurePassword,
                    enableSuggestions: false,
                    autocorrect: false,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      labelText: '密码',
                      suffixIcon: IconButton(
                        tooltip: obscurePassword ? '显示密码' : '隐藏密码',
                        onPressed: () {
                          setSheetState(() {
                            obscurePassword = !obscurePassword;
                          });
                        },
                        icon: Icon(
                          obscurePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _PasswordGeneratorControl(
                    controller: controller,
                    onGenerated: (password) =>
                        passwordController.text = password,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: urlController,
                    keyboardType: TextInputType.url,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(labelText: '网址'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: notesController,
                    minLines: 3,
                    maxLines: 5,
                    decoration: const InputDecoration(labelText: '备注'),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: androidSelectedCategoryId,
                    decoration: const InputDecoration(labelText: '分类'),
                    items: [
                      const DropdownMenuItem(
                        value: '',
                        child: Text('无分类'),
                      ),
                      for (final category in controller.vaultData.categories)
                        DropdownMenuItem(
                          value: category.id,
                          child: Text(category.name),
                        ),
                    ],
                    onChanged: (value) {
                      setSheetState(() {
                        androidSelectedCategoryId =
                            value == null || value.isEmpty ? null : value;
                      });
                    },
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    key: const ValueKey('android-item-save'),
                    onPressed: saving
                        ? null
                        : () async {
                            setSheetState(() {
                              saving = true;
                            });
                            final result = await controller.addOrUpdateItem(
                              id: item?.id,
                              title: titleController.text,
                              username: usernameController.text,
                              password: passwordController.text,
                              url: urlController.text,
                              notes: notesController.text,
                              tags: item?.tags ?? const [],
                              totpSecret: item?.totpSecret,
                              categoryId: androidSelectedCategoryId,
                            );
                            if (result.succeeded && sheetContext.mounted) {
                              Navigator.of(sheetContext).pop();
                              return;
                            }
                            if (sheetContext.mounted) {
                              setSheetState(() {
                                saving = false;
                              });
                            }
                          },
                    icon: const Icon(Icons.save_rounded),
                    label: const Text('保存'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );

  await navigator.push(route);
  // Controllers remain in use until the closing transition removes the sheet.
  await route.completed;
  titleController.dispose();
  usernameController.dispose();
  passwordController.dispose();
  urlController.dispose();
  notesController.dispose();
}

Future<void> _showItemEditor(
  BuildContext context, {
  required VaultController controller,
  VaultItem? item,
}) async {
  if (Theme.of(context).platform == TargetPlatform.android) {
    return _showAndroidItemEditor(context, controller: controller, item: item);
  }
  final titleController = TextEditingController(text: item?.title ?? '');
  final usernameController = TextEditingController(text: item?.username ?? '');
  final passwordController = TextEditingController(text: item?.password ?? '');
  final urlController = TextEditingController(text: item?.url ?? '');
  final notesController = TextEditingController(text: item?.notes ?? '');
  String? selectedCategoryId =
      item == null || item.folder.isEmpty ? null : item.folder;
  var saving = false;
  var obscurePassword = true;

  await _showGlassDialog<bool>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) {
        final viewportHeight = MediaQuery.sizeOf(context).height;
        final dialogHeight = (viewportHeight - 64).clamp(320.0, 660.0);
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
          child: _FrostedSurface(
            sigma: 20,
            borderRadius: BorderRadius.circular(16),
            borderColor: Theme.of(context).colorScheme.outlineVariant,
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
            child: SizedBox(
              width: 540,
              height: dialogHeight,
              child: Theme(
                data: Theme.of(context).copyWith(
                  inputDecorationTheme: Theme.of(context)
                      .inputDecorationTheme
                      .copyWith(
                        filled: true,
                        fillColor:
                            Theme.of(context).colorScheme.surfaceContainerLow,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 16,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: Color(0xFFD9DEE5),
                            width: 1,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: Theme.of(context).colorScheme.primary,
                            width: 1.2,
                          ),
                        ),
                      ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      item == null ? '新增条目' : '编辑条目',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 14),
                    Expanded(
                      child: Scrollbar(
                        thumbVisibility: true,
                        child: SingleChildScrollView(
                          primary: true,
                          padding: const EdgeInsets.only(
                              top: 10, right: 14, bottom: 4),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              TextField(
                                controller: titleController,
                                decoration:
                                    const InputDecoration(labelText: '名称'),
                              ),
                              const SizedBox(height: 10),
                              TextField(
                                controller: usernameController,
                                decoration:
                                    const InputDecoration(labelText: '账号'),
                              ),
                              const SizedBox(height: 10),
                              TextField(
                                controller: passwordController,
                                obscureText: obscurePassword,
                                enableSuggestions: false,
                                autocorrect: false,
                                decoration: InputDecoration(
                                  labelText: '密码',
                                  suffixIcon: IconButton(
                                    tooltip: obscurePassword ? '显示密码' : '隐藏密码',
                                    onPressed: () {
                                      setDialogState(() {
                                        obscurePassword = !obscurePassword;
                                      });
                                    },
                                    icon: Icon(
                                      obscurePassword
                                          ? Icons.visibility_outlined
                                          : Icons.visibility_off_outlined,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 10),
                              _PasswordGeneratorControl(
                                controller: controller,
                                onGenerated: (password) =>
                                    passwordController.text = password,
                              ),
                              const SizedBox(height: 10),
                              TextField(
                                controller: urlController,
                                decoration:
                                    const InputDecoration(labelText: '网址'),
                              ),
                              const SizedBox(height: 10),
                              TextField(
                                controller: notesController,
                                maxLines: 5,
                                decoration:
                                    const InputDecoration(labelText: '备注'),
                              ),
                              const SizedBox(height: 10),
                              DropdownButtonFormField<String>(
                                initialValue: selectedCategoryId,
                                decoration: const InputDecoration(
                                  labelText: '分类',
                                ),
                                items: [
                                  const DropdownMenuItem(
                                    value: '',
                                    child: Text('无分类'),
                                  ),
                                  for (final category
                                      in controller.vaultData.categories)
                                    DropdownMenuItem(
                                      value: category.id,
                                      child: Text(category.name),
                                    ),
                                ],
                                onChanged: (value) {
                                  setDialogState(() {
                                    selectedCategoryId =
                                        value == null || value.isEmpty
                                            ? null
                                            : value;
                                  });
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    _GlassDialogActionBar(
                      children: [
                        _GlassDialogButton(
                          label: '取消',
                          onTap: () => Navigator.of(context).pop(false),
                        ),
                        _GlassDialogButton(
                          label: saving ? '正在保存…' : '保存',
                          primary: true,
                          onTap: saving
                              ? null
                              : () async {
                                  setDialogState(() {
                                    saving = true;
                                  });
                                  final result =
                                      await controller.addOrUpdateItem(
                                    id: item?.id,
                                    title: titleController.text,
                                    username: usernameController.text,
                                    password: passwordController.text,
                                    url: urlController.text,
                                    notes: notesController.text,
                                    tags: item?.tags ?? const [],
                                    totpSecret: item?.totpSecret,
                                    categoryId: selectedCategoryId,
                                  );
                                  if (result.succeeded &&
                                      dialogContext.mounted) {
                                    Navigator.of(dialogContext).pop(true);
                                    return;
                                  }
                                  if (dialogContext.mounted) {
                                    setDialogState(() {
                                      saving = false;
                                    });
                                  }
                                },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    ),
  );

  titleController.dispose();
  usernameController.dispose();
  passwordController.dispose();
  urlController.dispose();
  notesController.dispose();
}

Future<void> _showAndroidItemDetails(
  BuildContext context, {
  required VaultController controller,
  required VaultItem item,
}) async {
  var showPassword = false;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => StatefulBuilder(
      builder: (context, setSheetState) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.72,
        minChildSize: 0.45,
        maxChildSize: 0.94,
        builder: (context, scrollController) => SafeArea(
          top: false,
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(item.title.trim().isEmpty ? '未命名' : item.title,
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontWeight: FontWeight.w700)),
                  ),
                  IconButton(
                    tooltip: '编辑条目',
                    onPressed: () {
                      Navigator.of(sheetContext).pop();
                      _showItemEditor(context,
                          controller: controller, item: item);
                    },
                    icon: const Icon(Icons.edit_outlined),
                  ),
                ],
              ),
              const Divider(height: 24),
              const SizedBox(height: 16),
              _DetailRow(
                label: '账号',
                value: item.username,
                onCopy: item.username.isEmpty
                    ? null
                    : () => controller.copySecret(item.username),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(width: 92, child: Text('密码:')),
                    Expanded(
                      child: SelectableText(
                          showPassword ? item.password : '••••••••'),
                    ),
                    IconButton(
                      tooltip: showPassword ? '隐藏密码' : '显示密码',
                      onPressed: () {
                        setSheetState(() {
                          showPassword = !showPassword;
                        });
                      },
                      icon: Icon(
                        showPassword
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                      ),
                    ),
                    IconButton(
                      tooltip: '复制密码',
                      onPressed: item.password.isEmpty
                          ? null
                          : () => controller.copySecret(item.password),
                      icon: const Icon(Icons.copy_outlined),
                    ),
                  ],
                ),
              ),
              _DetailRow(label: '网址', value: item.url),
              if (item.folder.isNotEmpty)
                _DetailRow(label: '文件夹', value: item.folder),
              if (item.tags.isNotEmpty)
                _DetailRow(label: '标签', value: item.tags.join(', ')),
              if ((item.totpSecret?.trim().isNotEmpty ?? false))
                _TotpPanel(
                  secretOrUri: item.totpSecret!,
                  onCopy: controller.copySecret,
                ),
              if (item.notes.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('备注', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                SelectableText(item.notes),
              ],
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () => Navigator.of(sheetContext).pop(),
                child: const Text('关闭'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

Future<void> _confirmDeleteItem(
  BuildContext context, {
  required VaultController controller,
  required VaultItem item,
}) async {
  if (Theme.of(context).platform == TargetPlatform.android) {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('移至回收站？'),
        content: Text('“${item.title}”可从回收站恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('移至回收站'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await controller.deleteItem(item.id);
    }
    return;
  }

  final confirmed = await _showGlassDialog<bool>(
    context: context,
    builder: (context) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      child: _FrostedSurface(
        sigma: 18,
        borderRadius: BorderRadius.circular(24),
        tint: const Color(0x12F6EBEF),
        borderColor: const Color(0x74E6D7DE),
        shadowColor: const Color(0x22110810),
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 16),
        child: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '删除条目',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: const Color(0xFF241A1E),
                    ),
              ),
              const SizedBox(height: 10),
              Text(
                '确认删除“${item.title.trim().isEmpty ? '未命名条目' : item.title}”？',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: const Color(0xFF4A3B41),
                    ),
              ),
              const SizedBox(height: 16),
              _GlassDialogActionBar(
                children: [
                  _GlassDialogButton(
                    label: '取消',
                    onTap: () => Navigator.of(context).pop(false),
                  ),
                  _GlassDialogButton(
                    label: '确认删除',
                    destructive: true,
                    onTap: () => Navigator.of(context).pop(true),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
  if (confirmed == true) {
    await controller.deleteItem(item.id);
  }
}

Future<void> _showItemDetails(
  BuildContext context, {
  required VaultController controller,
  required VaultItem item,
}) {
  if (Theme.of(context).platform == TargetPlatform.android) {
    return _showAndroidItemDetails(context, controller: controller, item: item);
  }
  var showPassword = false;
  return _showGlassDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        child: _FrostedSurface(
          sigma: 18,
          borderRadius: BorderRadius.circular(24),
          tint: const Color(0x14F7EEF2),
          borderColor: const Color(0x7FE7D9E1),
          shadowColor: const Color(0x22110810),
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 16),
          child: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  item.title,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: const Color(0xFF241A1E),
                      ),
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _DetailRow(
                          label: '账号',
                          value: item.username,
                          onCopy: item.username.isEmpty
                              ? null
                              : () => controller.copySecret(item.username),
                        ),
                        _DetailRow(
                          label: '密码',
                          value: showPassword ? item.password : '••••••••',
                          onCopy: item.password.isEmpty
                              ? null
                              : () => controller.copySecret(item.password),
                        ),
                        _DetailRow(label: '网址', value: item.url),
                        if (item.folder.isNotEmpty)
                          _DetailRow(label: '文件夹', value: item.folder),
                        if (item.tags.isNotEmpty)
                          _DetailRow(label: '标签', value: item.tags.join(', ')),
                        if ((item.totpSecret?.trim().isNotEmpty ?? false))
                          _TotpPanel(
                            secretOrUri: item.totpSecret!,
                            onCopy: controller.copySecret,
                          )
                        else
                          const _DetailRow(label: 'TOTP', value: ''),
                        const SizedBox(height: 10),
                        SelectableText(item.notes),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                _GlassDialogActionBar(
                  children: [
                    _GlassDialogButton(
                      label: showPassword ? '隐藏密码' : '显示密码',
                      onTap: () {
                        setDialogState(() {
                          showPassword = !showPassword;
                        });
                      },
                    ),
                    _GlassDialogButton(
                      label: '关闭',
                      primary: true,
                      onTap: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    this.onCopy,
  });

  final String label;
  final String value;
  final VoidCallback? onCopy;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text('$label:'),
          ),
          Expanded(child: SelectableText(value)),
          if (onCopy != null)
            IconButton(
              onPressed: onCopy,
              icon: const Icon(Icons.copy_outlined),
              tooltip: '复制',
            ),
        ],
      ),
    );
  }
}

class _ImportSummaryView extends StatelessWidget {
  const _ImportSummaryView({required this.summary});

  final ImportMergeSummary summary;

  @override
  Widget build(BuildContext context) {
    final changedDetails = summary.details
        .where((detail) => detail.kind != ImportChangeKind.unchangedItem)
        .toList();

    final lines = <String>[
      '导入条目总数：${summary.incomingItems}',
      '新增：${summary.newItems}',
      '更新：${summary.updatedItems}',
      '删除：${summary.deletedItems}',
      '未变化：${summary.unchangedItems}',
    ];
    if (summary.replacesLocalVault) {
      lines.insert(0, '当前没有本地密码库，导入文件将作为本地密码库。');
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final line in lines)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(line),
          ),
        if (changedDetails.isNotEmpty) ...[
          const Divider(),
          const SizedBox(height: 8),
          Text(
            '变更明细',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 220,
            child: ListView.separated(
              itemCount: changedDetails.length,
              separatorBuilder: (_, __) => const Divider(height: 12),
              itemBuilder: (context, index) {
                final detail = changedDetails[index];
                final title =
                    detail.title.trim().isEmpty ? '（未命名）' : detail.title;
                final subtitleParts = <String>[
                  'ID: ${detail.id}',
                  '导入更新时间: ${detail.incomingUpdatedAt.toIso8601String()}',
                  if (detail.localUpdatedAt != null)
                    '本地更新时间: ${detail.localUpdatedAt!.toIso8601String()}',
                ];
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 64,
                      child: Text(
                        _kindLabel(detail.kind),
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title),
                          const SizedBox(height: 2),
                          Text(
                            subtitleParts.join('  |  '),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ],
    );
  }

  String _kindLabel(ImportChangeKind kind) {
    switch (kind) {
      case ImportChangeKind.newItem:
        return '新增';
      case ImportChangeKind.updatedItem:
        return '更新';
      case ImportChangeKind.deletedItem:
        return '删除';
      case ImportChangeKind.unchangedItem:
        return '未变';
    }
  }
}

Future<void> _showLanSyncDialog(
  BuildContext context, {
  required VaultController controller,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _LanSyncDialog(controller: controller),
  );
}

class _LanSyncDialog extends StatefulWidget {
  const _LanSyncDialog({required this.controller});

  final VaultController controller;

  @override
  State<_LanSyncDialog> createState() => _LanSyncDialogState();
}

class _LanSyncDialogState extends State<_LanSyncDialog> {
  final _pairingCodeController = TextEditingController();
  final _passwordController = TextEditingController();
  List<LanSyncPeer> _peers = const [];
  LanSyncPeer? _selectedPeer;
  ImportPlan? _plan;
  bool _busy = false;
  String? _status;
  bool _advancedStatus = false;

  Future<void> _syncAll() async {
    final password = _passwordController.text;
    if (password.trim().isEmpty) {
      setState(() {
        _advancedStatus = false;
        _status = '请输入各设备共同使用的主密码。';
      });
      return;
    }
    setState(() {
      _advancedStatus = false;
      _busy = true;
      _plan = null;
      _status = '正在验证局域网设备并双向合并，请保持各端解锁…';
    });
    await widget.controller.syncLanWithPassword(password);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _status = widget.controller.message;
      _peers = widget.controller.lanSyncPeers;
      _selectedPeer = _peers.isEmpty ? null : _peers.first;
    });
    _passwordController.clear();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _discover();
    });
  }

  @override
  void dispose() {
    _pairingCodeController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _discover() async {
    setState(() {
      _advancedStatus = false;
      _busy = true;
      _status = '正在发现局域网设备…';
    });
    final result = await widget.controller.discoverLanSyncPeers();
    if (!mounted) {
      return;
    }
    setState(() {
      _busy = false;
      _peers = widget.controller.lanSyncPeers;
      final selectedId = _selectedPeer?.deviceId;
      _selectedPeer = _peers.isEmpty
          ? null
          : _peers.firstWhere(
              (peer) => peer.deviceId == selectedId,
              orElse: () => _peers.first,
            );
      _status = result.succeeded
          ? (_peers.isEmpty ? '没有发现可配对设备。' : '已发现 ${_peers.length} 台设备。')
          : widget.controller.message;
    });
  }

  Future<void> _startShare() async {
    setState(() {
      _advancedStatus = true;
      _busy = true;
      _status = '正在开启设备配对服务…';
    });
    final result = await widget.controller.startLanSyncShare();
    if (!mounted) {
      return;
    }
    setState(() {
      _busy = false;
      _status = result.succeeded
          ? '设备配对服务已开启，请在另一台设备输入配对码。'
          : widget.controller.message;
    });
  }

  Future<void> _stopShare() async {
    setState(() {
      _advancedStatus = true;
      _busy = true;
      _status = '正在关闭设备配对服务…';
    });
    await widget.controller.stopLanSyncShare();
    if (!mounted) {
      return;
    }
    setState(() {
      _busy = false;
      _status = '已关闭设备配对服务。';
    });
  }

  Future<void> _download() async {
    final peer = _selectedPeer;
    if (peer == null) {
      setState(() {
        _advancedStatus = true;
        _status = '请先选择来源设备。';
      });
      return;
    }
    final pairingCode = _pairingCodeController.text.trim();
    final sourcePassword = _passwordController.text.trim();
    if (pairingCode.isEmpty && sourcePassword.isEmpty) {
      setState(() {
        _advancedStatus = true;
        _status = '请输入来源设备的主密码。';
      });
      return;
    }
    setState(() {
      _advancedStatus = true;
      _busy = true;
      _plan = null;
      _status = '正在下载加密密码库…';
    });
    final bytes = await widget.controller.downloadLanSync(
      peer: peer,
      pairingCode: pairingCode,
      sharedPassword: sourcePassword,
    );
    if (bytes == null) {
      if (mounted) {
        setState(() {
          _busy = false;
          _status = widget.controller.message;
        });
      }
      return;
    }
    final plan = await widget.controller.previewImportBytes(
      bytes,
      _passwordController.text,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _busy = false;
      _plan = plan;
      _status = plan == null
          ? widget.controller.message
          : (plan.summary.replacesLocalVault
              ? '主密码验证成功，正在建立本地密码库…'
              : '下载完成，请确认需要合并的变更。');
    });
    if (plan?.summary.replacesLocalVault == true) {
      await _apply();
    }
  }

  Future<void> _apply() async {
    final plan = _plan;
    if (plan == null) {
      return;
    }
    setState(() {
      _advancedStatus = true;
      _busy = true;
      _status = plan.summary.replacesLocalVault ? '正在建立本地密码库…' : '正在合并密码库…';
    });
    final result = await widget.controller.applyImportPlan(plan);
    if (!mounted) {
      return;
    }
    if (result.succeeded) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _busy = false;
      _status = widget.controller.message;
    });
  }

  Widget _buildCompactDialog(BuildContext context) {
    final host = widget.controller.lanSyncHost;
    final colors = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('设备同步'),
      contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '设备连接同一局域网并保持解锁，使用共同主密码合并。',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _passwordController,
                obscureText: true,
                enabled: !_busy,
                decoration: const InputDecoration(labelText: '共同的主密码'),
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: _busy ? null : _syncAll,
                icon: const Icon(Icons.sync_rounded),
                label: const Text('验证并同步所有设备'),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _status ?? '正在发现局域网设备…',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                    ),
                  ),
                  if (_busy)
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    IconButton(
                      tooltip: '重新发现设备',
                      onPressed: _discover,
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                ],
              ),
              const Divider(height: 1),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(bottom: 8),
                title: const Text('更多选项'),
                children: [
                  if (host != null) ...[
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text('本机配对服务已开启',
                          style: Theme.of(context).textTheme.titleSmall),
                    ),
                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: SelectableText('配对码：${host.pairingCode}'),
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(host.addresses.isEmpty
                          ? '端口：${host.port}'
                          : '地址：${host.addresses.join('、')}  端口：${host.port}'),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _stopShare,
                      icon: const Icon(Icons.stop_circle_outlined),
                      label: const Text('停止本机配对服务'),
                    ),
                  ] else if (widget.controller.isUnlocked)
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _startShare,
                      icon: const Icon(Icons.wifi_tethering_rounded),
                      label: const Text('在本机开启配对服务'),
                    )
                  else
                    const Text('本机尚未解锁，当前仅可从另一台设备配对到本机。'),
                  const Divider(),
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: const Text('单台设备导入'),
                    children: [
                      if (_peers.isNotEmpty)
                        DropdownButtonFormField<LanSyncPeer>(
                          initialValue: _selectedPeer,
                          decoration: const InputDecoration(labelText: '来源设备'),
                          items: _peers
                              .map((peer) => DropdownMenuItem(
                                    value: peer,
                                    child: Text(peer.displayName),
                                  ))
                              .toList(),
                          onChanged: _busy
                              ? null
                              : (peer) => setState(() => _selectedPeer = peer),
                        )
                      else
                        const Text('未发现可配对设备'),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _pairingCodeController,
                        textCapitalization: TextCapitalization.characters,
                        decoration: const InputDecoration(
                          labelText: '配对码（可选）',
                          helperText: '通常只需输入来源设备主密码；配对码用于手动确认设备。',
                        ),
                      ),
                      const SizedBox(height: 8),
                      FilledButton.icon(
                        onPressed: _busy ? null : _download,
                        icon: const Icon(Icons.download_for_offline_rounded),
                        label: Text(
                            widget.controller.hasVault ? '配对并预览' : '配对并进入密码本'),
                      ),
                      if (_plan != null) ...[
                        const SizedBox(height: 14),
                        _ImportSummaryView(summary: _plan!.summary),
                        const SizedBox(height: 10),
                        FilledButton.icon(
                          onPressed: _busy ? null : _apply,
                          icon: const Icon(Icons.merge_type_rounded),
                          label: Text(_plan!.summary.replacesLocalVault
                              ? '确认建立本地密码库'
                              : '确认合并'),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        if (_advancedStatus && _status != null)
          SizedBox(
            width: double.infinity,
            child: Text(
              _status!,
              key: const ValueKey('lan-advanced-status'),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
            ),
          ),
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (Theme.of(context).platform == TargetPlatform.android ||
        Theme.of(context).platform == TargetPlatform.windows) {
      return _buildCompactDialog(context);
    }
    final host = widget.controller.lanSyncHost;
    return AlertDialog(
      title: const Text('设备配对与同步'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                '所有设备连接同一局域网并保持密码本已解锁。在任意一端输入共同的主密码，即可验证其他设备并将各端条目合并到一起。',
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _passwordController,
                obscureText: true,
                enabled: !_busy,
                decoration: const InputDecoration(labelText: '共同的主密码'),
              ),
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: _busy ? null : _syncAll,
                icon: const Icon(Icons.sync_rounded),
                label: const Text('验证并同步所有设备'),
              ),
              const SizedBox(height: 16),
              if (host != null) ...[
                _FrostedSurface(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('本机配对服务已开启'),
                      const SizedBox(height: 6),
                      SelectableText(
                        '配对码：${host.pairingCode}',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 2,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        host.addresses.isEmpty
                            ? '端口：${host.port}'
                            : '地址：${host.addresses.join('、')}  端口：${host.port}',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _stopShare,
                  icon: const Icon(Icons.stop_circle_outlined),
                  label: const Text('停止本机配对服务'),
                ),
              ] else if (widget.controller.isUnlocked)
                FilledButton.tonalIcon(
                  onPressed: _busy ? null : _startShare,
                  icon: const Icon(Icons.wifi_tethering_rounded),
                  label: const Text('在本机开启配对服务'),
                )
              else
                const Text('本机尚未解锁，当前仅可从另一台设备配对到本机。'),
              const Divider(height: 28),
              ExpansionTile(
                title: const Text('单台设备导入（高级）'),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _peers.isEmpty
                              ? '未发现可配对设备'
                              : '发现 ${_peers.length} 台设备',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                      IconButton(
                        tooltip: '重新发现设备',
                        onPressed: _busy ? null : _discover,
                        icon: const Icon(Icons.refresh_rounded),
                      ),
                    ],
                  ),
                  if (_peers.isNotEmpty)
                    DropdownButtonFormField<LanSyncPeer>(
                      initialValue: _selectedPeer,
                      decoration: const InputDecoration(labelText: '来源设备'),
                      items: _peers
                          .map(
                            (peer) => DropdownMenuItem(
                              value: peer,
                              child: Text(peer.displayName),
                            ),
                          )
                          .toList(),
                      onChanged: _busy
                          ? null
                          : (peer) => setState(() {
                                _selectedPeer = peer;
                              }),
                    ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _pairingCodeController,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      labelText: '配对码（可选）',
                      helperText: '通常只需输入来源设备主密码；配对码用于手动确认设备。',
                    ),
                  ),
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    onPressed: _busy ? null : _download,
                    icon: const Icon(Icons.download_for_offline_rounded),
                    label: Text(
                      widget.controller.hasVault ? '配对并预览' : '配对并进入密码本',
                    ),
                  ),
                  if (_plan != null) ...[
                    const SizedBox(height: 14),
                    _ImportSummaryView(summary: _plan!.summary),
                    const SizedBox(height: 10),
                    FilledButton.icon(
                      onPressed: _busy ? null : _apply,
                      icon: const Icon(Icons.merge_type_rounded),
                      label: Text(
                        _plan!.summary.replacesLocalVault
                            ? '确认建立本地密码库'
                            : '确认合并',
                      ),
                    ),
                  ],
                ],
              ),
              if (_busy) ...[
                const SizedBox(height: 12),
                const Center(child: CircularProgressIndicator()),
              ],
              if (_status != null) ...[
                const SizedBox(height: 10),
                Text(_status!),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}

class _RecycleBinSheet extends StatelessWidget {
  const _RecycleBinSheet({required this.controller});

  final VaultController controller;

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      minChildSize: 0.45,
      maxChildSize: 0.94,
      builder: (context, scrollController) => SafeArea(
        top: false,
        child: AnimatedBuilder(
          animation: controller,
          builder: (context, _) {
            final deletedItems = controller.vaultData.deletedItems;
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '回收站',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '恢复的条目会回到密码列表。永久删除无法撤销。',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: deletedItems.isEmpty
                        ? const Center(child: Text('回收站为空'))
                        : ListView.separated(
                            controller: scrollController,
                            itemCount: deletedItems.length,
                            separatorBuilder: (_, __) => const Divider(),
                            itemBuilder: (context, index) {
                              final item = deletedItems[index];
                              return ListTile(
                                title: Text(item.title),
                                subtitle: Text(
                                  item.username.isEmpty ? '已删除' : item.username,
                                ),
                                trailing: Wrap(
                                  spacing: 4,
                                  children: [
                                    IconButton(
                                      tooltip: '恢复 ${item.title}',
                                      icon: const Icon(Icons.restore_rounded),
                                      onPressed: controller.busy
                                          ? null
                                          : () =>
                                              controller.restoreItem(item.id),
                                    ),
                                    IconButton(
                                      tooltip: '永久删除 ${item.title}',
                                      icon: const Icon(
                                          Icons.delete_forever_rounded),
                                      onPressed: controller.busy
                                          ? null
                                          : () async {
                                              final confirmed =
                                                  await showDialog<bool>(
                                                context: context,
                                                builder: (dialogContext) =>
                                                    AlertDialog(
                                                  title: const Text('永久删除条目？'),
                                                  content: Text(
                                                    '“${item.title}”将被永久删除，且无法恢复。',
                                                  ),
                                                  actions: [
                                                    TextButton(
                                                      onPressed: () =>
                                                          Navigator.of(
                                                                  dialogContext)
                                                              .pop(false),
                                                      child: const Text('取消'),
                                                    ),
                                                    FilledButton(
                                                      onPressed: () =>
                                                          Navigator.of(
                                                                  dialogContext)
                                                              .pop(true),
                                                      child: const Text('永久删除'),
                                                    ),
                                                  ],
                                                ),
                                              );
                                              if (confirmed == true) {
                                                await controller
                                                    .deleteItemPermanently(
                                                        item.id);
                                              }
                                            },
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _AndroidCategoriesSheet extends StatelessWidget {
  const _AndroidCategoriesSheet({
    required this.controller,
    required this.onReordered,
  });

  final VaultController controller;
  final ValueChanged<List<String>> onReordered;

  Future<void> _showNameDialog(
    BuildContext context, {
    required String title,
    String initialName = '',
    required Future<VaultOperationResult> Function(String name) onSubmit,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => _CategoryNameDialog(
        title: title,
        initialName: initialName,
        onSubmit: onSubmit,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.68,
      minChildSize: 0.45,
      maxChildSize: 0.94,
      builder: (context, scrollController) => SafeArea(
        top: false,
        child: AnimatedBuilder(
          animation: controller,
          builder: (context, _) {
            final categories = controller.vaultData.categories.toList();
            final counts = <String, int>{
              for (final category in categories)
                category.id: controller.vaultData.activeItems
                    .where((item) => item.folder == category.id)
                    .length,
            };
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '分类管理',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                      ),
                      IconButton(
                        key: const ValueKey('android-category-add'),
                        tooltip: '新建分类',
                        onPressed: controller.busy
                            ? null
                            : () => _showNameDialog(
                                  context,
                                  title: '新建分类',
                                  onSubmit: controller.addCategory,
                                ),
                        icon: const Icon(Icons.add_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: categories.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.folder_off_outlined, size: 34),
                                const SizedBox(height: 8),
                                const Text('还没有分类'),
                                Text(
                                  '新增分类后，可在条目菜单中移动密码。',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          )
                        : ReorderableListView.builder(
                            scrollController: scrollController,
                            buildDefaultDragHandles: false,
                            itemCount: categories.length,
                            itemBuilder: (context, index) {
                              final category = categories[index];
                              return ListTile(
                                key:
                                    ValueKey('android-category-${category.id}'),
                                leading: const Icon(Icons.folder_outlined),
                                title: Text(category.name),
                                subtitle:
                                    Text('${counts[category.id] ?? 0} 条密码'),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    ReorderableDragStartListener(
                                      index: index,
                                      child: Tooltip(
                                        message: '拖动调整分类顺序',
                                        child: SizedBox(
                                          key: ValueKey(
                                              'android-category-drag-${category.id}'),
                                          width: 48,
                                          height: 48,
                                          child: const Icon(Icons.drag_handle),
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: '重命名 ${category.name}',
                                      icon: const Icon(Icons.edit_outlined),
                                      onPressed: controller.busy
                                          ? null
                                          : () => _showNameDialog(
                                                context,
                                                title: '重命名分类',
                                                initialName: category.name,
                                                onSubmit: (name) =>
                                                    controller.renameCategory(
                                                  categoryId: category.id,
                                                  name: name,
                                                ),
                                              ),
                                    ),
                                    IconButton(
                                      tooltip: '删除 ${category.name}',
                                      icon: const Icon(
                                          Icons.delete_outline_rounded),
                                      onPressed: controller.busy
                                          ? null
                                          : () async {
                                              final confirmed =
                                                  await showDialog<bool>(
                                                context: context,
                                                builder: (dialogContext) =>
                                                    AlertDialog(
                                                  title: const Text('删除分类？'),
                                                  content: Text(
                                                    '“${category.name}”中的密码会移回未分类，密码不会删除。',
                                                  ),
                                                  actions: [
                                                    TextButton(
                                                      onPressed: () =>
                                                          Navigator.of(
                                                                  dialogContext)
                                                              .pop(false),
                                                      child: const Text('取消'),
                                                    ),
                                                    FilledButton(
                                                      onPressed: () =>
                                                          Navigator.of(
                                                                  dialogContext)
                                                              .pop(true),
                                                      child: const Text('删除分类'),
                                                    ),
                                                  ],
                                                ),
                                              );
                                              if (confirmed == true) {
                                                await controller.deleteCategory(
                                                    category.id);
                                              }
                                            },
                                    ),
                                  ],
                                ),
                              );
                            },
                            onReorderItem: (oldIndex, newIndex) {
                              final orderedIds = categories
                                  .map((category) => category.id)
                                  .toList();
                              final movedId = orderedIds.removeAt(oldIndex);
                              orderedIds.insert(newIndex, movedId);
                              onReordered(orderedIds);
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

Future<void> _showAndroidCategoryPicker(
  BuildContext context, {
  required VaultController controller,
  required VaultItem item,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => SafeArea(
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final categories = controller.vaultData.categories.toList();
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '移动“${item.title}”',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  '选择一个分类，或选择未分类。',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      ListTile(
                        key: const ValueKey('android-category-none'),
                        leading: const Icon(Icons.inbox_outlined),
                        title: const Text('未分类'),
                        trailing: item.folder.isEmpty
                            ? const Icon(Icons.check_rounded)
                            : null,
                        onTap: () async {
                          final result = await controller.assignItemToCategory(
                            itemId: item.id,
                          );
                          if (!sheetContext.mounted) return;
                          if (result.succeeded) {
                            Navigator.of(sheetContext).pop();
                          }
                        },
                      ),
                      for (final category in categories)
                        ListTile(
                          key: ValueKey('android-move-${category.id}'),
                          leading: const Icon(Icons.folder_outlined),
                          title: Text(category.name),
                          trailing: item.folder == category.id
                              ? const Icon(Icons.check_rounded)
                              : null,
                          onTap: () async {
                            final result =
                                await controller.assignItemToCategory(
                              itemId: item.id,
                              categoryId: category.id,
                            );
                            if (!sheetContext.mounted) return;
                            if (result.succeeded) {
                              Navigator.of(sheetContext).pop();
                            }
                          },
                        ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    ),
  );
}

class _AndroidCategoryChip extends StatefulWidget {
  const _AndroidCategoryChip({
    super.key,
    required this.label,
    required this.active,
    required this.onTap,
    this.onItemDropped,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;
  final ValueChanged<String>? onItemDropped;

  @override
  State<_AndroidCategoryChip> createState() => _AndroidCategoryChipState();
}

class _AndroidCategoryChipState extends State<_AndroidCategoryChip> {
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final chip = Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        selected: widget.active,
        showCheckmark: false,
        label: Text(widget.label),
        onSelected: (_) => widget.onTap(),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(
            color: _dragging ? colorScheme.primary : colorScheme.outlineVariant,
          ),
        ),
      ),
    );
    if (widget.onItemDropped == null) {
      return chip;
    }
    return DragTarget<VaultItem>(
      onWillAcceptWithDetails: (_) => true,
      onAcceptWithDetails: (details) =>
          widget.onItemDropped?.call(details.data.id),
      onMove: (_) {
        if (!_dragging) {
          setState(() {
            _dragging = true;
          });
        }
      },
      onLeave: (_) {
        if (_dragging) {
          setState(() {
            _dragging = false;
          });
        }
      },
      builder: (context, candidateData, rejectedData) => chip,
    );
  }
}

class _AndroidDraggedEntryCard extends StatelessWidget {
  const _AndroidDraggedEntryCard({
    required this.item,
    required this.accountInfo,
  });

  final VaultItem item;
  final String accountInfo;

  @override
  Widget build(BuildContext context) {
    final title = item.title.trim().isEmpty ? '未命名' : item.title;
    final leadingText = title.isEmpty ? '•' : title[0].toUpperCase();
    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(12),
      color: Theme.of(context).colorScheme.surface,
      child: Container(
        width: 250,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Theme.of(context).colorScheme.primary),
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                leadingText,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: Theme.of(context).colorScheme.onSecondaryContainer,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (accountInfo.isNotEmpty)
                    Text(
                      accountInfo,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AndroidImportSheet extends StatefulWidget {
  const _AndroidImportSheet({required this.controller});

  final VaultController controller;

  @override
  State<_AndroidImportSheet> createState() => _AndroidImportSheetState();
}

class _AndroidImportSheetState extends State<_AndroidImportSheet> {
  final _passwordController = TextEditingController();
  ImportPlan? _plan;
  bool _loading = false;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _preview() async {
    setState(() {
      _loading = true;
    });
    final plan =
        await widget.controller.previewImport(_passwordController.text);
    if (!mounted) {
      return;
    }
    setState(() {
      _loading = false;
      _plan = plan;
    });
  }

  Future<void> _apply() async {
    final plan = _plan;
    if (plan == null) {
      return;
    }
    setState(() {
      _loading = true;
    });
    final result = await widget.controller.applyImportPlan(plan);
    if (!mounted) {
      return;
    }
    if (result.succeeded) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _loading = false;
    });
  }

  Future<void> _importFromBitwarden() async {
    final plan = await widget.controller.previewBitwardenImport();
    if (!mounted || plan == null) {
      return;
    }
    final decisions = await _showBitwardenImportDialog(context, plan);
    if (!mounted || decisions == null) {
      return;
    }
    final result = await widget.controller.applyBitwardenImport(
      plan,
      decisions: decisions,
    );
    if (!mounted) {
      return;
    }
    if (result.succeeded) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final summary = _plan?.summary;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.68,
      minChildSize: 0.5,
      maxChildSize: 0.94,
      builder: (context, scrollController) => SafeArea(
        top: false,
        child: ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            Text('导入加密备份', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            const Text('选择备份文件后先预览变更，再确认导入。'),
            const SizedBox(height: 16),
            TextField(
              controller: _passwordController,
              obscureText: true,
              enableSuggestions: false,
              autocorrect: false,
              decoration: const InputDecoration(labelText: '导入文件密码'),
            ),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: _loading || widget.controller.busy ? null : _preview,
              icon: const Icon(Icons.preview_rounded),
              label: const Text('选择并预览备份'),
            ),
            const SizedBox(height: 18),
            const Divider(height: 1),
            const SizedBox(height: 14),
            Text(
              '从 Bitwarden 导入',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            const Text('支持未加密 JSON 和 CSV。重复候选必须在预览中人工确认。'),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _loading || widget.controller.busy
                  ? null
                  : _importFromBitwarden,
              icon: const Icon(Icons.compare_arrows_rounded),
              label: const Text('选择 Bitwarden 文件并核验'),
            ),
            if (summary != null) ...[
              const SizedBox(height: 20),
              Text('导入预览', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text('条目：${summary.incomingItems}'),
              Text('新增：${summary.newItems}  更新：${summary.updatedItems}'),
              Text('删除：${summary.deletedItems}  未变：${summary.unchangedItems}'),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _loading || widget.controller.busy ? null : _apply,
                icon: const Icon(Icons.download_done_rounded),
                label: const Text('确认导入'),
              ),
            ],
            if (_loading) ...[
              const SizedBox(height: 16),
              const Center(child: CircularProgressIndicator()),
            ],
          ],
        ),
      ),
    );
  }
}

class _AndroidExportSheet extends StatefulWidget {
  const _AndroidExportSheet({required this.controller});

  final VaultController controller;

  @override
  State<_AndroidExportSheet> createState() => _AndroidExportSheetState();
}

class _AndroidExportSheetState extends State<_AndroidExportSheet> {
  final _passwordController = TextEditingController();
  bool _exporting = false;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _export() async {
    setState(() {
      _exporting = true;
    });
    final result = await widget.controller.exportVault(
      exportPassword: _passwordController.text,
    );
    if (!mounted) {
      return;
    }
    if (result.succeeded) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _exporting = false;
    });
  }

  Future<void> _exportBitwarden(BitwardenExchangeFormat format) async {
    final confirmed = await _confirmBitwardenExport(context, format);
    if (!mounted || !confirmed) {
      return;
    }
    setState(() {
      _exporting = true;
    });
    final result = await widget.controller.exportBitwarden(format);
    if (!mounted) {
      return;
    }
    if (result.succeeded) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _exporting = false;
    });
  }

  Future<void> _exportBitwardenDelta() async {
    setState(() {
      _exporting = true;
    });
    final succeeded = await _startBitwardenDeltaExport(
      context,
      widget.controller,
    );
    if (!mounted) {
      return;
    }
    if (succeeded) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _exporting = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.55,
      minChildSize: 0.4,
      maxChildSize: 0.8,
      builder: (context, scrollController) => SafeArea(
        top: false,
        child: ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            Text('导出加密备份', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            const Text('备份始终加密；可另设独立导出密码。'),
            const SizedBox(height: 16),
            TextField(
              controller: _passwordController,
              obscureText: true,
              enableSuggestions: false,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: '独立导出密码（可选）',
                helperText: '留空表示沿用当前密码库加密。',
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _exporting || widget.controller.busy ? null : _export,
              icon: const Icon(Icons.upload_rounded),
              label: const Text('选择位置并导出'),
            ),
            const SizedBox(height: 18),
            const Divider(height: 1),
            const SizedBox(height: 14),
            Text(
              '导出到 Bitwarden',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            const Text('交换文件包含明文凭据。导入 Bitwarden 后请立即删除。'),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _exporting || widget.controller.busy
                      ? null
                      : () => _exportBitwarden(BitwardenExchangeFormat.json),
                  icon: const Icon(Icons.data_object_rounded),
                  label: const Text('导出 JSON'),
                ),
                OutlinedButton.icon(
                  onPressed: _exporting || widget.controller.busy
                      ? null
                      : () => _exportBitwarden(BitwardenExchangeFormat.csv),
                  icon: const Icon(Icons.table_rows_rounded),
                  label: const Text('导出 CSV'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _exporting || widget.controller.busy
                  ? null
                  : _exportBitwardenDelta,
              icon: const Icon(Icons.rule_rounded),
              label: const Text('核对 Bitwarden 并导出缺失项'),
            ),
            const SizedBox(height: 4),
            const Text('以 Bitwarden 最新导出为基线，只导出其中不存在的本机条目。'),
            if (_exporting) ...[
              const SizedBox(height: 16),
              const Center(child: CircularProgressIndicator()),
            ],
          ],
        ),
      ),
    );
  }
}

class _AndroidSettingsSheet extends StatefulWidget {
  const _AndroidSettingsSheet({
    required this.controller,
  });

  final VaultController controller;

  @override
  State<_AndroidSettingsSheet> createState() => _AndroidSettingsSheetState();
}

class _AndroidSettingsSheetState extends State<_AndroidSettingsSheet> {
  final _oldPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  bool _changingPassword = false;

  @override
  void dispose() {
    _oldPasswordController.dispose();
    _newPasswordController.dispose();
    super.dispose();
  }

  Future<void> _changeMasterPassword() async {
    setState(() {
      _changingPassword = true;
    });
    final result = await widget.controller.changeMasterPassword(
      oldPassword: _oldPasswordController.text,
      newPassword: _newPasswordController.text,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _changingPassword = false;
      if (result.succeeded) {
        _oldPasswordController.clear();
        _newPasswordController.clear();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.84,
      minChildSize: 0.5,
      maxChildSize: 0.96,
      builder: (context, scrollController) => SafeArea(
        top: false,
        child: AnimatedBuilder(
          animation: widget.controller,
          builder: (context, _) => ListView(
            key: const ValueKey('android-settings-sheet'),
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [
              Text('设置', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 16),
              Text('自动锁定', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              const Text('此设置仅在当前应用会话中生效。'),
              const SizedBox(height: 8),
              DropdownButtonFormField<AutoLockPreset>(
                initialValue: widget.controller.autoLockPreset,
                isExpanded: true,
                decoration: const InputDecoration(labelText: '闲置自动锁定时间'),
                items: AutoLockPreset.values
                    .map(
                      (preset) => DropdownMenuItem(
                        value: preset,
                        child: Text(preset.label),
                      ),
                    )
                    .toList(),
                onChanged: widget.controller.busy
                    ? null
                    : (preset) {
                        if (preset != null) {
                          widget.controller.setAutoLockPreset(preset);
                        }
                      },
              ),
              const SizedBox(height: 20),
              Text('快速解锁', style: Theme.of(context).textTheme.titleMedium),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: widget.controller.quickUnlockEnabled,
                onChanged: !widget.controller.quickUnlockSupported ||
                        widget.controller.busy
                    ? null
                    : (enabled) async {
                        if (enabled) {
                          await widget.controller.enableQuickUnlock();
                        } else {
                          await widget.controller.disableQuickUnlock();
                        }
                      },
                title: const Text('使用系统认证'),
                subtitle: Text(
                  widget.controller.quickUnlockSupported
                      ? '使用设备安全认证保护会话密钥。'
                      : '当前设备不支持快速解锁。',
                ),
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: widget.controller.allowQuickUnlockOnFirstLaunch,
                onChanged: !widget.controller.quickUnlockSupported ||
                        !widget.controller.quickUnlockEnabled ||
                        widget.controller.busy
                    ? null
                    : (enabled) async {
                        await widget.controller
                            .setAllowQuickUnlockOnFirstLaunch(enabled);
                      },
                title: const Text('冷启动直接快速解锁'),
                subtitle: Text(
                  !widget.controller.quickUnlockSupported
                      ? '当前设备不支持快速解锁。'
                      : !widget.controller.quickUnlockEnabled
                          ? '请先开启使用系统认证。'
                          : '启动应用后可直接使用系统认证，无需先输入一次主密码。',
                ),
              ),
              const Divider(height: 32),
              Text('修改主密码', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              TextField(
                controller: _oldPasswordController,
                obscureText: true,
                enableSuggestions: false,
                autocorrect: false,
                decoration: const InputDecoration(labelText: '当前主密码'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _newPasswordController,
                obscureText: true,
                enableSuggestions: false,
                autocorrect: false,
                decoration: const InputDecoration(labelText: '新主密码'),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _changingPassword || widget.controller.busy
                    ? null
                    : _changeMasterPassword,
                icon: const Icon(Icons.key_rounded),
                label: const Text('修改主密码'),
              ),
              if (_changingPassword) ...[
                const SizedBox(height: 16),
                const Center(child: CircularProgressIndicator()),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _TotpPanel extends StatefulWidget {
  const _TotpPanel({
    required this.secretOrUri,
    required this.onCopy,
  });

  final String secretOrUri;
  final Future<void> Function(String text) onCopy;

  @override
  State<_TotpPanel> createState() => _TotpPanelState();
}

class _TotpPanelState extends State<_TotpPanel> {
  Timer? _timer;
  TotpResult? _result;
  Object? _error;
  int _secondsRemaining = 0;
  int? _counter;
  int _requestGeneration = 0;

  @override
  void initState() {
    super.initState();
    _refreshCode();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  @override
  void didUpdateWidget(covariant _TotpPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.secretOrUri != widget.secretOrUri) {
      _result = null;
      _error = null;
      _counter = null;
      _refreshCode();
    }
  }

  Future<void> _refreshCode() async {
    final requestGeneration = ++_requestGeneration;
    final timestamp = DateTime.now();
    try {
      final result = await _totpService.generate(
        widget.secretOrUri,
        timestamp: timestamp,
      );
      if (!mounted || requestGeneration != _requestGeneration) {
        return;
      }
      setState(() {
        _result = result;
        _error = null;
        _secondsRemaining = result.secondsRemaining;
        _counter = timestamp.millisecondsSinceEpoch ~/
            Duration.millisecondsPerSecond ~/
            result.periodSeconds;
      });
    } on Object catch (error) {
      if (!mounted || requestGeneration != _requestGeneration) {
        return;
      }
      setState(() {
        _result = null;
        _error = error;
      });
    }
  }

  void _tick() {
    final result = _result;
    if (!mounted || result == null) {
      return;
    }
    final nowSeconds =
        DateTime.now().millisecondsSinceEpoch ~/ Duration.millisecondsPerSecond;
    final counter = nowSeconds ~/ result.periodSeconds;
    final secondsRemaining =
        result.periodSeconds - (nowSeconds % result.periodSeconds);
    if (counter != _counter) {
      // Record the boundary before starting asynchronous HMAC work so a slow
      // calculation cannot allocate another Future on every timer tick.
      _counter = counter;
      _refreshCode();
      return;
    }
    if (secondsRemaining != _secondsRemaining) {
      setState(() {
        _secondsRemaining = secondsRemaining;
      });
    }
  }

  @override
  void dispose() {
    _requestGeneration++;
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return const _DetailRow(label: 'TOTP', value: 'TOTP 解析失败');
    }
    final result = _result;
    if (result == null) {
      return const _DetailRow(label: 'TOTP', value: '正在生成...');
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(width: 92, child: Text('TOTP:')),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(
                  result.code,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                Text(
                  '$_secondsRemaining 秒后刷新',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () {
              widget.onCopy(result.code);
            },
            icon: const Icon(Icons.copy_outlined),
            tooltip: '复制当前 TOTP',
          ),
        ],
      ),
    );
  }
}

class _FrostedSurface extends StatelessWidget {
  const _FrostedSurface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(10),
    this.borderRadius = const BorderRadius.all(Radius.circular(8)),
    this.sigma = 14,
    this.tint,
    this.borderColor,
    this.shadowColor,
    this.enableBlur = true,
    this.specularStrength = 1,
    this.plainOnAndroid = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final BorderRadius borderRadius;
  final double sigma;
  final Color? tint;
  final Color? borderColor;
  final Color? shadowColor;
  final bool enableBlur;
  final double specularStrength;
  final bool plainOnAndroid;

  @override
  Widget build(BuildContext context) {
    if (Theme.of(context).platform == TargetPlatform.android) {
      if (plainOnAndroid) {
        return Padding(padding: padding, child: child);
      }
      return Material(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        elevation: 0,
        borderRadius: borderRadius,
        clipBehavior: Clip.antiAlias,
        child: Padding(padding: padding, child: child),
      );
    }
    return Material(
      color: Colors.white,
      elevation: 0,
      borderRadius: borderRadius,
      clipBehavior: Clip.antiAlias,
      child: Container(
        padding: padding,
        decoration: BoxDecoration(
          borderRadius: borderRadius,
          border: Border.all(
            color: borderColor ?? const Color(0xFFD9DEE5),
          ),
        ),
        child: child,
      ),
    );
  }
}
