import 'package:flutter/material.dart';
import 'app_colors.dart';

/// Material 3 主题配置
class AppTheme {
  AppTheme._();
  
  static const double borderRadiusSmall = 4;
  static const double borderRadiusMedium = 8;
  static const double borderRadiusLarge = 12;
  static const double borderRadiusXLarge = 16;
  static const double borderRadiusXXLarge = 24;
  
  static const double spacingUnit = 4;
  static const double spacing1 = 4;
  static const double spacing2 = 8;
  static const double spacing3 = 12;
  static const double spacing4 = 16;
  static const double spacing5 = 24;
  static const double spacing6 = 32;
  static const double spacing7 = 48;
  static const double spacing8 = 64;
  
  static const double textSizeXS = 12;
  static const double textSizeSM = 14;
  static const double textSizeBase = 16;
  static const double textSizeLG = 18;
  static const double textSizeXL = 20;
  static const double textSize2XL = 24;
  static const double textSize3XL = 28;
  static const double textSize4XL = 32;
  static const double textSize5XL = 40;
  static const double textSize6XL = 48;

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: const ColorScheme.light(
        primary: AppColors.brand,
        onPrimary: Colors.white,
        secondary: AppColors.brandLight,
        onSecondary: Colors.white,
        surface: AppColors.lightSurface,
        onSurface: AppColors.lightText,
        error: AppColors.error,
        onError: Colors.white,
      ),
      scaffoldBackgroundColor: AppColors.lightBackground,
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(borderRadiusLarge),
        ),
        color: AppColors.lightSurface,
      ),
      appBarTheme: const AppBarTheme(
        elevation: 0,
        centerTitle: true,
        backgroundColor: AppColors.lightBackground,
        foregroundColor: AppColors.lightText,
        titleTextStyle: TextStyle(
          fontSize: textSizeLG,
          fontWeight: FontWeight.w600,
          color: AppColors.lightText,
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppColors.lightSurface,
        selectedItemColor: AppColors.brand,
        unselectedItemColor: AppColors.lightTextSecondary,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.lightDivider,
        thickness: 1,
      ),
      textTheme: const TextTheme(
        displayLarge: TextStyle(fontSize: textSize6XL, fontWeight: FontWeight.bold),
        displayMedium: TextStyle(fontSize: textSize5XL, fontWeight: FontWeight.bold),
        displaySmall: TextStyle(fontSize: textSize4XL, fontWeight: FontWeight.bold),
        headlineLarge: TextStyle(fontSize: textSize3XL, fontWeight: FontWeight.w600),
        headlineMedium: TextStyle(fontSize: textSize2XL, fontWeight: FontWeight.w600),
        headlineSmall: TextStyle(fontSize: textSizeXL, fontWeight: FontWeight.w600),
        titleLarge: TextStyle(fontSize: textSizeLG, fontWeight: FontWeight.w600),
        titleMedium: TextStyle(fontSize: textSizeBase, fontWeight: FontWeight.w600),
        titleSmall: TextStyle(fontSize: textSizeSM, fontWeight: FontWeight.w500),
        bodyLarge: TextStyle(fontSize: textSizeBase),
        bodyMedium: TextStyle(fontSize: textSizeSM),
        bodySmall: TextStyle(fontSize: textSizeXS),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thickness: WidgetStateProperty.all(8),
        radius: const Radius.circular(4),
        thumbColor: WidgetStateProperty.all(const Color(0xFF5B8DEF).withValues(alpha: 0.3)),
        trackColor: WidgetStateProperty.all(Colors.transparent),
      ),
    );
  }

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.brandLight,
        onPrimary: Colors.black,
        secondary: AppColors.brand,
        onSecondary: Colors.white,
        surface: AppColors.darkSurface,
        onSurface: AppColors.darkText,
        error: AppColors.error,
        onError: Colors.white,
      ),
      scaffoldBackgroundColor: AppColors.darkBackground,
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(borderRadiusLarge),
        ),
        color: AppColors.darkSurface,
      ),
      appBarTheme: const AppBarTheme(
        elevation: 0,
        centerTitle: true,
        backgroundColor: AppColors.darkBackground,
        foregroundColor: AppColors.darkText,
        titleTextStyle: TextStyle(
          fontSize: textSizeLG,
          fontWeight: FontWeight.w600,
          color: AppColors.darkText,
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppColors.darkSurface,
        selectedItemColor: AppColors.brandLight,
        unselectedItemColor: AppColors.darkTextSecondary,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.darkDivider,
        thickness: 1,
      ),
      textTheme: const TextTheme(
        displayLarge: TextStyle(fontSize: textSize6XL, fontWeight: FontWeight.bold),
        displayMedium: TextStyle(fontSize: textSize5XL, fontWeight: FontWeight.bold),
        displaySmall: TextStyle(fontSize: textSize4XL, fontWeight: FontWeight.bold),
        headlineLarge: TextStyle(fontSize: textSize3XL, fontWeight: FontWeight.w600),
        headlineMedium: TextStyle(fontSize: textSize2XL, fontWeight: FontWeight.w600),
        headlineSmall: TextStyle(fontSize: textSizeXL, fontWeight: FontWeight.w600),
        titleLarge: TextStyle(fontSize: textSizeLG, fontWeight: FontWeight.w600),
        titleMedium: TextStyle(fontSize: textSizeBase, fontWeight: FontWeight.w600),
        titleSmall: TextStyle(fontSize: textSizeSM, fontWeight: FontWeight.w500),
        bodyLarge: TextStyle(fontSize: textSizeBase),
        bodyMedium: TextStyle(fontSize: textSizeSM),
        bodySmall: TextStyle(fontSize: textSizeXS),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thickness: WidgetStateProperty.all(8),
        radius: const Radius.circular(4),
        thumbColor: WidgetStateProperty.all(const Color(0xFF5B8DEF).withValues(alpha: 0.4)),
        trackColor: WidgetStateProperty.all(Colors.transparent),
      ),
    );
  }
}
