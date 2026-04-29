import 'package:flutter/material.dart';

import 'desktop_theme_extension.dart';

class DesktopThemeScope extends StatelessWidget {
  const DesktopThemeScope({
    super.key,
    required this.child,
    this.textScale = 1.12,
  });

  final Widget child;
  final double textScale;

  static TextTheme _stripTextDecorations(TextTheme textTheme) {
    TextStyle? clear(TextStyle? style) =>
        style?.copyWith(decoration: TextDecoration.none);
    return textTheme.copyWith(
      displayLarge: clear(textTheme.displayLarge),
      displayMedium: clear(textTheme.displayMedium),
      displaySmall: clear(textTheme.displaySmall),
      headlineLarge: clear(textTheme.headlineLarge),
      headlineMedium: clear(textTheme.headlineMedium),
      headlineSmall: clear(textTheme.headlineSmall),
      titleLarge: clear(textTheme.titleLarge),
      titleMedium: clear(textTheme.titleMedium),
      titleSmall: clear(textTheme.titleSmall),
      bodyLarge: clear(textTheme.bodyLarge),
      bodyMedium: clear(textTheme.bodyMedium),
      bodySmall: clear(textTheme.bodySmall),
      labelLarge: clear(textTheme.labelLarge),
      labelMedium: clear(textTheme.labelMedium),
      labelSmall: clear(textTheme.labelSmall),
    );
  }

  static ThemeData buildTheme(ThemeData base) {
    final fallback = DesktopThemeExtension.fallback(base.brightness);
    final desktopTheme = base.extension<DesktopThemeExtension>() ?? fallback;
    final extensions = base.extensions.values
        .where((ext) => ext is! DesktopThemeExtension)
        .toList();
    extensions.add(desktopTheme);

    final scheme = ColorScheme.fromSeed(
      seedColor: desktopTheme.accent,
      brightness: base.brightness,
    ).copyWith(
      primary: desktopTheme.accent,
      surface: desktopTheme.surface,
      onSurface: desktopTheme.textPrimary,
      outline: desktopTheme.border,
    );

    final textTheme = _stripTextDecorations(base.textTheme).apply(
      bodyColor: desktopTheme.textPrimary,
      displayColor: desktopTheme.textPrimary,
    );
    final primaryTextTheme = _stripTextDecorations(base.primaryTextTheme).apply(
      bodyColor: desktopTheme.textPrimary,
      displayColor: desktopTheme.textPrimary,
    );

    return base.copyWith(
      colorScheme: scheme,
      scaffoldBackgroundColor: desktopTheme.background,
      canvasColor: desktopTheme.background,
      cardColor: desktopTheme.surface,
      dividerColor: desktopTheme.border,
      textTheme: textTheme,
      primaryTextTheme: primaryTextTheme,
      extensions: extensions,
    );
  }

  @override
  Widget build(BuildContext context) {
    final themed = buildTheme(Theme.of(context));
    final mediaQuery = MediaQuery.of(context);

    return Theme(
      data: themed,
      child: MediaQuery(
        data: mediaQuery.copyWith(
          textScaler: TextScaler.linear(textScale),
        ),
        child: DefaultTextStyle.merge(
          style: const TextStyle(decoration: TextDecoration.none),
          child: child,
        ),
      ),
    );
  }
}
