import 'package:gps_cielo/core/services/location_service.dart';

/// Coordinates a user picked for an address field, from a suggestion or GPS.
///
/// A pick only stays valid while the field still describes it. The exception
/// is a GPS position without a mapped address: whatever the user types
/// becomes the label for those coordinates.
class LocationSelection {
  ResolvedLocation? _picked;

  ResolvedLocation? get picked => _picked;

  void pick(ResolvedLocation location) => _picked = location;

  void clear() => _picked = null;

  /// Whether the pick still matches the field text.
  bool appliesTo(String text) {
    final picked = _picked;
    if (picked == null) return false;
    if (picked.source == LocationSource.gps && !picked.hasAddress) return true;
    return text.trim() == picked.address.trim();
  }

  /// The location to save for [text], or null when [text] must be geocoded.
  ResolvedLocation? locationFor(String text) {
    final picked = _picked;
    final trimmed = text.trim();
    if (picked == null || trimmed.isEmpty || !appliesTo(trimmed)) return null;
    return picked.hasAddress ? picked : picked.withAddress(trimmed);
  }
}
