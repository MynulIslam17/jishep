import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:gps_cielo/core/constants/app_colors.dart';
import 'package:gps_cielo/core/constants/app_typography.dart';
import 'package:gps_cielo/shared/widgets/buttons/app_primary_button.dart';

class ProfileContactSupportBottomSheet extends StatelessWidget {
  final ValueChanged<String> onSendMessage;

  const ProfileContactSupportBottomSheet({
    required this.onSendMessage,
    super.key,
  });

  static void show(
    BuildContext context, {
    required ValueChanged<String> onSendMessage,
  }) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) =>
          ProfileContactSupportBottomSheet(onSendMessage: onSendMessage),
    );
  }

  @override
  Widget build(BuildContext context) {
    final messageController = TextEditingController();

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24.r)),
        ),
        padding: EdgeInsets.fromLTRB(20.w, 12.h, 20.w, 28.h),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildModalHandle(),
            SizedBox(height: 12.h),
            _buildModalHeader(context, title: 'contact support'),
            SizedBox(height: 12.h),
            const Divider(color: AppColors.border, height: 1),
            SizedBox(height: 16.h),

            // Support Agent Illustration / Icon
            Center(
              child: Container(
                width: 72.r,
                height: 72.r,
                decoration: const BoxDecoration(
                  color: Color(0xFFE8EFF7),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.support_agent_rounded,
                  size: 42.r,
                  color: AppColors.primaryNavy,
                ),
              ),
            ),

            SizedBox(height: 14.h),

            Center(
              child: Text(
                'Find Support',
                style: AppTypography.heading(
                  color: AppColors.primaryNavy,
                  fontSize: 18.sp,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            SizedBox(height: 4.h),
            Center(
              child: Text(
                'Help us understanding what\'s happening, send us an E-mail for queries',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: const Color(0xFF64748B),
                  fontSize: 12.5.sp,
                  height: 1.35,
                ),
              ),
            ),

            SizedBox(height: 18.h),

            // Email Box
            Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 12.h),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12.r),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.mail_outline_rounded,
                    size: 20.r,
                    color: const Color(0xFF2E7D32),
                  ),
                  SizedBox(width: 10.w),
                  Text(
                    'support@gpscielochurch.org',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13.5.sp,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),

            SizedBox(height: 14.h),

            Text(
              'Or send messages to the admin',
              style: TextStyle(
                color: const Color(0xFF64748B),
                fontSize: 12.sp,
                fontWeight: FontWeight.w500,
              ),
            ),
            SizedBox(height: 8.h),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12.r),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: TextField(
                controller: messageController,
                maxLines: 2,
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 13.5.sp,
                ),
                decoration: const InputDecoration(
                  hintText: 'Type your message or query here...',
                  hintStyle: TextStyle(color: Color(0xFF94A3B8)),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),

            SizedBox(height: 20.h),

            AppPrimaryButton(
              label: 'Send Message',
              onPressed: () {
                final text = messageController.text.trim();
                if (text.isNotEmpty) {
                  onSendMessage(text);
                }
                Navigator.of(context).pop();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModalHandle() {
    return Center(
      child: Container(
        width: 40.w,
        height: 4.h,
        decoration: BoxDecoration(
          color: const Color(0xFFCBD5E1),
          borderRadius: BorderRadius.circular(2.r),
        ),
      ),
    );
  }

  Widget _buildModalHeader(BuildContext context, {required String title}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: AppTypography.heading(
            color: AppColors.primaryNavy,
            fontSize: 18.sp,
            fontWeight: FontWeight.w800,
          ),
        ),
        GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: Container(
            width: 32.r,
            height: 32.r,
            decoration: const BoxDecoration(
              color: Color(0xFFF1F5F9),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.close_rounded,
              size: 18.r,
              color: const Color(0xFF64748B),
            ),
          ),
        ),
      ],
    );
  }
}
