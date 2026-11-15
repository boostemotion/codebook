import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';

import '../../services/vault_storage_types.dart';
import '../bridge/vault_controller_provider.dart';
import '../theme/cipherbook_glyphs.dart';
import '../theme/cipherbook_visual_tokens.dart';

class VaultUnlockPage extends ConsumerStatefulWidget {
  const VaultUnlockPage({super.key});

  @override
  ConsumerState<VaultUnlockPage> createState() => _VaultUnlockPageState();
}

class _VaultUnlockPageState extends ConsumerState<VaultUnlockPage> {
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) {
      return;
    }
    final controller = ref.read(vaultControllerProvider);
    final password = _passwordController.text;
    if (password.trim().isEmpty) {
      setState(() {
        _error = '请输入主密码。';
      });
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final result = controller.canCreateVault
          ? await controller.createVault(password)
          : await controller.unlock(password);
      if (!mounted) {
        return;
      }
      if (result.succeeded) {
        _passwordController.clear();
      } else {
        setState(() {
          _error = _messageOf(result.error);
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
        });
      }
    }
  }

  Future<void> _quickUnlock() async {
    if (_submitting) {
      return;
    }
    final controller = ref.read(vaultControllerProvider);
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final result = await controller.unlockWithQuickUnlock();
      if (mounted && !result.succeeded) {
        setState(() {
          _error = _messageOf(result.error);
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
        });
      }
    }
  }

  Future<void> _recover() async {
    if (_submitting) {
      return;
    }
    final controller = ref.read(vaultControllerProvider);
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final result = await controller.recoverVault();
      if (mounted && !result.succeeded) {
        setState(() {
          _error = _messageOf(result.error);
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
        });
      }
    }
  }

  String _messageOf(Object? error) {
    if (error is StateError) {
      return error.message;
    }
    final message = error?.toString();
    if (message == null || message.isEmpty) {
      return '操作失败，请重试。';
    }
    return message
        .replaceFirst(RegExp(r'^Bad state: '), '')
        .replaceFirst(RegExp(r'^Exception: '), '');
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(vaultControllerProvider);
    final colorScheme = context.colorScheme;
    final storageState = controller.storageState;
    final loading = storageState == VaultStorageState.loading;
    final recoverable = controller.canRecoverVault;
    final canUseForm =
        !loading &&
        !recoverable &&
        (controller.canCreateVault ||
            storageState == VaultStorageState.available);
    final title = controller.canCreateVault ? '创建密码库' : '解锁密码库';
    final canSubmit =
        !_submitting &&
        !controller.busy &&
        _passwordController.text.trim().isNotEmpty;

    Widget formFor({required bool compact}) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (compact) ...[
            const _CompactUnlockHeader(),
            const SizedBox(height: 26),
          ],
          Text(
            title,
            style: AppTextStyle.title3
                .of(context, emphasized: true)
                .copyWith(color: colorScheme.onSurface),
          ),
          if (loading) ...[
            const SizedBox(height: 6),
            Text(
              '正在检查密码库…',
              style: AppTextStyle.body
                  .of(context)
                  .copyWith(color: colorScheme.onSurfaceVariant),
            ),
          ],
          const SizedBox(height: 24),
          if (loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 28),
              child: Center(
                child: ActivityIndicator(size: 28, semanticLabel: '正在检查本地密码库'),
              ),
            )
          else if (recoverable)
            _RecoveryPanel(
              error: _error,
              busy: _submitting,
              onRecover: _recover,
            )
          else if (!canUseForm)
            _StorageErrorPanel(state: storageState, error: _error)
          else ...[
            TextField(
              key: const ValueKey('prism-master-password'),
              controller: _passwordController,
              obscureText: _obscurePassword,
              autofocus: true,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              onChanged: (_) {
                if (_error != null) {
                  setState(() {
                    _error = null;
                  });
                } else {
                  setState(() {});
                }
              },
              decoration: InputDecoration(
                hintText: '输入主密码',
                filled: true,
                fillColor: CipherbookVisualTokens.surfaceRaised,
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
                prefixIcon: GlyphIcon(
                  VaultGlyphs.vault,
                  color: colorScheme.onSurfaceVariant,
                ),
                suffixIcon: IconButton(
                  onPressed: () {
                    setState(() {
                      _obscurePassword = !_obscurePassword;
                    });
                  },
                  tooltip: _obscurePassword ? '显示密码' : '隐藏密码',
                  icon: GlyphIcon(
                    _obscurePassword ? Glyphs.eye : Glyphs.eyeOff,
                  ),
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: AppTextStyle.footnote
                    .of(context)
                    .copyWith(color: colorScheme.error),
              ),
            ],
            const SizedBox(height: CipherbookVisualTokens.space16),
            SizedBox(
              height: CipherbookVisualTokens.mobileControlHeight,
              child: FilledButton(
                key: const ValueKey('prism-unlock-submit'),
                onPressed: canSubmit ? _submit : null,
                child: _submitting
                    ? const SizedBox.square(
                        dimension: 18,
                        child: ActivityIndicator(size: 18),
                      )
                    : Text(title),
              ),
            ),
            if (controller.canUseQuickUnlockNow) ...[
              const SizedBox(height: 12),
              Card(
                key: const ValueKey('prism-unlock-quick'),
                onPressed: _submitting ? null : _quickUnlock,
                shape: AppShape.all(
                  CipherbookVisualTokens.radiusControl,
                ).copyWith(side: CipherbookVisualTokens.borderSide),
                padding: const EdgeInsets.symmetric(
                  horizontal: CipherbookVisualTokens.space12,
                  vertical: CipherbookVisualTokens.space8,
                ),
                child: Row(
                  children: [
                    GlyphIcon(
                      VaultGlyphs.shield,
                      size: 18,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: CipherbookVisualTokens.space8),
                    Expanded(
                      child: Text(
                        '使用系统认证快速解锁',
                        style: AppTextStyle.subheadline.of(
                          context,
                          emphasized: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GlyphIcon(
                      Glyphs.chevronForward,
                      size: 16,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ],
          ],
        ],
      );
    }

    return ColoredBox(
      color: colorScheme.surface,
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final expanded =
                constraints.maxWidth >= 820 && constraints.maxHeight >= 620;
            if (expanded) {
              final width = math.min(920.0, constraints.maxWidth - 48);
              final height = math.min(520.0, constraints.maxHeight - 48);
              return Center(
                child: SizedBox(
                  width: width,
                  height: height,
                  child: Card(
                    inert: true,
                    shape: AppShape.all(
                      CipherbookVisualTokens.radiusPanel,
                    ).copyWith(side: CipherbookVisualTokens.strongBorderSide),
                    padding: const EdgeInsets.all(
                      CipherbookVisualTokens.space8,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Expanded(flex: 3, child: _UnlockBrandPanel()),
                        Expanded(
                          flex: 6,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 38),
                            child: Center(
                              child: SingleChildScrollView(
                                child: formFor(compact: false),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }
            return SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: math.max(0, constraints.maxHeight - 40),
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 460),
                    child: Card(
                      key: const ValueKey('prism-unlock-card'),
                      inert: true,
                      shape: AppShape.all(
                        CipherbookVisualTokens.radiusPanel,
                      ).copyWith(side: CipherbookVisualTokens.borderSide),
                      padding: const EdgeInsets.all(
                        CipherbookVisualTokens.space24,
                      ),
                      child: formFor(compact: true),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _CompactUnlockHeader extends StatelessWidget {
  const _CompactUnlockHeader();

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: CipherbookVisualTokens.accentSoft,
            border: Border.all(color: CipherbookVisualTokens.border),
            borderRadius: CipherbookVisualTokens.controlRadius,
          ),
          child: GlyphIcon(
            VaultGlyphs.vault,
            size: 22,
            color: colorScheme.primary,
          ),
        ),
        const SizedBox(width: CipherbookVisualTokens.space12),
        Text(
          'Cipherbook',
          style: AppTextStyle.subheadline
              .of(context, emphasized: true)
              .copyWith(color: colorScheme.onSurface),
        ),
      ],
    );
  }
}

class _UnlockBrandPanel extends StatelessWidget {
  const _UnlockBrandPanel();

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        border: Border.all(color: CipherbookVisualTokens.border),
        borderRadius: CipherbookVisualTokens.controlRadius,
      ),
      child: Padding(
        padding: const EdgeInsets.all(CipherbookVisualTokens.space32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 36,
              height: 2,
              decoration: BoxDecoration(
                color: colorScheme.primary,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
            const SizedBox(height: CipherbookVisualTokens.space20),
            Text(
              'Cipherbook',
              style: AppTextStyle.title3
                  .of(context, emphasized: true)
                  .copyWith(color: colorScheme.onSurface),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecoveryPanel extends StatelessWidget {
  const _RecoveryPanel({
    required this.error,
    required this.busy,
    required this.onRecover,
  });

  final String? error;
  final bool busy;
  final Future<void> Function() onRecover;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '检测到可恢复副本。',
          style: AppTextStyle.body
              .of(context)
              .copyWith(color: colorScheme.onSurfaceVariant),
        ),
        if (error != null) ...[
          const SizedBox(height: 10),
          Text(
            error!,
            style: AppTextStyle.footnote
                .of(context)
                .copyWith(color: colorScheme.error),
          ),
        ],
        const SizedBox(height: 18),
        FilledButton(
          onPressed: busy ? null : onRecover,
          child: const Text('从验证过的副本恢复'),
        ),
      ],
    );
  }
}

class _StorageErrorPanel extends StatelessWidget {
  const _StorageErrorPanel({required this.state, required this.error});

  final VaultStorageState state;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final message = switch (state) {
      VaultStorageState.corrupt => '主密码库文件无法验证，且没有可直接恢复的副本。',
      VaultStorageState.unsupportedVersion => '密码库版本高于当前应用支持的版本。',
      VaultStorageState.permissionDenied => '应用没有权限读取当前密码库文件。',
      _ => '密码库暂时不可用。',
    };
    return Surface(
      color: colorScheme.errorContainer,
      shape: AppShape.all(10),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              message,
              style: AppTextStyle.body
                  .of(context)
                  .copyWith(color: colorScheme.onErrorContainer),
            ),
            if (error != null) ...[
              const SizedBox(height: 8),
              Text(
                error!,
                style: AppTextStyle.footnote
                    .of(context)
                    .copyWith(color: colorScheme.onErrorContainer),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
