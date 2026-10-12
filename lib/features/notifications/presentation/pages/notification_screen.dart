import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:gps_cielo/core/constants/app_colors.dart';
import 'package:gps_cielo/core/constants/app_typography.dart';
import 'package:gps_cielo/core/utils/app_system_insets.dart';
import 'package:gps_cielo/features/notifications/presentation/controllers/notification_controller.dart';
import 'package:gps_cielo/features/notifications/presentation/widgets/notification_card.dart';
import 'package:gps_cielo/features/notifications/presentation/widgets/notification_empty_state.dart';

class NotificationScreen extends GetView<NotificationController> {
  const NotificationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final topInset = AppSystemInsets.top(context);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          // Navy Header
          Container(
            width: double.infinity,
            padding: EdgeInsets.fromLTRB(16.w, topInset + 8.h, 16.w, 16.h),
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
                Expanded(
                  child: Row(
                    children: [
                      Text(
                        'Notifications',
                        style: AppTypography.heading(
                          color: AppColors.textWhite,
                          fontSize: 20.sp,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      SizedBox(width: 8.w),
                      Obx(() {
                        final count = controller.unreadCount;
                        if (count == 0) return const SizedBox.shrink();
                        return Container(
                          padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 2.h),
                          decoration: BoxDecoration(
                            color: AppColors.primaryGold,
                            borderRadius: BorderRadius.circular(12.r),
                          ),
                          child: Text(
                            '$count new',
                            style: TextStyle(
                              color: AppColors.primaryNavyDark,
                              fontSize: 11.sp,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
                ),

                // Mark all as read button
                Obx(() {
                  if (controller.unreadCount == 0) return const SizedBox.shrink();
                  return GestureDetector(
                    onTap: () => controller.markAllAsRead(),
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.h),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8.r),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.done_all_rounded,
                            size: 14.r,
                            color: Colors.white,
                          ),
                          SizedBox(width: 4.w),
                          Text(
                            'Read all',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 11.5.sp,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),

          // Filter Tabs Bar
          Container(
            width: double.infinity,
            decoration: const BoxDecoration(
              color: Color(0xFFF8FAFC),
              border: Border(
                bottom: BorderSide(color: Color(0xFFE2E8F0), width: 1),
              ),
            ),
            child: Obx(
              () => SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                padding: EdgeInsets.symmetric(horizontal: 12.w),
                child: Row(
                  children: NotificationFilter.values.map((filter) {
                    final isSelected = controller.selectedFilter.value == filter;
                    return GestureDetector(
                      onTap: () => controller.selectFilter(filter),
                      child: Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: 14.w,
                          vertical: 12.h,
                        ),
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(
                              color: isSelected
                                  ? AppColors.primaryNavy
                                  : Colors.transparent,
                              width: 2.5,
                            ),
                          ),
                        ),
                        child: Text(
                          filter.label,
                          style: TextStyle(
                            color: isSelected
                                ? AppColors.primaryNavy
                                : const Color(0xFF64748B),
                            fontSize: 13.5.sp,
                            fontWeight: isSelected
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          ),

          // Notifications List Area
          Expanded(
            child: Obx(() {
              if (controller.isLoading.value) {
                return const Center(child: CircularProgressIndicator());
              }

              final list = controller.filteredNotifications;

              if (list.isEmpty) {
                return RefreshIndicator(
                  onRefresh: () => controller.loadNotifications(),
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: const [
                      NotificationEmptyState(),
                    ],
                  ),
                );
              }

              return RefreshIndicator(
                onRefresh: () => controller.loadNotifications(),
                child: ListView.separated(
                  physics: const BouncingScrollPhysics(
                    parent: AlwaysScrollableScrollPhysics(),
                  ),
                  padding: EdgeInsets.fromLTRB(16.w, 14.h, 16.w, 24.h),
                  itemCount: list.length,
                  separatorBuilder: (context, index) => SizedBox(height: 10.h),
                  itemBuilder: (context, index) {
                    final notif = list[index];
                    return NotificationCard(
                      notification: notif,
                      onTap: () => controller.handleNotificationTap(notif),
                      onDelete: () => controller.deleteNotification(notif.id),
                    );
                  },
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}
