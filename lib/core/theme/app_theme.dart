import 'package:flutter/material.dart';
import 'package:gps_cielo/core/constants/app_colors.dart';
import 'package:gps_cielo/core/constants/app_typography.dart';

class AppThemes {
  AppThemes._();

  static final lightTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    fontFamily: AppTypography.fontFamily,
    textTheme: AppTypography.lightTextTheme,
    primaryTextTheme: AppTypography.lightTextTheme,
    scaffoldBackgroundColor: AppColors.background,
    colorScheme: const ColorScheme.light(
      surface: AppColors.surface,
      onSurface: AppColors.textPrimary,
      onSurfaceVariant: AppColors.textSecondary,
      primary: AppColors.primaryNavy,
      onPrimary: AppColors.textWhite,
      secondary: AppColors.primaryGold,
      onSecondary: AppColors.textWhite,
      error: AppColors.danger,
      outline: AppColors.border,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.primaryNavy,
      foregroundColor: AppColors.textWhite,
      centerTitle: false,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    cardTheme: CardThemeData(
      color: AppColors.cardSurface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.border),
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: AppColors.divider,
      thickness: 1,
      space: 1,
    ),
  );

  static final darkTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    fontFamily: AppTypography.fontFamily,
    textTheme: AppTypography.darkTextTheme,
    primaryTextTheme: AppTypography.darkTextTheme,
    scaffoldBackgroundColor: AppColors.darkBackground,
    colorScheme: const ColorScheme.dark(
      surface: AppColors.darkSurface,
      onSurface: AppColors.textWhite,
      onSurfaceVariant: AppColors.textMuted,
      primary: AppColors.primaryNavyLight,
      onPrimary: AppColors.textWhite,
      secondary: AppColors.primaryGold,
      onSecondary: AppColors.textWhite,
      error: AppColors.danger,
      outline: AppColors.border,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.darkBackground,
      foregroundColor: AppColors.textWhite,
      centerTitle: false,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
  );
}
