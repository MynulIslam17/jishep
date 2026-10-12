import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:gps_cielo/core/constants/app_colors.dart';
import 'package:gps_cielo/core/constants/app_typography.dart';
import 'package:gps_cielo/core/models/household_model.dart';
import 'package:gps_cielo/core/utils/follow_up_date.dart';

class HouseholdDetailBottomSheet extends StatefulWidget {
  final HouseholdModel household;
  final ValueChanged<HouseholdModel>? onUpdated;
  final VoidCallback? onPrayToggle;
  final bool initialOpenNotes;

  const HouseholdDetailBottomSheet({
    required this.household,
    this.onUpdated,
    this.onPrayToggle,
    this.initialOpenNotes = false,
    super.key,
  });

  static Future<void> show(
    BuildContext context, {
    required HouseholdModel household,
    ValueChanged<HouseholdModel>? onUpdated,
    VoidCallback? onPrayToggle,
    bool initialOpenNotes = false,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => HouseholdDetailBottomSheet(
        household: household,
        onUpdated: onUpdated,
        onPrayToggle: onPrayToggle,
        initialOpenNotes: initialOpenNotes,
      ),
    );
  }

  @override
  State<HouseholdDetailBottomSheet> createState() =>
      _HouseholdDetailBottomSheetState();
}

class _HouseholdDetailBottomSheetState
    extends State<HouseholdDetailBottomSheet> {
  late HouseholdModel _currentHousehold;
  late bool _isFollowUpOpen;
  late final TextEditingController _notesController;
  late final FocusNode _notesFocusNode;
  late final ScrollController _scrollController;
  final GlobalKey _notesSectionKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _currentHousehold = widget.household;
    _isFollowUpOpen = widget.initialOpenNotes;
    _notesController = TextEditingController(
      text: widget.household.notes ?? '',
    );
    _notesFocusNode = FocusNode();
    _scrollController = ScrollController();

    _notesFocusNode.addListener(_onFocusChange);

    if (widget.initialOpenNotes) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToNotes();
      });
    }
  }

  @override
  void didUpdateWidget(covariant HouseholdDetailBottomSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.household != widget.household) {
      _currentHousehold = widget.household;
    }
  }

  @override
  void dispose() {
    _notesFocusNode.removeListener(_onFocusChange);
    _notesFocusNode.dispose();
    _notesController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (_notesFocusNode.hasFocus) {
      Future.delayed(const Duration(milliseconds: 250), () {
        if (mounted) {
          _scrollToNotes();
        }
      });
    }
  }

  void _scrollToNotes() {
    final keyContext = _notesSectionKey.currentContext;
    if (keyContext != null) {
      Scrollable.ensureVisible(
        keyContext,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
        alignment: 0.08,
      );
    }
  }

  void _togglePray() {
    setState(() {
      _currentHousehold = _currentHousehold.copyWith(
        isPrayed: !_currentHousehold.isPrayed,
      );
    });
    widget.onPrayToggle?.call();
    widget.onUpdated?.call(_currentHousehold);
  }

  void _toggleVisited() {
    setState(() {
      _currentHousehold = _currentHousehold.copyWith(
        isVisited: !_currentHousehold.isVisited,
      );
    });
    widget.onUpdated?.call(_currentHousehold);
  }

  void _toggleInvited() {
    setState(() {
      _currentHousehold = _currentHousehold.copyWith(
        isInvited: !_currentHousehold.isInvited,
      );
    });
    widget.onUpdated?.call(_currentHousehold);
  }

  void _toggleFollowUp() {
    setState(() {
      _isFollowUpOpen = !_isFollowUpOpen;
      if (_isFollowUpOpen) {
        _currentHousehold = _currentHousehold.copyWith(
          hasFollowUp: true,
          followUpDate: _currentHousehold.followUpDate ?? defaultFollowUpDate(),
        );
        widget.onUpdated?.call(_currentHousehold);
      }
    });

    if (_isFollowUpOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToNotes();
        _notesFocusNode.requestFocus();
      });
    } else {
      _notesFocusNode.unfocus();
    }
  }

  void _saveNotes() {
    _notesFocusNode.unfocus();
    final text = _notesController.text.trim();
    final updated = _currentHousehold.copyWith(
      hasFollowUp: true,
      followUpDate: _currentHousehold.followUpDate ?? defaultFollowUpDate(),
      notes: text.isNotEmpty ? text : 'Follow-up requested.',
    );
    setState(() {
      _currentHousehold = updated;
      _isFollowUpOpen = false;
    });
    widget.onUpdated?.call(updated);
  }

  @override
  Widget build(BuildContext context) {
    final item = _currentHousehold;
    final showNotesSection = _isFollowUpOpen;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24.r)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 20,
              offset: const Offset(0, -6),
            ),
          ],
        ),
        padding: EdgeInsets.fromLTRB(20.w, 12.h, 20.w, 24.h),
        child: SingleChildScrollView(
          controller: _scrollController,
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top Drag Handle
              Center(
                child: Container(
                  width: 40.w,
                  height: 4.h,
                  decoration: BoxDecoration(
                    color: const Color(0xFFCBD5E1),
                    borderRadius: BorderRadius.circular(2.r),
                  ),
                ),
              ),

              SizedBox(height: 14.h),

              // Header with Resident Name and Close Button
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      item.residentName,
                      style: AppTypography.heading(
                        color: AppColors.primaryNavy,
                        fontSize: 18.sp,
                        fontWeight: FontWeight.w800,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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
              ),

              SizedBox(height: 12.h),
              const Divider(color: AppColors.border, height: 1),
              SizedBox(height: 16.h),

              // Household Info Block
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 56.r,
                    height: 56.r,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8EFF7),
                      borderRadius: BorderRadius.circular(16.r),
                    ),
                    child: Icon(
                      Icons.home_rounded,
                      size: 28.r,
                      color: AppColors.primaryNavy.withValues(alpha: 0.85),
                    ),
                  ),
                  SizedBox(width: 14.w),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.residentName,
                          style: AppTypography.heading(
                            color: AppColors.textPrimary,
                            fontSize: 16.sp,
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        SizedBox(height: 2.h),
                        Text(
                          item.address,
                          style: AppTypography.body(
                            color: AppColors.textSecondary,
                            fontSize: 13.sp,
                          ),
                        ),
                        Text(
                          item.cityStateZip,
                          style: AppTypography.body(
                            color: const Color(0xFF94A3B8),
                            fontSize: 12.sp,
                          ),
                        ),

                        // Status Badges (Follow up / Visited / Invited)
                        if (item.hasFollowUp || item.isVisited || item.isInvited) ...[
                          SizedBox(height: 6.h),
                          Wrap(
                            spacing: 6.w,
                            runSpacing: 4.h,
                            children: [
                              if (item.hasFollowUp)
                                _buildStatusBadge(
                                  label: 'Follow up',
                                  color: const Color(0xFFD97706),
                                  bgColor: const Color(0xFFFEF3C7),
                                ),
                              if (item.isVisited)
                                _buildStatusBadge(
                                  label: 'Visited',
                                  color: const Color(0xFF2E7D32),
                                  bgColor: const Color(0xFFE8F5E9),
                                ),
                              if (item.isInvited)
                                _buildStatusBadge(
                                  label: 'Invited',
                                  color: AppColors.primaryNavy,
                                  bgColor: const Color(0xFFE8EFF7),
                                ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),

              // Dynamic Notes Section (Revealed when Follow up button is tapped)
              if (showNotesSection) ...[
                SizedBox(height: 16.h),
                Container(
                  key: _notesSectionKey,
                  width: double.infinity,
                  padding: EdgeInsets.all(14.r),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(14.r),
                    border: Border.all(color: const Color(0xFFCBD5E1)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'NOTES',
                            style: AppTypography.label(
                              color: const Color(0xFF64748B),
                              fontSize: 11.sp,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.6,
                            ),
                          ),
                          Text(
                            'Follow-up: ${item.followUpDate ?? 'Not scheduled'}',
                            style: AppTypography.label(
                              color: const Color(0xFFD97706),
                              fontSize: 11.5.sp,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 8.h),
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 8.h),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10.r),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: TextField(
                          controller: _notesController,
                          focusNode: _notesFocusNode,
                          maxLines: 3,
                          minLines: 2,
                          scrollPadding: EdgeInsets.only(bottom: 70.h),
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 13.5.sp,
                            height: 1.35,
                          ),
                          decoration: const InputDecoration(
                            hintText: 'Write follow-up notes about this household...',
                            hintStyle: TextStyle(color: Color(0xFF94A3B8)),
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ),
                      SizedBox(height: 10.h),
                      // Put Notes / Save Notes Action Button
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () {
                              _notesFocusNode.unfocus();
                              setState(() {
                                _isFollowUpOpen = false;
                              });
                            },
                            style: TextButton.styleFrom(
                              padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
                              foregroundColor: const Color(0xFF64748B),
                            ),
                            child: Text(
                              'Cancel',
                              style: TextStyle(
                                fontSize: 12.sp,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          SizedBox(width: 8.w),
                          ElevatedButton.icon(
                            onPressed: _saveNotes,
                            icon: Icon(Icons.check_rounded, size: 16.r, color: Colors.white),
                            label: Text(
                              'Put Notes',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12.5.sp,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primaryNavy,
                              elevation: 0,
                              padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 8.h),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8.r),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],

              SizedBox(height: 16.h),
              const Divider(color: AppColors.border, height: 1),
              SizedBox(height: 18.h),

              // Primary CTA Button: "Mark as Prayed" / "✓ Prayed"
              SizedBox(
                width: double.infinity,
                height: 48.h,
                child: ElevatedButton(
                  onPressed: _togglePray,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: item.isPrayed
                        ? const Color(0xFFE8F5E9)
                        : AppColors.primaryNavy,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12.r),
                      side: item.isPrayed
                          ? const BorderSide(color: Color(0xFFC8E6C9), width: 1.2)
                          : BorderSide.none,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (item.isPrayed) ...[
                        Icon(
                          Icons.check_rounded,
                          color: const Color(0xFF2E7D32),
                          size: 20.r,
                        ),
                        SizedBox(width: 6.w),
                      ],
                      Text(
                        item.isPrayed ? 'Prayed' : 'Mark as Prayed',
                        style: AppTypography.label(
                          color: item.isPrayed
                              ? const Color(0xFF2E7D32)
                              : Colors.white,
                          fontSize: 15.sp,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              SizedBox(height: 12.h),

              // Quick Actions Row (Visited, Invited, Follow up)
              Row(
                children: [
                  Expanded(
                    child: _buildActionButton(
                      label: 'Visited',
                      isSelected: item.isVisited,
                      selectedColor: const Color(0xFF2E7D32),
                      unselectedTextColor: const Color(0xFF2E7D32),
                      onTap: _toggleVisited,
                    ),
                  ),
                  SizedBox(width: 10.w),
                  Expanded(
                    child: _buildActionButton(
                      label: 'Invited',
                      isSelected: item.isInvited,
                      selectedColor: AppColors.primaryNavy,
                      unselectedTextColor: AppColors.primaryNavy,
                      onTap: _toggleInvited,
                    ),
                  ),
                  SizedBox(width: 10.w),
                  Expanded(
                    child: _buildActionButton(
                      label: 'Follow up',
                      isSelected: item.hasFollowUp || _isFollowUpOpen,
                      selectedColor: const Color(0xFFD97706),
                      unselectedTextColor: const Color(0xFFD97706),
                      onTap: _toggleFollowUp,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBadge({
    required String label,
    required Color color,
    required Color bgColor,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6.r),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11.sp,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required String label,
    required bool isSelected,
    required Color selectedColor,
    required Color unselectedTextColor,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: EdgeInsets.symmetric(vertical: 11.h),
        decoration: BoxDecoration(
          color: isSelected
              ? selectedColor.withValues(alpha: 0.12)
              : Colors.white,
          borderRadius: BorderRadius.circular(10.r),
          border: Border.all(
            color: isSelected ? selectedColor : const Color(0xFFE2E8F0),
            width: isSelected ? 1.4 : 1.0,
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: AppTypography.label(
              color: isSelected ? selectedColor : unselectedTextColor,
              fontSize: 13.sp,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
