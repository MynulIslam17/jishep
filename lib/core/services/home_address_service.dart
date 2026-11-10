import 'package:gps_cielo/core/data/user_repository.dart';
import 'package:gps_cielo/core/models/user_model.dart';
import 'package:gps_cielo/core/services/household_store.dart';
import 'package:gps_cielo/core/services/location_service.dart';

/// Saves the user's home address (`users/{uid}` address, latitude,
/// longitude). The only way the home location changes — from Profile ›
/// My address, or "Set as my home" on Home after the user confirms.
class HomeAddressService {
  HomeAddressService(this._users, this._store);

  final UserRepository _users;
  final HouseholdStore _store;

  Future<UserModel> save(UserModel user, ResolvedLocation location) async {
    final address = location.hasAddress
        ? location.address
        : location.coordinatesLabel;
    final updated = user.copyWith(
      address: address,
      latitude: location.latitude,
      longitude: location.longitude,
    );
    await _users.updateLocation(
      uid: user.id,
      address: address,
      latitude: location.latitude,
      longitude: location.longitude,
    );
    // The new home replaces any temporary search location.
    _store.discardTemporarySearch();
    await _store.bindUser(updated);
    return updated;
  }
}
