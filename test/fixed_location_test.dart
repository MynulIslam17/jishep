import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Blueprint §2.1: the primary location is chosen once, at signup. No screen
/// may offer to change it; a wrong address is corrected by support with the
/// audited operator tool (functions/tool/location_admin.js). The Firestore
/// rules refuse a client change too (tool/firestore_rules_test).
void main() {
  Iterable<File> dartFiles(String dir) => Directory(dir)
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'));

  test('the former location-change code is gone', () {
    expect(
      File('lib/core/services/home_address_service.dart').existsSync(),
      isFalse,
    );
    expect(
      File(
        'lib/features/profile/presentation/widgets/profile_address_bottom_sheet.dart',
      ).existsSync(),
      isFalse,
    );
    expect(
      File(
        'lib/features/profile/presentation/widgets/change_home_address.dart',
      ).existsSync(),
      isFalse,
    );
  });

  test('no screen offers to change, update or set the home address', () {
    final banned = RegExp(
      r"Change home address|Update Location|Set as my home|set-as-home|"
      r"change your address any time|HomeAddressService|updateAddress\(|"
      r"Look around another place|searchAround|isTemporary",
    );
    final hits = [
      for (final f in dartFiles('lib'))
        if (banned.hasMatch(f.readAsStringSync())) f.path,
    ];
    expect(hits, isEmpty);
  });

  test('only the signup setup screen saves a location', () {
    final callers = [
      for (final f in dartFiles('lib'))
        if (RegExp(r'\.updateLocation\(').hasMatch(f.readAsStringSync()))
          f.path,
    ];
    expect(callers, [
      'lib/features/auth/presentation/controllers/location_setup_controller.dart',
    ]);
  });
}
