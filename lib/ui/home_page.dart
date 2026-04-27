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
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.controller.addListener(_handleControllerChanged);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.removeListener(_handleControllerChanged);
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

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('Cipherbook'),
            actions: [
              if (widget.controller.isUnlocked)
                IconButton(
                  onPressed: widget.controller.busy
                      ? null
                      : () {
                          widget.controller.lock();
                        },
                  icon: const Icon(Icons.lock_outline),
                  tooltip: 'Lock',
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
              controller.hasVault
                  ? 'Unlock local vault'
                  : 'Create your first vault',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: masterPasswordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Master password',
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
              child: Text(controller.hasVault ? 'Unlock' : 'Create vault'),
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
                label: const Text('Quick unlock'),
              ),
            ],
            if (!controller.hasVault) ...[
              const SizedBox(height: 24),
              TextField(
                controller: importPasswordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Import file password',
                  helperText:
                      'Import an encrypted snapshot when no local vault exists.',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () async {
                  final plan =
                      await controller.previewImport(importPasswordController.text);
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
                label: const Text('Import as local vault'),
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
    required this.searchQuery,
    required this.onSearchChanged,
  });

  final VaultController controller;
  final TextEditingController searchController;
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
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            FilledButton.icon(
              onPressed: () => _showItemEditor(context, controller: controller),
              icon: const Icon(Icons.add),
              label: const Text('Add entry'),
            ),
            OutlinedButton.icon(
              onPressed: () => _showExportDialog(context, controller),
              icon: const Icon(Icons.upload_file_outlined),
              label: const Text('Export snapshot'),
            ),
            OutlinedButton.icon(
              onPressed: () => _showImportDialog(context, controller),
              icon: const Icon(Icons.download_outlined),
              label: const Text('Import and merge'),
            ),
            OutlinedButton.icon(
              onPressed: () => _showChangePasswordDialog(context, controller),
              icon: const Icon(Icons.key_outlined),
              label: const Text('Change password'),
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
                  controller.quickUnlockEnabled
                      ? 'Disable quick unlock'
                      : 'Enable quick unlock',
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),
        TextField(
          controller: searchController,
          onChanged: onSearchChanged,
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            labelText: 'Search entries',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 20),
        Expanded(
          child: items.isEmpty
              ? const Center(child: Text('No matching entries.'))
              : ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return Card(
                      child: ListTile(
                        title: Text(item.title),
                        subtitle: Text(
                          [item.username, item.url]
                              .where((part) => part.isNotEmpty)
                              .join('  -  '),
                        ),
                        trailing: Wrap(
                          spacing: 8,
                          children: [
                            IconButton(
                              onPressed: () => _showItemDetails(
                                context,
                                controller: controller,
                                item: item,
                              ),
                              icon: const Icon(Icons.visibility_outlined),
                            ),
                            IconButton(
                              onPressed: () {
                                controller.copySecret(item.password);
                              },
                              icon: const Icon(Icons.copy_outlined),
                              tooltip: 'Copy password',
                            ),
                            IconButton(
                              onPressed: () => _showItemEditor(
                                context,
                                controller: controller,
                                item: item,
                              ),
                              icon: const Icon(Icons.edit_outlined),
                            ),
                            IconButton(
                              onPressed: () => controller.deleteItem(item.id),
                              icon: const Icon(Icons.delete_outline),
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
      title: const Text('Import encrypted snapshot'),
      content: TextField(
        controller: passwordController,
        obscureText: true,
        decoration: const InputDecoration(
          labelText: 'Import file password',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Continue'),
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
      title: const Text('Import summary'),
      content: SizedBox(
        width: 360,
        child: _ImportSummaryView(summary: summary),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Import'),
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
      title: const Text('Export encrypted snapshot'),
      content: TextField(
        controller: passwordController,
        obscureText: true,
        decoration: const InputDecoration(
          labelText: 'Optional export password',
          helperText:
              'Leave empty to export with the current vault encryption.',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Export'),
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
      title: const Text('Change master password'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: oldPasswordController,
            obscureText: true,
            decoration:
                const InputDecoration(labelText: 'Current master password'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: newPasswordController,
            obscureText: true,
            decoration:
                const InputDecoration(labelText: 'New master password'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Save'),
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
      title: Text(item == null ? 'Add entry' : 'Edit entry'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                decoration: const InputDecoration(labelText: 'Title'),
              ),
              TextField(
                controller: usernameController,
                decoration: const InputDecoration(labelText: 'Username'),
              ),
              TextField(
                controller: passwordController,
                decoration: const InputDecoration(labelText: 'Password'),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: lengthController,
                      keyboardType: TextInputType.number,
                      decoration:
                          const InputDecoration(labelText: 'Generated length'),
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
                    label: const Text('Generate'),
                  ),
                ],
              ),
              TextField(
                controller: urlController,
                decoration: const InputDecoration(labelText: 'URL'),
              ),
              TextField(
                controller: totpController,
                decoration: const InputDecoration(
                  labelText: 'TOTP Secret or otpauth URI',
                ),
              ),
              TextField(
                controller: tagsController,
                decoration:
                    const InputDecoration(labelText: 'Tags, comma separated'),
              ),
              TextField(
                controller: notesController,
                maxLines: 5,
                decoration: const InputDecoration(labelText: 'Notes'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Save'),
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
              label: 'Username',
              value: item.username,
              onCopy: item.username.isEmpty
                  ? null
                  : () => controller.copySecret(item.username),
            ),
            _DetailRow(
              label: 'Password',
              value: item.password,
              onCopy: item.password.isEmpty
                  ? null
                  : () => controller.copySecret(item.password),
            ),
            _DetailRow(label: 'URL', value: item.url),
            _DetailRow(label: 'Tags', value: item.tags.join(', ')),
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
          child: const Text('Close'),
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
              tooltip: 'Copy',
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
    final lines = <String>[
      'Incoming items: ${summary.incomingItems}',
      'New items: ${summary.newItems}',
      'Updated items: ${summary.updatedItems}',
      'Deleted items: ${summary.deletedItems}',
      'Unchanged items: ${summary.unchangedItems}',
    ];
    if (summary.replacesLocalVault) {
      lines.insert(0, 'No local vault exists. This file will become the local vault.');
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
      ],
    );
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
                value: 'Invalid secret',
              );
            }
            if (!resultSnapshot.hasData) {
              return const _DetailRow(
                label: 'TOTP',
                value: 'Loading...',
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
                          'Refreshes in ${result.secondsRemaining}s',
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
                    tooltip: 'Copy current TOTP code',
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
