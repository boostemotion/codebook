import 'dart:ui' show Color;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prism_ui/prism_ui.dart';

enum ShellTabAnimation { slide, fade }

/// A neutral default hosts are expected to replace with product branding.
const shellDefaultAccentSeed = Color(0xFF0A84FF);

/// The initial settings supplied to [ShellSettingsController].
///
/// Hosts can override this provider without replacing the controller:
///
/// ```dart
/// ProviderScope(
///   overrides: [
///     initialShellSettingsProvider.overrideWithValue(
///       const ShellSettings(seedColor: Color(0xFF14B8A6)),
///     ),
///   ],
/// )
/// ```
final initialShellSettingsProvider = Provider<ShellSettings>(
  (ref) => const ShellSettings(),
);

class ShellSettings {
  const ShellSettings({
    this.themeMode = ThemeMode.system,
    this.colorStyle = ColorStyle.vivid,
    this.seedColor = shellDefaultAccentSeed,
    this.fontFamily = 'system',
    this.textScale = 1,
    this.liquidGlass = true,
    this.sidebarExpanded = true,
    this.floatingNavigationBar = true,
    this.compactDensity = true,
    this.tabAnimation = ShellTabAnimation.slide,
    this.reduceMotion = false,
    this.locale,
  });

  final ThemeMode themeMode;
  final ColorStyle colorStyle;
  final Color seedColor;
  final String fontFamily;
  final double textScale;
  final bool liquidGlass;
  final bool sidebarExpanded;
  final bool floatingNavigationBar;
  final bool compactDensity;
  final ShellTabAnimation tabAnimation;
  final bool reduceMotion;
  final String? locale;

  ShellSettings copyWith({
    ThemeMode? themeMode,
    ColorStyle? colorStyle,
    Color? seedColor,
    String? fontFamily,
    double? textScale,
    bool? liquidGlass,
    bool? sidebarExpanded,
    bool? floatingNavigationBar,
    bool? compactDensity,
    ShellTabAnimation? tabAnimation,
    bool? reduceMotion,
    String? locale,
    bool clearLocale = false,
  }) {
    return ShellSettings(
      themeMode: themeMode ?? this.themeMode,
      colorStyle: colorStyle ?? this.colorStyle,
      seedColor: seedColor ?? this.seedColor,
      fontFamily: fontFamily ?? this.fontFamily,
      textScale: textScale ?? this.textScale,
      liquidGlass: liquidGlass ?? this.liquidGlass,
      sidebarExpanded: sidebarExpanded ?? this.sidebarExpanded,
      floatingNavigationBar:
          floatingNavigationBar ?? this.floatingNavigationBar,
      compactDensity: compactDensity ?? this.compactDensity,
      tabAnimation: tabAnimation ?? this.tabAnimation,
      reduceMotion: reduceMotion ?? this.reduceMotion,
      locale: clearLocale ? null : locale ?? this.locale,
    );
  }
}

class ShellSettingsController extends Notifier<ShellSettings> {
  @override
  ShellSettings build() => ref.watch(initialShellSettingsProvider);

  void update(ShellSettings Function(ShellSettings value) updater) {
    state = updater(state);
  }
}

final shellSettingsProvider =
    NotifierProvider<ShellSettingsController, ShellSettings>(
      ShellSettingsController.new,
    );
