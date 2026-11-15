import 'package:flutter/widgets.dart';
import 'package:prism_ui/icons/icons.dart';

typedef ShellDestinationLabel = String Function(BuildContext context);

/// One page in a [ResponsiveShell].
///
/// [id] is the stable navigation/deep-link identifier, while [label] is
/// resolved on every build so hosts can bind it to their own localization.
class ShellDestinationSpec {
  const ShellDestinationSpec({
    required this.id,
    required this.glyph,
    required this.label,
    required this.builder,
    this.mobile = false,
    this.desktop = true,
    this.storageKey,
  });

  final String id;
  final Glyph glyph;
  final ShellDestinationLabel label;
  final WidgetBuilder builder;
  final bool mobile;
  final bool desktop;
  final String? storageKey;
}
