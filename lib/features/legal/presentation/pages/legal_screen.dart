import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:gps_cielo/core/constants/app_colors.dart';
import 'package:gps_cielo/core/constants/app_typography.dart';
import 'package:gps_cielo/features/legal/legal_content.dart';

/// Shows the Terms of Use or Privacy Policy. Works offline and before
/// sign-in.
class LegalScreen extends StatelessWidget {
  final LegalDocument document;

  const LegalScreen({required this.document, super.key});

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;
    final body = TextStyle(
      color: AppColors.textPrimary,
      fontSize: 14.sp,
      height: 1.5,
    );

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: EdgeInsets.fromLTRB(16.w, topInset + 8.h, 16.w, 18.h),
            color: AppColors.primaryNavy,
            child: Row(
              children: [
                Semantics(
                  button: true,
                  label: 'Back',
                  child: GestureDetector(
                    onTap: () => Get.back(),
                    child: Container(
                      width: 36.r,
                      height: 36.r,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.chevron_left_rounded,
                        color: AppColors.primaryNavy,
                        size: 22.r,
                      ),
                    ),
                  ),
                ),
                SizedBox(width: 14.w),
                Expanded(
                  child: Text(
                    document.title,
                    style: AppTypography.heading(
                      color: AppColors.textWhite,
                      fontSize: 20.sp,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: SelectionArea(
              child: ListView(
                padding: EdgeInsets.fromLTRB(20.w, 20.h, 20.w, 40.h),
                children: [
                  Text(
                    document.lastUpdated,
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12.5.sp,
                    ),
                  ),
                  SizedBox(height: 12.h),
                  Text(document.intro, style: body),
                  for (final section in document.sections) ...[
                    SizedBox(height: 22.h),
                    Text(
                      section.heading,
                      style: AppTypography.heading(
                        color: AppColors.primaryNavy,
                        fontSize: 16.sp,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    for (final block in section.blocks) ...[
                      SizedBox(height: 8.h),
                      if (block.bullets case final bullets?)
                        for (final item in bullets)
                          Padding(
                            padding: EdgeInsets.only(bottom: 6.h),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('•  ', style: body),
                                Expanded(child: Text(item, style: body)),
                              ],
                            ),
                          )
                      else
                        Text(block.text!, style: body),
                    ],
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
