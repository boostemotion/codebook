import 'dart:ui';

import 'package:flutter/material.dart';

import '../models/vault_models.dart';
import '../services/totp_service.dart';
import '../state/vault_controller.dart';

const TotpService _totpService = TotpService();
const Color _kDialogBarrierColor = Color(0x4A140A11);

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
  bool _searchKeyboardWasVisible = false;
  bool _wasUnlocked = false;
  bool _canSubmitMasterPassword = false;

  String _searchQuery = '';
  _SortMode _sortMode = _SortMode.frequent;

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
    _vaultScrollController.dispose();
    _masterPasswordController.dispose();
    _importPasswordController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _masterPasswordController.clear();
      _importPasswordController.clear();
      _canSubmitMasterPassword = false;
      _searchFocusNode.unfocus();
      widget.controller.handleAppPaused();
    }
  }

  void _handleControllerChanged() {
    final isUnlocked = widget.controller.isUnlocked;
    if (_wasUnlocked != isUnlocked) {
      if (!isUnlocked) {
        _masterPasswordController.clear();
        _canSubmitMasterPassword = false;
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
      return;
    }
    if (_searchKeyboardWasVisible && _searchFocusNode.hasFocus) {
      _searchFocusNode.unfocus();
    }
    _searchKeyboardWasVisible = false;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        return Scaffold(
          extendBody: true,
          body: Listener(
            onPointerDown: (_) => widget.controller.registerActivity(),
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
                                final platform = Theme.of(context).platform;
                                final isDesktopPlatform =
                                    platform == TargetPlatform.windows ||
                                        platform == TargetPlatform.macOS ||
                                        platform == TargetPlatform.linux;
                                final maxWidth = isDesktopPlatform
                                    ? 1240.0
                                    : double.infinity;

                                return Align(
                                  alignment: Alignment.topCenter,
                                  child: ConstrainedBox(
                                    constraints:
                                        BoxConstraints(maxWidth: maxWidth),
                                    child: _VaultView(
                                      controller: widget.controller,
                                      searchController: _searchController,
                                      searchFocusNode: _searchFocusNode,
                                      isSearchFocused:
                                          _searchFocusNode.hasFocus,
                                      scrollController: _vaultScrollController,
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
                              canSubmitMasterPassword: _canSubmitMasterPassword,
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
        );
      },
    );
  }
}

class _GlassBackground extends StatelessWidget {
  const _GlassBackground();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFFF7F1F2),
                  Color(0xFFF1E8EC),
                  Color(0xFFEDE3E8),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          top: -120,
          left: -90,
          child: IgnorePointer(
            child: Container(
              width: 280,
              height: 280,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [Color(0x66E7BBCB), Color(0x00E7BBCB)],
                ),
              ),
            ),
          ),
        ),
        Positioned(
          right: -130,
          bottom: -120,
          child: IgnorePointer(
            child: Container(
              width: 320,
              height: 320,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [Color(0x55E4C4D0), Color(0x00E4C4D0)],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _LockedView extends StatelessWidget {
  const _LockedView({
    required this.controller,
    required this.masterPasswordController,
    required this.importPasswordController,
    required this.canSubmitMasterPassword,
    required this.onMasterPasswordChanged,
  });

  final VaultController controller;
  final TextEditingController masterPasswordController;
  final TextEditingController importPasswordController;
  final bool canSubmitMasterPassword;
  final ValueChanged<String> onMasterPasswordChanged;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          child: _FrostedSurface(
            sigma: 24,
            padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  controller.hasVault ? '解锁密码本' : '创建密码本',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
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
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _VaultView extends StatelessWidget {
  const _VaultView({
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
  Widget build(BuildContext context) {
    final keyboardVisible = MediaQuery.viewInsetsOf(context).bottom > 0;
    final viewportWidth = MediaQuery.sizeOf(context).width;
    final platform = Theme.of(context).platform;
    final isDesktopPlatform = platform == TargetPlatform.windows ||
        platform == TargetPlatform.macOS ||
        platform == TargetPlatform.linux;
    final shouldHideDock =
        keyboardVisible || (!isDesktopPlatform && isSearchFocused);
    final dockMaxWidth = isDesktopPlatform ? 980.0 : double.infinity;
    final items = controller.vaultData.activeItems.where((item) {
      if (searchQuery.isEmpty) {
        return true;
      }
      final haystack = [
        item.title,
        item.username,
        item.url,
        item.notes,
        item.tags.join(' '),
      ].join(' ').toLowerCase();
      return haystack.contains(searchQuery);
    }).toList()
      ..sort((a, b) {
        if (sortMode == _SortMode.alphabetical) {
          return a.title.toLowerCase().compareTo(b.title.toLowerCase());
        }
        final byUpdatedAt = b.updatedAt.compareTo(a.updatedAt);
        if (byUpdatedAt != 0) {
          return byUpdatedAt;
        }
        return a.title.toLowerCase().compareTo(b.title.toLowerCase());
      });

    return Stack(
      children: [
        Positioned.fill(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (isDesktopPlatform)
                Padding(
                  key: const ValueKey('vault-header'),
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    '共 ${items.length} 条',
                    textAlign: TextAlign.right,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: const Color(0xA54A373F),
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.2,
                        ),
                  ),
                ),
              _SearchField(
                key: const ValueKey('vault-toolbar'),
                controller: searchController,
                focusNode: searchFocusNode,
                onChanged: onSearchChanged,
                sortMode: sortMode,
                onClear: () {
                  searchController.clear();
                  onSearchChanged('');
                },
                onSortModeChanged: onSortModeChanged,
              ),
              const SizedBox(height: 8),
              Expanded(
                child: items.isEmpty
                    ? _FrostedSurface(
                        key: const ValueKey('vault-empty'),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 22,
                        ),
                        child: Center(
                          child: Text(
                            searchQuery.isEmpty ? '还没有条目' : '没有匹配条目',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                      )
                    : ListView.separated(
                        key: const ValueKey('vault-list'),
                        controller: scrollController,
                        itemCount: items.length,
                        padding: EdgeInsets.fromLTRB(
                          0,
                          0,
                          0,
                          isDesktopPlatform ? 96 : 116,
                        ),
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
                              isDesktop: isDesktopPlatform,
                              onView: () => _showItemDetails(
                                context,
                                controller: controller,
                                item: item,
                              ),
                              onCopy: () =>
                                  controller.copySecret(item.password),
                              onEdit: () => _showItemEditor(
                                context,
                                controller: controller,
                                item: item,
                              ),
                              onDelete: () => controller.deleteItem(item.id),
                            ),
                          );
                        },
                      ),
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
                      axisAlignment: 1,
                      child: FadeTransition(opacity: animation, child: child),
                    );
                  },
                  child: shouldHideDock
                      ? const SizedBox.shrink(
                          key: ValueKey('liquid-dock-hidden'))
                      : _BottomActionDock(
                          key: const ValueKey('liquid-dock'),
                          controller: controller,
                        ),
                ),
              ),
            ),
          ),
        ),
      ],
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
            borderRadius: BorderRadius.circular(24),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            tint: const Color(0x20FFFFFF),
            borderColor: const Color(0xA6FFFFFF),
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
                  color: Color(0x8A6E5A63),
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
      borderRadius: BorderRadius.circular(24),
      padding: EdgeInsets.zero,
      tint: const Color(0x20FFFFFF),
      borderColor: const Color(0xA6FFFFFF),
      child: Tooltip(
        message: '排序方式',
        child: Semantics(
          button: true,
          label: '排序方式',
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(24),
              onTap: () async {
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
                        color: Color(0xFF5F4A53),
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(
                      Icons.unfold_more_rounded,
                      size: 16,
                      color: Color(0xCC5F4A53),
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
  frequent('\u5e38\u7528\u6392\u5e8f', '\u5e38\u7528'),
  alphabetical('\u5b57\u6bcd\u6392\u5e8f', '\u5b57\u6bcd');

  const _SortMode(this.label, this.shortLabel);
  final String label;
  final String shortLabel;
}

Future<_SortMode?> _showSortModePicker(
  BuildContext context,
  _SortMode mode,
) {
  return _showGlassDialog<_SortMode>(
    context: context,
    builder: (context) {
      Widget option(_SortMode item) {
        final active = item == mode;
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => Navigator.of(context).pop(item),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                color: active ? const Color(0x2EFFFFFF) : Colors.transparent,
                border: Border.all(
                  color: active
                      ? const Color(0xC4FFFFFF)
                      : const Color(0x74FFFFFF),
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
                        color: const Color(0xFF3B2932),
                      ),
                    ),
                  ),
                  if (active)
                    const Icon(
                      Icons.check_rounded,
                      size: 18,
                      color: Color(0xFF563842),
                    ),
                ],
              ),
            ),
          ),
        );
      }

      return Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        child: _FrostedSurface(
          sigma: 18,
          borderRadius: BorderRadius.circular(24),
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
          tint: const Color(0x24FFFFFF),
          borderColor: const Color(0xAAFFFFFF),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              option(_SortMode.frequent),
              option(_SortMode.alphabetical),
            ],
          ),
        ),
      );
    },
  );
}

class _BottomActionDock extends StatefulWidget {
  const _BottomActionDock({
    super.key,
    required this.controller,
  });

  final VaultController controller;

  @override
  State<_BottomActionDock> createState() => _BottomActionDockState();
}

class _BottomActionDockState extends State<_BottomActionDock> {
  int _activeIndex = 0;

  @override
  Widget build(BuildContext context) {
    final items = <_DockActionData>[
      _DockActionData(
        icon: Icons.add_circle_outline_rounded,
        label: '新增',
        onTap: () => _showItemEditor(context, controller: widget.controller),
      ),
      _DockActionData(
        icon: Icons.download_rounded,
        label: '导入',
        onTap: () => _showImportDialog(context, widget.controller),
      ),
      _DockActionData(
        icon: Icons.upload_file_rounded,
        label: '导出',
        onTap: () => _showExportDialog(context, widget.controller),
      ),
      _DockActionData(
        icon: Icons.settings_rounded,
        label: '设置',
        onTap: () => _openSettingsMenu(context),
      ),
    ];

    return _FrostedSurface(
      sigma: 20,
      borderRadius: BorderRadius.circular(34),
      padding: const EdgeInsets.fromLTRB(6, 6, 6, 5),
      tint: const Color(0x1FFFFFFF),
      borderColor: const Color(0xB2FFFFFF),
      shadowColor: const Color(0x2A291B21),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final slotWidth = constraints.maxWidth / items.length;
          return SizedBox(
            height: 58,
            child: Stack(
              children: [
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOutCubic,
                  left: (slotWidth * _activeIndex) + 3,
                  top: 2,
                  bottom: 2,
                  width: slotWidth - 6,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(30),
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color(0xA3FFFFFF),
                          Color(0x52FFFFFF),
                        ],
                      ),
                      border: Border.all(color: const Color(0xD6FFFFFF)),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x304A303A),
                          blurRadius: 10,
                          offset: Offset(0, 3),
                        ),
                      ],
                    ),
                    child: const DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.all(Radius.circular(30)),
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Color(0x6EFFFFFF),
                            Color(0x00FFFFFF),
                          ],
                        ),
                      ),
                    ),
                  ),
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
                            setState(() {
                              _activeIndex = i;
                            });
                            items[i].onTap();
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

  Future<void> _openSettingsMenu(BuildContext context) async {
    final action = await showModalBottomSheet<_DockSettingAction>(
      context: context,
      builder: (context) {
        final enabled = widget.controller.quickUnlockEnabled;
        final supported = widget.controller.quickUnlockSupported;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.key_rounded),
                  title: const Text('修改主密码'),
                  onTap: () {
                    Navigator.of(context)
                        .pop(_DockSettingAction.changePassword);
                  },
                ),
                ListTile(
                  leading: Icon(
                    enabled
                        ? Icons.phonelink_lock_outlined
                        : Icons.fingerprint_rounded,
                  ),
                  title: Text(enabled ? '关闭快速解锁' : '开启快速解锁'),
                  subtitle: Text(supported ? '使用系统认证保护会话密钥' : '当前设备不支持'),
                  enabled: supported,
                  onTap: !supported
                      ? null
                      : () {
                          Navigator.of(context).pop(
                            enabled
                                ? _DockSettingAction.disableQuickUnlock
                                : _DockSettingAction.enableQuickUnlock,
                          );
                        },
                ),
              ],
            ),
          ),
        );
      },
    );

    if (!context.mounted || action == null) {
      return;
    }
    switch (action) {
      case _DockSettingAction.changePassword:
        await _showChangePasswordDialog(context, widget.controller);
      case _DockSettingAction.enableQuickUnlock:
        await widget.controller.enableQuickUnlock();
      case _DockSettingAction.disableQuickUnlock:
        await widget.controller.disableQuickUnlock();
    }
  }
}

class _DockActionData {
  const _DockActionData({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
}

enum _DockSettingAction {
  changePassword,
  enableQuickUnlock,
  disableQuickUnlock,
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
    final titleStyle = Theme.of(context).textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w900,
          fontSize: 19,
          height: 1.0,
          letterSpacing: -0.15,
          color: const Color(0xFF241A1E),
        );
    final accountStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
          fontWeight: FontWeight.w500,
          fontSize: 12,
          color: const Color(0xFF5B4A51),
        );

    final tint = _hovered ? const Color(0x1EFFFFFF) : const Color(0x12FFFFFF);
    final border = _hovered ? const Color(0xBCFFFFFF) : const Color(0x95FFFFFF);

    return MouseRegion(
      onEnter: widget.isDesktop ? (_) => setState(() => _hovered = true) : null,
      onExit: widget.isDesktop ? (_) => setState(() => _hovered = false) : null,
      child: AnimatedScale(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        scale: _hovered ? 1.006 : 1.0,
        child: _FrostedSurface(
          sigma: 12,
          enableBlur: true,
          tint: tint,
          borderColor: border,
          borderRadius: BorderRadius.circular(14),
          padding: const EdgeInsets.fromLTRB(9, 5, 4, 5),
          child: Row(
            children: [
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: widget.item.title, style: titleStyle),
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
    );
  }
}

class _MiniActionButton extends StatefulWidget {
  const _MiniActionButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

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

    return MouseRegion(
      onEnter:
          isDesktopPlatform ? (_) => setState(() => _hovered = true) : null,
      onExit:
          isDesktopPlatform ? (_) => setState(() => _hovered = false) : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: _hovered ? const Color(0x2BFFFFFF) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: IconButton(
          onPressed: widget.onTap,
          icon: Icon(widget.icon, color: const Color(0xFF3C2C32)),
          tooltip: widget.tooltip,
          iconSize: 15,
          splashRadius: 14,
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
          padding: const EdgeInsets.all(3),
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
}) {
  return showDialog<T>(
    context: context,
    barrierColor: _kDialogBarrierColor,
    builder: (context) => _DockPopupEntrance(child: builder(context)),
  );
}

Future<void> _showImportDialog(
  BuildContext context,
  VaultController controller,
) async {
  final passwordController = TextEditingController();
  final confirmedPassword = await _showGlassDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('输入导入文件密码'),
      content: TextField(
        controller: passwordController,
        obscureText: true,
        decoration: const InputDecoration(
          labelText: '导入文件密码',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('继续'),
        ),
      ],
    ),
  );

  if (confirmedPassword != true || !context.mounted) {
    passwordController.dispose();
    return;
  }

  final plan = await controller.previewImport(passwordController.text);
  passwordController.dispose();
  if (plan == null || !context.mounted) {
    return;
  }

  final confirmedImport = await _showImportSummaryDialog(context, plan.summary);
  if (confirmedImport == true && context.mounted) {
    await controller.applyImportPlan(plan);
  }
}

Future<bool?> _showImportSummaryDialog(
  BuildContext context,
  ImportMergeSummary summary,
) {
  return _showGlassDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('导入预览'),
      content: SizedBox(
        width: 380,
        child: _ImportSummaryView(summary: summary),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('确认导入'),
        ),
      ],
    ),
  );
}

Future<void> _showExportDialog(
  BuildContext context,
  VaultController controller,
) async {
  final passwordController = TextEditingController();
  final confirmed = await _showGlassDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('导出加密备份'),
      content: TextField(
        controller: passwordController,
        obscureText: true,
        decoration: const InputDecoration(
          labelText: '导出密码（可选）',
          helperText: '留空表示沿用当前密码库加密。',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('导出'),
        ),
      ],
    ),
  );
  if (confirmed == true && context.mounted) {
    await controller.exportVault(exportPassword: passwordController.text);
  }
  passwordController.dispose();
}

Future<void> _showChangePasswordDialog(
  BuildContext context,
  VaultController controller,
) async {
  final oldPasswordController = TextEditingController();
  final newPasswordController = TextEditingController();
  final confirmed = await _showGlassDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('修改主密码'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: oldPasswordController,
            obscureText: true,
            decoration: const InputDecoration(labelText: '当前主密码'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: newPasswordController,
            obscureText: true,
            decoration: const InputDecoration(labelText: '新主密码'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('保存'),
        ),
      ],
    ),
  );
  if (confirmed == true && context.mounted) {
    await controller.changeMasterPassword(
      oldPassword: oldPasswordController.text,
      newPassword: newPasswordController.text,
    );
  }
  oldPasswordController.dispose();
  newPasswordController.dispose();
}

Future<void> _showItemEditor(
  BuildContext context, {
  required VaultController controller,
  VaultItem? item,
}) async {
  final titleController = TextEditingController(text: item?.title ?? '');
  final usernameController = TextEditingController(text: item?.username ?? '');
  final passwordController = TextEditingController(text: item?.password ?? '');
  final urlController = TextEditingController(text: item?.url ?? '');
  final notesController = TextEditingController(text: item?.notes ?? '');
  final tagsController =
      TextEditingController(text: item == null ? '' : item.tags.join(', '));
  final totpController = TextEditingController(text: item?.totpSecret ?? '');
  final lengthController = TextEditingController(text: '20');

  final saved = await _showGlassDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(item == null ? '新增条目' : '编辑条目'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                decoration: const InputDecoration(labelText: '名称'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: usernameController,
                decoration: const InputDecoration(labelText: '账号'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: passwordController,
                decoration: const InputDecoration(labelText: '密码'),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: lengthController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: '自动密码长度'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.tonalIcon(
                    onPressed: () {
                      final length = int.tryParse(lengthController.text) ?? 20;
                      passwordController.text =
                          controller.generatePassword(length: length);
                    },
                    icon: const Icon(Icons.password_outlined),
                    label: const Text('生成密码'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: urlController,
                decoration: const InputDecoration(labelText: '网址'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: totpController,
                decoration: const InputDecoration(
                  labelText: 'TOTP 密钥 / otpauth URI',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: tagsController,
                decoration: const InputDecoration(labelText: '标签（逗号分隔）'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: notesController,
                maxLines: 5,
                decoration: const InputDecoration(labelText: '备注'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('保存'),
        ),
      ],
    ),
  );

  if (saved == true && context.mounted) {
    final tags = tagsController.text
        .split(',')
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList();
    await controller.addOrUpdateItem(
      id: item?.id,
      title: titleController.text,
      username: usernameController.text,
      password: passwordController.text,
      url: urlController.text,
      notes: notesController.text,
      tags: tags,
      totpSecret: totpController.text,
    );
  }

  titleController.dispose();
  usernameController.dispose();
  passwordController.dispose();
  urlController.dispose();
  notesController.dispose();
  tagsController.dispose();
  totpController.dispose();
  lengthController.dispose();
}

Future<void> _showItemDetails(
  BuildContext context, {
  required VaultController controller,
  required VaultItem item,
}) {
  return _showGlassDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(item.title),
      content: SizedBox(
        width: 500,
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
                value: item.password,
                onCopy: item.password.isEmpty
                    ? null
                    : () => controller.copySecret(item.password),
              ),
              _DetailRow(label: '网址', value: item.url),
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
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
      ],
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

class _TotpPanel extends StatelessWidget {
  const _TotpPanel({
    required this.secretOrUri,
    required this.onCopy,
  });

  final String secretOrUri;
  final Future<void> Function(String text) onCopy;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DateTime>(
      stream: Stream<DateTime>.periodic(
        const Duration(seconds: 1),
        (_) => DateTime.now(),
      ),
      initialData: DateTime.now(),
      builder: (context, snapshot) {
        return FutureBuilder<TotpResult>(
          future: _totpService.generate(
            secretOrUri,
            timestamp: snapshot.data,
          ),
          builder: (context, resultSnapshot) {
            if (resultSnapshot.hasError) {
              return const _DetailRow(
                label: 'TOTP',
                value: 'TOTP 解析失败',
              );
            }
            if (!resultSnapshot.hasData) {
              return const _DetailRow(
                label: 'TOTP',
                value: '正在生成...',
              );
            }
            final result = resultSnapshot.data!;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(
                    width: 92,
                    child: Text('TOTP:'),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SelectableText(
                          result.code,
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        Text(
                          '${result.secondsRemaining} 秒后刷新',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () {
                      onCopy(result.code);
                    },
                    icon: const Icon(Icons.copy_outlined),
                    tooltip: '复制当前 TOTP',
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _FrostedSurface extends StatelessWidget {
  const _FrostedSurface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(10),
    this.borderRadius = const BorderRadius.all(Radius.circular(18)),
    this.sigma = 14,
    this.tint,
    this.borderColor,
    this.shadowColor,
    this.enableBlur = true,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final BorderRadius borderRadius;
  final double sigma;
  final Color? tint;
  final Color? borderColor;
  final Color? shadowColor;
  final bool enableBlur;

  @override
  Widget build(BuildContext context) {
    final decorated = Container(
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            (tint ?? const Color(0xCCFFFFFF)).withValues(alpha: 0.52),
            (tint ?? const Color(0x88FFFFFF)).withValues(alpha: 0.34),
          ],
        ),
        border: Border.all(
          color: borderColor ?? const Color(0x9AFFFFFF),
          width: 1.1,
        ),
        boxShadow: [
          BoxShadow(
            color: shadowColor ?? const Color(0x201D1116),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );

    if (!enableBlur) {
      return decorated;
    }

    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
        child: decorated,
      ),
    );
  }
}
