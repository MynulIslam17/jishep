import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:gps_cielo/core/models/user_model.dart';
import 'package:gps_cielo/core/constants/app_colors.dart';
import 'package:gps_cielo/core/constants/app_strings.dart';
import 'package:gps_cielo/core/constants/app_typography.dart';
import 'package:gps_cielo/core/services/location_service.dart';
import 'package:gps_cielo/core/utils/search_range.dart';
import 'package:gps_cielo/core/utils/system_ui_config.dart';
import 'package:gps_cielo/features/auth/presentation/controllers/location_setup_controller.dart';
import 'package:gps_cielo/shared/widgets/buttons/app_primary_button.dart';
import 'package:gps_cielo/shared/widgets/household/household_row.dart';
import 'package:gps_cielo/shared/widgets/inputs/address_autocomplete.dart';
import 'package:gps_cielo/shared/widgets/inputs/option_chips.dart';
import 'package:gps_cielo/shared/widgets/inputs/selected_location_note.dart';
import 'package:gps_cielo/shared/widgets/map/household_osm_map.dart';
import 'package:latlong2/latlong.dart';

/// First-run setup (Figma 1.1–1.5): a 4-step wizard with Back / Continue.
/// See [LocationSetupController] for the steps.
class LocationSetupScreen extends GetView<LocationSetupController> {
  const LocationSetupScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiConfig.lightOverlay,
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: GestureDetector(
          // Tap outside the field closes the keyboard and suggestions.
          onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
          behavior: HitTestBehavior.translucent,
          child: SafeArea(
            child: Obx(() {
              final step = controller.step.value;
              return Column(
                children: [
                  _TopBar(step: step),
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      child: KeyedSubtree(
                        key: ValueKey('setup-step-$step'),
                        child: switch (step) {
                          0 => const _AddressStep(),
                          1 => const _ConfirmPinStep(),
                          2 => const _GoalStep(),
                          _ => const _MeetStep(),
                        },
                      ),
                    ),
                  ),
                ],
              );
            }),
          ),
        ),
      ),
    );
  }
}

/// Back arrow, "Step N of 4" and the progress dots.
class _TopBar extends GetView<LocationSetupController> {
  const _TopBar({required this.step});

  final int step;

  @override
  Widget build(BuildContext context) {
    const total = LocationSetupController.stepCount;
    return Padding(
      padding: EdgeInsets.fromLTRB(4.w, 6.h, 16.w, 4.h),
      child: Row(
        children: [
          SizedBox(
            width: 44.r,
            height: 44.r,
            child: step == 0
                ? null
                : IconButton(
                    key: const ValueKey('setup-back'),
                    tooltip: 'Back',
                    onPressed: controller.back,
                    icon: Icon(
                      Icons.arrow_back_rounded,
                      color: AppColors.textPrimary,
                      size: 22.r,
                    ),
                  ),
          ),
          Expanded(
            child: Text(
              'Step ${step + 1} of $total',
              key: const ValueKey('setup-step-label'),
              textAlign: TextAlign.center,
              style: AppTypography.label(
                color: AppColors.textSecondary,
                fontSize: 12.5.sp,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Row(
            children: [
              for (var i = 0; i < total; i++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: EdgeInsets.only(left: 4.w),
                  width: i == step ? 18.w : 7.w,
                  height: 7.h,
                  decoration: BoxDecoration(
                    color: i <= step ? AppColors.primaryNavy : AppColors.border,
                    borderRadius: BorderRadius.circular(4.r),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A step: big title, a line under it, scrolling content and a bottom
/// area with the buttons (hidden while the keyboard is open).
class _StepLayout extends StatelessWidget {
  const _StepLayout({
    required this.title,
    required this.subtitle,
    required this.body,
    required this.actions,
    this.scroll = true,
  });

  final String title;
  final String subtitle;
  final List<Widget> body;
  final List<Widget> actions;

  /// False for a step whose content fills the space (a map).
  final bool scroll;

  @override
  Widget build(BuildContext context) {
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    final header = [
      Text(
        title,
        style: AppTypography.heading(
          color: AppColors.textPrimary,
          fontSize: 24.sp,
          fontWeight: FontWeight.w800,
        ),
      ),
      SizedBox(height: 6.h),
      Text(
        subtitle,
        style: AppTypography.body(
          color: AppColors.textSecondary,
          fontSize: 14.sp,
          height: 1.4,
        ),
      ),
      SizedBox(height: 20.h),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: scroll
              ? ListView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: EdgeInsets.fromLTRB(20.w, 12.h, 20.w, 16.h),
                  children: [...header, ...body],
                )
              : Padding(
                  padding: EdgeInsets.fromLTRB(20.w, 12.h, 20.w, 12.h),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [...header, ...body],
                  ),
                ),
        ),
        if (!keyboardOpen)
          Container(
            padding: EdgeInsets.fromLTRB(20.w, 10.h, 20.w, 12.h),
            decoration: const BoxDecoration(
              color: AppColors.surface,
              border: Border(top: BorderSide(color: AppColors.border)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: actions,
            ),
          ),
      ],
    );
  }
}

Widget _secondaryButton(String label, VoidCallback onPressed, {Key? key}) {
  return TextButton(
    key: key,
    onPressed: onPressed,
    style: TextButton.styleFrom(
      foregroundColor: AppColors.primaryNavy,
      minimumSize: Size.fromHeight(42.h),
    ),
    child: Text(
      label,
      style: AppTypography.label(fontSize: 14.sp, fontWeight: FontWeight.w700),
    ),
  );
}

/// 1.1 Where do you want to pray? Home or any US area.
class _AddressStep extends GetView<LocationSetupController> {
  const _AddressStep();

  @override
  Widget build(BuildContext context) {
    return _StepLayout(
      title: 'Where do you want to pray?',
      subtitle:
          'Your home or any US neighborhood. Search a city, state, ZIP or '
          'address. Only you see it.',
      body: [
        Obx(() {
          final near = controller.selectedLocation.value;
          return AddressAutocomplete(
            key: const ValueKey('setup-address'),
            controller: controller.addressController,
            onSelected: controller.selectSuggestion,
            nearLatitude: near?.latitude,
            nearLongitude: near?.longitude,
            fieldBuilder: (context, fieldController, focusNode) =>
                _AddressField(
                  controller: fieldController,
                  focusNode: focusNode,
                ),
          );
        }),
        Obx(
          () =>
              SelectedLocationNote(location: controller.selectedLocation.value),
        ),
        SizedBox(height: 12.h),
        Obx(
          () => OutlinedButton.icon(
            key: const ValueKey('use-current-location'),
            onPressed: controller.isLocating.value
                ? null
                : controller.useCurrentLocation,
            icon: controller.isLocating.value
                ? SizedBox(
                    width: 16.r,
                    height: 16.r,
                    child: const CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(Icons.my_location_rounded, size: 18.r),
            label: Text(
              controller.isLocating.value
                  ? 'Finding your location…'
                  : 'Use my current location',
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primaryNavy,
              minimumSize: Size.fromHeight(46.h),
              side: const BorderSide(color: AppColors.border),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12.r),
              ),
              textStyle: AppTypography.label(
                fontSize: 13.5.sp,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        Obx(() {
          final error = controller.locationError.value;
          if (error == null) return const SizedBox.shrink();
          return _LocationErrorNote(
            error: error,
            onFix: controller.openLocationSettings,
            onRetry: controller.useCurrentLocation,
          );
        }),
      ],
      actions: [
        Obx(
          () => AppPrimaryButton(
            key: const ValueKey('setup-continue'),
            label: 'Continue',
            isLoading: controller.isResolving.value,
            onPressed: controller.continueFromAddress,
          ),
        ),
        Center(
          child: TextButton(
            key: const ValueKey('setup-sign-out'),
            onPressed: controller.signOut,
            child: Obx(() {
              final email = controller.accountLabel.value;
              return Text(
                email.isEmpty
                    ? 'Not you? Sign out'
                    : 'Signed in as $email · Sign out',
                textAlign: TextAlign.center,
                style: AppTypography.label(
                  color: AppColors.textSecondary,
                  fontSize: 12.sp,
                  fontWeight: FontWeight.w600,
                ),
              );
            }),
          ),
        ),
      ],
    );
  }
}

/// 1.2 Is this the right spot? The map moves under a fixed pin.
class _ConfirmPinStep extends GetView<LocationSetupController> {
  const _ConfirmPinStep();

  @override
  Widget build(BuildContext context) {
    final location = controller.selectedLocation.value;
    return _StepLayout(
      title: 'Is this the right spot?',
      subtitle: 'Drag the map so the pin sits where you want to pray.',
      scroll: false,
      body: [
        Expanded(
          child: location == null
              ? const SizedBox.shrink()
              : _PinMap(
                  key: const ValueKey('pin-map'),
                  latitude: location.latitude,
                  longitude: location.longitude,
                  onMoved: controller.adjustPin,
                ),
        ),
        SizedBox(height: 12.h),
        Container(
          padding: EdgeInsets.all(12.r),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(14.r),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              const HouseTile(),
              SizedBox(width: 10.w),
              Expanded(
                child: Text(
                  location == null
                      ? ''
                      : (location.hasAddress
                            ? location.address
                            : location.coordinatesLabel),
                  key: const ValueKey('pin-address'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.label(
                    color: AppColors.textPrimary,
                    fontSize: 13.5.sp,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
      actions: [
        AppPrimaryButton(
          key: const ValueKey('confirm-pin'),
          label: 'Yes, pray here',
          onPressed: () => controller.goToStep(2),
        ),
        _secondaryButton(
          'Change address',
          () => controller.goToStep(0),
          key: const ValueKey('change-address'),
        ),
      ],
    );
  }
}

/// Map with a pin fixed in the middle; dragging the map moves home.
class _PinMap extends StatefulWidget {
  const _PinMap({
    required this.latitude,
    required this.longitude,
    required this.onMoved,
    super.key,
  });

  final double latitude;
  final double longitude;
  final void Function(double latitude, double longitude) onMoved;

  @override
  State<_PinMap> createState() => _PinMapState();
}

class _PinMapState extends State<_PinMap> {
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _onPosition(MapCamera camera, bool hasGesture) {
    if (!hasGesture) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      widget.onMoved(camera.center.latitude, camera.center.longitude);
    });
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18.r),
      child: Stack(
        children: [
          Positioned.fill(
            child: FlutterMap(
              options: MapOptions(
                initialCenter: LatLng(widget.latitude, widget.longitude),
                initialZoom: 18,
                minZoom: 4,
                maxZoom: 19,
                backgroundColor: const Color(0xFFE2EBF5),
                onPositionChanged: _onPosition,
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                ),
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'org.gaccchurch.gpsceilo',
                  maxNativeZoom: 19,
                ),
                const Align(
                  alignment: Alignment.bottomLeft,
                  child: Padding(
                    padding: EdgeInsets.all(4),
                    child: ColoredBox(
                      color: Color(0xD9FFFFFF),
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        child: Text(
                          '© OpenStreetMap contributors',
                          style: TextStyle(
                            fontSize: 10,
                            color: Color(0xFF334155),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // The pin's tip marks the map center.
          IgnorePointer(
            child: Center(
              child: Transform.translate(
                offset: Offset(0, -20.r),
                child: Icon(
                  Icons.location_on,
                  key: const ValueKey('center-pin'),
                  size: 44.r,
                  color: AppColors.danger,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 1.3 How many neighbors a day?
class _GoalStep extends GetView<LocationSetupController> {
  const _GoalStep();

  @override
  Widget build(BuildContext context) {
    return _StepLayout(
      title: 'How many neighbors a day?',
      subtitle:
          'Pray for a few neighbors each day. When you have prayed for all '
          'of them, a new round starts.',
      body: [
        Obx(
          () => OptionChips(
            options: LocationSetupController.dailyGoals,
            selected: controller.dailyGoal.value,
            caption: 'a day',
            keyPrefix: 'goal',
            onSelected: controller.setDailyGoal,
          ),
        ),
        SizedBox(height: 14.h),
        Obx(() {
          final text = roundLengthText(
            controller.neighborhoodHomes,
            controller.dailyGoal.value,
          );
          return text == null
              ? const SizedBox.shrink()
              : GoalNote(key: const ValueKey('cycle-days'), text: text);
        }),
        // The km range only exists on the old `households` path.
        if (SearchRange.userChoosesRange) ...[
          SizedBox(height: 24.h),
          Text(
            'Neighborhood range',
            style: AppTypography.heading(
              color: AppColors.textPrimary,
              fontSize: 15.sp,
              fontWeight: FontWeight.w700,
            ),
          ),
          SizedBox(height: 8.h),
          Obx(
            () => Wrap(
              spacing: 8.w,
              runSpacing: 8.h,
              children: [
                for (final km in SearchRange.distanceOptionsKm)
                  ChoiceChip(
                    key: ValueKey('range-$km'),
                    label: Text(SearchRange.formatKm(km)),
                    selected: controller.rangeKm.value == km,
                    showCheckmark: false,
                    selectedColor: AppColors.primaryNavy,
                    labelStyle: TextStyle(
                      color: controller.rangeKm.value == km
                          ? Colors.white
                          : AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                    onSelected: (_) => controller.setRange(km),
                  ),
              ],
            ),
          ),
        ],
        SizedBox(height: 16.h),
        Text(
          'You can change the number of homes and your goal later in '
          'Profile.',
          style: AppTypography.body(
            color: AppColors.textMuted,
            fontSize: 12.sp,
          ),
        ),
        SizedBox(height: 24.h),
        const _IntentionPicker(),
      ],
      actions: [
        AppPrimaryButton(
          key: const ValueKey('setup-continue'),
          label: 'Continue',
          onPressed: () => controller.goToStep(3),
        ),
      ],
    );
  }
}

/// Optional prayer focus: suggested chips or the user's own words.
class _IntentionPicker extends GetView<LocationSetupController> {
  const _IntentionPicker();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'What will you pray for? (optional)',
          style: AppTypography.heading(
            color: AppColors.textPrimary,
            fontSize: 15.sp,
            fontWeight: FontWeight.w700,
          ),
        ),
        SizedBox(height: 8.h),
        Obx(() {
          final chosen = controller.prayerIntention.value;
          return Wrap(
            spacing: 8.w,
            runSpacing: 8.h,
            children: [
              for (final option in LocationSetupController.intentionOptions)
                ChoiceChip(
                  key: ValueKey('intention-$option'),
                  label: Text(option),
                  selected: chosen == option,
                  showCheckmark: false,
                  selectedColor: AppColors.primaryNavy,
                  labelStyle: TextStyle(
                    color: chosen == option
                        ? Colors.white
                        : AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                  onSelected: (_) => controller.toggleIntention(option),
                ),
            ],
          );
        }),
        SizedBox(height: 10.h),
        TextField(
          key: const ValueKey('intention-custom'),
          maxLength: UserModel.maxIntentionLength,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            hintText: 'Or write your own',
            isDense: true,
          ),
          onChanged: controller.setCustomIntention,
        ),
      ],
    );
  }
}

/// 1.4 Meet your N neighbors — or 1.5 "This area isn't available yet".
class _MeetStep extends GetView<LocationSetupController> {
  const _MeetStep();

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (controller.previewUnavailable.value &&
          !controller.isLoadingPreview.value) {
        return _unavailable();
      }
      final homes = controller.previewHouseholds.toList();
      final loading = controller.isLoadingPreview.value;
      final n = homes.length;
      final goal = controller.dailyGoal.value;
      final days = controller.cycleDays;
      final location = controller.selectedLocation.value;
      return _StepLayout(
        title: loading || n == 0
            ? 'Meet your neighbors'
            : 'Meet your $n ${n == 1 ? 'neighbor' : 'neighbors'}',
        subtitle: 'These are the homes nearest yours. Start with $goal a day.',
        body: [
          Container(
            height: 220.h,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: const Color(0xFFE8EDF5),
              borderRadius: BorderRadius.circular(18.r),
              border: Border.all(color: AppColors.border),
            ),
            child: location == null
                ? const SizedBox.shrink()
                : HouseholdOsmMap(
                    key: const ValueKey('setup-map'),
                    centerLatitude: location.latitude,
                    centerLongitude: location.longitude,
                    households: homes,
                    areaMeters: SearchRange.userChoosesRange
                        ? controller.rangeKm.value * 1000
                        : null,
                    interactive: false,
                    markerSize: 24,
                  ),
          ),
          SizedBox(height: 12.h),
          Text(
            loading
                ? controller.previewSummary
                : n == 0
                ? controller.previewSummary
                : '${n >= controller.neighborhoodHomes ? 'Nearest' : 'Only'} '
                      '$n ${n == 1 ? 'home' : 'homes'} · $goal a day'
                      '${days == null ? '' : ', full round in about $days '
                                '${days == 1 ? 'day' : 'days'}'}',
            key: const ValueKey('preview-count'),
            style: AppTypography.label(
              color: AppColors.textPrimary,
              fontSize: 13.5.sp,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (controller.previewError.value)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const ValueKey('preview-retry'),
                onPressed: controller.retryPreview,
                icon: Icon(Icons.refresh_rounded, size: 16.r),
                label: const Text('Try again'),
              ),
            ),
          if (loading)
            Padding(
              padding: EdgeInsets.symmetric(vertical: 24.h),
              child: const Center(child: CircularProgressIndicator()),
            ),
          if (!loading) ...[
            SizedBox(height: 10.h),
            for (final h in homes.take(5)) ...[
              KeyedSubtree(
                key: ValueKey('preview-home-${h.id}'),
                child: HouseholdRow(
                  household: h,
                  from: location == null
                      ? null
                      : (
                          latitude: location.latitude,
                          longitude: location.longitude,
                        ),
                  showChevron: false,
                ),
              ),
              SizedBox(height: 8.h),
            ],
            if (n > 5)
              Center(
                child: Text(
                  'and ${n - 5} more',
                  style: AppTypography.body(
                    color: AppColors.textSecondary,
                    fontSize: 12.5.sp,
                  ),
                ),
              ),
          ],
        ],
        actions: [
          const _FixedLocationNote(),
          AppPrimaryButton(
            key: const ValueKey('confirm-home'),
            label: 'Start praying',
            isLoading: controller.isSubmitting.value,
            onPressed: controller.confirmLocation,
          ),
        ],
      );
    });
  }

  Widget _unavailable() {
    return _StepLayout(
      title: AppStrings.areaUnavailable,
      subtitle:
          "We don't have household data around this address yet. "
          '${AppStrings.areaComingSoon}',
      body: [
        Container(
          key: const ValueKey('preview-unavailable'),
          padding: EdgeInsets.all(20.r),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(18.r),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            children: [
              Icon(
                Icons.travel_explore_rounded,
                size: 44.r,
                color: AppColors.primaryNavy,
              ),
              SizedBox(height: 12.h),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
                decoration: BoxDecoration(
                  color: prayedGreenLight,
                  borderRadius: BorderRadius.circular(20.r),
                ),
                child: Text(
                  AppStrings.areasAvailable,
                  textAlign: TextAlign.center,
                  style: AppTypography.label(
                    color: prayedGreen,
                    fontSize: 12.5.sp,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              SizedBox(height: 12.h),
              Text(
                'You can finish setup now. Your neighbors appear as soon as '
                'your area is added. To change this address later, contact '
                'support.',
                textAlign: TextAlign.center,
                style: AppTypography.body(
                  color: AppColors.textSecondary,
                  fontSize: 13.sp,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
      actions: [
        const _FixedLocationNote(),
        AppPrimaryButton(
          key: const ValueKey('confirm-home'),
          label: 'Finish setup',
          isLoading: controller.isSubmitting.value,
          onPressed: controller.confirmLocation,
        ),
        _secondaryButton(
          'Change address',
          () => controller.goToStep(0),
          key: const ValueKey('change-address'),
        ),
      ],
    );
  }
}

class _AddressField extends StatelessWidget {
  const _AddressField({required this.controller, required this.focusNode});

  final TextEditingController controller;
  final FocusNode focusNode;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([controller, focusNode]),
      builder: (context, _) {
        final focused = focusNode.hasFocus;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: AppColors.inputSurface,
            borderRadius: BorderRadius.circular(12.r),
            border: Border.all(
              color: focused ? AppColors.primaryNavy : AppColors.border,
              width: focused ? 1.4 : 1,
            ),
          ),
          padding: EdgeInsets.only(left: 12.w),
          child: Row(
            children: [
              Icon(
                Icons.search_rounded,
                color: AppColors.textSecondary,
                size: 20.r,
              ),
              SizedBox(width: 8.w),
              Expanded(
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  textInputAction: TextInputAction.search,
                  textCapitalization: TextCapitalization.words,
                  style: AppTypography.label(
                    color: AppColors.textPrimary,
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w600,
                  ),
                  decoration: InputDecoration(
                    hintText: 'e.g. House 12, Road 5, Demra, Dhaka',
                    hintStyle: AppTypography.body(
                      color: AppColors.textSecondary,
                      fontSize: 13.5.sp,
                    ),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 14.h),
                  ),
                ),
              ),
              if (controller.text.isNotEmpty)
                IconButton(
                  key: const ValueKey('clear-address'),
                  tooltip: 'Clear',
                  onPressed: () {
                    controller.clear();
                    focusNode.requestFocus();
                  },
                  icon: Icon(
                    Icons.close_rounded,
                    size: 18.r,
                    color: AppColors.textSecondary,
                  ),
                )
              else
                SizedBox(width: 12.w),
            ],
          ),
        );
      },
    );
  }
}

class _LocationErrorNote extends StatelessWidget {
  const _LocationErrorNote({
    required this.error,
    required this.onFix,
    required this.onRetry,
  });

  final LocationException error;
  final VoidCallback onFix;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final needsSettings =
        error.reason == LocationFailure.servicesDisabled ||
        error.reason == LocationFailure.permissionDeniedForever;
    return Container(
      key: const ValueKey('location-error'),
      margin: EdgeInsets.only(top: 10.h),
      padding: EdgeInsets.all(12.r),
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.location_off_outlined,
            size: 18.r,
            color: AppColors.danger,
          ),
          SizedBox(width: 8.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  error.message,
                  style: AppTypography.body(
                    color: AppColors.textPrimary,
                    fontSize: 12.5.sp,
                    height: 1.35,
                  ),
                ),
                SizedBox(height: 4.h),
                Text(
                  'You can also type your address above.',
                  style: AppTypography.body(
                    color: AppColors.textSecondary,
                    fontSize: 12.sp,
                  ),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: needsSettings ? onFix : onRetry,
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      foregroundColor: AppColors.primaryNavy,
                    ),
                    child: Text(needsSettings ? 'Open settings' : 'Try again'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Shown above the final confirmation: the primary location is chosen once
/// (blueprint §2.1); later corrections go through support.
class _FixedLocationNote extends StatelessWidget {
  const _FixedLocationNote();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: 10.h),
      child: Row(
        key: const ValueKey('fixed-location-note'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline_rounded,
            size: 16.r,
            color: AppColors.textSecondary,
          ),
          SizedBox(width: 6.w),
          Expanded(
            child: Text(
              AppStrings.primaryLocationSetupNote,
              style: AppTypography.body(
                color: AppColors.textSecondary,
                fontSize: 12.sp,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
