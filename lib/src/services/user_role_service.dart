import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/user_profile.dart';
import '../models/user_role.dart';

abstract class UserRoleService {
  Future<UserProfile> fetchOrCreateProfile({
    required String uid,
    String displayName = '',
    String? email,
  });

  Future<UserProfile?> fetchProfile(String uid);

  Future<void> updateDisplayName(String uid, String displayName);

  Future<void> linkAccount({
    required String secondaryUid,
    required String primaryUid,
    required String secondaryEmail,
    required Set<UserRole> roles,
  });

  Future<void> unlinkAccount({
    required String secondaryUid,
    required String primaryUid,
    required String secondaryEmail,
  });

  Future<void> updateRoles(String targetUid, Set<UserRole> roles);

  Stream<List<UserProfile>> streamAllProfiles();
}

class FirestoreUserRoleService implements UserRoleService {
  FirestoreUserRoleService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  @override
  Future<UserProfile> fetchOrCreateProfile({
    required String uid,
    String displayName = '',
    String? email,
  }) async {
    final scouter = UserProfile(
      uid: uid,
      displayName: displayName,
      email: email,
      roles: const {UserRole.scouter},
    );
    final viewer = UserProfile(
      uid: uid,
      displayName: displayName,
      email: email,
      roles: const {UserRole.viewer},
    );
    try {
      final ref = _firestore.collection('userProfiles').doc(uid);
      final doc = await ref.get();
      if (!doc.exists || doc.data() == null) {
        final data = <String, dynamic>{
          'uid': uid,
          'displayName': displayName,
          'email': ?email,
          'roles': ['scouter'],
          'createdAt': DateTime.now().toUtc().toIso8601String(),
        };

        try {
          await ref.set(data);
        } catch (_) {}
        return scouter;
      }
      return UserProfile.fromJson(uid, doc.data()!);
    } catch (_) {
      try {
        final cached = await _firestore
            .collection('userProfiles')
            .doc(uid)
            .get(const GetOptions(source: Source.cache));
        final data = cached.data();
        if (cached.exists && data != null) {
          return UserProfile.fromJson(uid, data);
        }
      } catch (_) {}
      return viewer;
    }
  }

  @override
  Future<UserProfile?> fetchProfile(String uid) async {
    try {
      final doc = await _firestore.collection('userProfiles').doc(uid).get();
      final data = doc.data();
      if (!doc.exists || data == null) return null;
      return UserProfile.fromJson(uid, data);
    } catch (_) {
      try {
        final cached = await _firestore
            .collection('userProfiles')
            .doc(uid)
            .get(const GetOptions(source: Source.cache));
        final data = cached.data();
        if (cached.exists && data != null) {
          return UserProfile.fromJson(uid, data);
        }
      } catch (_) {}
      return null;
    }
  }

  @override
  Future<void> updateDisplayName(String uid, String displayName) async {
    await _firestore.collection('userProfiles').doc(uid).set({
      'displayName': displayName,
    }, SetOptions(merge: true));
  }

  @override
  Future<void> linkAccount({
    required String secondaryUid,
    required String primaryUid,
    required String secondaryEmail,
    required Set<UserRole> roles,
  }) async {
    final profiles = _firestore.collection('userProfiles');

    await profiles.doc(secondaryUid).set({
      'canonicalUid': primaryUid,
      'roles': roles.map((r) => r.name).toList(),
    }, SetOptions(merge: true));
    await profiles.doc(primaryUid).set({
      'linkedEmails': FieldValue.arrayUnion([secondaryEmail]),
    }, SetOptions(merge: true));
  }

  @override
  Future<void> unlinkAccount({
    required String secondaryUid,
    required String primaryUid,
    required String secondaryEmail,
  }) async {
    final profiles = _firestore.collection('userProfiles');

    await profiles.doc(secondaryUid).set({
      'canonicalUid': FieldValue.delete(),
      'roles': [UserRole.viewer.name],
    }, SetOptions(merge: true));
    await profiles.doc(primaryUid).set({
      'linkedEmails': FieldValue.arrayRemove([secondaryEmail]),
    }, SetOptions(merge: true));
  }

  @override
  Future<void> updateRoles(String targetUid, Set<UserRole> roles) async {
    await _firestore.collection('userProfiles').doc(targetUid).set({
      'roles': roles.map((r) => r.name).toList(),
    }, SetOptions(merge: true));
  }

  @override
  Stream<List<UserProfile>> streamAllProfiles() {
    return _firestore
        .collection('userProfiles')
        .snapshots()
        .map(
          (snapshot) =>
              snapshot.docs
                  .map((doc) => UserProfile.fromJson(doc.id, doc.data()))
                  .toList()
                ..sort(UserProfile.byDisplayName),
        );
  }
}
