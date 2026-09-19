import 'dart:async';

import 'package:spectrumstrategy/src/models/user_profile.dart';
import 'package:spectrumstrategy/src/models/user_role.dart';
import 'package:spectrumstrategy/src/services/user_role_service.dart';

class FakeUserRoleService implements UserRoleService {
  final Map<String, Set<UserRole>> _roles = {};
  final Map<String, String> _displayNames = {};
  final Map<String, String> _emails = {};
  final Map<String, String> _canonicalUids = {};
  final Map<String, List<String>> _linkedEmails = {};

  Object? fetchFailure;

  Completer<void>? gate;

  void setRoles(String uid, Set<UserRole> roles) => _roles[uid] = roles;

  void setRole(String uid, UserRole role) => _roles[uid] = {role};

  void setProfile(
    String uid, {
    String? displayName,
    String? email,
    Set<UserRole>? roles,
    String? canonicalUid,
    List<String>? linkedEmails,
  }) {
    if (roles != null) _roles[uid] = roles;
    _roles.putIfAbsent(uid, () => {UserRole.viewer});
    if (displayName != null) _displayNames[uid] = displayName;
    if (email != null) _emails[uid] = email;
    if (canonicalUid != null) _canonicalUids[uid] = canonicalUid;
    if (linkedEmails != null) _linkedEmails[uid] = linkedEmails;
  }

  UserProfile _profileFor(String uid) => UserProfile(
    uid: uid,
    displayName: _displayNames[uid] ?? uid,
    email: _emails[uid],
    roles: _roles[uid] ?? {UserRole.viewer},
    canonicalUid: _canonicalUids[uid],
    linkedEmails: _linkedEmails[uid] ?? const [],
  );

  @override
  Future<UserProfile> fetchOrCreateProfile({
    required String uid,
    String displayName = '',
    String? email,
  }) async {
    final held = gate;
    if (held != null) await held.future;
    final failure = fetchFailure;
    if (failure != null) throw failure;
    if (!_roles.containsKey(uid)) {
      _roles[uid] = {UserRole.scouter};
      _displayNames[uid] = displayName;
      if (email != null) _emails[uid] = email;
    }
    return _profileFor(uid);
  }

  @override
  Future<UserProfile?> fetchProfile(String uid) async =>
      _roles.containsKey(uid) ? _profileFor(uid) : null;

  @override
  Future<void> updateDisplayName(String uid, String displayName) async {
    _displayNames[uid] = displayName;
  }

  @override
  Future<void> linkAccount({
    required String secondaryUid,
    required String primaryUid,
    required String secondaryEmail,
    required Set<UserRole> roles,
  }) async {
    _canonicalUids[secondaryUid] = primaryUid;
    _roles[secondaryUid] = roles;
    final emails = _linkedEmails.putIfAbsent(primaryUid, () => <String>[]);
    if (!emails.contains(secondaryEmail)) emails.add(secondaryEmail);
  }

  @override
  Future<void> unlinkAccount({
    required String secondaryUid,
    required String primaryUid,
    required String secondaryEmail,
  }) async {
    _canonicalUids.remove(secondaryUid);
    _roles[secondaryUid] = {UserRole.viewer};
    _linkedEmails[primaryUid]?.remove(secondaryEmail);
  }

  final Set<String> failingRoleWrites = {};

  @override
  Future<void> updateRoles(String uid, Set<UserRole> roles) async {
    if (failingRoleWrites.contains(uid)) {
      throw StateError('write refused for $uid');
    }
    _roles[uid] = roles;
  }

  @override
  Stream<List<UserProfile>> streamAllProfiles() {
    return Stream.value(_roles.keys.map(_profileFor).toList());
  }
}
