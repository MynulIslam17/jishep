import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:gps_cielo/core/constants/app_colors.dart';
import 'package:gps_cielo/core/constants/app_typography.dart';
import 'package:gps_cielo/core/utils/app_system_insets.dart';
import 'package:gps_cielo/features/profile/presentation/controllers/profile_controller.dart';
import 'package:gps_cielo/features/profile/presentation/widgets/profile_about_bottom_sheet.dart';
import 'package:gps_cielo/shared/widgets/avatar/user_avatar_image.dart';
import 'package:gps_cielo/features/profile/presentation/widgets/profile_address_bottom_sheet.dart';
import 'package:gps_cielo/features/profile/presentation/widgets/profile_contact_support_bottom_sheet.dart';
import 'package:gps_cielo/features/profile/presentation/widgets/profile_delete_account_dialog.dart';
import 'package:gps_cielo/features/profile/presentation/widgets/profile_impact_card.dart';
import 'package:gps_cielo/features/profile/presentation/widgets/profile_prayer_preferences_bottom_sheet.dart';
import 'package:gps_cielo/routes/app_routes.dart';

class ProfileScreen extends GetView<ProfileController> {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final topInset = AppSystemInsets.top(context);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Column(
          children: [
            // Navy Header
            Container(
              width: double.infinity,
              padding: EdgeInsets.fromLTRB(20.w, topInset + 10.h, 20.w, 18.h),
              color: AppColors.primaryNavy,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'My Profile',
                  style: AppTypography.heading(
                    color: AppColors.textWhite,
                    fontSize: 22.sp,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),

            Padding(
              padding: EdgeInsets.all(16.r),
              child: Column(
                children: [
                  // User Info Card with Edit Profile Button
                  Container(
                    padding: EdgeInsets.all(16.r),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(16.r),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Obx(() {
                      final user = controller.user.value;
                      final name = (user?.fullName.isNotEmpty ?? false)
                          ? user!.fullName
                          : 'Your name';
                      final email = user?.email ?? '';

                      return Row(
                        children: [
                          // Avatar with Edit Badge
                          GestureDetector(
                            onTap: () => Get.toNamed(AppRoutes.editProfile),
                            child: Stack(
                              children: [
                                Container(
                                  width: 58.r,
                                  height: 58.r,
                                  clipBehavior: Clip.antiAlias,
                                  decoration: const BoxDecoration(
                                    color: Color(0xFFE2E8F0),
                                    shape: BoxShape.circle,
                                  ),
                                  child: UserAvatarImage(
                                    user: user,
                                    placeholder: Icon(
                                      Icons.person_rounded,
                                      size: 32.r,
                                      color: const Color(0xFF94A3B8),
                                    ),
                                  ),
                                ),
                                Positioned(
                                  right: 0,
                                  bottom: 0,
                                  child: Container(
                                    width: 18.r,
                                    height: 18.r,
                                    decoration: BoxDecoration(
                                      color: AppColors.primaryNavy,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: Colors.white,
                                        width: 1.5,
                                      ),
                                    ),
                                    child: Icon(
                                      Icons.edit_rounded,
                                      size: 10.r,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          SizedBox(width: 14.w),

                          // Name & Email
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name,
                                  style: AppTypography.heading(
                                    color: AppColors.textPrimary,
                                    fontSize: 15.5.sp,
                                    fontWeight: FontWeight.w700,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                SizedBox(height: 2.h),
                                Text(
                                  email,
                                  style: AppTypography.body(
                                    color: AppColors.textSecondary,
                                    fontSize: 12.sp,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),

                          // Edit Profile Button
                          GestureDetector(
                            onTap: () => Get.toNamed(AppRoutes.editProfile),
                            child: Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: 12.w,
                                vertical: 6.h,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(20.r),
                                border: Border.all(
                                  color: const Color(0xFFCBD5E1),
                                ),
                              ),
                              child: Text(
                                'Edit profile',
                                style: TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 11.5.sp,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    }),
                  ),

                  SizedBox(height: 16.h),

                  // MY IMPACT Card
                  Obx(() {
                    final user = controller.user.value;
                    return ProfileImpactCard(
                      homesPrayed: user?.homesPrayed ?? 47,
                      visitsMade: user?.visitsMade ?? 12,
                    );
                  }),

                  SizedBox(height: 16.h),

                  // Menu Options Container
                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(16.r),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Column(
                      children: [
                        // 1. My Address
                        Obx(
                          () => _buildMenuItem(
                            icon: Icons.location_on_outlined,
                            title: 'My address',
                            subtitle:
                                (controller.user.value?.address.isNotEmpty ??
                                    false)
                                ? controller.user.value!.address
                                : 'Set your home address',
                            onTap: () => ProfileAddressBottomSheet.show(
                              context,
                              currentAddress:
                                  controller.user.value?.address ?? '',
                              nearLatitude: controller.user.value?.latitude,
                              nearLongitude: controller.user.value?.longitude,
                              onSaveAddress: (newAddr, location) => controller
                                  .updateAddress(newAddr, location: location),
                            ),
                          ),
                        ),
                        const Divider(height: 1, color: AppColors.border),

                        // 2. Prayer Preferences
                        Obx(
                          () => _buildMenuItem(
                            icon: Icons.star_border_rounded,
                            title: 'Prayer preferences',
                            subtitle:
                                '${controller.user.value?.dailyPrayerTarget ?? 5} households per day',
                            onTap: () =>
                                ProfilePrayerPreferencesBottomSheet.show(
                                  context,
                                  initialTarget:
                                      controller
                                          .user
                                          .value
                                          ?.dailyPrayerTarget ??
                                      5,
                                  onSavePreferences: (target) => controller
                                      .updatePrayerPreferences(target),
                                ),
                          ),
                        ),
                        const Divider(height: 1, color: AppColors.border),

                        // 3. About GPS PARA EL CIELO
                        _buildMenuItem(
                          icon: Icons.info_outline_rounded,
                          title: 'About GPS PARA EL CIELO',
                          onTap: () => ProfileAboutBottomSheet.show(context),
                        ),
                        const Divider(height: 1, color: AppColors.border),

                        // 4. Contact Support
                        _buildMenuItem(
                          icon: Icons.headset_mic_outlined,
                          title: 'Contact support',
                          onTap: () => ProfileContactSupportBottomSheet.show(
                            context,
                            onSendMessage: (msg) =>
                                controller.sendSupportMessage(msg),
                          ),
                        ),
                        const Divider(height: 1, color: AppColors.border),

                        // 5. Log Out
                        _buildMenuItem(
                          icon: Icons.logout_rounded,
                          title: 'Log out',
                          titleColor: AppColors.danger,
                          iconColor: AppColors.danger,
                          onTap: () => _showSignOutDialog(context),
                        ),
                        const Divider(height: 1, color: AppColors.border),

                        // 6. Delete Account
                        _buildMenuItem(
                          icon: Icons.delete_forever_rounded,
                          title: 'Delete account',
                          titleColor: AppColors.danger,
                          iconColor: AppColors.danger,
                          onTap: () => ProfileDeleteAccountDialog.show(
                            context,
                            requiresPassword: controller.accountUsesPassword,
                            onDelete: (password) =>
                                controller.deleteAccount(password: password),
                          ),
                        ),
                      ],
                    ),
                  ),

                  SizedBox(height: 32.h),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuItem({
    required IconData icon,
    required String title,
    String? subtitle,
    Color? titleColor,
    Color? iconColor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
        child: Row(
          children: [
            Container(
              width: 36.r,
              height: 36.r,
              decoration: BoxDecoration(
                color: (iconColor ?? const Color(0xFF64748B)).withValues(
                  alpha: 0.1,
                ),
                borderRadius: BorderRadius.circular(10.r),
              ),
              child: Icon(
                icon,
                size: 20.r,
                color: iconColor ?? const Color(0xFF64748B),
              ),
            ),
            SizedBox(width: 14.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: titleColor ?? AppColors.textPrimary,
                      fontSize: 14.5.sp,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (subtitle != null) ...[
                    SizedBox(height: 2.h),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: const Color(0xFF94A3B8),
                        fontSize: 12.sp,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: AppColors.textMuted,
              size: 20.r,
            ),
          ],
        ),
      ),
    );
  }

  void _showSignOutDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16.r),
        ),
        title: Text(
          'Log Out',
          style: AppTypography.heading(
            color: AppColors.primaryNavy,
            fontSize: 18.sp,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Text(
          'Are you sure you want to log out of GPS PARA EL CIELO?',
          style: TextStyle(color: AppColors.textPrimary, fontSize: 14.sp),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger,
              elevation: 0,
            ),
            onPressed: () {
              Navigator.of(ctx).pop();
              controller.signOut();
            },
            child: const Text('Log Out', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}
