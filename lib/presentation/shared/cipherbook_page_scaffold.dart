import 'package:flutter/widgets.dart';
import 'package:prism_ui/prism_ui.dart';

class CipherbookPageScaffold extends StatelessWidget {
  const CipherbookPageScaffold({super.key, required this.body});

  final Widget body;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: context.colorScheme.surface,
      child: SafeArea(top: true, bottom: false, child: body),
    );
  }
}
