import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/user_profile.dart';
import '../models/user_role.dart';
import '../services/spectrum_auth_service.dart';
import '../services/user_role_service.dart';

class UserRoleController extends ChangeNotifier {
  UserRoleController({required this._authService, required this._roleService});

  final SpectrumAuthService _authService;
  final UserRoleService _roleService;

  Future<void>? _bootstrapFuture;
  StreamSubscription<SpectrumAuthSnapshot>? _authSubscription;

  Set<UserRole> _roles = {UserRole.viewer};
  String? _currentUid;
  UserProfile? _profile;
  UserProfile? _canonicalProfile;

  int _fetchGeneration = 0;

  Set<UserRole> get roles => Set.unmodifiable(_roles);

  String? get currentUid => _currentUid;

  UserProfile? get profile => _profile;

  UserProfile? get identityProfile => _canonicalProfile ?? _profile;

  String get displayName => identityProfile?.displayName.isNotEmpty == true
      ? identityProfile!.displayName
      : (_authService.currentUser?.displayName ?? '');

  bool get isLinkedSecondary => _profile?.isLinkedSecondary ?? false;

  List<String> get linkedEmails {
    final identity = identityProfile;
    if (identity == null) return const [];
    final ownEmail = _profile?.email;
    return [
      if (identity.email != null && identity.email != ownEmail) identity.email!,
      ...identity.linkedEmails.where((e) => e != ownEmail),
    ];
  }

  bool get isResolvingAuth =>
      _authService.snapshot.state == SpectrumAuthState.unknown ||
      _rolesFetchInFlight;

  bool _rolesFetchInFlight = false;

  bool get canManageUsers => _roles.canManageUsers;

  bool get isDebug => _roles.isDebug;

  List<int> get visibleTabIndices => _roles.visibleTabIndices;
  List<int> get primaryTabIndices => _roles.primaryTabIndices;
  List<int> get secondaryTabIndices => _roles.secondaryTabIndices;

  Object? _rolesError;

  Object? get rolesError => _rolesError;

  Future<void> bootstrap() {
    return _bootstrapFuture ??= _doBootstrap().onError<Object>((
      error,
      stackTrace,
    ) {
      _bootstrapFuture = null;
      Error.throwWithStackTrace(error, stackTrace);
    });
  }

  Future<void> _doBootstrap() async {
    _authSubscription = _authService.snapshotStream.listen(_onAuthSnapshot);
    await _onAuthSnapshot(_authService.snapshot);
  }

  Future<void> _onAuthSnapshot(SpectrumAuthSnapshot snapshot) async {
    if (snapshot.state == SpectrumAuthState.unknown) {
      return;
    }
    if (snapshot.state == SpectrumAuthState.signedIn && snapshot.user != null) {
      final user = snapshot.user!;
      _currentUid = user.uid;
      final gen = ++_fetchGeneration;
      _rolesFetchInFlight = true;
      try {
        final profile = await _roleService.fetchOrCreateProfile(
          uid: user.uid,
          displayName: user.displayName,
          email: user.email,
        );

        final canonicalUid = profile.canonicalUid;
        final canonical = canonicalUid != null && canonicalUid.isNotEmpty
            ? await _roleService.fetchProfile(canonicalUid)
            : null;
        if (gen == _fetchGeneration) {
          _profile = profile;
          _canonicalProfile = canonical;
          _roles = profile.roles;
          _rolesError = null;
          _rolesFetchInFlight = false;
          notifyListeners();
          await _publishDisplayName();
        }
      } catch (error) {
        if (gen == _fetchGeneration) {
          _profile = null;
          _canonicalProfile = null;
          _roles = {UserRole.viewer};
          _rolesError = error;

          _rolesFetchInFlight = false;
          notifyListeners();
        }
      }
    } else if (snapshot.state == SpectrumAuthState.signedOut) {
      ++_fetchGeneration;
      _currentUid = null;
      _profile = null;
      _canonicalProfile = null;
      _roles = {UserRole.viewer};
      _rolesError = null;

      _rolesFetchInFlight = false;
      notifyListeners();
    } else {
      _rolesFetchInFlight = false;
      notifyListeners();
    }
  }

  Future<void> _publishDisplayName() async {
    final wanted = displayName;
    if (wanted.isEmpty) return;
    if (_authService.currentUser?.displayName == wanted) return;
    try {
      await _authService.updateDisplayName(wanted);
    } catch (error) {
      debugPrint('Could not publish the display name: $error');
    }
  }

  Future<void> updateDisplayName(String targetUid, String newName) async {
    final trimmed = newName.trim();
    if (!canManageUsers) {
      throw StateError('Only admins can change a display name');
    }
    if (targetUid == _currentUid) {
      throw StateError('Admins cannot rename themselves via the GUI');
    }
    if (trimmed.isEmpty) {
      throw ArgumentError('A display name cannot be empty');
    }
    await _roleService.updateDisplayName(targetUid, trimmed);
  }

  Future<void> linkAccounts({
    required UserProfile secondary,
    required UserProfile primary,
  }) async {
    if (!canManageUsers) {
      throw StateError('Only admins can link accounts');
    }
    if (secondary.uid == primary.uid) {
      throw StateError('An account cannot be linked to itself');
    }
    if (primary.isLinkedSecondary) {
      throw StateError(
        'That account is already linked to another one; link to the primary',
      );
    }
    final email = secondary.email;
    if (email == null || email.isEmpty) {
      throw StateError('The account being linked has no email address');
    }
    await _roleService.linkAccount(
      secondaryUid: secondary.uid,
      primaryUid: primary.uid,
      secondaryEmail: email,
      roles: primary.roles,
    );
  }

  Future<void> unlinkAccount(UserProfile secondary) async {
    if (!canManageUsers) {
      throw StateError('Only admins can unlink accounts');
    }
    final primaryUid = secondary.canonicalUid;
    if (primaryUid == null || primaryUid.isEmpty) {
      throw StateError('That account is not linked to another one');
    }
    await _roleService.unlinkAccount(
      secondaryUid: secondary.uid,
      primaryUid: primaryUid,
      secondaryEmail: secondary.email ?? '',
    );
  }

  Future<void> updateUserRoles(String targetUid, Set<UserRole> newRoles) async {
    if (!canManageUsers) {
      throw StateError('Only admins can update user roles');
    }
    if (targetUid == _currentUid) {
      throw StateError('Admins cannot change their own roles via the GUI');
    }
    await _roleService.updateRoles(targetUid, newRoles);
  }

  Future<void> updateUserRolesWithLinked(
    UserProfile target,
    Set<UserRole> newRoles,
    List<UserProfile> roster,
  ) async {
    if (!canManageUsers) {
      throw StateError('Only admins can update user roles');
    }
    if (target.uid == _currentUid) {
      throw StateError('Admins cannot change their own roles via the GUI');
    }
    final primaryUid = target.isLinkedSecondary
        ? target.canonicalUid!
        : target.uid;
    final uids = <String>{
      primaryUid,
      target.uid,
      for (final profile in roster)
        if (profile.canonicalUid == primaryUid) profile.uid,
    };

    Object? failure;
    StackTrace? failureStack;
    for (final uid in uids) {
      if (uid == _currentUid) continue;
      try {
        await _roleService.updateRoles(uid, newRoles);
      } catch (error, stackTrace) {
        failure ??= error;
        failureStack ??= stackTrace;
      }
    }
    if (failure != null) {
      Error.throwWithStackTrace(failure, failureStack!);
    }
  }

  Stream<List<UserProfile>> streamAllProfiles() {
    return _roleService.streamAllProfiles();
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }
}
