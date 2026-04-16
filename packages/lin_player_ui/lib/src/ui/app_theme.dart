import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';

import 'package:lin_player_prefs/preferences.dart';
import 'app_style.dart';

/// Centralized theme (light/dark + optional Material You dynamic color).
class AppTheme {
  static const String _appFontFamily = 'Noto Sans SC';

  static String _fontFamily(TargetPlatform platform) {
    // Use a bundled CJK+Latin font across all platforms to keep glyphs & weights
    // consistent.
    //
    // Note: emoji are still expected to fall back to platform emoji fonts.
    return _appFontFamily;
  }

  static List<String> _fontFallback(TargetPlatform platform) {
    return switch (platform) {
      TargetPlatform.windows => const <String>[
          // System UI fallbacks (best-effort for rare missing glyphs).
          'Segoe UI',
          'Microsoft YaHei UI',
          'Microsoft YaHei',
          'Microsoft JhengHei UI',
          'Microsoft JhengHei',
          // Emoji / symbols.
          'Segoe UI Emoji',
          'Segoe UI Symbol',
        ],
      TargetPlatform.macOS => const <String>[
          // System UI fallbacks (best-effort for rare missing glyphs).
          '.SF NS Text',
          'SF Pro Text',
          'PingFang SC',
          'Helvetica Neue',
          // Emoji.
          'Apple Color Emoji',
        ],
      TargetPlatform.linux => const <String>[
          // System UI fallbacks (best-effort for rare missing glyphs).
          'Noto Sans',
          'DejaVu Sans',
          // Emoji.
          'Noto Color Emoji',
        ],
      TargetPlatform.android => const <String>[
          'Roboto',
          'Noto Color Emoji',
        ],
      TargetPlatform.iOS => const <String>[
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
    required UiTemplate template,
    ColorScheme? dynamicScheme,
    Color? seed,
    Color? secondarySeed,
  }) {
    final resolvedSeed = seed ?? template.seed;
    final resolvedSecondarySeed = secondarySeed ?? template.secondarySeed;

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
    required UiTemplate template,
    Color? seed,
    Color? secondarySeed,
    bool compact = false,
  }) {
    final scheme = _resolveScheme(
      brightness: Brightness.light,
      template: template,
      dynamicScheme: dynamicScheme,
      seed: seed,
      secondarySeed: secondarySeed,
    );
    return _build(scheme, template: template, compact: compact);
  }

  static ThemeData dark({
    ColorScheme? dynamicScheme,
    required UiTemplate template,
    Color? seed,
    Color? secondarySeed,
    bool compact = false,
  }) {
    final scheme = _resolveScheme(
      brightness: Brightness.dark,
      template: template,
      dynamicScheme: dynamicScheme,
      seed: seed,
      secondarySeed: secondarySeed,
    );
    return _build(scheme, template: template, compact: compact);
  }

  static ThemeData _build(
    ColorScheme scheme, {
    required UiTemplate template,
    required bool compact,
  }) {
    final platform = defaultTargetPlatform;
    final appFontFamily = _fontFamily(platform);
    final appFontFallback = _fontFallback(platform);
    final isDark = scheme.brightness == Brightness.dark;
    final effectiveCompact = compact || template == UiTemplate.proTool;
    final style = _styleFor(
      template,
      isDark: isDark,
      compact: effectiveCompact,
    );

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: scheme.brightness,
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
    final glassSurfaces = template == UiTemplate.candyGlass ||
        template == UiTemplate.stickerJournal ||
        template == UiTemplate.neonHud ||
        template == UiTemplate.washiWatercolor;

    final appBarBg = glassSurfaces
        ? scheme.surface.withValues(alpha: isDark ? 0.64 : 0.82)
        : scheme.surface;
    final navBarBg = glassSurfaces
        ? scheme.surfaceContainerHigh.withValues(alpha: isDark ? 0.70 : 0.82)
        : scheme.surfaceContainerHigh;
    final surfaceHigh = glassSurfaces
        ? scheme.surfaceContainerHigh.withValues(alpha: isDark ? 0.62 : 0.78)
        : scheme.surfaceContainerHigh;
    final outline =
        scheme.outlineVariant.withValues(alpha: isDark ? 0.42 : 0.7);
    final outlineSoft =
        scheme.outlineVariant.withValues(alpha: isDark ? 0.36 : 0.55);
    final glassOutline =
        scheme.outlineVariant.withValues(alpha: isDark ? 0.30 : 0.48);

    final cardSide = switch (template) {
      UiTemplate.neonHud => BorderSide(
          color: scheme.primary.withValues(alpha: isDark ? 0.55 : 0.70),
          width: style.borderWidth + 0.2,
        ),
      UiTemplate.candyGlass => BorderSide(
          color: glassOutline,
          width: style.borderWidth,
        ),
      UiTemplate.pixelArcade => BorderSide(
          color: scheme.secondary.withValues(alpha: isDark ? 0.50 : 0.70),
          width: style.borderWidth + 0.6,
        ),
      UiTemplate.mangaStoryboard => BorderSide(
          color: scheme.onSurface.withValues(alpha: isDark ? 0.55 : 0.75),
          width: style.borderWidth + 0.8,
        ),
      UiTemplate.proTool => BorderSide(
          color: outlineSoft,
          width: style.borderWidth,
        ),
      UiTemplate.stickerJournal => BorderSide(
          color: scheme.secondary.withValues(alpha: isDark ? 0.35 : 0.55),
          width: style.borderWidth,
        ),
      UiTemplate.washiWatercolor => BorderSide(
          color: glassOutline,
          width: style.borderWidth,
        ),
      _ => BorderSide.none,
    };

    final navIndicatorShape = switch (template) {
      UiTemplate.neonHud => RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(
            color: scheme.primary.withValues(alpha: isDark ? 0.70 : 0.80),
            width: style.borderWidth,
          ),
        ),
      UiTemplate.pixelArcade => RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(
            color: scheme.secondary.withValues(alpha: isDark ? 0.55 : 0.75),
            width: style.borderWidth + 0.4,
          ),
        ),
      UiTemplate.mangaStoryboard => RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(
            color: scheme.onSurface.withValues(alpha: isDark ? 0.55 : 0.75),
            width: style.borderWidth + 0.6,
          ),
        ),
      UiTemplate.stickerJournal => RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: scheme.secondary.withValues(alpha: isDark ? 0.35 : 0.55),
            width: style.borderWidth,
          ),
        ),
      _ => RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    };

    final appBarBorder = switch (template) {
      UiTemplate.neonHud ||
      UiTemplate.pixelArcade ||
      UiTemplate.mangaStoryboard =>
        Border(bottom: BorderSide(color: outline, width: style.borderWidth)),
      _ => null,
    };

    final chipRadius = switch (template) {
      UiTemplate.candyGlass => 14.0,
      UiTemplate.stickerJournal => 14.0,
      UiTemplate.neonHud => 10.0,
      UiTemplate.minimalCovers => 12.0,
      UiTemplate.washiWatercolor => 12.0,
      UiTemplate.pixelArcade => 8.0,
      UiTemplate.mangaStoryboard => 10.0,
      UiTemplate.proTool => 10.0,
    };

    final outlinedInputs = template == UiTemplate.candyGlass ||
        template == UiTemplate.stickerJournal ||
        template == UiTemplate.neonHud ||
        template == UiTemplate.pixelArcade ||
        template == UiTemplate.mangaStoryboard;

    return base.copyWith(
      textTheme: textTheme,
      scaffoldBackgroundColor:
          hasBackdrop ? Colors.transparent : scheme.surface,
      appBarTheme: base.appBarTheme.copyWith(
        backgroundColor: appBarBg,
        surfaceTintColor: Colors.transparent,
        shape: appBarBorder,
        elevation: 0,
        toolbarHeight: effectiveCompact ? 44 : 48,
        titleTextStyle:
            textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
      ),
      navigationBarTheme: base.navigationBarTheme.copyWith(
        backgroundColor: navBarBg,
        indicatorColor: scheme.primary.withValues(
          alpha: isDark
              ? (glassSurfaces ? 0.22 : 0.18)
              : (glassSurfaces ? 0.18 : 0.14),
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
          side: switch (template) {
            UiTemplate.neonHud => BorderSide(
                color: scheme.primary.withValues(alpha: isDark ? 0.50 : 0.70),
                width: style.borderWidth,
              ),
            UiTemplate.pixelArcade => BorderSide(
                color: scheme.secondary.withValues(alpha: isDark ? 0.45 : 0.65),
                width: style.borderWidth + 0.4,
              ),
            UiTemplate.mangaStoryboard => BorderSide(
                color: scheme.onSurface.withValues(alpha: isDark ? 0.45 : 0.65),
                width: style.borderWidth + 0.5,
              ),
            _ => BorderSide.none,
          },
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
        enabledBorder: !outlinedInputs
            ? null
            : OutlineInputBorder(
                borderRadius: radius,
                borderSide: BorderSide(color: outlineSoft),
              ),
        focusedBorder: !outlinedInputs
            ? null
            : OutlineInputBorder(
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
        thickness: switch (template) {
          UiTemplate.mangaStoryboard => 1.4,
          UiTemplate.pixelArcade => 1.2,
          _ => 1,
        },
        space: effectiveCompact ? 12 : 16,
      ),
      navigationRailTheme: base.navigationRailTheme.copyWith(
        backgroundColor: navBarBg,
        indicatorColor: scheme.primary.withValues(
          alpha: isDark
              ? (glassSurfaces ? 0.22 : 0.18)
              : (glassSurfaces ? 0.18 : 0.14),
        ),
        useIndicator: true,
      ),
    );
  }

  static AppStyle _styleFor(
    UiTemplate template, {
    required bool isDark,
    required bool compact,
  }) {
    switch (template) {
      case UiTemplate.candyGlass:
        return AppStyle(
          template: template,
          compact: compact,
          radius: 22,
          panelRadius: 22,
          borderWidth: 1.0,
          background: AppBackgroundKind.gradient,
          pattern: AppPatternKind.dotsSparkles,
          backgroundIntensity: 1.0,
          patternOpacity: isDark ? 0.06 : 0.075,
        );
      case UiTemplate.stickerJournal:
        return AppStyle(
          template: template,
          compact: compact,
          radius: 20,
          panelRadius: 20,
          borderWidth: 1.0,
          background: AppBackgroundKind.gradient,
          pattern: AppPatternKind.dotsSparkles,
          backgroundIntensity: 0.9,
          patternOpacity: isDark ? 0.045 : 0.06,
        );
      case UiTemplate.neonHud:
        return AppStyle(
          template: template,
          compact: compact,
          radius: 14,
          panelRadius: 14,
          borderWidth: 1.2,
          background: AppBackgroundKind.gradient,
          pattern: AppPatternKind.grid,
          backgroundIntensity: 0.9,
          patternOpacity: isDark ? 0.065 : 0.075,
        );
      case UiTemplate.minimalCovers:
        return AppStyle(
          template: template,
          compact: compact,
          radius: 18,
          panelRadius: 18,
          borderWidth: 1.0,
          background: AppBackgroundKind.none,
          pattern: AppPatternKind.none,
          backgroundIntensity: 0.0,
          patternOpacity: 0.0,
        );
      case UiTemplate.washiWatercolor:
        return AppStyle(
          template: template,
          compact: compact,
          radius: 20,
          panelRadius: 20,
          borderWidth: 1.0,
          background: AppBackgroundKind.gradient,
          pattern: AppPatternKind.none,
          backgroundIntensity: 0.85,
          patternOpacity: 0.0,
        );
      case UiTemplate.pixelArcade:
        return AppStyle(
          template: template,
          compact: compact,
          radius: 10,
          panelRadius: 10,
          borderWidth: 1.4,
          background: AppBackgroundKind.none,
          pattern: AppPatternKind.pixels,
          backgroundIntensity: 0.8,
          patternOpacity: isDark ? 0.06 : 0.085,
        );
      case UiTemplate.mangaStoryboard:
        return AppStyle(
          template: template,
          compact: compact,
          radius: 16,
          panelRadius: 16,
          borderWidth: 1.0,
          background: AppBackgroundKind.none,
          pattern: AppPatternKind.halftone,
          backgroundIntensity: 0.8,
          patternOpacity: isDark ? 0.045 : 0.075,
        );
      case UiTemplate.proTool:
        return AppStyle(
          template: template,
          compact: true,
          radius: 14,
          panelRadius: 14,
          borderWidth: 1.0,
          background: AppBackgroundKind.none,
          pattern: AppPatternKind.grid,
          backgroundIntensity: 0.35,
          patternOpacity: isDark ? 0.03 : 0.04,
        );
    }
  }
}
