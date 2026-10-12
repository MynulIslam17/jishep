import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:gps_cielo/core/constants/app_colors.dart';
import 'package:gps_cielo/core/constants/app_typography.dart';
import 'package:gps_cielo/core/utils/app_system_insets.dart';
import 'package:gps_cielo/features/main_nav/presentation/models/main_nav_destination.dart';

class AppBottomNavigationBar extends StatelessWidget {
  const AppBottomNavigationBar({
    required this.selectedDestination,
    required this.onDestinationSelected,
    super.key,
  });

  final MainNavDestination selectedDestination;
  final ValueChanged<MainNavDestination> onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    final bottomInset = AppSystemInsets.bottom(context);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: const Border(
          top: BorderSide(color: AppColors.border, width: 1),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      padding: EdgeInsets.fromLTRB(12.w, 8.h, 12.w, bottomInset > 0 ? bottomInset : 8.h),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildNavItem(
            destination: MainNavDestination.home,
            label: 'Home',
            icon: Icons.home_outlined,
            activeIcon: Icons.home_rounded,
          ),
          _buildNavItem(
            destination: MainNavDestination.neighborhood,
            label: 'Neighborhood',
            icon: Icons.location_on_outlined,
            activeIcon: Icons.location_on_rounded,
          ),
          _buildNavItem(
            destination: MainNavDestination.prayerList,
            label: 'Prayer List',
            icon: Icons.favorite_border_rounded,
            activeIcon: Icons.favorite_rounded,
          ),
          _buildNavItem(
            destination: MainNavDestination.followUp,
            label: 'Follow-up',
            icon: Icons.assignment_outlined,
            activeIcon: Icons.assignment_rounded,
          ),
          _buildNavItem(
            destination: MainNavDestination.profile,
            label: 'Profile',
            icon: Icons.person_outline_rounded,
            activeIcon: Icons.person_rounded,
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem({
    required MainNavDestination destination,
    required String label,
    required IconData icon,
    required IconData activeIcon,
  }) {
    final isSelected = selectedDestination == destination;

    return InkWell(
      onTap: () => onDestinationSelected(destination),
      borderRadius: BorderRadius.circular(16.r),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 36.r,
              height: 36.r,
              decoration: BoxDecoration(
                color: isSelected ? AppColors.primaryNavy : Colors.transparent,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Icon(
                  isSelected ? activeIcon : icon,
                  size: 20.r,
                  color: isSelected ? AppColors.textWhite : AppColors.textSecondary,
                ),
              ),
            ),
            SizedBox(height: 3.h),
            Text(
              label,
              style: AppTypography.label(
                color: isSelected ? AppColors.primaryNavy : AppColors.textSecondary,
                fontSize: 10.sp,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
