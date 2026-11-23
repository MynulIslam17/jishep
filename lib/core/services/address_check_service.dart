import 'package:cloud_functions/cloud_functions.dart';
import 'package:gps_cielo/core/models/household_model.dart';

/// Result of a Melissa address check for one household, as returned by the
/// `enrichHousehold` Cloud Function: the address, the building, and (when
/// the server allows it) the recorded property owner from Melissa Property.
/// No resident names.
class AddressCheck {
  const AddressCheck({
    required this.status,
    this.residential,
    this.verifiedLine,
    this.verifiedCityStateZip,
    this.geocodeLevel,
    this.checkedAt,
    this.cached = false,
    this.propertyUse,
    this.yearBuilt,
    this.propertyFound,
    this.ownerName,
    this.ownerIsCompany = false,
    this.ownerRequested = false,
    this.isTestFixture = false,
  });

  /// True when the server asked Melissa for the owner (owner names are on).
  final bool ownerRequested;

  /// True for the local emulator's fictional test fixture (code "TEST").
  final bool isTestFixture;

  /// Recorded owner (public property record), or null. Not necessarily
  /// who lives at the address.
  final String? ownerName;
  final bool ownerIsCompany;

  /// Melissa Property's use group, e.g. "Single Family Residential".
  final String? propertyUse;
  final int? yearBuilt;

  /// true = parcel found, false = Melissa has no parcel, null = not asked
  /// or unavailable.
  final bool? propertyFound;

  /// "Single Family Residential · built 1962", or null.
  String? get propertyLine {
    if (propertyFound != true) return null;
    final parts = [
      propertyUse,
      if (yearBuilt != null) 'built $yearBuilt',
    ].whereType<String>();
    return parts.isEmpty ? null : parts.join(' · ');
  }

  /// `verified`, `partial` or `not_found`.
  final String status;

  /// true = residence, false = business, null = Melissa doesn't know.
  final bool? residential;
  final String? verifiedLine;
  final String? verifiedCityStateZip;

  /// `rooftop`, `street` or `zip`.
  final String? geocodeLevel;
  final DateTime? checkedAt;
  final bool cached;

  bool get isVerified => status == 'verified';

  /// One line for the household sheet.
  String get summary {
    final kind = switch (residential) {
      true => 'residential address',
      false => 'business address',
      null => 'address (home or business unknown)',
    };
    return switch (status) {
      'verified' => 'Verified $kind',
      'partial' => 'Partly verified $kind',
      _ => 'Melissa has no match for this address',
    };
  }

  static AddressCheck fromMap(Map<Object?, Object?> data) {
    String? text(Object? v) {
      final s = v?.toString().trim() ?? '';
      return s.isEmpty ? null : s;
    }

    final address = data['address'];
    String? line;
    String? cityStateZip;
    if (address is Map) {
      line = [
        text(address['line']),
        text(address['suite']),
      ].whereType<String>().join(' ');
      final city = text(address['city']);
      final stateZip = [
        text(address['state']),
        text(address['zip']),
      ].whereType<String>().join(' ');
      cityStateZip = [
        city,
        stateZip.isEmpty ? null : stateZip,
      ].whereType<String>().join(', ');
    }
    final residential = data['residential'];
    final property = data['property'];
    bool? propertyFound;
    String? propertyUse;
    int? yearBuilt;
    String? ownerName;
    var ownerIsCompany = false;
    var ownerRequested = false;
    if (property is Map) {
      ownerRequested = property['ownerRequested'] == true;
      final owner = property['owner'];
      if (owner is Map) {
        ownerName = text(owner['name']);
        ownerIsCompany = owner['isCompany'] == true || owner['isTrust'] == true;
      }
      final status = text(property['status']);
      propertyFound = status == 'found'
          ? true
          : status == 'not_found'
          ? false
          : null;
      propertyUse = text(property['useGroup']);
      final y = property['yearBuilt'];
      yearBuilt = y is num ? y.toInt() : null;
    }
    return AddressCheck(
      status: text(data['status']) ?? 'not_found',
      residential: residential is bool ? residential : null,
      verifiedLine: (line?.isEmpty ?? true) ? null : line,
      verifiedCityStateZip: (cityStateZip?.isEmpty ?? true)
          ? null
          : cityStateZip,
      geocodeLevel: text(data['geocodeLevel']),
      checkedAt: DateTime.tryParse(data['checkedAt']?.toString() ?? ''),
      cached: data['cached'] == true,
      propertyFound: propertyFound,
      propertyUse: propertyUse,
      yearBuilt: yearBuilt,
      ownerName: ownerName,
      ownerIsCompany: ownerIsCompany,
      ownerRequested: ownerRequested,
      isTestFixture:
          data['codes'] is List && (data['codes'] as List).contains('TEST'),
    );
  }
}

/// A check that could not be made; [message] is shown to the user.
class AddressCheckException implements Exception {
  const AddressCheckException(this.message, {this.reason});
  final String message;
  final String? reason;
  @override
  String toString() => message;
}

/// The parts of a household address the backend needs.
typedef AddressParts = ({String line, String city, String state, String zip});

/// Calls the `enrichHousehold` Cloud Function. Melissa keys stay on the
/// server; the app sends only the household id and its address.
class AddressCheckService {
  AddressCheckService({
    Future<Map<Object?, Object?>> Function(Map<String, Object?> data)? call,
    this.includeProperty = true,
  }) : _call = call ?? _callFunction;

  /// Also ask Melissa Property for building facts (9 more credits).
  final bool includeProperty;

  /// Sends [data] to the function; replaced in tests.
  final Future<Map<Object?, Object?>> Function(Map<String, Object?> data) _call;

  static Future<Map<Object?, Object?>> _callFunction(
    Map<String, Object?> data,
  ) async {
    final callable = FirebaseFunctions.instanceFor(
      region: 'us-central1',
    ).httpsCallable('enrichHousehold');
    final result = await callable.call<Map<Object?, Object?>>(data);
    return result.data;
  }

  static final RegExp _cityStateZip = RegExp(
    r'^\s*(?:(.*?),\s*)?([A-Za-z]{2})(?:\s+(\d{5}(?:-\d{4})?))?\s*$',
  );

  /// Splits "CITY, ST 12345" (as stored on Overture households). Returns
  /// null when there is no house number or no two-letter state.
  static AddressParts? partsOf(HouseholdModel household) {
    final line = household.address.trim();
    if (!RegExp(r'\d').hasMatch(line)) return null;
    final m = _cityStateZip.firstMatch(household.cityStateZip);
    if (m == null) return null;
    final city = m.group(1)?.trim() ?? '';
    final zip = m.group(3) ?? '';
    if (city.isEmpty && zip.isEmpty) return null;
    return (line: line, city: city, state: m.group(2)!.toUpperCase(), zip: zip);
  }

  Future<AddressCheck> check(HouseholdModel household) async {
    final parts = partsOf(household);
    if (parts == null) {
      throw const AddressCheckException(
        'This home has no full street address to check.',
        reason: 'no_street_address',
      );
    }
    try {
      final data = await _call({
        'householdId': household.id,
        'line': parts.line,
        'city': parts.city,
        'state': parts.state,
        'zip': parts.zip,
        'includeProperty': includeProperty,
      });
      return AddressCheck.fromMap(data);
    } on FirebaseFunctionsException catch (e) {
      throw AddressCheckException(
        messageFor(e.code, e.message),
        reason: e.message,
      );
    } catch (_) {
      throw const AddressCheckException(
        'Address check is unavailable. Check your connection and try again.',
      );
    }
  }

  /// User-facing text for a Cloud Function error ([reason] is the
  /// backend's reason string).
  static String messageFor(String code, String? reason) {
    switch (reason) {
      case 'user_daily_limit':
        return "You've reached today's limit of address checks. Try again tomorrow.";
      case 'app_daily_limit':
      case 'out_of_credits':
        return 'Address checks are paused for now. Your homes and prayers are not affected.';
      case 'no_street_address':
        return 'This home has no full street address to check.';
      case 'sign_in_required':
        return 'Please sign in again to check addresses.';
    }
    if (code == 'not-found') {
      return 'Address checks are not set up yet.';
    }
    return 'Address check is unavailable right now. Try again later.';
  }
}
