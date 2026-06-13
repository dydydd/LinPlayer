import 'package:flutter/material.dart';
import 'tv_design_tokens.dart';

/// TV 端主题
/// TV 端强制深色模式，所有组件基于 TvDesignTokens
class TvTheme {
  TvTheme._();

  static ThemeData get theme => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: TvDesignTokens.background,
        colorScheme: const ColorScheme.dark(
          primary: TvDesignTokens.brand,
          onPrimary: TvDesignTokens.textPrimary,
          secondary: TvDesignTokens.brandLight,
          onSecondary: TvDesignTokens.textPrimary,
          surface: TvDesignTokens.surface,
          onSurface: TvDesignTokens.textPrimary,
          error: TvDesignTokens.error,
          onError: TvDesignTokens.textPrimary,
          background: TvDesignTokens.background,
          onBackground: TvDesignTokens.textPrimary,
        ),
        textTheme: _textTheme,
        appBarTheme: _appBarTheme,
        cardTheme: _cardTheme,
        dividerTheme: _dividerTheme,
        iconTheme: _iconTheme,
        elevatedButtonTheme: _elevatedButtonTheme,
        textButtonTheme: _textButtonTheme,
        outlinedButtonTheme: _outlinedButtonTheme,
        inputDecorationTheme: _inputDecorationTheme,
        scrollbarTheme: _scrollbarTheme,
      );

  static const TextTheme _textTheme = TextTheme(
    displayLarge: TextStyle(
      fontSize: TvDesignTokens.fontSizeXxl,
      fontWeight: TvDesignTokens.fontWeightBold,
      color: TvDesignTokens.textPrimary,
      height: TvDesignTokens.lineHeightTight,
    ),
    displayMedium: TextStyle(
      fontSize: TvDesignTokens.fontSizeXl,
      fontWeight: TvDesignTokens.fontWeightBold,
      color: TvDesignTokens.textPrimary,
      height: TvDesignTokens.lineHeightTight,
    ),
    titleLarge: TextStyle(
      fontSize: TvDesignTokens.fontSizeLg,
      fontWeight: TvDesignTokens.fontWeightMedium,
      color: TvDesignTokens.textPrimary,
      height: TvDesignTokens.lineHeightNormal,
    ),
    titleMedium: TextStyle(
      fontSize: TvDesignTokens.fontSizeMd,
      fontWeight: TvDesignTokens.fontWeightMedium,
      color: TvDesignTokens.textPrimary,
      height: TvDesignTokens.lineHeightNormal,
    ),
    bodyLarge: TextStyle(
      fontSize: TvDesignTokens.fontSizeMd,
      fontWeight: TvDesignTokens.fontWeightRegular,
      color: TvDesignTokens.textPrimary,
      height: TvDesignTokens.lineHeightNormal,
    ),
    bodyMedium: TextStyle(
      fontSize: TvDesignTokens.fontSizeSm,
      fontWeight: TvDesignTokens.fontWeightRegular,
      color: TvDesignTokens.textSecondary,
      height: TvDesignTokens.lineHeightNormal,
    ),
    bodySmall: TextStyle(
      fontSize: TvDesignTokens.fontSizeXs,
      fontWeight: TvDesignTokens.fontWeightRegular,
      color: TvDesignTokens.textDisabled,
      height: TvDesignTokens.lineHeightNormal,
    ),
    labelLarge: TextStyle(
      fontSize: TvDesignTokens.fontSizeSm,
      fontWeight: TvDesignTokens.fontWeightMedium,
      color: TvDesignTokens.textPrimary,
      height: TvDesignTokens.lineHeightNormal,
    ),
  );

  static const AppBarTheme _appBarTheme = AppBarTheme(
    backgroundColor: Colors.transparent,
    elevation: 0,
    centerTitle: false,
    titleTextStyle: TextStyle(
      fontSize: TvDesignTokens.fontSizeXl,
      fontWeight: TvDesignTokens.fontWeightMedium,
      color: TvDesignTokens.textPrimary,
    ),
    iconTheme: IconThemeData(
      color: TvDesignTokens.textPrimary,
      size: 32,
    ),
  );

  static const CardThemeData _cardTheme = CardThemeData(
    color: TvDesignTokens.surface,
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(TvDesignTokens.posterRadius)),
    ),
  );

  static const DividerThemeData _dividerTheme = DividerThemeData(
    color: TvDesignTokens.divider,
    thickness: 1,
    space: TvDesignTokens.spacingMd,
  );

  static const IconThemeData _iconTheme = IconThemeData(
    color: TvDesignTokens.textPrimary,
    size: 32,
  );

  static final ElevatedButtonThemeData _elevatedButtonTheme = ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: TvDesignTokens.brand,
      foregroundColor: TvDesignTokens.textPrimary,
      padding: const EdgeInsets.symmetric(
        horizontal: TvDesignTokens.spacingLg,
        vertical: TvDesignTokens.spacingSm,
      ),
      textStyle: const TextStyle(
        fontSize: TvDesignTokens.fontSizeMd,
        fontWeight: TvDesignTokens.fontWeightMedium,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(TvDesignTokens.posterRadius),
      ),
    ),
  );

  static final TextButtonThemeData _textButtonTheme = TextButtonThemeData(
    style: TextButton.styleFrom(
      foregroundColor: TvDesignTokens.brand,
      padding: const EdgeInsets.symmetric(
        horizontal: TvDesignTokens.spacingMd,
        vertical: TvDesignTokens.spacingSm,
      ),
      textStyle: const TextStyle(
        fontSize: TvDesignTokens.fontSizeMd,
        fontWeight: TvDesignTokens.fontWeightMedium,
      ),
    ),
  );

  static final OutlinedButtonThemeData _outlinedButtonTheme = OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      foregroundColor: TvDesignTokens.textPrimary,
      side: const BorderSide(color: TvDesignTokens.divider, width: 2),
      padding: const EdgeInsets.symmetric(
        horizontal: TvDesignTokens.spacingLg,
        vertical: TvDesignTokens.spacingSm,
      ),
      textStyle: const TextStyle(
        fontSize: TvDesignTokens.fontSizeMd,
        fontWeight: TvDesignTokens.fontWeightMedium,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(TvDesignTokens.posterRadius),
      ),
    ),
  );

  static const InputDecorationTheme _inputDecorationTheme = InputDecorationTheme(
    filled: true,
    fillColor: TvDesignTokens.surface,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(TvDesignTokens.posterRadius)),
      borderSide: BorderSide(color: TvDesignTokens.divider),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(TvDesignTokens.posterRadius)),
      borderSide: BorderSide(color: TvDesignTokens.divider),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(TvDesignTokens.posterRadius)),
      borderSide: BorderSide(color: TvDesignTokens.brand, width: 2),
    ),
    contentPadding: EdgeInsets.symmetric(
      horizontal: TvDesignTokens.spacingMd,
      vertical: TvDesignTokens.spacingSm,
    ),
    hintStyle: TextStyle(
      fontSize: TvDesignTokens.fontSizeMd,
      color: TvDesignTokens.textDisabled,
    ),
    labelStyle: TextStyle(
      fontSize: TvDesignTokens.fontSizeMd,
      color: TvDesignTokens.textSecondary,
    ),
  );

  static const ScrollbarThemeData _scrollbarTheme = ScrollbarThemeData(
    thickness: WidgetStatePropertyAll(8.0),
    radius: Radius.circular(4),
    thumbColor: WidgetStatePropertyAll(TvDesignTokens.textDisabled),
    trackColor: WidgetStatePropertyAll(Colors.transparent),
  );
}
