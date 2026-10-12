import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:gps_cielo/core/constants/app_colors.dart';
import 'package:gps_cielo/core/constants/app_typography.dart';
import 'package:gps_cielo/features/notifications/data/models/notification_model.dart';

class NotificationCard extends StatelessWidget {
  final NotificationModel notification;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const NotificationCard({
    required this.notification,
    required this.onTap,
    required this.onDelete,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final style = _getNotificationStyle(notification.type);

    return Dismissible(
      key: Key(notification.id),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onDelete(),
      background: Container(
        alignment: Alignment.centerRight,
        padding: EdgeInsets.symmetric(horizontal: 20.w),
        decoration: BoxDecoration(
          color: AppColors.danger,
          borderRadius: BorderRadius.circular(16.r),
        ),
        child: Icon(
          Icons.delete_outline_rounded,
          color: Colors.white,
          size: 24.r,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16.r),
        child: Container(
          padding: EdgeInsets.all(14.r),
          decoration: BoxDecoration(
            color: notification.isRead ? AppColors.surface : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(16.r),
            border: Border.all(
              color: notification.isRead ? AppColors.border : AppColors.primaryNavy.withValues(alpha: 0.2),
              width: notification.isRead ? 1.0 : 1.5,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Category Icon Container
              Container(
                width: 42.r,
                height: 42.r,
                decoration: BoxDecoration(
                  color: style.bgColor,
                  borderRadius: BorderRadius.circular(12.r),
                ),
                child: Icon(
                  style.icon,
                  size: 22.r,
                  color: style.iconColor,
                ),
              ),

              SizedBox(width: 12.w),

              // Title, Message, and Relative Time
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            notification.title,
                            style: AppTypography.heading(
                              color: AppColors.textPrimary,
                              fontSize: 14.sp,
                              fontWeight: notification.isRead
                                  ? FontWeight.w600
                                  : FontWeight.w800,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        SizedBox(width: 8.w),
                        Row(
                          children: [
                            Text(
                              _formatTime(notification.timestamp),
                              style: TextStyle(
                                color: const Color(0xFF94A3B8),
                                fontSize: 11.sp,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            if (!notification.isRead) ...[
                              SizedBox(width: 6.w),
                              Container(
                                width: 7.r,
                                height: 7.r,
                                decoration: const BoxDecoration(
                                  color: AppColors.primaryGold,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),

                    SizedBox(height: 4.h),

                    Text(
                      notification.message,
                      style: TextStyle(
                        color: notification.isRead
                            ? AppColors.textSecondary
                            : AppColors.textPrimary,
                        fontSize: 12.5.sp,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTime(DateTime timestamp) {
    final diff = DateTime.now().difference(timestamp);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'Yesterday';
    return '${diff.inDays}d ago';
  }

  _NotificationStyle _getNotificationStyle(NotificationType type) {
    return switch (type) {
      NotificationType.prayerReminder => _NotificationStyle(
          icon: Icons.notifications_active_rounded,
          iconColor: const Color(0xFFD97706),
          bgColor: const Color(0xFFFEF3C7),
        ),
      NotificationType.followUpDue => _NotificationStyle(
          icon: Icons.event_note_rounded,
          iconColor: const Color(0xFFEA580C),
          bgColor: const Color(0xFFFFEDD5),
        ),
      NotificationType.milestone => _NotificationStyle(
          icon: Icons.emoji_events_rounded,
          iconColor: const Color(0xFF2E7D32),
          bgColor: const Color(0xFFE8F5E9),
        ),
      NotificationType.scripture => _NotificationStyle(
          icon: Icons.menu_book_rounded,
          iconColor: AppColors.primaryNavy,
          bgColor: const Color(0xFFE8EFF7),
        ),
      NotificationType.churchNews => _NotificationStyle(
          icon: Icons.campaign_rounded,
          iconColor: const Color(0xFF1E88E5),
          bgColor: const Color(0xFFE3F2FD),
        ),
    };
  }
}

class _NotificationStyle {
  final IconData icon;
  final Color iconColor;
  final Color bgColor;

  _NotificationStyle({
    required this.icon,
    required this.iconColor,
    required this.bgColor,
  });
}
