import 'package:flutter/widgets.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';

import '../theme/cipherbook_visual_tokens.dart';

class PasswordDetailNavigation extends StatelessWidget {
  const PasswordDetailNavigation({
    super.key,
    required this.onBack,
    this.backButtonKey,
  });

  final VoidCallback onBack;
  final Key? backButtonKey;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 56,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: TextButton.icon(
                key: backButtonKey,
                onPressed: onBack,
                icon: const GlyphIcon(Glyphs.arrowBack),
                label: const Text('返回列表'),
                style: const ButtonStyle(
                  minimumSize: Size(0, 44),
                  tapTargetSize: TapTargetSize.shrinkWrap,
                ),
              ),
            ),
          ),
        ),
        SizedBox(
          height: 1,
          child: ColoredBox(color: colorScheme.outlineVariant),
        ),
      ],
    );
  }
}

class PasswordDetailFrame extends StatelessWidget {
  const PasswordDetailFrame({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(CipherbookVisualTokens.space16),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1000),
          child: child,
        ),
      ),
    );
  }
}
