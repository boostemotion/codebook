import 'package:flutter/foundation.dart';
import 'package:prism_ui/prism_ui.dart';

import 'shell_settings.dart';

typedef ShellThemeBuilder =
    ThemeData Function(ShellSettings settings, Brightness brightness);

ThemeData shellThemeOf(ShellSettings settings, Brightness brightness) {
  final scheme = seededColorScheme(
    seedColor: settings.seedColor,
    brightness: brightness,
    style: settings.colorStyle,
  );
  final desktop = switch (defaultTargetPlatform) {
    TargetPlatform.windows ||
    TargetPlatform.linux ||
    TargetPlatform.macOS => true,
    _ => false,
  };
  return ThemeData(
    colorScheme: scheme,
    fontFamily: settings.fontFamily == 'system' ? null : settings.fontFamily,
    visualDensity: desktop
        ? settings.compactDensity
              ? VisualDensity.compact
              : VisualDensity.standard
        : null,
    elevatedColorScheme: brightness == Brightness.dark ? scheme.elevated : null,
  );
}
