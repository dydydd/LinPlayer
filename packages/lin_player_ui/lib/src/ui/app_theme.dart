import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';

import 'app_style.dart';

/// Centralized theme (light/dark + optional Material You dynamic color).
class AppTheme {
  static const Color _defaultSeed = Color(0xFFFF6FB1);
  static const Color _defaultSecondarySeed = Color(0xFF7DD9FF);

  static String? _fontFamily(TargetPlatform platform) {
    return switch (platform) {
      // Native desktop UI fonts render mixed CJK/Latin text more consistently
      // than the bundled variable font we previously shipped.
      TargetPlatform.windows => 'Microsoft YaHei UI',
      TargetPlatform.macOS => 'PingFang SC',
      // Let Linux/mobile keep the platform default face and use fallbacks for
      // missing glyphs rather than forcing a bundled font asset.
      TargetPlatform.linux => null,
      TargetPlatform.android => null,
      TargetPlatform.iOS => null,
      TargetPlatform.fuchsia => null,
    };
  }

  static List<String> _fontFallback(TargetPlatform platform) {
    return switch (platform) {
      TargetPlatform.windows => const <String>[
          'Segoe UI',
          'Microsoft YaHei',
          'Microsoft JhengHei UI',
          'Microsoft JhengHei',
          'Malgun Gothic',
          'Segoe UI Emoji',
          'Segoe UI Symbol',
        ],
      TargetPlatform.macOS => const <String>[
          '.SF NS Text',
          'SF Pro Text',
          'PingFang SC',
          'Hiragino Sans GB',
          'Helvetica Neue',
          'Apple Color Emoji',
        ],
      TargetPlatform.linux => const <String>[
          'Noto Sans CJK SC',
          'Source Han Sans SC',
          'WenQuanYi Micro Hei',
          'Noto Sans',
          'DejaVu Sans',
          'Noto Color Emoji',
        ],
      TargetPlatform.android => const <String>[
          'Roboto',
          'Noto Sans CJK SC',
          'Noto Color Emoji',
        ],
      TargetPlatform.iOS => const <String>[
          'PingFang SC',
          '.SF Pro Text',
          'Helvetica Neue',
          'Apple Color Emoji',
        ],
      TargetPlatform.fuchsia => const <String>[
          'Roboto',
          'Noto Color Emoji',
        ],
    };
  }

  static ColorScheme _resolveScheme({
    required Brightness brightness,
    ColorScheme? dynamicScheme,
    Color? seed,
    Color? secondarySeed,
  }) {
    final resolvedSeed = seed ?? _defaultSeed;
    final resolvedSecondarySeed = secondarySeed ?? _defaultSecondarySeed;

    final primaryScheme = ColorScheme.fromSeed(
      seedColor: resolvedSeed,
      brightness: brightness,
    );
    final secondaryScheme = ColorScheme.fromSeed(
      seedColor: resolvedSecondarySeed,
      brightness: brightness,
    );

    final seeded = primaryScheme.copyWith(
      secondary: secondaryScheme.primary,
      onSecondary: secondaryScheme.onPrimary,
      secondaryContainer: secondaryScheme.primaryContainer,
      onSecondaryContainer: secondaryScheme.onPrimaryContainer,
    );

    // When Material You / Monet is available, use the full dynamic scheme so
    // the visible accent colors actually follow the system palette.
    if (dynamicScheme != null) return dynamicScheme;

    return seeded;
  }

  static ThemeData light({
    ColorScheme? dynamicScheme,
    Color? seed,
    Color? secondarySeed,
    bool compact = false,
  }) {
    final scheme = _resolveScheme(
      brightness: Brightness.light,
      dynamicScheme: dynamicScheme,
      seed: seed,
      secondarySeed: secondarySeed,
    );
    return _build(scheme, compact: compact);
  }

  static ThemeData dark({
    ColorScheme? dynamicScheme,
    Color? seed,
    Color? secondarySeed,
    bool compact = false,
  }) {
    final scheme = _resolveScheme(
      brightness: Brightness.dark,
      dynamicScheme: dynamicScheme,
      seed: seed,
      secondarySeed: secondarySeed,
    );
    return _build(scheme, compact: compact);
  }

  static ThemeData _build(
    ColorScheme scheme, {
    required bool compact,
  }) {
    final platform = defaultTargetPlatform;
    final appFontFamily = _fontFamily(platform);
    final appFontFallback = _fontFallback(platform);
    final isDark = scheme.brightness == Brightness.dark;
    final effectiveCompact = compact;
    final style = _styleFor(isDark: isDark, compact: effectiveCompact);

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: scheme.brightness,
      typography: Typography.material2021(platform: platform),
      visualDensity: effectiveCompact
          ? VisualDensity.compact
          : VisualDensity.adaptivePlatformDensity,
      materialTapTargetSize: effectiveCompact
          ? MaterialTapTargetSize.shrinkWrap
          : MaterialTapTargetSize.padded,
      fontFamily: appFontFamily,
      fontFamilyFallback: appFontFallback,
      extensions: <ThemeExtension<dynamic>>[style],
    );

    final radius = BorderRadius.circular(style.radius);
    TextStyle? scale(TextStyle? style) {
      if (style == null) return null;
      final size = style.fontSize;
      final scaled = size == null
          ? style
          : style.copyWith(
              fontSize: size * (effectiveCompact ? 0.90 : 0.92),
            );
      return scaled.copyWith(
        decoration: TextDecoration.none,
      );
    }

    final textTheme = base.textTheme.copyWith(
      displayLarge: scale(base.textTheme.displayLarge),
      displayMedium: scale(base.textTheme.displayMedium),
      displaySmall: scale(base.textTheme.displaySmall),
      headlineLarge: scale(base.textTheme.headlineLarge),
      headlineMedium: scale(base.textTheme.headlineMedium),
      headlineSmall: scale(base.textTheme.headlineSmall),
      titleLarge: scale(base.textTheme.titleLarge),
      titleMedium: scale(base.textTheme.titleMedium),
      titleSmall: scale(base.textTheme.titleSmall),
      bodyLarge: scale(base.textTheme.bodyLarge),
      bodyMedium: scale(base.textTheme.bodyMedium),
      bodySmall: scale(base.textTheme.bodySmall),
      labelLarge: scale(base.textTheme.labelLarge),
      labelMedium: scale(base.textTheme.labelMedium),
      labelSmall: scale(base.textTheme.labelSmall),
    );

    final hasBackdrop = style.background != AppBackgroundKind.none ||
        style.pattern != AppPatternKind.none;
    final appBarBg = scheme.surface.withValues(alpha: isDark ? 0.64 : 0.82);
    final navBarBg =
        scheme.surfaceContainerHigh.withValues(alpha: isDark ? 0.70 : 0.82);
    final surfaceHigh =
        scheme.surfaceContainerHigh.withValues(alpha: isDark ? 0.62 : 0.78);
    final outline =
        scheme.outlineVariant.withValues(alpha: isDark ? 0.42 : 0.7);
    final outlineSoft =
        scheme.outlineVariant.withValues(alpha: isDark ? 0.36 : 0.55);
    final glassOutline =
        scheme.outlineVariant.withValues(alpha: isDark ? 0.30 : 0.48);

    final cardSide = BorderSide(
      color: glassOutline,
      width: style.borderWidth,
    );

    final navIndicatorShape =
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(14));

    const chipRadius = 14.0;

    return base.copyWith(
      textTheme: textTheme,
      scaffoldBackgroundColor:
          hasBackdrop ? Colors.transparent : scheme.surface,
      appBarTheme: base.appBarTheme.copyWith(
        backgroundColor: appBarBg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        toolbarHeight: effectiveCompact ? 44 : 48,
        titleTextStyle:
            textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
      ),
      navigationBarTheme: base.navigationBarTheme.copyWith(
        backgroundColor: navBarBg,
        indicatorColor: scheme.primary.withValues(
          alpha: isDark ? 0.22 : 0.18,
        ),
        indicatorShape: navIndicatorShape,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        height: effectiveCompact ? 50 : 54,
      ),
      cardTheme: base.cardTheme.copyWith(
        color: surfaceHigh,
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: radius, side: cardSide),
      ),
      listTileTheme: base.listTileTheme.copyWith(
        iconColor: scheme.onSurfaceVariant,
        contentPadding: EdgeInsets.symmetric(
          horizontal: effectiveCompact ? 10 : 12,
          vertical: effectiveCompact ? 2 : 4,
        ),
        horizontalTitleGap: 12,
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: surfaceHigh,
        selectedColor: scheme.primary.withValues(alpha: 0.2),
        padding: EdgeInsets.symmetric(
          horizontal: effectiveCompact ? 8 : 10,
          vertical: effectiveCompact ? 4 : 6,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(chipRadius),
          side: BorderSide.none,
        ),
        labelStyle: (textTheme.labelLarge ?? const TextStyle()).copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
      inputDecorationTheme: base.inputDecorationTheme.copyWith(
        filled: true,
        fillColor: surfaceHigh,
        border: OutlineInputBorder(
            borderRadius: radius, borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: outlineSoft),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(
            color: scheme.primary.withValues(alpha: isDark ? 0.95 : 1.0),
            width: style.borderWidth + 0.2,
          ),
        ),
        contentPadding: EdgeInsets.symmetric(
          horizontal: effectiveCompact ? 12 : 14,
          vertical: effectiveCompact ? 10 : 12,
        ),
      ),
      floatingActionButtonTheme: base.floatingActionButtonTheme.copyWith(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        shape: RoundedRectangleBorder(borderRadius: radius),
      ),
      dividerTheme: base.dividerTheme.copyWith(
        color: outline,
        thickness: 1,
        space: effectiveCompact ? 12 : 16,
      ),
      navigationRailTheme: base.navigationRailTheme.copyWith(
        backgroundColor: navBarBg,
        indicatorColor: scheme.primary.withValues(
          alpha: isDark ? 0.22 : 0.18,
        ),
        useIndicator: true,
      ),
    );
  }

  static AppStyle _styleFor({
    required bool isDark,
    required bool compact,
  }) {
    return AppStyle(
      compact: compact,
      radius: 22,
      panelRadius: 22,
      borderWidth: 1.0,
      background: AppBackgroundKind.gradient,
      pattern: AppPatternKind.dotsSparkles,
      backgroundIntensity: 1.0,
      patternOpacity: isDark ? 0.06 : 0.075,
    );
  }
}
