import 'dart:async';

import 'package:flutter/services.dart' show TextInputAction;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';

import '../../services/lan_sync_service.dart';
import '../../state/vault_controller.dart';
import '../bridge/vault_controller_provider.dart';
import '../shared/cipherbook_page_scaffold.dart';
import '../theme/cipherbook_glyphs.dart';
import '../theme/cipherbook_visual_tokens.dart';

class CipherbookSyncPage extends ConsumerWidget {
  const CipherbookSyncPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(vaultControllerProvider);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final host = controller.lanSyncHost;
        final peers = controller.lanSyncPeers;
        return CipherbookPageScaffold(
          body: LayoutBuilder(
            builder: (context, constraints) {
              final padding = CipherbookVisualTokens.pagePadding(
                constraints.maxWidth,
              );
              return ListView(
                padding: padding,
                children: [
                  Center(
                    child: ConstrainedBox(
                      key: const ValueKey('prism-sync-content'),
                      constraints: const BoxConstraints(maxWidth: 760),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _SyncStatusCard(
                            active: host != null,
                            deviceName: host?.deviceName,
                            busy: controller.busy,
                            message: controller.message,
                            onStart: () {
                              unawaited(controller.startLanSyncShare());
                            },
                            onStop: () {
                              unawaited(controller.stopLanSyncShare());
                            },
                            onDiscover: () {
                              unawaited(controller.discoverLanSyncPeers());
                            },
                          ),
                          const SizedBox(height: CipherbookVisualTokens.space8),
                          _SyncDevicesCard(
                            peers: peers,
                            busy: controller.busy,
                            onSync: () {
                              unawaited(
                                _showLanSyncPasswordDialog(
                                  context,
                                  controller: controller,
                                ),
                              );
                            },
                          ),
                        ],
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
}

class _SyncStatusCard extends StatelessWidget {
  const _SyncStatusCard({
    required this.active,
    required this.deviceName,
    required this.busy,
    required this.message,
    required this.onStart,
    required this.onStop,
    required this.onDiscover,
  });

  final bool active;
  final String? deviceName;
  final bool busy;
  final String? message;
  final VoidCallback onStart;
  final VoidCallback onStop;
  final VoidCallback onDiscover;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return Card(
      inert: true,
      shape: AppShape.all(
        CipherbookVisualTokens.radiusPanel,
      ).copyWith(side: CipherbookVisualTokens.borderSide),
      padding: const EdgeInsets.all(CipherbookVisualTokens.space20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      active ? '共享已开启' : '共享未开启',
                      style: AppTextStyle.headline.of(
                        context,
                        emphasized: true,
                      ),
                    ),
                    if ((deviceName ?? '').isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        deviceName!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyle.footnote
                            .of(context)
                            .copyWith(color: colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: CipherbookVisualTokens.space12),
              Text(
                active ? '运行中' : '已关闭',
                style: AppTextStyle.footnote
                    .of(context, emphasized: true)
                    .copyWith(
                      color: active
                          ? colorScheme.primary
                          : colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
          if ((message ?? '').isNotEmpty) ...[
            const SizedBox(height: CipherbookVisualTokens.space12),
            Container(
              padding: const EdgeInsets.only(
                left: CipherbookVisualTokens.space8,
              ),
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(color: colorScheme.primary, width: 2),
                ),
              ),
              child: Text(
                message!,
                style: AppTextStyle.footnote
                    .of(context)
                    .copyWith(color: colorScheme.onSurfaceVariant),
              ),
            ),
          ],
          const SizedBox(height: CipherbookVisualTokens.space16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.end,
            children: [
              if (active)
                OutlinedButton.icon(
                  key: const ValueKey('prism-sync-secondary'),
                  onPressed: busy ? null : onStop,
                  icon: const GlyphIcon(Glyphs.close, size: 16),
                  label: const Text('停止共享'),
                )
              else
                OutlinedButton.icon(
                  key: const ValueKey('prism-sync-secondary'),
                  onPressed: busy ? null : onDiscover,
                  icon: const GlyphIcon(Glyphs.search, size: 16),
                  label: const Text('发现设备'),
                ),
              FilledButton.icon(
                key: const ValueKey('prism-sync-primary'),
                onPressed: busy ? null : (active ? onDiscover : onStart),
                icon: GlyphIcon(
                  active ? Glyphs.search : VaultGlyphs.sync,
                  size: 16,
                ),
                label: Text(active ? '发现设备' : '开启共享'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SyncDevicesCard extends StatelessWidget {
  const _SyncDevicesCard({
    required this.peers,
    required this.busy,
    required this.onSync,
  });

  final List<LanSyncPeer> peers;
  final bool busy;
  final VoidCallback onSync;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return Card(
      inert: true,
      shape: AppShape.all(
        CipherbookVisualTokens.radiusPanel,
      ).copyWith(side: CipherbookVisualTokens.borderSide),
      padding: const EdgeInsets.all(CipherbookVisualTokens.space20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                '局域网设备',
                style: AppTextStyle.headline.of(context, emphasized: true),
              ),
              const Spacer(),
              Text(
                '${peers.length}',
                style: AppTextStyle.footnote
                    .of(context, emphasized: true)
                    .copyWith(color: colorScheme.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: CipherbookVisualTokens.space12),
          if (peers.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(
                vertical: CipherbookVisualTokens.space24,
              ),
              child: Text(
                '未发现设备',
                textAlign: TextAlign.center,
                style: AppTextStyle.subheadline
                    .of(context)
                    .copyWith(color: colorScheme.onSurfaceVariant),
              ),
            )
          else
            for (var index = 0; index < peers.length; index++) ...[
              if (index > 0)
                const SizedBox(height: CipherbookVisualTokens.space4),
              Card(
                inert: true,
                shape: AppShape.all(
                  CipherbookVisualTokens.radiusControl,
                ).copyWith(side: CipherbookVisualTokens.borderSide),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        peers[index].deviceName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyle.subheadline.of(
                          context,
                          emphasized: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '已发现',
                      style: AppTextStyle.caption1
                          .of(context)
                          .copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          if (peers.isNotEmpty) ...[
            const SizedBox(height: CipherbookVisualTokens.space16),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                key: const ValueKey('prism-sync-all'),
                onPressed: busy ? null : onSync,
                icon: const GlyphIcon(VaultGlyphs.sync, size: 16),
                label: Text('同步 ${peers.length} 台设备'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

Future<void> _showLanSyncPasswordDialog(
  BuildContext context, {
  required VaultController controller,
}) {
  return showFloatingDialog<void>(
    context: context,
    child: _LanSyncPasswordDialog(controller: controller),
  );
}

class _LanSyncPasswordDialog extends StatefulWidget {
  const _LanSyncPasswordDialog({required this.controller});

  final VaultController controller;

  @override
  State<_LanSyncPasswordDialog> createState() => _LanSyncPasswordDialogState();
}

class _LanSyncPasswordDialogState extends State<_LanSyncPasswordDialog> {
  final TextEditingController _passwordController = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final password = _passwordController.text;
    if (password.trim().isEmpty) {
      setState(() {
        _error = '请输入共同主密码。';
      });
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    final result = await widget.controller.syncLanWithPassword(password);
    if (!mounted) {
      return;
    }
    if (result.succeeded) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _submitting = false;
      _error = widget.controller.message ?? '同步失败，请稍后重试。';
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const ValueKey('prism-sync-password-dialog'),
      title: '同步局域网设备',
      hasFields: true,
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          key: const ValueKey('prism-sync-password-confirm'),
          onPressed: _submitting ? null : () => unawaited(_submit()),
          child: Text(_submitting ? '同步中…' : '开始同步'),
        ),
      ],
      child: SizedBox(
        width: 360,
        child: TextField(
          key: const ValueKey('prism-sync-password-field'),
          controller: _passwordController,
          autofocus: true,
          obscureText: true,
          enabled: !_submitting,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) {
            if (!_submitting) {
              unawaited(_submit());
            }
          },
          decoration: InputDecoration(hintText: '共同主密码', errorText: _error),
        ),
      ),
    );
  }
}
