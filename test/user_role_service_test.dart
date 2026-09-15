import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:spectrumstrategy/src/models/user_role.dart';
import 'package:spectrumstrategy/src/services/user_role_service.dart';

void main() {
  group('fetchOrCreateProfile', () {
    test('creates a scouter profile on first sign-in', () async {
      final firestore = FakeFirebaseFirestore();
      final service = FirestoreUserRoleService(firestore: firestore);

      final profile = await service.fetchOrCreateProfile(
        uid: 'new-uid',
        displayName: 'New User',
      );

      expect(profile.roles, {UserRole.scouter});
      final doc = await firestore
          .collection('userProfiles')
          .doc('new-uid')
          .get();
      expect(doc.data()!['roles'], ['scouter']);
    });
  });

  group('updateRoles', () {
    test('creates a profile doc when none exists yet', () async {
      final firestore = FakeFirebaseFirestore();
      final service = FirestoreUserRoleService(firestore: firestore);

      await service.updateRoles('foreign-uid', {UserRole.admin});

      final doc = await firestore
          .collection('userProfiles')
          .doc('foreign-uid')
          .get();
      expect(doc.exists, isTrue);
      expect(doc.data()!['roles'], ['admin']);
    });

    test(
      'merges roles into an existing profile without clobbering it',
      () async {
        final firestore = FakeFirebaseFirestore();
        await firestore.collection('userProfiles').doc('u1').set({
          'uid': 'u1',
          'displayName': 'Existing User',
          'roles': ['viewer'],
        });
        final service = FirestoreUserRoleService(firestore: firestore);

        await service.updateRoles('u1', {UserRole.strategy});

        final doc = await firestore.collection('userProfiles').doc('u1').get();
        expect(doc.data()!['displayName'], 'Existing User');
        expect(doc.data()!['roles'], ['strategy']);
      },
    );
  });

  group('streamAllProfiles', () {
    test('includes a profile with no displayName field', () async {
      final firestore = FakeFirebaseFirestore();

      await firestore.collection('userProfiles').doc('no-name-uid').set({
        'uid': 'no-name-uid',
        'roles': ['scouter'],
      });
      await firestore.collection('userProfiles').doc('named-uid').set({
        'uid': 'named-uid',
        'displayName': 'Amy',
        'roles': ['admin'],
      });
      final service = FirestoreUserRoleService(firestore: firestore);

      final profiles = await service.streamAllProfiles().first;

      expect(
        profiles.map((p) => p.uid),
        containsAll(['no-name-uid', 'named-uid']),
      );
    });

    test('sorts client-side by display name, tie-broken by uid', () async {
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('userProfiles').doc('b-uid').set({
        'uid': 'b-uid',
        'displayName': 'Zed',
        'roles': ['viewer'],
      });
      await firestore.collection('userProfiles').doc('a-uid').set({
        'uid': 'a-uid',
        'displayName': '',
        'roles': ['viewer'],
      });
      final service = FirestoreUserRoleService(firestore: firestore);

      final profiles = await service.streamAllProfiles().first;

      expect(profiles.map((p) => p.uid).toList(), ['a-uid', 'b-uid']);
    });
  });
}
