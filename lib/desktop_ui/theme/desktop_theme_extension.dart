import 'package:flutter/material.dart';

@immutable
class DesktopThemeExtension extends ThemeExtension<DesktopThemeExtension> {
  const DesktopThemeExtension({
    required this.background,
    required this.backgroundGradientStart,
    required this.backgroundGradientEnd,
    required this.sidebarColor,
    required this.surface,
    required this.surfaceElevated,
    required this.border,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.link,
    required this.accent,
    required this.headerBackground,
    required this.headerScrolledBackground,
    required this.topTabBackground,
    required this.topTabActiveBackground,
    required this.topTabInactiveForeground,
    required this.categoryOverlay,
    required this.posterOverlay,
    required this.posterControlBackground,
    required this.posterBadgeBackground,
    required this.shadowColor,
    required this.hover,
    required this.focus,
  });

  final Color background;
  final Color backgroundGradientStart;
  final Color backgroundGradientEnd;
  final Color sidebarColor;
  final Color surface;
  final Color surfaceElevated;
  final Color border;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color link;
  final Color accent;
  final Color headerBackground;
  final Color headerScrolledBackground;
  final Color topTabBackground;
  final Color topTabActiveBackground;
  final Color topTabInactiveForeground;
  final Color categoryOverlay;
  final Color posterOverlay;
  final Color posterControlBackground;
  final Color posterBadgeBackground;
  final Color shadowColor;
  final Color hover;
  final Color focus;

  factory DesktopThemeExtension.fallback(Brightness brightness) {
    if (brightness == Brightness.dark) {
      return const DesktopThemeExtension(
        background: Color(0xFF060A11),
        backgroundGradientStart: Color(0xFF0B131D),
        backgroundGradientEnd: Color(0xFF05070B),
        sidebarColor: Color(0xF0141B25),
        surface: Color(0xFF111923),
        surfaceElevated: Color(0xFF17212D),
        border: Color(0x334F6277),
        textPrimary: Color(0xFFF5F7FB),
        textSecondary: Color(0xFFD5DDE8),
        textMuted: Color(0xFF97A7BB),
        link: Color(0xFFB4D0F5),
        accent: Color(0xFF78B8AD),
        headerBackground: Color(0x80101720),
        headerScrolledBackground: Color(0xEE0B1119),
        topTabBackground: Color(0x4D18202B),
        topTabActiveBackground: Color(0xFF1D2835),
        topTabInactiveForeground: Color(0xBBD5DDE8),
        categoryOverlay: Color(0xB30A1119),
        posterOverlay: Color(0xC9151C24),
        posterControlBackground: Color(0xCC071018),
        posterBadgeBackground: Color(0xFF78B8AD),
        shadowColor: Color(0xA0000000),
        hover: Color(0x2E78B8AD),
        focus: Color(0xFF9BD2C9),
      );
    }
    return const DesktopThemeExtension(
      background: Color(0xFFF1F4F8),
      backgroundGradientStart: Color(0xFFF7F9FC),
      backgroundGradientEnd: Color(0xFFE7EDF4),
      sidebarColor: Color(0xF5FCFDFE),
      surface: Color(0xFFFFFFFF),
      surfaceElevated: Color(0xFFF4F7FB),
      border: Color(0x26485A6E),
      textPrimary: Color(0xFF15202D),
      textSecondary: Color(0xFF435567),
      textMuted: Color(0xFF718398),
      link: Color(0xFF2E688F),
      accent: Color(0xFF447C86),
      headerBackground: Color(0xD9FFFFFF),
      headerScrolledBackground: Color(0xF2FFFFFF),
      topTabBackground: Color(0xD6EAF0F3),
      topTabActiveBackground: Color(0xFFFFFFFF),
      topTabInactiveForeground: Color(0xFF607287),
      categoryOverlay: Color(0x4DFFFFFF),
      posterOverlay: Color(0x59061018),
      posterControlBackground: Color(0xE8FFFFFF),
      posterBadgeBackground: Color(0xFF447C86),
      shadowColor: Color(0x160C1520),
      hover: Color(0x18447C86),
      focus: Color(0xFF2C6E88),
    );
  }

  static DesktopThemeExtension of(BuildContext context) {
    final fallback = DesktopThemeExtension.fallback(
      Theme.of(context).brightness,
    );
    return Theme.of(context).extension<DesktopThemeExtension>() ?? fallback;
  }

  @override
  DesktopThemeExtension copyWith({
    Color? background,
    Color? backgroundGradientStart,
    Color? backgroundGradientEnd,
    Color? sidebarColor,
    Color? surface,
    Color? surfaceElevated,
    Color? border,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? link,
    Color? accent,
    Color? headerBackground,
    Color? headerScrolledBackground,
    Color? topTabBackground,
    Color? topTabActiveBackground,
    Color? topTabInactiveForeground,
    Color? categoryOverlay,
    Color? posterOverlay,
    Color? posterControlBackground,
    Color? posterBadgeBackground,
    Color? shadowColor,
    Color? hover,
    Color? focus,
  }) {
    return DesktopThemeExtension(
      background: background ?? this.background,
      backgroundGradientStart:
          backgroundGradientStart ?? this.backgroundGradientStart,
      backgroundGradientEnd:
          backgroundGradientEnd ?? this.backgroundGradientEnd,
      sidebarColor: sidebarColor ?? this.sidebarColor,
      surface: surface ?? this.surface,
      surfaceElevated: surfaceElevated ?? this.surfaceElevated,
      border: border ?? this.border,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textMuted: textMuted ?? this.textMuted,
      link: link ?? this.link,
      accent: accent ?? this.accent,
      headerBackground: headerBackground ?? this.headerBackground,
      headerScrolledBackground:
          headerScrolledBackground ?? this.headerScrolledBackground,
      topTabBackground: topTabBackground ?? this.topTabBackground,
      topTabActiveBackground:
          topTabActiveBackground ?? this.topTabActiveBackground,
      topTabInactiveForeground:
          topTabInactiveForeground ?? this.topTabInactiveForeground,
      categoryOverlay: categoryOverlay ?? this.categoryOverlay,
      posterOverlay: posterOverlay ?? this.posterOverlay,
      posterControlBackground:
          posterControlBackground ?? this.posterControlBackground,
      posterBadgeBackground:
          posterBadgeBackground ?? this.posterBadgeBackground,
      shadowColor: shadowColor ?? this.shadowColor,
      hover: hover ?? this.hover,
      focus: focus ?? this.focus,
    );
  }

  @override
  ThemeExtension<DesktopThemeExtension> lerp(
    covariant ThemeExtension<DesktopThemeExtension>? other,
    double t,
  ) {
    if (other is! DesktopThemeExtension) {
      return this;
    }
    return DesktopThemeExtension(
      background: Color.lerp(background, other.background, t) ?? background,
      backgroundGradientStart: Color.lerp(
              backgroundGradientStart, other.backgroundGradientStart, t) ??
          backgroundGradientStart,
      backgroundGradientEnd:
          Color.lerp(backgroundGradientEnd, other.backgroundGradientEnd, t) ??
              backgroundGradientEnd,
      sidebarColor:
          Color.lerp(sidebarColor, other.sidebarColor, t) ?? sidebarColor,
      surface: Color.lerp(surface, other.surface, t) ?? surface,
      surfaceElevated: Color.lerp(surfaceElevated, other.surfaceElevated, t) ??
          surfaceElevated,
      border: Color.lerp(border, other.border, t) ?? border,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t) ?? textPrimary,
      textSecondary:
          Color.lerp(textSecondary, other.textSecondary, t) ?? textSecondary,
      textMuted: Color.lerp(textMuted, other.textMuted, t) ?? textMuted,
      link: Color.lerp(link, other.link, t) ?? link,
      accent: Color.lerp(accent, other.accent, t) ?? accent,
      headerBackground:
          Color.lerp(headerBackground, other.headerBackground, t) ??
              headerBackground,
      headerScrolledBackground: Color.lerp(
              headerScrolledBackground, other.headerScrolledBackground, t) ??
          headerScrolledBackground,
      topTabBackground:
          Color.lerp(topTabBackground, other.topTabBackground, t) ??
              topTabBackground,
      topTabActiveBackground:
          Color.lerp(topTabActiveBackground, other.topTabActiveBackground, t) ??
              topTabActiveBackground,
      topTabInactiveForeground: Color.lerp(
              topTabInactiveForeground, other.topTabInactiveForeground, t) ??
          topTabInactiveForeground,
      categoryOverlay: Color.lerp(categoryOverlay, other.categoryOverlay, t) ??
          categoryOverlay,
      posterOverlay:
          Color.lerp(posterOverlay, other.posterOverlay, t) ?? posterOverlay,
      posterControlBackground: Color.lerp(
              posterControlBackground, other.posterControlBackground, t) ??
          posterControlBackground,
      posterBadgeBackground:
          Color.lerp(posterBadgeBackground, other.posterBadgeBackground, t) ??
              posterBadgeBackground,
      shadowColor: Color.lerp(shadowColor, other.shadowColor, t) ?? shadowColor,
      hover: Color.lerp(hover, other.hover, t) ?? hover,
      focus: Color.lerp(focus, other.focus, t) ?? focus,
    );
  }
}
