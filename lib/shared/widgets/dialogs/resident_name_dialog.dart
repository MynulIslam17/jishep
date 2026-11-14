import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:gps_cielo/core/constants/app_colors.dart';
import 'package:gps_cielo/core/constants/app_typography.dart';
import 'package:gps_cielo/core/models/household_model.dart';

/// Asks for the name of the people living in a household. Private to the
/// user. Returns `(name: ...)` with the new name (null = removed), or null
/// when cancelled.
class ResidentNameDialog extends StatefulWidget {
  const ResidentNameDialog({this.initialName, super.key});

  final String? initialName;

  static Future<({String? name})?> show(
    BuildContext context, {
    String? initialName,
  }) {
    return showDialog<({String? name})>(
      context: context,
      builder: (_) => ResidentNameDialog(initialName: initialName),
    );
  }

  @override
  State<ResidentNameDialog> createState() => _ResidentNameDialogState();
}

class _ResidentNameDialogState extends State<ResidentNameDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialName ?? '',
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() => Navigator.of(
    context,
  ).pop((name: HouseholdModel.cleanName(_controller.text)));

  @override
  Widget build(BuildContext context) {
    final hasName = widget.initialName != null;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
      backgroundColor: AppColors.surface,
      child: Padding(
        padding: EdgeInsets.fromLTRB(20.w, 20.h, 20.w, 12.h),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              hasName ? 'Edit name' : 'Add name',
              style: AppTypography.heading(
                color: AppColors.textPrimary,
                fontSize: 18.sp,
                fontWeight: FontWeight.w700,
              ),
            ),
            SizedBox(height: 6.h),
            Text(
              'Who lives here? Only you can see this name.',
              style: AppTypography.body(
                color: AppColors.textSecondary,
                fontSize: 13.sp,
              ),
            ),
            SizedBox(height: 14.h),
            TextField(
              key: const ValueKey('resident-name-field'),
              controller: _controller,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.done,
              maxLength: HouseholdModel.maxNameLength,
              maxLengthEnforcement: MaxLengthEnforcement.enforced,
              onSubmitted: (_) => _save(),
              decoration: InputDecoration(
                hintText: 'e.g. Martha and Odalis Cordova',
                filled: true,
                fillColor: AppColors.inputSurface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12.r),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            Row(
              children: [
                if (hasName)
                  TextButton(
                    key: const ValueKey('resident-name-remove'),
                    onPressed: () => Navigator.of(context).pop((name: null)),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.danger,
                    ),
                    child: const Text('Remove name'),
                  ),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.textSecondary,
                  ),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  key: const ValueKey('resident-name-save'),
                  onPressed: _save,
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.primaryNavy,
                  ),
                  child: const Text(
                    'Save',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
