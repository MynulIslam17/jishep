import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:gps_cielo/core/constants/app_colors.dart';
import 'package:gps_cielo/core/constants/app_typography.dart';
import 'package:gps_cielo/core/models/household_model.dart';

/// Asks for the name of the people living in a household (Figma 4.2 "Add a
/// name"). Private to the user. Returns `(name: ...)` with the new name
/// (null = removed), or null when cancelled.
class ResidentNameDialog extends StatefulWidget {
  const ResidentNameDialog({this.initialName, this.addressLine, super.key});

  final String? initialName;

  /// "151 MARKET ST · Paterson, NJ" under the title.
  final String? addressLine;

  static Future<({String? name})?> show(
    BuildContext context, {
    String? initialName,
    String? addressLine,
  }) {
    return showModalBottomSheet<({String? name})>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ResidentNameDialog(
        initialName: initialName,
        addressLine: addressLine,
      ),
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
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
  }

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
    final inset = MediaQuery.of(context).viewInsets.bottom;
    final safe = MediaQuery.of(context).padding.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: inset),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24.r)),
        ),
        padding: EdgeInsets.fromLTRB(20.w, 16.h, 20.w, 16.h + safe),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    hasName ? 'Edit name' : 'Add a name',
                    style: AppTypography.heading(
                      color: AppColors.textPrimary,
                      fontSize: 17.sp,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: Container(
                    width: 30.r,
                    height: 30.r,
                    decoration: const BoxDecoration(
                      color: Color(0xFFF1F5F9),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.close_rounded,
                      size: 17.r,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
            if (widget.addressLine != null) ...[
              SizedBox(height: 4.h),
              Text(
                widget.addressLine!,
                style: AppTypography.body(
                  color: AppColors.textSecondary,
                  fontSize: 12.sp,
                ),
              ),
            ],
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
                hintText: 'e.g. The Smith Family',
                counterText: '',
                filled: true,
                fillColor: AppColors.surface,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 14.w,
                  vertical: 13.h,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12.r),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12.r),
                  borderSide: const BorderSide(
                    color: AppColors.primaryNavy,
                    width: 1.6,
                  ),
                ),
              ),
            ),
            SizedBox(height: 8.h),
            Row(
              children: [
                Icon(
                  Icons.visibility_outlined,
                  size: 14.r,
                  color: AppColors.textMuted,
                ),
                SizedBox(width: 5.w),
                Expanded(
                  child: Text(
                    'Only you can see this name',
                    style: AppTypography.body(
                      color: AppColors.textSecondary,
                      fontSize: 11.5.sp,
                    ),
                  ),
                ),
                Text(
                  '${_controller.text.length}/${HouseholdModel.maxNameLength}',
                  key: const ValueKey('resident-name-count'),
                  style: AppTypography.body(
                    color: AppColors.textMuted,
                    fontSize: 11.5.sp,
                  ),
                ),
              ],
            ),
            SizedBox(height: 16.h),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textPrimary,
                      side: const BorderSide(color: AppColors.border),
                      minimumSize: Size(0, 46.h),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12.r),
                      ),
                    ),
                    child: const Text('Cancel'),
                  ),
                ),
                SizedBox(width: 10.w),
                Expanded(
                  child: ElevatedButton(
                    key: const ValueKey('resident-name-save'),
                    onPressed: _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryNavy,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      minimumSize: Size(0, 46.h),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12.r),
                      ),
                    ),
                    child: const Text(
                      'Save name',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
            if (hasName)
              Center(
                child: TextButton(
                  key: const ValueKey('resident-name-remove'),
                  onPressed: () => Navigator.of(context).pop((name: null)),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.danger,
                  ),
                  child: const Text('Remove name'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
