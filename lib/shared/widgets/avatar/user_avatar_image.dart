import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:gps_cielo/core/models/user_model.dart';

/// Circle-clipped content for a user's profile photo.
///
/// Prefers the photo stored in Firestore ([UserModel.avatarBase64]), then a
/// remote URL (e.g. the Google account photo), then [placeholder].
class UserAvatarImage extends StatelessWidget {
  final UserModel? user;
  final Widget placeholder;

  const UserAvatarImage({
    required this.user,
    required this.placeholder,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final bytes = _decode(user?.avatarBase64);
    if (bytes != null) {
      return Image.memory(
        bytes,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => placeholder,
      );
    }

    final url = user?.avatarUrl;
    if (url != null && url.isNotEmpty) {
      return Image.network(
        url,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => placeholder,
      );
    }

    return placeholder;
  }

  static final Map<String, Uint8List> _cache = {};

  static Uint8List? _decode(String? data) {
    if (data == null || data.isEmpty) return null;
    final cached = _cache[data];
    if (cached != null) return cached;
    try {
      final bytes = base64Decode(data);
      _cache
        ..clear()
        ..[data] = bytes;
      return bytes;
    } catch (_) {
      return null;
    }
  }
}
