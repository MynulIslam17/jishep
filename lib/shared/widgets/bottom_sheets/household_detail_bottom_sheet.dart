import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:gps_cielo/core/constants/app_colors.dart';
import 'package:gps_cielo/core/constants/app_typography.dart';
import 'package:gps_cielo/core/models/household_model.dart';
import 'package:gps_cielo/core/utils/follow_up_date.dart';
import 'package:gps_cielo/shared/widgets/dialogs/resident_name_dialog.dart';
import 'package:gps_cielo/shared/widgets/household/household_row.dart';

class HouseholdDetailBottomSheet extends StatefulWidget {
  final HouseholdModel household;
  final ValueChanged<HouseholdModel>? onUpdated;
  final VoidCallback? onPrayToggle;
  final bool initialOpenNotes;

  /// Where the distance is measured from; by default the saved home.
  final ({double latitude, double longitude})? from;

  const HouseholdDetailBottomSheet({
    required this.household,
    this.onUpdated,
    this.onPrayToggle,
    this.initialOpenNotes = false,
    this.from,
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
    // One save: the toggle when given, otherwise the full update.
    final toggle = widget.onPrayToggle;
    if (toggle != null) {
      toggle();
    } else {
      widget.onUpdated?.call(_currentHousehold);
    }
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

  Future<void> _editName() async {
    final result = await ResidentNameDialog.show(
      context,
      initialName: _currentHousehold.residentName,
      addressLine: [
        _currentHousehold.address,
        if (_currentHousehold.cityStateZip.isNotEmpty)
          _currentHousehold.cityStateZip,
      ].join(' · '),
    );
    if (result == null || !mounted) return; // cancelled
    if (result.name == _currentHousehold.residentName) return;
    final updated = _currentHousehold.withName(result.name);
    setState(() => _currentHousehold = updated);
    widget.onUpdated?.call(updated);
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

  /// "120 m from home", or null without a home or household location.
  String? _distanceText(HouseholdModel item) {
    final label = homeDistanceLabel(item, from: widget.from);
    return label == null ? null : '$label from home';
  }

  @override
  Widget build(BuildContext context) {
    final item = _currentHousehold;
    final distance = _distanceText(item);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final canEdit = widget.onUpdated != null;
    final notes = item.notes?.trim() ?? '';

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
        padding: EdgeInsets.fromLTRB(20.w, 10.h, 20.w, 24.h),
        child: SingleChildScrollView(
          controller: _scrollController,
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
              SizedBox(height: 12.h),

              // "Household" + close
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Household',
                      style: AppTypography.heading(
                        color: AppColors.textPrimary,
                        fontSize: 15.sp,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Semantics(
                    button: true,
                    label: 'Close',
                    child: GestureDetector(
                      key: const ValueKey('household-close'),
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
                  ),
                ],
              ),
              SizedBox(height: 14.h),

              // Who and where
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const HouseTile(size: 46),
                  SizedBox(width: 12.w),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.displayName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.heading(
                            color: AppColors.textPrimary,
                            fontSize: 17.sp,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        SizedBox(height: 2.h),
                        Text(
                          item.address,
                          style: AppTypography.body(
                            color: AppColors.textSecondary,
                            fontSize: 12.5.sp,
                          ),
                        ),
                        if (item.cityStateZip.isNotEmpty)
                          Text(
                            item.cityStateZip,
                            style: AppTypography.body(
                              color: AppColors.textMuted,
                              fontSize: 11.5.sp,
                            ),
                          ),
                        if (distance != null)
                          Text(
                            distance,
                            key: const ValueKey('household-distance'),
                            style: AppTypography.body(
                              color: AppColors.textMuted,
                              fontSize: 11.5.sp,
                            ),
                          ),
                        if (item.isPrayed || item.isVisited || item.isInvited)
                          Padding(
                            padding: EdgeInsets.only(top: 6.h),
                            child: Wrap(
                              spacing: 6.w,
                              runSpacing: 4.h,
                              children: [
                                if (item.isPrayed)
                                  _statusPill(
                                    item.prayedOn(DateTime.now())
                                        ? 'Prayed today'
                                        : 'Prayed',
                                    prayedGreen,
                                    prayedGreenLight,
                                  ),
                                if (item.isVisited)
                                  _statusPill(
                                    'Visited',
                                    prayedGreen,
                                    prayedGreenLight,
                                  ),
                                if (item.isInvited)
                                  _statusPill(
                                    'Invited',
                                    AppColors.primaryNavy,
                                    const Color(0xFFE8EFF7),
                                  ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),

              // Add name (dashed) / Edit name
              if (canEdit) ...[
                SizedBox(height: 14.h),
                if (item.residentName == null)
                  _addNameButton()
                else
                  TextButton.icon(
                    key: const ValueKey('household-edit-name'),
                    onPressed: _editName,
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.primaryNavy,
                      padding: EdgeInsets.zero,
                      minimumSize: Size(0, 32.h),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    ),
                    icon: Icon(Icons.edit_outlined, size: 16.r),
                    label: Text(
                      'Edit name',
                      style: AppTypography.body(
                        color: AppColors.primaryNavy,
                        fontSize: 13.sp,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],

              // Saved notes (read-only) while the editor is closed
              if (notes.isNotEmpty && !_isFollowUpOpen) ...[
                SizedBox(height: 10.h),
                Container(
                  key: const ValueKey('household-notes'),
                  width: double.infinity,
                  padding: EdgeInsets.all(12.r),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12.r),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'NOTES',
                        style: AppTypography.label(
                          color: AppColors.textSecondary,
                          fontSize: 10.5.sp,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.6,
                        ),
                      ),
                      SizedBox(height: 4.h),
                      Text(
                        notes,
                        style: AppTypography.body(
                          color: AppColors.textPrimary,
                          fontSize: 13.sp,
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              if (_isFollowUpOpen) ...[
                SizedBox(height: 14.h),
                _notesEditor(item),
              ],

              SizedBox(height: 16.h),

              // Mark as Prayed / ✓ Prayed
              SizedBox(
                width: double.infinity,
                height: 48.h,
                child: ElevatedButton(
                  key: const ValueKey('household-pray'),
                  onPressed: _togglePray,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: item.isPrayed
                        ? prayedGreenLight
                        : AppColors.primaryNavy,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12.r),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (item.isPrayed) ...[
                        Icon(
                          Icons.check_rounded,
                          color: prayedGreen,
                          size: 20.r,
                        ),
                        SizedBox(width: 6.w),
                      ],
                      Text(
                        item.isPrayed ? 'Prayed' : 'Mark as Prayed',
                        style: AppTypography.label(
                          color: item.isPrayed ? prayedGreen : Colors.white,
                          fontSize: 15.sp,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(height: 10.h),

              // Visited · Invited · Follow up
              Row(
                children: [
                  Expanded(
                    child: _actionChip(
                      key: 'household-visited',
                      label: 'Visited',
                      icon: Icons.directions_walk_rounded,
                      color: prayedGreen,
                      selected: item.isVisited,
                      onTap: _toggleVisited,
                    ),
                  ),
                  SizedBox(width: 8.w),
                  Expanded(
                    child: _actionChip(
                      key: 'household-invited',
                      label: 'Invited',
                      icon: Icons.mail_outline_rounded,
                      color: AppColors.primaryNavy,
                      selected: item.isInvited,
                      onTap: _toggleInvited,
                    ),
                  ),
                  SizedBox(width: 8.w),
                  Expanded(
                    child: _actionChip(
                      key: 'household-follow-up',
                      label: 'Follow up',
                      icon: Icons.schedule_rounded,
                      color: const Color(0xFFD97706),
                      selected: item.hasFollowUp || _isFollowUpOpen,
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

  /// Figma 4.1: dashed "+ Add name — who lives here?".
  Widget _addNameButton() {
    return Semantics(
      button: true,
      child: InkWell(
        key: const ValueKey('household-edit-name'),
        onTap: _editName,
        borderRadius: BorderRadius.circular(12.r),
        child: CustomPaint(
          painter: _DashedBorderPainter(
            color: AppColors.primaryNavy.withValues(alpha: 0.45),
            radius: 12.r,
          ),
          child: Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(vertical: 12.h, horizontal: 12.w),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5FB),
              borderRadius: BorderRadius.circular(12.r),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.add_rounded,
                  size: 18.r,
                  color: AppColors.primaryNavy,
                ),
                SizedBox(width: 6.w),
                Text(
                  'Add name',
                  style: AppTypography.body(
                    color: AppColors.primaryNavy,
                    fontSize: 13.sp,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Flexible(
                  child: Text(
                    ' — who lives here?',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.body(
                      color: AppColors.textSecondary,
                      fontSize: 13.sp,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _notesEditor(HouseholdModel item) {
    return Container(
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
                  color: AppColors.textSecondary,
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
              border: Border.all(color: AppColors.border),
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
                hintStyle: TextStyle(color: AppColors.textMuted),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          SizedBox(height: 10.h),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () {
                  _notesFocusNode.unfocus();
                  setState(() => _isFollowUpOpen = false);
                },
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.textSecondary,
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
                icon: Icon(
                  Icons.check_rounded,
                  size: 16.r,
                  color: Colors.white,
                ),
                label: Text(
                  'Save notes',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12.5.sp,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryNavy,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8.r),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statusPill(String label, Color color, Color background) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(20.r),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_rounded, size: 12.r, color: color),
          SizedBox(width: 3.w),
          Text(
            label,
            style: AppTypography.label(
              color: color,
              fontSize: 11.sp,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionChip({
    required String key,
    required String label,
    required IconData icon,
    required Color color,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        key: ValueKey(key),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: 40.h,
          decoration: BoxDecoration(
            color: selected ? color.withValues(alpha: 0.12) : Colors.white,
            borderRadius: BorderRadius.circular(10.r),
            border: Border.all(
              color: selected ? color : AppColors.border,
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 15.r, color: color),
              SizedBox(width: 5.w),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.label(
                    color: color,
                    fontSize: 12.5.sp,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A rounded rectangle drawn with dashes.
class _DashedBorderPainter extends CustomPainter {
  _DashedBorderPainter({required this.color, required this.radius});

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)),
      );
    for (final metric in path.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += 9) {
        canvas.drawPath(metric.extractPath(d, d + 5), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter old) =>
      old.color != color || old.radius != radius;
}
