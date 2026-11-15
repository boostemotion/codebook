import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prism_ui/prism_ui.dart';

import 'shell_settings.dart';
import 'shell_platform.dart';
import 'shell_theme.dart';

/// Host-neutral application root for the retained Prism frontend.
///
/// Product-specific localization, pages, and branding stay in the host app.
class FrontendShellApp extends ConsumerWidget {
  const FrontendShellApp({
    super.key,
    required this.title,
    required this.home,
    required this.localizationsDelegates,
    required this.supportedLocales,
    this.themeBuilder = shellThemeOf,
    this.minTextScale = 0.8,
    this.maxTextScale = 1.6,
    this.desktopTopInset = 32,
    this.mobileWidthBreakpoint = 620,
    this.mobilePlatformPredicate = defaultMobilePlatformPredicate,
    this.builder,
  });

  final String title;
  final Widget home;
  final Iterable<LocalizationsDelegate<dynamic>> localizationsDelegates;
  final Iterable<Locale> supportedLocales;
  final ShellThemeBuilder themeBuilder;
  final double minTextScale;
  final double maxTextScale;
  final double desktopTopInset;
  final double mobileWidthBreakpoint;
  final bool Function(TargetPlatform platform) mobilePlatformPredicate;
  final TransitionBuilder? builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(shellSettingsProvider);
    return PrismApp(
      title: title,
      theme: themeBuilder(settings, Brightness.light),
      darkTheme: themeBuilder(settings, Brightness.dark),
      themeMode: settings.themeMode,
      locale: _parseLocale(settings.locale),
      supportedLocales: supportedLocales,
      localizationsDelegates: localizationsDelegates,
      textScale: settings.textScale,
      minTextScale: minTextScale,
      maxTextScale: maxTextScale,
      liquidGlass: settings.liquidGlass ? LiquidGlassQuality.standard : null,
      debugShowCheckedModeBanner: false,
      builder: (context, child) {
        final media = MediaQuery.of(context);
        final desktop = switch (defaultTargetPlatform) {
          TargetPlatform.windows ||
          TargetPlatform.linux ||
          TargetPlatform.macOS => true,
          _ => false,
        };
        final isMobile =
            mobilePlatformPredicate(defaultTargetPlatform) ||
            media.size.width < mobileWidthBreakpoint;
        final shell = ViewScope(
          size: media.size,
          isMobile: isMobile,
          child: MediaQuery(
            data: media.copyWith(
              disableAnimations:
                  settings.reduceMotion || media.disableAnimations,
              padding: desktop
                  ? media.padding.copyWith(
                      top: math.max(media.padding.top, desktopTopInset),
                    )
                  : media.padding,
            ),
            child: child ?? const SizedBox.shrink(),
          ),
        );
        return builder?.call(context, shell) ?? shell;
      },
      home: home,
    );
  }

  Locale? _parseLocale(String? value) {
    if (value == null || value.isEmpty) {
      return null;
    }
    final parts = value.split(RegExp(r'[_-]'));
    return parts.length > 1
        ? Locale.fromSubtags(languageCode: parts.first, countryCode: parts[1])
        : Locale(parts.first);
  }
}
