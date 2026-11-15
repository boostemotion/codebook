import 'package:flutter/widgets.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';

import '../../models/vault_models.dart';
import '../../state/vault_controller.dart';
import '../shared/password_inspector.dart';
import '../theme/cipherbook_glyphs.dart';
import 'category_workbench_tokens.dart';

class CategoryItemDetailsInspector extends StatelessWidget {
  const CategoryItemDetailsInspector({
    super.key,
    required this.controller,
    required this.item,
    required this.onSelectItem,
    this.onEdit,
    this.onMoved,
  });

  final VaultController controller;
  final VaultItem item;
  final ValueChanged<VaultItem> onSelectItem;
  final VoidCallback? onEdit;
  final VoidCallback? onMoved;

  @override
  Widget build(BuildContext context) {
    return PasswordInspector(
      controller: controller,
      item: item,
      cardKey: const ValueKey('prism-category-item-details'),
      keyPrefix: 'prism-category-detail',
      onEdit: onEdit,
      onSelectItem: onSelectItem,
      onMoved: onMoved,
    );
  }
}

class CategoryItemDetailsEmpty extends StatelessWidget {
  const CategoryItemDetailsEmpty({
    super.key,
    required this.title,
    required this.countLabel,
    required this.message,
    required this.hint,
  });

  final String title;
  final String countLabel;
  final String message;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return Card(
      key: const ValueKey('prism-category-detail-empty'),
      inert: true,
      radius: CategoryWorkbenchTokens.panelRadius,
      shape: AppShape.all(
        CategoryWorkbenchTokens.panelRadius,
      ).copyWith(side: BorderSide(color: colorScheme.outlineVariant)),
      padding: const EdgeInsets.all(CategoryWorkbenchTokens.space20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: colorScheme.secondaryContainer,
                  borderRadius: AppRadius.sm,
                ),
                child: GlyphIcon(
                  VaultGlyphs.vault,
                  size: 22,
                  color: colorScheme.onSecondaryContainer,
                ),
              ),
              const SizedBox(width: CategoryWorkbenchTokens.space12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      key: const ValueKey('prism-category-detail-empty-title'),
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyle.title2.of(context, emphasized: true),
                    ),
                    const SizedBox(height: CategoryWorkbenchTokens.space4),
                    Text(
                      key: const ValueKey('prism-category-detail-empty-count'),
                      countLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyle.footnote
                          .of(context)
                          .copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: CategoryWorkbenchTokens.space20),
          Text(
            key: const ValueKey('prism-category-detail-empty-message'),
            message,
            style: AppTextStyle.subheadline.of(context, emphasized: true),
          ),
          const SizedBox(height: CategoryWorkbenchTokens.space8),
          Text(
            key: const ValueKey('prism-category-detail-empty-hint'),
            hint,
            style: AppTextStyle.caption1
                .of(context)
                .copyWith(color: colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
