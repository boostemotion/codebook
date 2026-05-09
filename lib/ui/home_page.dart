import 'package:flutter/material.dart';

import '../models/vault_models.dart';
import '../services/totp_service.dart';
import '../state/vault_controller.dart';

const TotpService _totpService = TotpService();

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
  final ScrollController _vaultScrollController = ScrollController();
  String _searchQuery = '';
  bool _hideAppBarTitle = false;
  bool _hideTopActions = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.controller.addListener(_handleControllerChanged);
    _vaultScrollController.addListener(_handleVaultScroll);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.removeListener(_handleControllerChanged);
    _vaultScrollController.removeListener(_handleVaultScroll);
    _vaultScrollController.dispose();
    _masterPasswordController.dispose();
    _importPasswordController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      widget.controller.handleAppPaused();
    }
  }

  void _handleControllerChanged() {
    final message = widget.controller.message;
    if (!mounted || message == null || message.isEmpty) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
    widget.controller.clearMessage();
  }

  void _handleVaultScroll() {
    if (!_vaultScrollController.hasClients) {
      return;
    }
    final shouldHideTitle = _vaultScrollController.offset > 24;
    final shouldHideActions = _vaultScrollController.offset > 12;
    if (shouldHideTitle == _hideAppBarTitle &&
        shouldHideActions == _hideTopActions) {
      return;
    }
    setState(() {
      _hideAppBarTitle = shouldHideTitle;
      _hideTopActions = shouldHideActions;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(
            title: AnimatedOpacity(
              duration: const Duration(milliseconds: 180),
              opacity: _hideAppBarTitle ? 0 : 1,
              child: const Text('密码本'),
            ),
            actions: [
              if (widget.controller.isUnlocked)
                IconButton(
                  onPressed: widget.controller.busy
                      ? null
                      : () {
                          widget.controller.lock();
                        },
                  icon: const Icon(Icons.lock_outline),
                  tooltip: '閿佸畾',
                ),
            ],
          ),
          body: Listener(
            onPointerDown: (_) => widget.controller.registerActivity(),
            child: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: widget.controller.isUnlocked
                      ? _VaultView(
                          controller: widget.controller,
                          searchController: _searchController,
                          scrollController: _vaultScrollController,
                          hideTopActions: _hideTopActions,
                          searchQuery: _searchQuery,
                          onSearchChanged: (value) {
                            setState(() {
                              _searchQuery = value.trim().toLowerCase();
                            });
                          },
                        )
                      : _LockedView(
                          controller: widget.controller,
                          masterPasswordController: _masterPasswordController,
                          importPasswordController: _importPasswordController,
                        ),
                ),
                if (widget.controller.busy)
                  const ColoredBox(
                    color: Color(0x66000000),
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

class _LockedView extends StatelessWidget {
  const _LockedView({
    required this.controller,
    required this.masterPasswordController,
    required this.importPasswordController,
  });

  final VaultController controller;
  final TextEditingController masterPasswordController;
  final TextEditingController importPasswordController;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              controller.hasVault ? '解锁本地密码库' : '创建第一个密码库',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: masterPasswordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: '主密码',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) {
                if (controller.hasVault) {
                  controller.unlock(masterPasswordController.text);
                } else {
                  controller.createVault(masterPasswordController.text);
                }
              },
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () {
                if (controller.hasVault) {
                  controller.unlock(masterPasswordController.text);
                } else {
                  controller.createVault(masterPasswordController.text);
                }
              },
              child: Text(controller.hasVault ? '解锁' : '创建密码库'),
            ),
            if (controller.quickUnlockSupported &&
                controller.quickUnlockEnabled &&
                controller.hasVault) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () {
                  controller.unlockWithQuickUnlock();
                },
                icon: const Icon(Icons.fingerprint),
                label: const Text('快速解锁'),
              ),
            ],
            if (!controller.hasVault) ...[
              const SizedBox(height: 24),
              TextField(
                controller: importPasswordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: '瀵煎叆鏂囦欢瀵嗙爜',
                  helperText: '没有本地密码库时，可导入一个加密备份。',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
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
                icon: const Icon(Icons.file_open_outlined),
                label: const Text('瀵煎叆涓烘湰鍦板瘑鐮佸簱'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _VaultView extends StatelessWidget {
  const _VaultView({
    required this.controller,
    required this.searchController,
    required this.scrollController,
    required this.hideTopActions,
    required this.searchQuery,
    required this.onSearchChanged,
  });

  final VaultController controller;
  final TextEditingController searchController;
  final ScrollController scrollController;
  final bool hideTopActions;
  final String searchQuery;
  final ValueChanged<String> onSearchChanged;

  @override
  Widget build(BuildContext context) {
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
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          child: hideTopActions
              ? const SizedBox.shrink()
              : Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    FilledButton.icon(
                      onPressed: () =>
                          _showItemEditor(context, controller: controller),
                      icon: const Icon(Icons.add),
                      label: const Text('新增条目'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _showExportDialog(context, controller),
                      icon: const Icon(Icons.upload_file_outlined),
                      label: const Text('导出备份'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _showImportDialog(context, controller),
                      icon: const Icon(Icons.download_outlined),
                      label: const Text('导入并合并'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () =>
                          _showChangePasswordDialog(context, controller),
                      icon: const Icon(Icons.key_outlined),
                      label: const Text('修改主密码'),
                    ),
                    if (controller.quickUnlockSupported)
                      OutlinedButton.icon(
                        onPressed: () {
                          if (controller.quickUnlockEnabled) {
                            controller.disableQuickUnlock();
                          } else {
                            controller.enableQuickUnlock();
                          }
                        },
                        icon: Icon(
                          controller.quickUnlockEnabled
                              ? Icons.phonelink_lock_outlined
                              : Icons.fingerprint,
                        ),
                        label: Text(
                          controller.quickUnlockEnabled ? '关闭快速解锁' : '开启快速解锁',
                        ),
                      ),
                  ],
                ),
        ),
        SizedBox(height: hideTopActions ? 0 : 16),
        TextField(
          controller: searchController,
          onChanged: onSearchChanged,
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            labelText: '搜索条目',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: items.isEmpty
              ? const Center(child: Text('没有匹配的条目。'))
              : ListView.separated(
                  controller: scrollController,
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  itemBuilder: (context, index) {
                    final item = items[index];
                    final accountInfo = [item.username, item.url]
                        .where((part) => part.isNotEmpty)
                        .join('  -  ');
                    return Card(
                      elevation: 0.8,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 8, 4, 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    item.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(
                                          fontSize: 21,
                                          fontWeight: FontWeight.w800,
                                          height: 1.0,
                                        ),
                                  ),
                                ),
                                if (accountInfo.isNotEmpty) ...[
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      accountInfo,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.end,
                                      style:
                                          Theme.of(context).textTheme.bodySmall,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 1),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                IconButton(
                                  onPressed: () => _showItemDetails(
                                    context,
                                    controller: controller,
                                    item: item,
                                  ),
                                  icon: const Icon(Icons.visibility_outlined),
                                  iconSize: 20,
                                  splashRadius: 18,
                                  visualDensity: VisualDensity.compact,
                                  constraints: const BoxConstraints(
                                    minWidth: 30,
                                    minHeight: 30,
                                  ),
                                ),
                                IconButton(
                                  onPressed: () {
                                    controller.copySecret(item.password);
                                  },
                                  icon: const Icon(Icons.copy_outlined),
                                  iconSize: 20,
                                  splashRadius: 18,
                                  visualDensity: VisualDensity.compact,
                                  constraints: const BoxConstraints(
                                    minWidth: 30,
                                    minHeight: 30,
                                  ),
                                  tooltip: '复制密码',
                                ),
                                IconButton(
                                  onPressed: () => _showItemEditor(
                                    context,
                                    controller: controller,
                                    item: item,
                                  ),
                                  icon: const Icon(Icons.edit_outlined),
                                  iconSize: 20,
                                  splashRadius: 18,
                                  visualDensity: VisualDensity.compact,
                                  constraints: const BoxConstraints(
                                    minWidth: 30,
                                    minHeight: 30,
                                  ),
                                ),
                                IconButton(
                                  onPressed: () =>
                                      controller.deleteItem(item.id),
                                  icon: const Icon(Icons.delete_outline),
                                  iconSize: 20,
                                  splashRadius: 18,
                                  visualDensity: VisualDensity.compact,
                                  constraints: const BoxConstraints(
                                    minWidth: 30,
                                    minHeight: 30,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

Future<void> _showImportDialog(
  BuildContext context,
  VaultController controller,
) async {
  final passwordController = TextEditingController();
  final confirmedPassword = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('瀵煎叆鍔犲瘑澶囦唤'),
      content: TextField(
        controller: passwordController,
        obscureText: true,
        decoration: const InputDecoration(
          labelText: '瀵煎叆鏂囦欢瀵嗙爜',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('鍙栨秷'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('缁х画'),
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
  return showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('瀵煎叆棰勮'),
      content: SizedBox(
        width: 360,
        child: _ImportSummaryView(summary: summary),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('鍙栨秷'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('瀵煎叆'),
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
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('瀵煎嚭鍔犲瘑澶囦唤'),
      content: TextField(
        controller: passwordController,
        obscureText: true,
        decoration: const InputDecoration(
          labelText: '瀵煎嚭瀵嗙爜锛堝彲閫夛級',
          helperText: '留空则沿用当前本地密码库的加密。',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('鍙栨秷'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('瀵煎嚭'),
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
  final confirmed = await showDialog<bool>(
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
            decoration: const InputDecoration(labelText: '鏂颁富瀵嗙爜'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('鍙栨秷'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('淇濆瓨'),
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
  final saved = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(item == null ? '鏂板鏉＄洰' : '缂栬緫鏉＄洰'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                decoration: const InputDecoration(labelText: '鍚嶇О'),
              ),
              TextField(
                controller: usernameController,
                decoration: const InputDecoration(labelText: '璐﹀彿'),
              ),
              TextField(
                controller: passwordController,
                decoration: const InputDecoration(labelText: '瀵嗙爜'),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: lengthController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: '鐢熸垚闀垮害'),
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
                    label: const Text('鐢熸垚'),
                  ),
                ],
              ),
              TextField(
                controller: urlController,
                decoration: const InputDecoration(labelText: '缃戝潃'),
              ),
              TextField(
                controller: totpController,
                decoration: const InputDecoration(
                  labelText: 'TOTP 瀵嗛挜鎴?otpauth URI',
                ),
              ),
              TextField(
                controller: tagsController,
                decoration: const InputDecoration(labelText: '鏍囩锛岀敤閫楀彿鍒嗛殧'),
              ),
              TextField(
                controller: notesController,
                maxLines: 5,
                decoration: const InputDecoration(labelText: '澶囨敞'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('鍙栨秷'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('淇濆瓨'),
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
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(item.title),
      content: SizedBox(
        width: 500,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _DetailRow(
              label: '璐﹀彿',
              value: item.username,
              onCopy: item.username.isEmpty
                  ? null
                  : () => controller.copySecret(item.username),
            ),
            _DetailRow(
              label: '瀵嗙爜',
              value: item.password,
              onCopy: item.password.isEmpty
                  ? null
                  : () => controller.copySecret(item.password),
            ),
            _DetailRow(label: '缃戝潃', value: item.url),
            _DetailRow(label: '鏍囩', value: item.tags.join(', ')),
            if ((item.totpSecret?.trim().isNotEmpty ?? false))
              _TotpPanel(
                secretOrUri: item.totpSecret!,
                onCopy: controller.copySecret,
              )
            else
              const _DetailRow(label: 'TOTP', value: ''),
            const SizedBox(height: 12),
            SelectableText(item.notes),
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('鍏抽棴'),
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
            width: 90,
            child: Text('$label:'),
          ),
          Expanded(child: SelectableText(value)),
          if (onCopy != null)
            IconButton(
              onPressed: onCopy,
              icon: const Icon(Icons.copy_outlined),
              tooltip: '澶嶅埗',
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
      '瀵煎叆鏂囦欢鏉＄洰锛?{summary.incomingItems}',
      '鏂板锛?{summary.newItems}',
      '鏇存柊锛?{summary.updatedItems}',
      '鍒犻櫎锛?{summary.deletedItems}',
      '涓嶅彉锛?{summary.unchangedItems}',
    ];
    if (summary.replacesLocalVault) {
      lines.insert(0, '当前没有本地密码库，此文件将作为本地密码库。');
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
            '鍙樻洿鏉＄洰',
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
                  'ID锛?{detail.id}',
                  '瀵煎叆锛?{detail.incomingUpdatedAt.toIso8601String()}',
                  if (detail.localUpdatedAt != null)
                    '鏈湴锛?{detail.localUpdatedAt!.toIso8601String()}',
                ];
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 80,
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
        return '鏂板';
      case ImportChangeKind.updatedItem:
        return '鏇存柊';
      case ImportChangeKind.deletedItem:
        return '鍒犻櫎';
      case ImportChangeKind.unchangedItem:
        return '璺宠繃';
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
                value: '瀵嗛挜鏃犳晥',
              );
            }
            if (!resultSnapshot.hasData) {
              return const _DetailRow(
                label: 'TOTP',
                value: '鍔犺浇涓?..',
              );
            }
            final result = resultSnapshot.data!;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(
                    width: 90,
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
                          '${result.secondsRemaining} 绉掑悗鍒锋柊',
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
                    tooltip: '复制当前 TOTP 验证码',
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
