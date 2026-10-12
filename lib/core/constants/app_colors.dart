import 'package:flutter/material.dart';

abstract final class AppColors {
  // --- Brand Colors (from Figma) ---
  static const Color primaryNavy = Color(0xFF1B2A4A);
  static const Color primaryNavyDark = Color(0xFF131F37);
  static const Color primaryNavyLight = Color(0xFF263B66);

  static const Color primaryGold = Color(0xFFC9A24B);
  static const Color primaryGoldLight = Color(0xFFE2BC68);
  static const Color primaryGoldDark = Color(0xFFA58133);

  // --- Background & Surfaces ---
  static const Color background = Color(0xFFF8FAFC);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color cardSurface = Color(0xFFFFFFFF);
  static const Color inputSurface = Color(0xFFF1F5F9);
  static const Color darkBackground = Color(0xFF0F172A);
  static const Color darkSurface = Color(0xFF1E293B);

  // --- Typography / Content ---
  static const Color textPrimary = Color(0xFF0F172A);
  static const Color textSecondary = Color(0xFF64748B);
  static const Color textMuted = Color(0xFF94A3B8);
  static const Color textWhite = Color(0xFFFFFFFF);

  // --- Borders & Dividers ---
  static const Color border = Color(0xFFE2E8F0);
  static const Color borderLight = Color(0xFFF1F5F9);
  static const Color divider = Color(0xFFE2E8F0);

  // --- Status & Accent ---
  static const Color success = Color(0xFF22C55E);
  static const Color successLight = Color(0xFFE8F8EE);
  static const Color danger = Color(0xFFEF4444);
  static const Color dangerLight = Color(0xFFFEE2E2);
  static const Color warning = Color(0xFFF59E0B);
  static const Color warningLight = Color(0xFFFEF3C7);
  static const Color info = Color(0xFF3B82F6);
  static const Color infoLight = Color(0xFFDBEAFE);

  // --- Gradients ---
  static const LinearGradient navyGradient = LinearGradient(
    colors: [primaryNavy, primaryNavyDark],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  static const LinearGradient goldGradient = LinearGradient(
    colors: [primaryGoldLight, primaryGold],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}
