import 'package:flutter/widgets.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';

import '../../models/vault_models.dart';
import '../theme/cipherbook_glyphs.dart';
import '../theme/cipherbook_visual_tokens.dart';

abstract final class CipherbookPasswordRowMetrics {
  static const double listHorizontalPadding = 16;
  static const double rowGap = 8;
  static const double cardHorizontalPadding = 12;
  static const double cardVerticalPadding = 10;
  static const double leadingSlotWidth = 22;
  static const double leadingGap = 8;
  static const double avatarSize = 38;
  static const double avatarGap = 11;
  static const double textActionGap = 8;
  static const double trailingSlotWidth = 44;
}

class CipherbookPasswordRow extends StatelessWidget {
  const CipherbookPasswordRow({
    super.key,
    required this.item,
    required this.categoryName,
    required this.onPressed,
    this.onTrailingPressed,
    this.trailingKey,
    this.trailingTooltip = '查看详情',
    this.leading,
    this.leadingTooltip,
    this.selected = false,
    this.showTrailing = true,
    this.stripUrlScheme = false,
  });

  final VaultItem item;
  final String? categoryName;
  final VoidCallback? onPressed;
  final VoidCallback? onTrailingPressed;
  final Key? trailingKey;
  final String trailingTooltip;
  final Widget? leading;
  final String? leadingTooltip;
  final bool selected;
  final bool showTrailing;
  final bool stripUrlScheme;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final title = item.title.trim().isEmpty ? '未命名' : item.title.trim();
    final rawUrl = item.url.trim();
    final displayUrl = stripUrlScheme
        ? rawUrl.replaceFirst(RegExp(r'^https?://', caseSensitive: false), '')
        : rawUrl;
    final metadata = [
      if (item.username.trim().isNotEmpty) item.username.trim(),
      if (displayUrl.isNotEmpty) displayUrl,
      if ((categoryName ?? '').trim().isNotEmpty) categoryName!.trim(),
    ].join(' · ');
    final leading = this.leading;
    final trailingPressed = onTrailingPressed ?? onPressed;
    return Card(
      isSelected: selected,
      onPressed: onPressed,
      shape: AppShape.all(CipherbookVisualTokens.radiusControl).copyWith(
        side: selected
            ? CipherbookVisualTokens.accentBorderSide
            : CipherbookVisualTokens.borderSide,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: CipherbookPasswordRowMetrics.cardHorizontalPadding,
        vertical: CipherbookPasswordRowMetrics.cardVerticalPadding,
      ),
      child: Row(
        children: [
          if (leading != null) ...[
            SizedBox(
              width: CipherbookPasswordRowMetrics.leadingSlotWidth,
              height: 32,
              child: Center(
                child: Tooltip(message: leadingTooltip ?? '', child: leading),
              ),
            ),
            const SizedBox(width: CipherbookPasswordRowMetrics.leadingGap),
          ],
          _PasswordInitial(title: title, selected: selected),
          const SizedBox(width: CipherbookPasswordRowMetrics.avatarGap),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        key: ValueKey('prism-password-title-${item.id}'),
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyle.subheadline
                            .of(context, emphasized: true)
                            .copyWith(
                              color: selected
                                  ? colorScheme.primary
                                  : colorScheme.onSurface,
                            ),
                      ),
                    ),
                    if (item.favorite)
                      GlyphIcon(
                        VaultGlyphs.favorite,
                        size: 15,
                        color: colorScheme.primary,
                      ),
                  ],
                ),
                if (metadata.isNotEmpty)
                  Text(
                    key: ValueKey('prism-password-metadata-${item.id}'),
                    metadata,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyle.footnote
                        .of(context)
                        .copyWith(color: colorScheme.onSurfaceVariant),
                  ),
              ],
            ),
          ),
          if (showTrailing) ...[
            const SizedBox(width: CipherbookPasswordRowMetrics.textActionGap),
            SizedBox(
              width: CipherbookPasswordRowMetrics.trailingSlotWidth,
              child: IconButton(
                key: trailingKey,
                onPressed: trailingPressed,
                tooltip: trailingTooltip,
                icon: const GlyphIcon(Glyphs.chevronForward),
                iconSize: 16,
                padding: EdgeInsets.zero,
                style: const ButtonStyle(
                  minimumSize: Size.square(
                    CipherbookPasswordRowMetrics.trailingSlotWidth,
                  ),
                  maximumSize: Size.square(
                    CipherbookPasswordRowMetrics.trailingSlotWidth,
                  ),
                  tapTargetSize: TapTargetSize.shrinkWrap,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PasswordInitial extends StatelessWidget {
  const _PasswordInitial({required this.title, required this.selected});

  final String title;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final normalized = title.trim();
    return Container(
      width: CipherbookPasswordRowMetrics.avatarSize,
      height: CipherbookPasswordRowMetrics.avatarSize,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: selected
            ? CipherbookVisualTokens.accentSoft
            : context.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(
          CipherbookVisualTokens.radiusAvatar,
        ),
        border: Border.all(
          color: selected
              ? CipherbookVisualTokens.accent
              : CipherbookVisualTokens.border,
        ),
      ),
      child: Text(
        normalized.isEmpty ? '?' : normalized.characters.first.toUpperCase(),
        style: AppTextStyle.subheadline
            .of(context, emphasized: true)
            .copyWith(
              color: selected
                  ? context.colorScheme.primary
                  : context.colorScheme.onSecondaryContainer,
            ),
      ),
    );
  }
}
