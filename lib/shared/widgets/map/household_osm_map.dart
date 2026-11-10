import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:gps_cielo/core/constants/app_colors.dart';
import 'package:gps_cielo/core/models/household_model.dart';
import 'package:gps_cielo/core/utils/search_range.dart';
import 'package:latlong2/latlong.dart';

const double _minCircleMeters = 120;

/// Radius of the search circle: just large enough to include every household
/// (with a small margin), and never smaller than [_minCircleMeters].
double searchCircleRadiusMeters(
  double centerLatitude,
  double centerLongitude,
  Iterable<HouseholdModel> households,
) {
  final farthest = SearchRange.farthestMeters(centerLatitude, centerLongitude, [
    for (final h in households) (latitude: h.latitude, longitude: h.longitude),
  ]);
  return math.max(_minCircleMeters, (farthest ?? 0) + 25);
}

/// The north, east, south and west edges of a circle.
List<LatLng> searchCircleBounds(LatLng center, double radiusMeters) {
  const distance = Distance();
  return [
    for (final bearing in const [0.0, 90.0, 180.0, 270.0])
      distance.offset(center, radiusMeters, bearing),
  ];
}

/// Lets a parent zoom a [HouseholdOsmMap] from its own buttons.
class HouseholdMapHandle {
  _HouseholdOsmMapState? _state;

  Future<void> zoomIn() async => _state?._zoomBy(1);

  Future<void> zoomOut() async => _state?._zoomBy(-1);

  /// Re-frames the whole search circle.
  void recenter() => _state?._frameAll();
}

/// OpenStreetMap showing the search center (home or a searched place), a
/// circle around the nearby households, and one pin per household (gold once
/// prayed for).
///
/// Rendered in Flutter with `flutter_map` (raster OSM tiles), so it needs no
/// native map view or API key and works the same on devices and emulators.
///
/// Only build this when the center is known.
class HouseholdOsmMap extends StatefulWidget {
  const HouseholdOsmMap({
    required this.centerLatitude,
    required this.centerLongitude,
    required this.households,
    this.handle,
    this.interactive = true,
    this.initZoom = 17,
    this.markerSize = 40,
    this.onHouseholdTap,
    this.onReadyChanged,
    this.areaMeters,
    super.key,
  });

  final double centerLatitude;
  final double centerLongitude;
  final List<HouseholdModel> households;
  final HouseholdMapHandle? handle;

  /// When false the map ignores pan/zoom gestures (for previews inside scroll
  /// views); the +/- buttons still work through [handle].
  final bool interactive;
  final double initZoom;

  /// Pin size; smaller pins suit small previews.
  final double markerSize;
  final ValueChanged<HouseholdModel>? onHouseholdTap;
  final ValueChanged<bool>? onReadyChanged;

  /// The search range in meters. When set, the circle is exactly this range
  /// (whatever number of homes is pinned inside it).
  final double? areaMeters;

  @override
  State<HouseholdOsmMap> createState() => _HouseholdOsmMapState();
}

class _HouseholdOsmMapState extends State<HouseholdOsmMap> {
  static const double _minZoom = 3;
  static const double _maxZoom = 19;

  /// OpenStreetMap's tile policy requires identifying the app.
  static const String _userAgentPackage = 'org.gaccchurch.gpsceilo';

  final MapController _controller = MapController();
  bool _isReady = false;

  /// Last laid-out size; the view is re-framed when it changes (e.g. a tab
  /// or page transition first lays the map out at a different size).
  Size? _lastSize;

  LatLng get _center => LatLng(widget.centerLatitude, widget.centerLongitude);

  double get _pinSize => widget.markerSize * 0.7;

  @override
  void initState() {
    super.initState();
    widget.handle?._state = this;
  }

  @override
  void didUpdateWidget(covariant HouseholdOsmMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.handle != widget.handle) {
      if (oldWidget.handle?._state == this) oldWidget.handle?._state = null;
      widget.handle?._state = this;
    }

    final centerMoved =
        oldWidget.centerLatitude != widget.centerLatitude ||
        oldWidget.centerLongitude != widget.centerLongitude;
    final householdsAppeared =
        oldWidget.households.isEmpty && widget.households.isNotEmpty;
    final householdsChanged = !_sameIds(oldWidget.households);
    final areaChanged = oldWidget.areaMeters != widget.areaMeters;
    // A Home filter only hides pins inside the same area: keep the view.
    final filteredOnly =
        householdsChanged &&
        !centerMoved &&
        !areaChanged &&
        widget.areaMeters != null &&
        oldWidget.households.isNotEmpty &&
        widget.households.isNotEmpty;
    if (centerMoved ||
        householdsAppeared ||
        areaChanged ||
        (householdsChanged && !filteredOnly)) {
      // Re-frame after this frame's layers are built.
      _frameAfterLayout();
    }
  }

  bool _sameIds(List<HouseholdModel> previous) {
    final current = widget.households;
    if (previous.length != current.length) return false;
    for (var i = 0; i < current.length; i++) {
      if (previous[i].id != current[i].id) return false;
    }
    return true;
  }

  void _onMapReady() {
    if (!mounted) return;
    _isReady = true;
    // Fit once the first layout has settled.
    _frameAfterLayout();
    widget.onReadyChanged?.call(true);
  }

  void _zoomBy(double delta) {
    if (!_isReady || !mounted) return;
    final camera = _controller.camera;
    _controller.move(
      camera.center,
      (camera.zoom + delta).clamp(_minZoom, _maxZoom),
    );
  }

  /// Re-frames after the current layout, making sure a frame is scheduled.
  void _frameAfterLayout() {
    SchedulerBinding.instance
      ..addPostFrameCallback((_) => _frameAll())
      ..ensureVisualUpdate();
  }

  /// Zooms so the whole search circle (and so every household pin inside
  /// it) is visible. This is the default view; the user's own zoom is not
  /// remembered and is replaced whenever the center or the homes change.
  void _frameAll() {
    if (!_isReady || !mounted) return;
    _controller.fitCamera(
      CameraFit.coordinates(
        coordinates: searchCircleBounds(_center, _circleRadiusMeters()),
        padding: const EdgeInsets.all(12),
        maxZoom: widget.initZoom,
      ),
    );
  }

  Iterable<HouseholdModel> get _locatedHouseholds =>
      widget.households.where((h) => h.latitude != 0 || h.longitude != 0);

  double _circleRadiusMeters() {
    final area = widget.areaMeters;
    if (area != null && area > 0) return area;
    return searchCircleRadiusMeters(
      widget.centerLatitude,
      widget.centerLongitude,
      _locatedHouseholds,
    );
  }

  @override
  void dispose() {
    if (widget.handle?._state == this) widget.handle?._state = null;
    _controller.dispose();
    super.dispose();
  }

  Marker _householdMarker(HouseholdModel household) {
    final size = _pinSize;
    final pin = Icon(
      Icons.location_on,
      size: size,
      color: household.isPrayed ? AppColors.primaryGold : AppColors.primaryNavy,
    );
    final onTap = widget.onHouseholdTap;
    return Marker(
      key: ValueKey('household-pin-${household.id}'),
      point: LatLng(household.latitude, household.longitude),
      width: size,
      height: size,
      alignment: Alignment.topCenter,
      child: onTap == null
          ? pin
          : GestureDetector(onTap: () => onTap(household), child: pin),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        if (size != _lastSize) {
          final hadSize = _lastSize != null;
          _lastSize = size;
          if (hadSize) {
            _frameAfterLayout();
          }
        }
        return _buildMap();
      },
    );
  }

  Widget _buildMap() {
    final homeSize = _pinSize + 6;
    return FlutterMap(
      mapController: _controller,
      options: MapOptions(
        initialCenter: _center,
        initialZoom: widget.initZoom,
        minZoom: _minZoom,
        maxZoom: _maxZoom,
        backgroundColor: const Color(0xFFE2EBF5),
        onMapReady: _onMapReady,
        interactionOptions: InteractionOptions(
          flags: widget.interactive
              ? InteractiveFlag.all & ~InteractiveFlag.rotate
              : InteractiveFlag.none,
        ),
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: _userAgentPackage,
          maxNativeZoom: 19,
        ),
        CircleLayer(
          circles: [
            CircleMarker(
              point: _center,
              radius: _circleRadiusMeters(),
              useRadiusInMeter: true,
              color: AppColors.primaryNavy.withValues(alpha: 0.08),
              borderColor: AppColors.primaryNavy.withValues(alpha: 0.4),
              borderStrokeWidth: 2,
            ),
          ],
        ),
        MarkerLayer(
          markers: [
            for (final household in _locatedHouseholds)
              _householdMarker(household),
            Marker(
              key: const ValueKey('center-pin'),
              point: _center,
              width: homeSize,
              height: homeSize,
              child: Icon(
                Icons.home_rounded,
                size: homeSize,
                color: AppColors.danger,
              ),
            ),
          ],
        ),
        // Required OSM credit; one compact line that never overflows.
        Align(
          alignment: Alignment.bottomLeft,
          child: Container(
            margin: const EdgeInsets.all(4),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Text(
              '© OpenStreetMap contributors',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10, color: Color(0xFF334155)),
            ),
          ),
        ),
      ],
    );
  }
}
