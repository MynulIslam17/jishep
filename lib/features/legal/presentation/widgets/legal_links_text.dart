import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:gps_cielo/core/constants/app_colors.dart';
import 'package:gps_cielo/core/constants/app_typography.dart';
import 'package:gps_cielo/routes/app_routes.dart';

/// "[prefix] Terms of Use and Privacy Policy[suffix]" as one paragraph, so it
/// wraps like normal text; both titles open the document.
class LegalLinksText extends StatefulWidget {
  final String prefix;
  final String suffix;
  final TextAlign textAlign;

  const LegalLinksText({
    required this.prefix,
    this.suffix = '',
    this.textAlign = TextAlign.start,
    super.key,
  });

  @override
  State<LegalLinksText> createState() => _LegalLinksTextState();
}

class _LegalLinksTextState extends State<LegalLinksText> {
  late final _terms = TapGestureRecognizer()
    ..onTap = () => Get.toNamed(AppRoutes.terms);
  late final _privacy = TapGestureRecognizer()
    ..onTap = () => Get.toNamed(AppRoutes.privacy);

  @override
  void dispose() {
    _terms.dispose();
    _privacy.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final plain = AppTypography.body(
      color: AppColors.textSecondary,
      fontSize: 12.sp,
    ).copyWith(height: 1.5);
    final link = AppTypography.label(
      color: AppColors.primaryNavy,
      fontSize: 12.sp,
      fontWeight: FontWeight.w700,
    ).copyWith(decoration: TextDecoration.underline, height: 1.5);

    return SizedBox(
      width: double.infinity,
      child: Text.rich(
        TextSpan(
          style: plain,
          children: [
            TextSpan(text: '${widget.prefix} '),
            TextSpan(text: 'Terms of Use', style: link, recognizer: _terms),
            const TextSpan(text: ' and '),
            TextSpan(text: 'Privacy Policy', style: link, recognizer: _privacy),
            if (widget.suffix.isNotEmpty) TextSpan(text: widget.suffix),
          ],
        ),
        textAlign: widget.textAlign,
      ),
    );
  }
}
