import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_shell/prism_shell.dart';
import 'package:prism_ui/prism_ui.dart';

void main() {
  test('package starts from host-neutral branding', () {
    const settings = ShellSettings();

    expect(settings.seedColor, shellDefaultAccentSeed);
    expect(settings.colorStyle, ColorStyle.vivid);
    expect(settings.themeMode, ThemeMode.system);
  });

  test('host can replace every visual setting', () {
    const settings = ShellSettings(seedColor: Color(0xFF14B8A6));
    final updated = settings.copyWith(
      themeMode: ThemeMode.dark,
      colorStyle: ColorStyle.tinted,
      textScale: 1.25,
      liquidGlass: false,
      reduceMotion: true,
      locale: 'en_US',
    );

    expect(updated.seedColor, const Color(0xFF14B8A6));
    expect(updated.themeMode, ThemeMode.dark);
    expect(updated.colorStyle, ColorStyle.tinted);
    expect(updated.textScale, 1.25);
    expect(updated.liquidGlass, isFalse);
    expect(updated.reduceMotion, isTrue);
    expect(updated.locale, 'en_US');
  });

  test('theme builder derives both brightnesses', () {
    const settings = ShellSettings(seedColor: Color(0xFF0A84FF));
    final light = shellThemeOf(settings, Brightness.light);
    final dark = shellThemeOf(settings, Brightness.dark);

    expect(light.brightness, Brightness.light);
    expect(dark.brightness, Brightness.dark);
    expect(light.colorScheme.primary, isNot(dark.colorScheme.primary));
  });
}
