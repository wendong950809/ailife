import 'package:flutter/material.dart';

class AppColors {
  static const Color primary = Color(0xFF4A6CF7);
  static const Color primaryLight = Color(0xFF6B8AFF);
  static const Color primaryDark = Color(0xFF3A56D4);
  static const Color primaryTint = Color(0x144A6CF7);
  static const Color primaryTintMd = Color(0x294A6CF7);

  static const Color bg = Color(0xFFF5F7FA);
  static const Color bgSecondary = Color(0xFFEEEEF2);
  static const Color bgTertiary = Color(0xFFE5E7ED);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color border = Color(0xFFE1E4EA);
  static const Color borderLight = Color(0xFFECF0F5);

  static const Color textPrimary = Color(0xFF1A1D26);
  static const Color textSecondary = Color(0xFF6B7085);
  static const Color textTertiary = Color(0xFF9DA3B4);
  static const Color textInverse = Color(0xFFFFFFFF);
  static const Color textLink = Color(0xFF4A6CF7);

  static const Color stateSuccess = Color(0xFF4A9A6F);
  static const Color stateWarning = Color(0xFFC4964A);
  static const Color stateError = Color(0xFFC45C5C);
  static const Color stateInfo = Color(0xFF5C8EC4);
}

class AppTheme {
  static ThemeData get lightTheme {
    const colorScheme = ColorScheme(
      primary: AppColors.primary,
      onPrimary: AppColors.textInverse,
      primaryContainer: AppColors.primaryTint,
      onPrimaryContainer: AppColors.primary,
      secondary: AppColors.stateSuccess,
      onSecondary: AppColors.textInverse,
      surface: AppColors.surface,
      onSurface: AppColors.textPrimary,
      surfaceVariant: AppColors.bgSecondary,
      onSurfaceVariant: AppColors.textSecondary,
      error: AppColors.stateError,
      onError: AppColors.textInverse,
      brightness: Brightness.light,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.bg,
      fontFamily: 'SF Pro Text',
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        elevation: 0,
        backgroundColor: AppColors.bg,
        foregroundColor: AppColors.textPrimary,
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
        ),
      ),
      cardTheme: CardTheme(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.borderLight),
        ),
        color: AppColors.surface,
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primary, width: 1),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        hintStyle: const TextStyle(
          fontSize: 14,
          color: AppColors.textTertiary,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.textInverse,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        type: BottomNavigationBarType.fixed,
        backgroundColor: AppColors.surface,
        elevation: 0,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: AppColors.textTertiary,
        selectedLabelStyle: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w500,
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.borderLight,
        thickness: 1,
        space: 1,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.primaryTint,
        labelStyle: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w500,
          color: AppColors.primary,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(9999),
        ),
        side: BorderSide.none,
      ),
    );
  }

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      colorScheme: const ColorScheme(
        primary: AppColors.primary,
        onPrimary: AppColors.textInverse,
        secondary: AppColors.stateSuccess,
        onSecondary: AppColors.textInverse,
        surface: Color(0xFF1C1C1C),
        onSurface: Color(0xFFF0F0F0),
        error: AppColors.stateError,
        onError: AppColors.textInverse,
        brightness: Brightness.dark,
      ),
    );
  }
}
