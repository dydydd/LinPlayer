import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, immutable;
import 'package:flutter/material.dart';

import 'app_style.dart';

@immutable
class AppThemePalette {
  const AppThemePalette({
    required this.id,
    required this.label,
    required this.description,
    required this.primarySeed,
    required this.secondarySeed,
  });

  final String id;
  final String label;
  final String description;
  final Color primarySeed;
  final Color secondarySeed;
}

/// Centralized theme (light/dark + curated palette presets).
class AppTheme {
  static const AppThemePalette _defaultPalette = AppThemePalette(
    id: 'warm',
    label: '暖樱',
    description: '柔和粉金，保留当前默认风格。',
    primarySeed: Color(0xFFFF6FB1),
    secondarySeed: Color(0xFF7DD9FF),
  );

  static const List<AppThemePalette> palettes = <AppThemePalette>[
    _defaultPalette,
    AppThemePalette(
      id: 'ocean',
      label: '海盐',
      description: '清透蓝绿，层次更干净。',
      primarySeed: Color(0xFF3D7DFF),
      secondarySeed: Color(0xFF31C7B4),
    ),
    AppThemePalette(
      id: 'forest',
      label: '松雾',
      description: '安静青绿，长时间看更稳。',
      primarySeed: Color(0xFF2E8B57),
      secondarySeed: Color(0xFFC89A3D),
    ),
    AppThemePalette(
      id: 'graphite',
      label: '石墨',
      description: '冷灰蓝调，暗色模式更克制。',
      primarySeed: Color(0xFF5B6C92),
      secondarySeed: Color(0xFF8F7AF7),
    ),
  ];

  static AppThemePalette paletteForId(String? id) {
    final normalized = (id ?? '').trim().toLowerCase();
    for (final palette in palettes) {
      if (palette.id == normalized) return palette;
    }
    return _defaultPalette;
  }

  static String normalizeTemplateId(String? id) => paletteForId(id).id;

  static String labelFor(String? id) => paletteForId(id).label;

  static String descriptionFor(String? id) => paletteForId(id).description;

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
    Color? seed,
    Color? secondarySeed,
  }) {
    final palette = _defaultPalette;
    final resolvedSeed = seed ?? palette.primarySeed;
    final resolvedSecondarySeed = secondarySeed ?? palette.secondarySeed;

    final primaryScheme = ColorScheme.fromSeed(
      seedColor: resolvedSeed,
      brightness: brightness,
    );
    final secondaryScheme = ColorScheme.fromSeed(
      seedColor: resolvedSecondarySeed,
      brightness: brightness,
    );

    return primaryScheme.copyWith(
      secondary: secondaryScheme.primary,
      onSecondary: secondaryScheme.onPrimary,
      secondaryContainer: secondaryScheme.primaryContainer,
      onSecondaryContainer: secondaryScheme.onPrimaryContainer,
      tertiary: secondaryScheme.tertiary,
      onTertiary: secondaryScheme.onTertiary,
      tertiaryContainer: secondaryScheme.tertiaryContainer,
      onTertiaryContainer: secondaryScheme.onTertiaryContainer,
    );
  }

  static ColorScheme previewScheme({
    required String paletteId,
    required Brightness brightness,
  }) {
    final palette = paletteForId(paletteId);
    return _resolveScheme(
      brightness: brightness,
      seed: palette.primarySeed,
      secondarySeed: palette.secondarySeed,
    );
  }

  static ThemeData light({
    String themeTemplate = 'warm',
    bool compact = false,
  }) {
    final palette = paletteForId(themeTemplate);
    final scheme = _resolveScheme(
      brightness: Brightness.light,
      seed: palette.primarySeed,
      secondarySeed: palette.secondarySeed,
    );
    return _build(scheme, compact: compact);
  }

  static ThemeData dark({
    String themeTemplate = 'warm',
    bool compact = false,
  }) {
    final palette = paletteForId(themeTemplate);
    final scheme = _resolveScheme(
      brightness: Brightness.dark,
      seed: palette.primarySeed,
      secondarySeed: palette.secondarySeed,
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
