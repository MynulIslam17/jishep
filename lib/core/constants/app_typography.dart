import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:gps_cielo/core/constants/app_colors.dart';

abstract final class AppTypography {
  static String? get fontFamily => GoogleFonts.inter().fontFamily;

  static TextTheme get lightTextTheme =>
      GoogleFonts.interTextTheme(ThemeData.light().textTheme);

  static TextTheme get darkTextTheme =>
      GoogleFonts.interTextTheme(ThemeData.dark().textTheme);

  static TextStyle style({
    Color? color,
    double? fontSize,
    FontWeight? fontWeight,
    FontStyle? fontStyle,
    double? letterSpacing,
    double? height,
  }) {
    return GoogleFonts.inter(
      color: color ?? AppColors.textPrimary,
      fontSize: fontSize,
      fontWeight: fontWeight,
      fontStyle: fontStyle,
      letterSpacing: letterSpacing,
      height: height,
    );
  }

  static TextStyle heading({
    Color? color,
    double? fontSize = 24,
    FontWeight fontWeight = FontWeight.w700,
    FontStyle? fontStyle,
    double? height,
    double? letterSpacing,
  }) {
    return style(
      color: color,
      fontSize: fontSize,
      fontWeight: fontWeight,
      fontStyle: fontStyle,
      height: height,
      letterSpacing: letterSpacing,
    );
  }

  static TextStyle subheading({
    Color? color,
    double? fontSize = 18,
    FontWeight fontWeight = FontWeight.w600,
    FontStyle? fontStyle,
    double? height,
    double? letterSpacing,
  }) {
    return style(
      color: color,
      fontSize: fontSize,
      fontWeight: fontWeight,
      fontStyle: fontStyle,
      height: height,
      letterSpacing: letterSpacing,
    );
  }

  static TextStyle body({
    Color? color,
    double? fontSize = 14,
    FontWeight fontWeight = FontWeight.w400,
    FontStyle? fontStyle,
    double? height,
    double? letterSpacing,
  }) {
    return style(
      color: color,
      fontSize: fontSize,
      fontWeight: fontWeight,
      fontStyle: fontStyle,
      height: height,
      letterSpacing: letterSpacing,
    );
  }

  static TextStyle label({
    Color? color,
    double? fontSize = 12,
    FontWeight fontWeight = FontWeight.w600,
    FontStyle? fontStyle,
    double? height,
    double? letterSpacing,
  }) {
    return style(
      color: color,
      fontSize: fontSize,
      fontWeight: fontWeight,
      fontStyle: fontStyle,
      height: height,
      letterSpacing: letterSpacing,
    );
  }
}
