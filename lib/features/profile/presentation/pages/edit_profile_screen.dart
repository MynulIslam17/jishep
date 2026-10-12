import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:gps_cielo/core/constants/app_colors.dart';
import 'package:gps_cielo/core/constants/app_typography.dart';
import 'package:gps_cielo/core/utils/app_system_insets.dart';
import 'package:gps_cielo/features/profile/presentation/controllers/profile_controller.dart';
import 'package:gps_cielo/shared/widgets/avatar/user_avatar_image.dart';
import 'package:gps_cielo/shared/widgets/buttons/app_primary_button.dart';

class EditProfileScreen extends GetView<ProfileController> {
  const EditProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final topInset = AppSystemInsets.top(context);
    final user = controller.user.value;

    final nameController = TextEditingController(text: user?.fullName ?? '');
    final emailController = TextEditingController(text: user?.email ?? '');
    final churchController = TextEditingController(
      text: user?.churchAffiliation ?? '',
    );

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: Column(
        children: [
          // Navy Header
          Container(
            width: double.infinity,
            padding: EdgeInsets.fromLTRB(16.w, topInset + 8.h, 16.w, 18.h),
            color: AppColors.primaryNavy,
            child: Row(
              children: [
                GestureDetector(
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
                SizedBox(width: 14.w),
                Text(
                  'Edit Profile',
                  style: AppTypography.heading(
                    color: AppColors.textWhite,
                    fontSize: 20.sp,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),

          Expanded(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: EdgeInsets.fromLTRB(20.w, 28.h, 20.w, 28.h),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Center Avatar with Edit Badge
                  Center(
                    child: GestureDetector(
                      onTap: controller.pickAndUploadAvatar,
                      child: Stack(
                        children: [
                          Obx(() {
                            final placeholder = Icon(
                              Icons.person_rounded,
                              size: 48.r,
                              color: const Color(0xFF94A3B8),
                            );
                            return Container(
                              width: 88.r,
                              height: 88.r,
                              clipBehavior: Clip.antiAlias,
                              decoration: const BoxDecoration(
                                color: Color(0xFFE2E8F0),
                                shape: BoxShape.circle,
                              ),
                              child: controller.isUploadingAvatar.value
                                  ? const Center(
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : UserAvatarImage(
                                      user: controller.user.value,
                                      placeholder: placeholder,
                                    ),
                            );
                          }),
                          Positioned(
                            right: 0,
                            bottom: 0,
                            child: Container(
                              width: 28.r,
                              height: 28.r,
                              decoration: BoxDecoration(
                                color: AppColors.primaryNavy,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white,
                                  width: 2,
                                ),
                              ),
                              child: Icon(
                                Icons.edit_rounded,
                                size: 14.r,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  SizedBox(height: 32.h),

                  // Full Name Field
                  _buildEditField(
                    label: 'FULL NAME',
                    controller: nameController,
                    hint: 'Enter your full name',
                  ),

                  SizedBox(height: 20.h),

                  // Email Field
                  _buildEditField(
                    label: 'EMAIL',
                    controller: emailController,
                    hint: 'Enter your email address',
                    keyboardType: TextInputType.emailAddress,
                  ),

                  SizedBox(height: 20.h),

                  // Church Affiliation Field
                  _buildEditField(
                    label: 'CHURCH AFFILIATION',
                    controller: churchController,
                    hint: 'Enter your church name',
                  ),

                  SizedBox(height: 48.h),

                  // Save Changes CTA
                  Obx(
                    () => AppPrimaryButton(
                      label: 'Save Changes',
                      isLoading: controller.isLoading.value,
                      onPressed: () async {
                        final success = await controller.updateProfileInfo(
                          fullName: nameController.text,
                          email: emailController.text,
                          churchAffiliation: churchController.text,
                        );
                        if (success) {
                          Get.back();
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEditField({
    required String label,
    required TextEditingController controller,
    required String hint,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: const Color(0xFF64748B),
            fontSize: 11.sp,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
          ),
        ),
        SizedBox(height: 8.h),
        Container(
          height: 48.h,
          padding: EdgeInsets.symmetric(horizontal: 14.w),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(12.r),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  keyboardType: keyboardType,
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w600,
                  ),
                  decoration: InputDecoration(
                    hintText: hint,
                    hintStyle: TextStyle(
                      color: const Color(0xFF94A3B8),
                      fontSize: 13.5.sp,
                    ),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
              Icon(
                Icons.edit_outlined,
                color: const Color(0xFF94A3B8),
                size: 18.r,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
