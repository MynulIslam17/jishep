// These fakes exercise the repository's transaction callback without a server.
// ignore_for_file: subtype_of_sealed_class

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gps_cielo/core/data/user_repository.dart';
import 'package:gps_cielo/core/models/user_model.dart';

class _Document implements DocumentReference<Map<String, dynamic>> {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Snapshot implements DocumentSnapshot<Map<String, dynamic>> {
  _Snapshot(this.value);

  final Map<String, dynamic>? value;

  @override
  bool get exists => value != null;

  @override
  String get id => 'user-1';

  @override
  Map<String, dynamic>? data() => value;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Transaction implements Transaction {
  _Transaction(this.value);

  final Map<String, dynamic>? value;
  Map<String, dynamic>? write;

  @override
  Future<DocumentSnapshot<T>> get<T extends Object?>(
    DocumentReference<T> documentReference,
  ) async => _Snapshot(value) as DocumentSnapshot<T>;

  @override
  Transaction set<T>(
    DocumentReference<T> documentReference,
    T data, [
    SetOptions? options,
  ]) {
    write = Map<String, dynamic>.from(data as Map<String, dynamic>);
    return this;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Firestore implements FirebaseFirestore {
  _Firestore({this.data, this.concurrentData});

  Map<String, dynamic>? data;
  final Map<String, dynamic>? concurrentData;
  int writes = 0;

  @override
  DocumentReference<Map<String, dynamic>> doc(String path) {
    expect(path, 'users/user-1');
    return _Document();
  }

  @override
  Future<T> runTransaction<T>(
    TransactionHandler<T> transactionHandler, {
    Duration timeout = const Duration(seconds: 30),
    int maxAttempts = 5,
  }) async {
    var transaction = _Transaction(data);
    var result = await transactionHandler(transaction);
    if (concurrentData != null) {
      // Simulate Firestore retrying after another client wins the first write.
      data = concurrentData;
      transaction = _Transaction(data);
      result = await transactionHandler(transaction);
    }
    if (transaction.write != null) {
      writes++;
      data = transaction.write;
    }
    return result;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final candidate = UserModel(id: 'user-1', fullName: 'New', email: 'a@b.co');

  test('creates a missing profile with timestamps', () async {
    final firestore = _Firestore();
    final result = await UserRepository(
      firestore: firestore,
    ).createUser(candidate);

    expect(result.fullName, 'New');
    expect(firestore.writes, 1);
    expect(firestore.data!['createdAt'], isA<FieldValue>());
    expect(firestore.data!['updatedAt'], isA<FieldValue>());
  });

  test('existing profile and createdAt are preserved', () async {
    final existing = {
      'fullName': 'Existing',
      'email': 'existing@example.com',
      'address': 'Saved address',
      'createdAt': Timestamp(10, 0),
    };
    final firestore = _Firestore(data: existing);
    final result = await UserRepository(
      firestore: firestore,
    ).createUser(candidate);

    expect(result.fullName, 'Existing');
    expect(result.address, 'Saved address');
    expect(firestore.writes, 0);
    expect(firestore.data, existing);
    expect(firestore.data!['createdAt'], Timestamp(10, 0));
  });

  test('transaction retry returns the concurrently created profile', () async {
    final winner = {
      'fullName': 'Other client',
      'email': 'other@example.com',
      'createdAt': Timestamp(20, 0),
    };
    final firestore = _Firestore(concurrentData: winner);
    final result = await UserRepository(
      firestore: firestore,
    ).createUser(candidate);

    expect(result.fullName, 'Other client');
    expect(firestore.writes, 0);
    expect(firestore.data, winner);
  });
}
