import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:gps_cielo/core/constants/app_colors.dart';
import 'package:gps_cielo/core/constants/app_typography.dart';

class SnackbarService {
  SnackbarService._();

  static const Duration _duration = Duration(seconds: 3);
  static bool _isShowing = false;
  static Timer? _resetTimer;

  static void showSuccess(String title, String message) {
    _show(
      title: title,
      message: message,
      accent: AppColors.success,
      icon: Icons.check_circle_rounded,
    );
  }

  static void showError(String title, String message) {
    _show(
      title: title,
      message: message,
      accent: AppColors.danger,
      icon: Icons.error_rounded,
    );
  }

  static void showInfo(String title, String message) {
    _show(
      title: title,
      message: message,
      accent: AppColors.info,
      icon: Icons.info_rounded,
    );
  }

  static void _show({
    required String title,
    required String message,
    required Color accent,
    required IconData icon,
  }) {
    if (Get.testMode) return;
    if (_isShowing || Get.isSnackbarOpen) return;

    _isShowing = true;
    _resetTimer?.cancel();

    Get.showSnackbar(
      GetSnackBar(
        snackPosition: SnackPosition.TOP,
        backgroundColor: Colors.transparent,
        margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        padding: EdgeInsets.zero,
        borderRadius: 12,
        duration: _duration,
        animationDuration: const Duration(milliseconds: 220),
        isDismissible: true,
        dismissDirection: DismissDirection.horizontal,
        messageText: Material(
          color: AppColors.surface,
          elevation: 4,
          shadowColor: Colors.black12,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: AppColors.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: IntrinsicHeight(
            child: Row(
              children: [
                Container(width: 4, color: accent),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
                    child: Row(
                      children: [
                        Icon(icon, color: accent, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTypography.heading(
                                  color: AppColors.textPrimary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (message.trim().isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  message,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTypography.body(
                                    color: AppColors.textSecondary,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    _resetTimer = Timer(_duration, () => _isShowing = false);
  }
}
