import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gps_cielo/core/data/user_repository.dart';
import 'package:gps_cielo/shared/widgets/inputs/app_segmented_switch.dart';

void main() {
  group('deleteUserData', () {
    test('removes the user\'s support messages and keeps others', () async {
      final db = FakeFirebaseFirestore();
      await db.collection('users').doc('me').set({'fullName': 'Me'});
      await db.collection('users/me/household_status').doc('h1').set({
        'isPrayed': true,
      });
      await UserRepository(
        firestore: db,
      ).sendSupportMessage(uid: 'me', email: 'a@b.c', message: 'hi');
      await UserRepository(
        firestore: db,
      ).sendSupportMessage(uid: 'other', email: 'x@y.z', message: 'yo');

      await UserRepository(firestore: db).deleteUserData('me');

      final left = await db.collection('support_messages').get();
      expect(left.docs.map((d) => d['uid']), ['other']);
      expect((await db.collection('users').doc('me').get()).exists, isFalse);
      expect(
        (await db.collection('users/me/household_status').get()).docs,
        isEmpty,
      );
    });
  });

  group('deleteUserData with older deployed rules', () {
    test('a denied devices collection does not block deletion', () async {
      final db = _DevicesDeniedFirestore();
      await db.collection('users').doc('me').set({'fullName': 'Me'});
      await db.collection('users/me/household_status').doc('h1').set({
        'isPrayed': true,
      });
      await db.collection('users/me/notifications').doc('n1').set({
        'title': 'hi',
      });

      await UserRepository(firestore: db).deleteUserData('me');

      expect((await db.collection('users').doc('me').get()).exists, isFalse);
      expect(
        (await db.collection('users/me/household_status').get()).docs,
        isEmpty,
      );
      expect(
        (await db.collection('users/me/notifications').get()).docs,
        isEmpty,
      );
    });

    test('a denied required collection still fails the deletion', () async {
      final db = _DevicesDeniedFirestore(deny: 'household_status');
      await db.collection('users').doc('me').set({'fullName': 'Me'});

      await expectLater(
        UserRepository(firestore: db).deleteUserData('me'),
        throwsA(
          isA<FirebaseException>().having(
            (e) => e.code,
            'code',
            'permission-denied',
          ),
        ),
      );
      expect((await db.collection('users').doc('me').get()).exists, isTrue);
    });
  });

  group('AppSegmentedSwitch', () {
    Future<List<int>> pump(WidgetTester tester, int selected) async {
      final taps = <int>[];
      await tester.pumpWidget(
        ScreenUtilInit(
          designSize: const Size(400, 800),
          builder: (_, _) => MaterialApp(
            home: Scaffold(
              body: AppSegmentedSwitch(
                labels: const ['Email', 'Phone Number'],
                selectedIndex: selected,
                onChanged: taps.add,
              ),
            ),
          ),
        ),
      );
      return taps;
    }

    testWidgets('tapping the other option reports it; no ink ripple', (
      tester,
    ) async {
      final taps = await pump(tester, 0);
      expect(find.byType(InkWell), findsNothing);

      await tester.tap(find.text('Phone Number'));
      await tester.tap(find.text('Email')); // already selected
      expect(taps, [1]);
    });

    testWidgets('one thumb slides to the selected option', (tester) async {
      await pump(tester, 0);
      Alignment thumb() =>
          tester.widget<AnimatedAlign>(find.byType(AnimatedAlign)).alignment
              as Alignment;
      expect(thumb().x, -1);

      await pump(tester, 1);
      await tester.pumpAndSettle();
      expect(thumb().x, 1);
      expect(find.byType(AnimatedAlign), findsOneWidget);
    });
  });
}

/// Behaves like Firestore with rules that have no match for one of the
/// user's subcollections: reading it is denied.
class _DevicesDeniedFirestore extends FakeFirebaseFirestore {
  final String deny;

  _DevicesDeniedFirestore({this.deny = 'devices'});

  @override
  CollectionReference<Map<String, dynamic>> collection(String path) {
    if (path.endsWith('/$deny')) return _DeniedCollection();
    return super.collection(path);
  }
}

// ignore: subtype_of_sealed_class
class _DeniedCollection implements CollectionReference<Map<String, dynamic>> {
  @override
  Query<Map<String, dynamic>> limit(int limit) => this;

  @override
  Future<QuerySnapshot<Map<String, dynamic>>> get([GetOptions? options]) =>
      Future.error(
        FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied'),
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
