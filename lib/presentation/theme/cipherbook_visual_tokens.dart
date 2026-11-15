import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:prism_shell/prism_shell.dart';
import 'package:prism_ui/prism_ui.dart';

abstract final class CipherbookVisualTokens {
  static const bgApp = Color(0xFF161310);
  static const surface = Color(0xFF161310);
  static const surfaceRaised = Color(0xFF302B27);
  static const surfaceMuted = Color(0xFF292522);
  static const border = Color(0xFF453E38);
  static const borderStrong = Color(0xFF62574F);

  static const textPrimary = Color(0xFFF4EEE7);
  static const textSecondary = Color(0xFFB8AEA3);

  static const accent = Color(0xFFFAA251);
  static const accentHover = Color(0xFFFFB36B);
  static const accentPressed = Color(0xFFE58D3D);
  static const accentSoft = Color(0xFF3A2A1D);
  static const success = Color(0xFF6DB88A);
  static const warning = Color(0xFFD9A441);
  static const danger = Color(0xFFD86D65);
  static const dangerSoft = Color(0xFF3A211F);

  static const space4 = 4.0;
  static const space8 = 8.0;
  static const space12 = 12.0;
  static const space16 = 16.0;
  static const space20 = 20.0;
  static const space24 = 24.0;
  static const space32 = 32.0;
  static const space48 = 48.0;

  static const radiusControl = 16.0;
  static const radiusPanel = 20.0;
  static const radiusDialog = 24.0;
  static const radiusAvatar = 12.0;

  static const rowHeight = 50.0;
  static const dashboardRowHeight = 48.0;
  static const controlHeight = 44.0;
  static const mobileControlHeight = 44.0;
  static const pageToolbarHeight = 54.0;
  static const maxContentWidth = 1120.0;
  static const dashboardCardLaneHeight = 448.0;

  static const motionFast = Duration(milliseconds: 150);
  static const motionPage = Duration(milliseconds: 250);
  static const curve = Curves.easeOutCubic;

  static EdgeInsets pagePadding(double width) {
    final horizontal = width >= 900 ? space24 : space16;
    return EdgeInsets.fromLTRB(horizontal, space16, horizontal, space32);
  }

  static BorderRadius get controlRadius => BorderRadius.circular(radiusControl);
  static BorderRadius get panelRadius => BorderRadius.circular(radiusPanel);
  static BorderRadius get dialogRadius => BorderRadius.circular(radiusDialog);

  static const BorderSide borderSide = BorderSide(color: border);
  static const BorderSide strongBorderSide = BorderSide(color: borderStrong);
  static const BorderSide accentBorderSide = BorderSide(color: accent);

  static ButtonThemeData get buttonTheme => ButtonThemeData(
    icon: ButtonStyle(
      minimumSize: const Size.square(controlHeight),
      visualDensity: VisualDensity.standard,
      shape: AppShape.full,
    ),
    filled: ButtonStyle(
      shape: AppShape.full,
      minimumSize: const Size(0, controlHeight),
      padding: const EdgeInsets.symmetric(horizontal: space16),
      visualDensity: VisualDensity.standard,
    ),
    outlined: ButtonStyle(
      shape: AppShape.full,
      minimumSize: const Size(0, controlHeight),
      padding: const EdgeInsets.symmetric(horizontal: space12),
      visualDensity: VisualDensity.standard,
    ),
    text: ButtonStyle(
      shape: AppShape.full,
      minimumSize: const Size(0, controlHeight),
      padding: const EdgeInsets.symmetric(horizontal: space8),
      visualDensity: VisualDensity.standard,
    ),
  );

  static const ColorScheme darkColorScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: accent,
    onPrimary: Color(0xFF21150B),
    primaryContainer: accentSoft,
    onPrimaryContainer: textPrimary,
    secondary: warning,
    onSecondary: Color(0xFF211A0B),
    secondaryContainer: surfaceRaised,
    onSecondaryContainer: textPrimary,
    tertiary: success,
    onTertiary: Color(0xFF0B1B12),
    tertiaryContainer: Color(0xFF203126),
    onTertiaryContainer: textPrimary,
    error: danger,
    onError: Color(0xFF1D0F0E),
    errorContainer: dangerSoft,
    onErrorContainer: Color(0xFFF0B4AF),
    surface: bgApp,
    onSurface: textPrimary,
    surfaceDim: bgApp,
    surfaceBright: surface,
    surfaceContainerLowest: bgApp,
    surfaceContainerLow: surface,
    surfaceContainer: surfaceMuted,
    surfaceContainerHigh: surfaceRaised,
    surfaceContainerHighest: surfaceRaised,
    onSurfaceVariant: textSecondary,
    outline: borderStrong,
    outlineVariant: border,
    shadow: Color(0xFF000000),
    scrim: Color(0xCC000000),
    inverseSurface: textPrimary,
    onInverseSurface: bgApp,
    inversePrimary: accentPressed,
    surfaceTint: Color(0x00000000),
  );
}

ThemeData cipherbookPrismTheme(ShellSettings settings, Brightness brightness) {
  final desktop = switch (defaultTargetPlatform) {
    TargetPlatform.windows ||
    TargetPlatform.linux ||
    TargetPlatform.macOS => true,
    _ => false,
  };
  final configuredFamily = settings.fontFamily == 'system'
      ? null
      : settings.fontFamily;
  return ThemeData(
    colorScheme: CipherbookVisualTokens.darkColorScheme,
    fontFamily: configuredFamily ?? (desktop ? 'Segoe UI Variable' : null),
    fontFamilyFallback: desktop
        ? const ['Microsoft YaHei UI', 'Microsoft YaHei', 'Segoe UI']
        : const ['Noto Sans CJK SC', 'sans-serif'],
    visualDensity: settings.compactDensity
        ? VisualDensity.compact
        : VisualDensity.standard,
    tapTargetSize: desktop ? TapTargetSize.shrinkWrap : TapTargetSize.padded,
    scaffoldBackgroundColor: CipherbookVisualTokens.bgApp,
    elevatedColorScheme: CipherbookVisualTokens.darkColorScheme.elevated,
  );
}
