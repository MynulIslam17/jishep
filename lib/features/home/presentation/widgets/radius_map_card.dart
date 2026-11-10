import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:gps_cielo/core/constants/app_colors.dart';
import 'package:gps_cielo/core/constants/app_typography.dart';
import 'package:gps_cielo/core/models/household_model.dart';
import 'package:gps_cielo/core/utils/search_range.dart';
import 'package:gps_cielo/shared/widgets/map/household_osm_map.dart';

/// Home-screen "search area" card: a radius selector (how many nearest homes
/// to show) above an interactive OpenStreetMap map of those homes.
///
/// The map can be dragged in any direction and pinch-zoomed; drags that start
/// on the map move the map, drags elsewhere scroll the page.
class RadiusMapCard extends StatefulWidget {
  const RadiusMapCard({
    required this.radiusHomes,
    required this.households,
    this.radiusOptions = SearchRange.options,
    this.rangeMeters,
    this.defaultRadius,
    this.isRadiusFiltered = false,
    this.onResetRadius,
    this.onRadiusChanged,
    this.centerLatitude,
    this.centerLongitude,
    this.centerLabel = '',
    this.isTemporary = false,
    this.isLoading = false,
    this.foundInRange,
    this.rangeComplete = true,
    this.onHouseholdTap,
    this.onExpand,
    super.key,
  });

  final int radiusHomes;
  final List<int> radiusOptions;

  /// The search range from Settings, in meters (the circle).
  final double? rangeMeters;

  /// Default number of households (Settings > My preferences).
  final int? defaultRadius;

  /// True when the slider differs from the default number.
  final bool isRadiusFiltered;
  final VoidCallback? onResetRadius;
  final ValueChanged<int>? onRadiusChanged;
  final List<HouseholdModel> households;

  /// The current search center. Without it a placeholder is shown.
  final double? centerLatitude;
  final double? centerLongitude;
  final String centerLabel;

  /// True when the center is a searched place rather than the home address.
  final bool isTemporary;
  final bool isLoading;

  /// Every household within the range (more than are shown on the map).
  final int? foundInRange;

  /// False when only the nearest part of the range was read: the count is
  /// then shown as a lower bound ("200+ in range").
  final bool rangeComplete;
  final ValueChanged<HouseholdModel>? onHouseholdTap;

  /// Opens the full neighborhood map.
  final VoidCallback? onExpand;

  @override
  State<RadiusMapCard> createState() => _RadiusMapCardState();
}

class _RadiusMapCardState extends State<RadiusMapCard> {
  final HouseholdMapHandle _mapHandle = HouseholdMapHandle();
  bool _isMapReady = false;

  /// Slider value while dragging; null once the parent has the new radius.
  int? _draggingRadius;

  bool get _hasCenter =>
      widget.centerLatitude != null && widget.centerLongitude != null;

  @override
  void didUpdateWidget(covariant RadiusMapCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final hadCenter =
        oldWidget.centerLatitude != null && oldWidget.centerLongitude != null;
    if (hadCenter != _hasCenter) _isMapReady = false;
    // The parent accepted (or reverted) the radius: follow its value.
    if (oldWidget.radiusHomes != widget.radiusHomes ||
        _draggingRadius == widget.radiusHomes) {
      _draggingRadius = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(),
          _buildRadiusSelector(),
          SizedBox(height: 8.h),
          SizedBox(height: 210.h, child: _buildMapArea()),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final String subtitle;
    if (!_hasCenter) {
      subtitle = 'Set a location to see homes around it';
    } else if (widget.centerLabel.trim().isEmpty) {
      subtitle = widget.isTemporary ? 'Around a searched place' : 'Around home';
    } else {
      subtitle = 'Around ${widget.centerLabel.trim()}';
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(14.w, 14.h, 14.w, 10.h),
      child: Row(
        children: [
          Container(
            width: 36.r,
            height: 36.r,
            decoration: BoxDecoration(
              color: AppColors.primaryNavy.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(
              widget.isTemporary
                  ? Icons.travel_explore_rounded
                  : Icons.radar_rounded,
              size: 18.r,
              color: AppColors.primaryNavy,
            ),
          ),
          SizedBox(width: 10.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Search area',
                  style: AppTypography.heading(
                    color: AppColors.textPrimary,
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 2.h),
                Text(
                  subtitle,
                  key: const ValueKey('radius-card-subtitle'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.body(
                    color: AppColors.textSecondary,
                    fontSize: 12.sp,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: 8.w),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 5.h),
            decoration: BoxDecoration(
              color: AppColors.primaryNavy,
              borderRadius: BorderRadius.circular(20.r),
            ),
            child: Text(
              '${widget.foundInRange ?? widget.households.length}${widget.rangeComplete ? '' : '+'} in range',
              key: const ValueKey('radius-card-count'),
              style: AppTypography.label(
                color: Colors.white,
                fontSize: 11.sp,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The search range (km) comes from Settings and never changes here. This
  /// slider only chooses how many of the households found within it to show,
  /// nearest first, so the distance and the circle stay the same.
  Widget _buildRadiusSelector() {
    final options = widget.radiusOptions;
    final value = (_draggingRadius ?? widget.radiusHomes).clamp(
      options.first,
      options.last,
    );
    final onChanged = widget.onRadiusChanged;
    final rangeMeters = widget.rangeMeters;
    final rangeText = rangeMeters == null
        ? null
        : SearchRange.formatDistance(rangeMeters);

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 14.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  rangeText == null
                      ? 'Households to show'
                      : 'Search range $rangeText · change it in Settings',
                  key: const ValueKey('radius-caption'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.label(
                    color: AppColors.textSecondary,
                    fontSize: 12.sp,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (widget.isRadiusFiltered && widget.onResetRadius != null)
                GestureDetector(
                  key: const ValueKey('radius-reset'),
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    setState(() => _draggingRadius = null);
                    widget.onResetRadius!();
                  },
                  child: Padding(
                    padding: EdgeInsets.only(left: 8.w),
                    child: Text(
                      'Default (${widget.defaultRadius ?? SearchRange.defaultHomes})',
                      style: AppTypography.label(
                        color: AppColors.primaryNavy,
                        fontSize: 12.5.sp,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          SizedBox(height: 2.h),
          Text(
            SearchRange.label(
              shown: widget.isLoading ? value : widget.households.length,
              requested: value,
              rangeKm: rangeMeters == null || widget.isLoading
                  ? null
                  : rangeMeters / 1000,
            ),
            key: const ValueKey('radius-value'),
            style: AppTypography.heading(
              color: AppColors.primaryNavy,
              fontSize: 14.sp,
              fontWeight: FontWeight.w800,
            ),
          ),
          ...[
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 4.h,
                activeTrackColor: AppColors.primaryNavy,
                inactiveTrackColor: const Color(0xFFE2E8F0),
                thumbColor: AppColors.primaryNavy,
                overlayColor: AppColors.primaryNavy.withValues(alpha: 0.12),
                activeTickMarkColor: Colors.white.withValues(alpha: 0.7),
                inactiveTickMarkColor: AppColors.primaryNavy.withValues(
                  alpha: 0.25,
                ),
                thumbShape: RoundSliderThumbShape(enabledThumbRadius: 9.r),
                overlayShape: RoundSliderOverlayShape(overlayRadius: 18.r),
                valueIndicatorColor: AppColors.primaryNavy,
                showValueIndicator: ShowValueIndicator.onDrag,
              ),
              child: Slider(
                key: const ValueKey('radius-slider'),
                value: value.toDouble(),
                min: options.first.toDouble(),
                max: options.last.toDouble(),
                divisions: options.length - 1,
                label: '${value.round()} homes',
                semanticFormatterCallback: (v) =>
                    'Show the nearest ${v.round()} homes',
                // Filtering is local (no new search), so apply it live.
                onChanged: onChanged == null
                    ? null
                    : (v) {
                        final homes = v.round();
                        if (homes == (_draggingRadius ?? widget.radiusHomes)) {
                          return;
                        }
                        setState(() => _draggingRadius = homes);
                        onChanged(homes);
                      },
              ),
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 18.r),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  for (final option in options)
                    Text(
                      '$option',
                      style: AppTypography.body(
                        color: option == value
                            ? AppColors.primaryNavy
                            : AppColors.textSecondary,
                        fontSize: 11.sp,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMapArea() {
    return Container(
      color: const Color(0xFFE2EBF5),
      child: Stack(
        children: [
          if (_hasCenter)
            Positioned.fill(
              child: HouseholdOsmMap(
                centerLatitude: widget.centerLatitude!,
                centerLongitude: widget.centerLongitude!,
                households: widget.households,
                areaMeters: widget.rangeMeters,
                handle: _mapHandle,
                markerSize: 30,
                onHouseholdTap: widget.onHouseholdTap,
                onReadyChanged: (ready) {
                  if (mounted) setState(() => _isMapReady = ready);
                },
              ),
            )
          else
            _buildPlaceholder(),

          if (widget.isLoading)
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: LinearProgressIndicator(
                minHeight: 2.5,
                color: AppColors.primaryNavy,
                backgroundColor: Colors.transparent,
              ),
            ),

          if (_hasCenter && widget.onExpand != null)
            Positioned(
              top: 10.h,
              right: 10.w,
              child: _controlBox([
                _controlButton(
                  Icons.open_in_full_rounded,
                  'Open full map',
                  widget.onExpand,
                  key: const ValueKey('radius-card-expand'),
                ),
              ]),
            ),

          if (_hasCenter)
            Positioned(
              bottom: 10.h,
              right: 10.w,
              child: _controlBox([
                _controlButton(
                  Icons.add,
                  'Zoom in',
                  _isMapReady ? _mapHandle.zoomIn : null,
                ),
                _divider(),
                _controlButton(
                  Icons.remove,
                  'Zoom out',
                  _isMapReady ? _mapHandle.zoomOut : null,
                ),
                _divider(),
                _controlButton(
                  Icons.center_focus_strong_rounded,
                  'Show full range',
                  _isMapReady ? _mapHandle.recenter : null,
                  key: const ValueKey('radius-card-recenter'),
                ),
              ]),
            ),
        ],
      ),
    );
  }

  Widget _controlBox(List<Widget> children) {
    return Material(
      color: AppColors.surface,
      elevation: 2,
      shadowColor: Colors.black.withValues(alpha: 0.2),
      borderRadius: BorderRadius.circular(10.r),
      clipBehavior: Clip.antiAlias,
      child: Column(mainAxisSize: MainAxisSize.min, children: children),
    );
  }

  Widget _divider() =>
      Container(height: 1, width: 30.r, color: AppColors.border);

  Widget _controlButton(
    IconData icon,
    String tooltip,
    VoidCallback? onTap, {
    Key? key,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        key: key,
        onTap: onTap,
        child: SizedBox.square(
          dimension: 34.r,
          child: Icon(
            icon,
            size: 18.r,
            color: onTap == null
                ? AppColors.textSecondary
                : AppColors.textPrimary,
          ),
        ),
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Positioned.fill(
      child: Stack(
        children: [
          CustomPaint(size: Size.infinite, painter: _MapGridPainter()),
          Center(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 24.w),
              child: Text(
                'Set your address to see your neighborhood map',
                textAlign: TextAlign.center,
                style: AppTypography.label(
                  color: AppColors.textSecondary,
                  fontSize: 12.sp,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MapGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.6)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;

    final path = Path()
      ..moveTo(0, size.height * 0.3)
      ..lineTo(size.width, size.height * 0.4)
      ..moveTo(size.width * 0.4, 0)
      ..lineTo(size.width * 0.35, size.height)
      ..moveTo(size.width * 0.7, 0)
      ..lineTo(size.width * 0.8, size.height)
      ..moveTo(0, size.height * 0.75)
      ..lineTo(size.width, size.height * 0.7);

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
