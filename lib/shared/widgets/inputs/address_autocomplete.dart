import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:gps_cielo/core/constants/app_colors.dart';
import 'package:gps_cielo/core/constants/app_typography.dart';
import 'package:gps_cielo/core/services/address_suggestion_service.dart';

/// Adds search-as-you-type address suggestions to an existing text field.
///
/// [fieldBuilder] builds the visible input using the provided controller and
/// focus node, so each screen keeps its own styling.
class AddressAutocomplete extends StatefulWidget {
  const AddressAutocomplete({
    required this.controller,
    required this.fieldBuilder,
    required this.onSelected,
    this.nearLatitude,
    this.nearLongitude,
    this.openUp = false,
    super.key,
  });

  final TextEditingController controller;
  final Widget Function(
    BuildContext context,
    TextEditingController controller,
    FocusNode focusNode,
  )
  fieldBuilder;
  final ValueChanged<AddressSuggestion> onSelected;

  /// Biases results towards this point (e.g. the user's saved location).
  final double? nearLatitude;
  final double? nearLongitude;

  /// Show suggestions above the field (useful inside bottom sheets).
  final bool openUp;

  @override
  State<AddressAutocomplete> createState() => _AddressAutocompleteState();
}

enum _SearchStatus { idle, loading, empty, error }

class _AddressAutocompleteState extends State<AddressAutocomplete> {
  static const Duration debounce = Duration(milliseconds: 500);

  final FocusNode _focusNode = FocusNode();
  late final AddressSuggestionService _service =
      Get.isRegistered<AddressSuggestionService>()
      ? Get.find<AddressSuggestionService>()
      : AddressSuggestionService();

  final ValueNotifier<_SearchStatus> _status = ValueNotifier(
    _SearchStatus.idle,
  );
  String _errorMessage = '';
  int _requestId = 0;

  void _setStatus(_SearchStatus status) {
    if (mounted) _status.value = status;
  }

  Future<Iterable<AddressSuggestion>> _options(TextEditingValue value) async {
    final query = value.text.trim();
    final requestId = ++_requestId;
    // Text set by code (saved address, GPS result) must not hit the network.
    if (!_focusNode.hasFocus ||
        query.length < AddressSuggestionService.minQueryLength) {
      _setStatus(_SearchStatus.idle);
      return const [];
    }

    await Future<void>.delayed(debounce);
    if (requestId != _requestId || !mounted) return const [];

    _setStatus(_SearchStatus.loading);
    try {
      final results = await _service.search(
        query,
        nearLatitude: widget.nearLatitude,
        nearLongitude: widget.nearLongitude,
      );
      // RawAutocomplete also drops results of superseded calls.
      if (requestId != _requestId) return const [];
      _setStatus(results.isEmpty ? _SearchStatus.empty : _SearchStatus.idle);
      return results;
    } on AddressSearchException catch (e) {
      if (requestId != _requestId) return const [];
      _errorMessage = e.message;
      _setStatus(_SearchStatus.error);
      return const [];
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _status.dispose();
    super.dispose();
  }

  Widget _buildStatus() {
    return ValueListenableBuilder<_SearchStatus>(
      valueListenable: _status,
      builder: (context, status, _) {
        final (String? text, Color color) = switch (status) {
          _SearchStatus.idle => (null, AppColors.textSecondary),
          _SearchStatus.loading => (
            'Searching addresses...',
            AppColors.textSecondary,
          ),
          _SearchStatus.empty => (
            'No matches found. You can keep typing your full address.',
            AppColors.textSecondary,
          ),
          _SearchStatus.error => (_errorMessage, AppColors.danger),
        };
        if (text == null) return const SizedBox.shrink();
        return Padding(
          padding: EdgeInsets.only(top: 6.h, left: 4.w),
          child: Row(
            children: [
              if (status == _SearchStatus.loading) ...[
                SizedBox(
                  width: 12.r,
                  height: 12.r,
                  child: const CircularProgressIndicator(strokeWidth: 1.6),
                ),
                SizedBox(width: 6.w),
              ],
              Expanded(
                child: Text(
                  text,
                  key: const ValueKey('address-search-status'),
                  style: AppTypography.body(color: color, fontSize: 11.5.sp),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final field = RawAutocomplete<AddressSuggestion>(
      textEditingController: widget.controller,
      focusNode: _focusNode,
      optionsViewOpenDirection: widget.openUp
          ? OptionsViewOpenDirection.up
          : OptionsViewOpenDirection.down,
      displayStringForOption: (option) => option.fullAddress,
      optionsBuilder: _options,
      onSelected: (option) {
        _requestId++;
        _setStatus(_SearchStatus.idle);
        _focusNode.unfocus();
        widget.onSelected(option);
      },
      fieldViewBuilder: (context, controller, focusNode, _) {
        return widget.fieldBuilder(context, controller, focusNode);
      },
      optionsViewBuilder: (context, onSelected, options) {
        return Align(
          alignment: widget.openUp ? Alignment.bottomLeft : Alignment.topLeft,
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 4.h),
            child: Material(
              elevation: 6,
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12.r),
              clipBehavior: Clip.antiAlias,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: 290.h),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Flexible(
                      child: ListView.separated(
                        padding: EdgeInsets.zero,
                        shrinkWrap: true,
                        itemCount: options.length,
                        separatorBuilder: (_, _) =>
                            const Divider(height: 1, color: AppColors.border),
                        itemBuilder: (context, index) {
                          final option = options.elementAt(index);
                          return InkWell(
                            onTap: () => onSelected(option),
                            child: Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: 14.w,
                                vertical: 10.h,
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.location_on_outlined,
                                    size: 18.r,
                                    color: AppColors.primaryNavy,
                                  ),
                                  SizedBox(width: 10.w),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          option.title,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: AppTypography.label(
                                            color: AppColors.textPrimary,
                                            fontSize: 13.5.sp,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        if (option.subtitle.isNotEmpty)
                                          Text(
                                            option.subtitle,
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
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const Divider(height: 1, color: AppColors.border),
                    Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 14.w,
                        vertical: 6.h,
                      ),
                      child: Text(
                        _service.attribution,
                        style: AppTypography.body(
                          color: AppColors.textSecondary,
                          fontSize: 10.5.sp,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [field, _buildStatus()],
    );
  }
}
