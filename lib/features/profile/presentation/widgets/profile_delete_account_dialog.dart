import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:gps_cielo/core/constants/app_colors.dart';
import 'package:gps_cielo/core/constants/app_typography.dart';

/// Confirms permanent account deletion. Password accounts must re-enter their
/// password; Google accounts are asked to confirm with Google.
class ProfileDeleteAccountDialog extends StatefulWidget {
  final bool requiresPassword;

  /// Performs the deletion; returns true when the account was deleted.
  final Future<bool> Function(String? password) onDelete;

  const ProfileDeleteAccountDialog({
    required this.requiresPassword,
    required this.onDelete,
    super.key,
  });

  static Future<void> show(
    BuildContext context, {
    required bool requiresPassword,
    required Future<bool> Function(String? password) onDelete,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => ProfileDeleteAccountDialog(
        requiresPassword: requiresPassword,
        onDelete: onDelete,
      ),
    );
  }

  @override
  State<ProfileDeleteAccountDialog> createState() =>
      _ProfileDeleteAccountDialogState();
}

class _ProfileDeleteAccountDialogState
    extends State<ProfileDeleteAccountDialog> {
  final _passwordController = TextEditingController();
  bool _isDeleting = false;
  bool _obscure = true;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    setState(() => _isDeleting = true);
    final deleted = await widget.onDelete(
      widget.requiresPassword ? _passwordController.text : null,
    );
    if (!mounted) return;
    if (deleted) {
      Navigator.of(context).pop();
    } else {
      setState(() => _isDeleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
      title: Text(
        'Delete Account',
        style: AppTypography.heading(
          color: AppColors.danger,
          fontSize: 18.sp,
          fontWeight: FontWeight.w700,
        ),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'This permanently deletes your account, profile, prayer and '
            'follow-up history, and notifications. This cannot be undone.',
            style: TextStyle(color: AppColors.textPrimary, fontSize: 14.sp),
          ),
          SizedBox(height: 14.h),
          if (widget.requiresPassword)
            TextField(
              controller: _passwordController,
              obscureText: _obscure,
              enabled: !_isDeleting,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Confirm your password',
                border: const OutlineInputBorder(),
                isDense: true,
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscure
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    size: 18.r,
                  ),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
            )
          else
            Text(
              'You may be asked to confirm with your Google account.',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12.5.sp,
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _isDeleting ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.danger,
            elevation: 0,
          ),
          onPressed: _isDeleting ? null : _delete,
          child: _isDeleting
              ? SizedBox(
                  width: 18.r,
                  height: 18.r,
                  child: const CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text(
                  'Delete',
                  style: TextStyle(color: Colors.white),
                ),
        ),
      ],
    );
  }
}
