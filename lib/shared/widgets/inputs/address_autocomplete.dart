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
  ) fieldBuilder;
  final ValueChanged<AddressSuggestion> onSelected;

  /// Biases results towards this point (e.g. the user's saved location).
  final double? nearLatitude;
  final double? nearLongitude;

  /// Show suggestions above the field (useful inside bottom sheets).
  final bool openUp;

  @override
  State<AddressAutocomplete> createState() => _AddressAutocompleteState();
}

class _AddressAutocompleteState extends State<AddressAutocomplete> {
  static const Duration _debounce = Duration(milliseconds: 350);

  final FocusNode _focusNode = FocusNode();
  late final AddressSuggestionService _service =
      Get.isRegistered<AddressSuggestionService>()
          ? Get.find<AddressSuggestionService>()
          : AddressSuggestionService();

  int _requestId = 0;

  Future<Iterable<AddressSuggestion>> _options(TextEditingValue value) async {
    final query = value.text.trim();
    final requestId = ++_requestId;
    if (query.length < AddressSuggestionService.minQueryLength) {
      return const [];
    }

    await Future<void>.delayed(_debounce);
    if (requestId != _requestId || !mounted) return const [];

    return _service.search(
      query,
      nearLatitude: widget.nearLatitude,
      nearLongitude: widget.nearLongitude,
    );
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RawAutocomplete<AddressSuggestion>(
      textEditingController: widget.controller,
      focusNode: _focusNode,
      optionsViewOpenDirection: widget.openUp
          ? OptionsViewOpenDirection.up
          : OptionsViewOpenDirection.down,
      displayStringForOption: (option) => option.fullAddress,
      optionsBuilder: _options,
      onSelected: (option) {
        _focusNode.unfocus();
        widget.onSelected(option);
      },
      fieldViewBuilder: (context, controller, focusNode, _) {
        return widget.fieldBuilder(context, controller, focusNode);
      },
      optionsViewBuilder: (context, onSelected, options) {
        return Align(
          alignment:
              widget.openUp ? Alignment.bottomLeft : Alignment.topLeft,
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 4.h),
            child: Material(
              elevation: 6,
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12.r),
              clipBehavior: Clip.antiAlias,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: 260.h),
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
                                crossAxisAlignment: CrossAxisAlignment.start,
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
            ),
          ),
        );
      },
    );
  }
}
