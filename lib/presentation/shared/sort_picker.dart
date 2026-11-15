import 'package:flutter/widgets.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';

import '../theme/cipherbook_visual_tokens.dart';

class SortChoice<T> {
  const SortChoice({required this.value, required this.label, this.key});

  final T value;
  final String label;
  final Key? key;
}

Future<T?> showSortPicker<T>({
  required BuildContext context,
  required String title,
  required T selected,
  required List<SortChoice<T>> choices,
}) {
  return showFloatingDialog<T>(
    context: context,
    child: Builder(
      builder: (dialogContext) {
        return AlertDialog(
          title: title,
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
              for (var index = 0; index < choices.length; index++)
                Padding(
                  padding: EdgeInsets.only(
                    bottom: index == choices.length - 1
                        ? 0
                        : CipherbookVisualTokens.space4,
                  ),
                  child: Card(
                    key: choices[index].key,
                    isSelected: choices[index].value == selected,
                    onPressed: () =>
                        Navigator.of(dialogContext).pop(choices[index].value),
                    shape: AppShape.all(CipherbookVisualTokens.radiusControl)
                        .copyWith(
                          side: choices[index].value == selected
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
                            choices[index].label,
                            style: AppTextStyle.subheadline.of(
                              dialogContext,
                              emphasized: true,
                            ),
                          ),
                        ),
                        if (choices[index].value == selected)
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
}
