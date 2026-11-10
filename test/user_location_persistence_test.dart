// ignore_for_file: subtype_of_sealed_class
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gps_cielo/core/data/user_repository.dart';

class _Write {
  Map<String, dynamic>? data;
  SetOptions? options;
}

class _Doc implements DocumentReference<Map<String, dynamic>> {
  _Doc(this.path);

  @override
  final String path;
  final _Write last = _Write();

  Map<String, dynamic>? get written => last.data;
  SetOptions? get options => last.options;

  @override
  Future<void> set(Map<String, dynamic> data, [SetOptions? options]) async {
    last
      ..data = data
      ..options = options;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Firestore implements FirebaseFirestore {
  final Map<String, _Doc> docs = {};

  @override
  DocumentReference<Map<String, dynamic>> doc(String path) =>
      docs.putIfAbsent(path, () => _Doc(path));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('saving the home location merges only location fields', () async {
    final db = _Firestore();
    await UserRepository(firestore: db).updateLocation(
      uid: 'alice',
      address: 'Dhanmondi, Dhaka, Dhaka Division 1205, Bangladesh',
      latitude: 23.7479124,
      longitude: 90.3745866,
      radiusHomes: 15,
    );

    final doc = db.docs['users/alice']!;
    expect(doc.options?.merge, isTrue);
    expect(doc.written!.keys.toSet(), {
      'address',
      'latitude',
      'longitude',
      'radiusHomes',
      'updatedAt',
    });
    expect(doc.written!['latitude'], isA<double>());
    expect(doc.written!['longitude'], isA<double>());
    expect(doc.written!['updatedAt'], isA<FieldValue>());
    expect(doc.written!.containsKey('createdAt'), isFalse);
  });

  test('radius is left untouched when not given', () async {
    final db = _Firestore();
    await UserRepository(firestore: db).updateLocation(
      uid: 'alice',
      address: 'Uttara',
      latitude: 23.87,
      longitude: 90.37,
    );
    expect(
      db.docs['users/alice']!.written!.containsKey('radiusHomes'),
      isFalse,
    );
  });
}
