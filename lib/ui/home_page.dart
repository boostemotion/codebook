import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

import '../models/vault_models.dart';
import '../services/totp_service.dart';
import '../state/vault_controller.dart';

const TotpService _totpService = TotpService();
const Color _kDialogBarrierColor = Color(0x4A140A11);
final _GlassPerfBus _glassPerfBus = _GlassPerfBus();

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
                  Color(0xFFF0E5EA),
                  Color(0xFFE5D7DF),
                  Color(0xFFDCCDD6),
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
                  colors: [Color(0x7ACF9FB2), Color(0x00CF9FB2)],
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
                  colors: [Color(0x66C9B0BD), Color(0x00C9B0BD)],
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

enum _VaultTab { passwords, add, importVault, exportVault, settings }

extension on _VaultTab {
  String get label => switch (this) {
        _VaultTab.passwords => '密码',
        _VaultTab.add => '新增',
        _VaultTab.importVault => '导入',
        _VaultTab.exportVault => '导出',
        _VaultTab.settings => '设置',
      };

  IconData get icon => switch (this) {
        _VaultTab.passwords => Icons.lock_outline_rounded,
        _VaultTab.add => Icons.add_circle_outline_rounded,
        _VaultTab.importVault => Icons.download_rounded,
        _VaultTab.exportVault => Icons.upload_file_rounded,
        _VaultTab.settings => Icons.settings_rounded,
      };
}

class _VaultView extends StatefulWidget {
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
  State<_VaultView> createState() => _VaultViewState();
}

class _VaultViewState extends State<_VaultView> {
  _VaultTab _tab = _VaultTab.passwords;
  final TextEditingController _addTitleController = TextEditingController();
  final TextEditingController _addUsernameController = TextEditingController();
  final TextEditingController _addPasswordController = TextEditingController();
  final TextEditingController _addUrlController = TextEditingController();
  final TextEditingController _addNotesController = TextEditingController();
  final TextEditingController _addTagsController = TextEditingController();
  final TextEditingController _addTotpController = TextEditingController();
  final TextEditingController _addLengthController = TextEditingController(
    text: '20',
  );
  final TextEditingController _importPasswordController =
      TextEditingController();
  final TextEditingController _exportPasswordController =
      TextEditingController();
  final TextEditingController _oldPasswordController = TextEditingController();
  final TextEditingController _newPasswordController = TextEditingController();

  ImportPlan? _pendingImportPlan;
  ImportMergeSummary? _importSummary;

  @override
  void dispose() {
    _addTitleController.dispose();
    _addUsernameController.dispose();
    _addPasswordController.dispose();
    _addUrlController.dispose();
    _addNotesController.dispose();
    _addTagsController.dispose();
    _addTotpController.dispose();
    _addLengthController.dispose();
    _importPasswordController.dispose();
    _exportPasswordController.dispose();
    _oldPasswordController.dispose();
    _newPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final keyboardVisible = MediaQuery.viewInsetsOf(context).bottom > 0;
    final viewportWidth = MediaQuery.sizeOf(context).width;
    final platform = Theme.of(context).platform;
    final isDesktopPlatform = platform == TargetPlatform.windows ||
        platform == TargetPlatform.macOS ||
        platform == TargetPlatform.linux;
    final shouldHideDock = keyboardVisible ||
        (!isDesktopPlatform &&
            widget.isSearchFocused &&
            _tab == _VaultTab.passwords);
    final dockMaxWidth = isDesktopPlatform ? 980.0 : double.infinity;
    final items = widget.controller.vaultData.activeItems.where((item) {
      if (widget.searchQuery.isEmpty) {
        return true;
      }
      final haystack = [
        item.title,
        item.username,
        item.url,
        item.notes,
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
                    ? _buildPasswordsPage(items, isDesktopPlatform)
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
                      axisAlignment: 1,
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
                            setState(() {
                              _tab = _VaultTab.values[index];
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
      child: ListView.separated(
        key: const ValueKey('vault-list'),
        controller: widget.scrollController,
        itemCount: items.length,
        padding: EdgeInsets.fromLTRB(0, 0, 0, isDesktopPlatform ? 96 : 116),
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
                controller: widget.controller,
                item: item,
              ),
              onCopy: () => widget.controller.copySecret(item.password),
              onEdit: () => _showItemEditor(
                context,
                controller: widget.controller,
                item: item,
              ),
              onDelete: () => widget.controller.deleteItem(item.id),
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
              decoration: const InputDecoration(labelText: '密码'),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _addLengthController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: '自动密码长度'),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.tonalIcon(
                  onPressed: () {
                    final length =
                        int.tryParse(_addLengthController.text) ?? 20;
                    _addPasswordController.text =
                        widget.controller.generatePassword(length: length);
                    _glassPerfBus.pulse();
                  },
                  icon: const Icon(Icons.password_outlined),
                  label: const Text('生成密码'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _addUrlController,
              decoration: const InputDecoration(labelText: '网址'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _addTotpController,
              decoration: const InputDecoration(labelText: 'TOTP 密钥 / URI'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _addTagsController,
              decoration: const InputDecoration(labelText: '标签（逗号分隔）'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _addNotesController,
              maxLines: 4,
              decoration: const InputDecoration(labelText: '备注'),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: widget.controller.busy
                    ? null
                    : () async {
                        final tags = _addTagsController.text
                            .split(',')
                            .map((value) => value.trim())
                            .where((value) => value.isNotEmpty)
                            .toList();
                        await widget.controller.addOrUpdateItem(
                          title: _addTitleController.text,
                          username: _addUsernameController.text,
                          password: _addPasswordController.text,
                          url: _addUrlController.text,
                          notes: _addNotesController.text,
                          tags: tags,
                          totpSecret: _addTotpController.text,
                        );
                        _glassPerfBus.pulse(heavy: true);
                        _addTitleController.clear();
                        _addUsernameController.clear();
                        _addPasswordController.clear();
                        _addUrlController.clear();
                        _addNotesController.clear();
                        _addTagsController.clear();
                        _addTotpController.clear();
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
                              await widget.controller.applyImportPlan(
                                _pendingImportPlan!,
                              );
                              if (!mounted) {
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
          const SizedBox(height: 10),
          Text(
            '导出时会弹出文件选择器页面，导出完成后会给出消息提示。',
            style: Theme.of(context).textTheme.bodySmall,
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
                  : () => widget.controller.changeMasterPassword(
                        oldPassword: _oldPasswordController.text,
                        newPassword: _newPasswordController.text,
                      ),
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
      borderRadius: BorderRadius.circular(18),
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
  double _flowDirection = 1;
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
      borderRadius: BorderRadius.circular(34),
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

                    final begin = _flowDirection > 0
                        ? const Alignment(-0.95, -0.55)
                        : const Alignment(0.95, -0.55);
                    final end = _flowDirection > 0
                        ? const Alignment(0.95, 0.85)
                        : const Alignment(-0.95, 0.85);

                    return Positioned(
                      left: highlightLeft,
                      top: 2,
                      bottom: 2,
                      width: morphWidth,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(30),
                          gradient: LinearGradient(
                            begin: begin,
                            end: end,
                            colors: const [
                              Color(0x7AFFF9FD),
                              Color(0x40FFFFFF),
                            ],
                          ),
                          border: Border.all(color: const Color(0xABFFFFFF)),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x233B222E),
                              blurRadius: 12,
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
                                Color(0x38FFFFFF),
                                Color(0x00FFFFFF),
                              ],
                            ),
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
                              _flowDirection = i > _activeIndex ? 1 : -1;
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
  _glassPerfBus.pulse(heavy: true);
  return showDialog<T>(
    context: context,
    barrierColor: _kDialogBarrierColor,
    builder: (context) => _DockPopupEntrance(child: builder(context)),
  ).whenComplete(_glassPerfBus.pulse);
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
    return _LiquidGlassSurface(
      padding: padding,
      borderRadius: borderRadius,
      sigma: sigma,
      tint: tint,
      borderColor: borderColor,
      shadowColor: shadowColor,
      enableBlur: enableBlur,
      child: child,
    );
  }
}

class _LiquidGlassSurface extends StatelessWidget {
  const _LiquidGlassSurface({
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
    return AnimatedBuilder(
      animation: _glassPerfBus,
      builder: (context, _) {
        final tier = _glassPerfBus.tier;
        final effectiveSigma = (sigma * tier.blurScale).clamp(4.0, 26.0);

        final decorated = Container(
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: borderRadius,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                (tint ?? const Color(0x8CF6EBEF)).withValues(alpha: 0.36),
                (tint ?? const Color(0x4CE7DAE1)).withValues(alpha: 0.20),
              ],
            ),
            border: Border.all(
              color: borderColor ?? const Color(0x8AF7EEF2),
              width: 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: shadowColor ?? const Color(0x26110810),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: child,
        );

        if (!enableBlur) {
          return decorated;
        }

        return FutureBuilder<FragmentProgram?>(
          future: _LiquidShaderProgramLoader.load(),
          builder: (context, snapshot) {
            return ClipRRect(
              borderRadius: borderRadius,
              child: BackdropFilter(
                filter: ImageFilter.blur(
                  sigmaX: effectiveSigma,
                  sigmaY: effectiveSigma,
                ),
                child: CustomPaint(
                  foregroundPainter: _LiquidSpecularPainter(
                    program: snapshot.data,
                    borderRadius: borderRadius,
                    strength: tier.shaderStrength,
                  ),
                  child: decorated,
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _LiquidShaderProgramLoader {
  static Future<FragmentProgram?>? _cachedProgram;

  static Future<FragmentProgram?> load() {
    return _cachedProgram ??= FragmentProgram.fromAsset(
      'shaders/liquid_glass.frag',
    ).then<FragmentProgram?>((value) => value).catchError((_) => null);
  }
}

class _LiquidSpecularPainter extends CustomPainter {
  const _LiquidSpecularPainter({
    required this.program,
    required this.borderRadius,
    required this.strength,
  });

  final FragmentProgram? program;
  final BorderRadius borderRadius;
  final double strength;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) {
      return;
    }
    final rect = Offset.zero & size;
    if (program == null) {
      final fallbackPaint = Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x12FFFFFF), Color(0x00FFFFFF)],
        ).createShader(rect)
        ..blendMode = BlendMode.softLight;
      canvas.drawRRect(borderRadius.toRRect(rect), fallbackPaint);
      return;
    }
    final shader = program!.fragmentShader();
    shader
      ..setFloat(0, size.width)
      ..setFloat(1, size.height)
      ..setFloat(2, strength);

    final paint = Paint()
      ..shader = shader
      ..blendMode = BlendMode.softLight;
    canvas.drawRRect(borderRadius.toRRect(rect), paint);
  }

  @override
  bool shouldRepaint(covariant _LiquidSpecularPainter oldDelegate) {
    return oldDelegate.program != program ||
        oldDelegate.strength != strength ||
        oldDelegate.borderRadius != borderRadius;
  }
}
