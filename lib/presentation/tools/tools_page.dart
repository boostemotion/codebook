import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';
import 'package:prism_shell/prism_shell.dart';

import '../../state/vault_controller.dart';
import '../bridge/vault_controller_provider.dart';
import '../shared/cipherbook_page_scaffold.dart';
import '../shell/cipherbook_navigation.dart';
import '../theme/cipherbook_visual_tokens.dart';

class CipherbookToolsPage extends ConsumerWidget {
  const CipherbookToolsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(vaultControllerProvider);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
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
                      constraints: const BoxConstraints(maxWidth: 760),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _ToolStatusCard(
                            title: '快速解锁',
                            value: controller.quickUnlockSupported
                                ? controller.quickUnlockEnabled
                                      ? '已开启'
                                      : '设备支持，尚未开启'
                                : '当前设备不支持',
                          ),
                          const SizedBox(height: CipherbookVisualTokens.space4),
                          _ToolStatusCard(
                            key: const ValueKey('prism-tools-security'),
                            title: '密码检查',
                            value: '重复与弱密码',
                            onPressed: () {
                              ShellNavigationScope.navigationOf(
                                context,
                              ).select(CipherbookDestinationId.security);
                            },
                          ),
                          const SizedBox(height: CipherbookVisualTokens.space4),
                          _ToolStatusCard(
                            key: const ValueKey('prism-auto-lock-setting'),
                            title: '自动锁定',
                            value:
                                controller.autoLockPreset?.label ??
                                '${controller.autoLockDuration.inMinutes} 分钟',
                            onPressed: () {
                              unawaited(
                                _showAutoLockPicker(
                                  context: context,
                                  controller: controller,
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: CipherbookVisualTokens.space4),
                          _ToolStatusCard(
                            title: '局域网同步',
                            value: controller.lanSyncHost == null
                                ? '未开启共享'
                                : '已开启共享',
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

class _ToolStatusCard extends StatelessWidget {
  const _ToolStatusCard({
    super.key,
    required this.title,
    required this.value,
    this.onPressed,
  });

  final String title;
  final String value;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return Card(
      inert: onPressed == null,
      onPressed: onPressed,
      shape: AppShape.all(
        CipherbookVisualTokens.radiusControl,
      ).copyWith(side: CipherbookVisualTokens.borderSide),
      padding: const EdgeInsets.symmetric(
        horizontal: CipherbookVisualTokens.space12,
        vertical: CipherbookVisualTokens.space12,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: AppTextStyle.subheadline.of(context, emphasized: true),
            ),
          ),
          Text(
            value,
            style: AppTextStyle.footnote
                .of(context)
                .copyWith(color: colorScheme.onSurfaceVariant),
          ),
          if (onPressed != null) ...[
            const SizedBox(width: 8),
            GlyphIcon(
              Glyphs.chevronForward,
              size: 16,
              color: colorScheme.onSurfaceVariant,
            ),
          ],
        ],
      ),
    );
  }
}

Future<void> _showAutoLockPicker({
  required BuildContext context,
  required VaultController controller,
}) async {
  final selected = await showFloatingDialog<AutoLockPreset>(
    context: context,
    child: Builder(
      builder: (dialogContext) {
        return AlertDialog(
          title: '自动锁定',
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
              for (final preset in AutoLockPreset.values)
                Padding(
                  padding: EdgeInsets.only(
                    bottom: preset == AutoLockPreset.values.last ? 0 : 8,
                  ),
                  child: Card(
                    key: ValueKey('prism-auto-lock-${preset.name}'),
                    isSelected: controller.autoLockPreset == preset,
                    onPressed: () => Navigator.of(dialogContext).pop(preset),
                    shape: AppShape.all(CipherbookVisualTokens.radiusControl)
                        .copyWith(
                          side: controller.autoLockPreset == preset
                              ? CipherbookVisualTokens.accentBorderSide
                              : CipherbookVisualTokens.borderSide,
                        ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: CipherbookVisualTokens.space12,
                      vertical: CipherbookVisualTokens.space8,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            preset.label,
                            style: AppTextStyle.subheadline.of(
                              dialogContext,
                              emphasized: true,
                            ),
                          ),
                        ),
                        if (controller.autoLockPreset == preset)
                          GlyphIcon(
                            Glyphs.check,
                            size: 18,
                            color: dialogContext.colorScheme.primary,
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    ),
  );
  if (selected != null) {
    controller.setAutoLockPreset(selected);
  }
}
