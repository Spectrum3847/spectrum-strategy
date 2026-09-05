import 'dart:async';

import '../models/user_profile.dart';
import '../models/user_role.dart';
import '../scouting/models/scout_assignment.dart';
import '../scouting/models/scout_shift_schedule.dart';
import '../scouting/models/shift_trade.dart';
import '../scouting/services/scout_assignment_sync_service.dart';
import '../scouting/services/scout_shift_sync_service.dart';
import '../scouting/services/shift_trade_sync_service.dart';
import 'spectrum_auth_service.dart';
import 'user_role_service.dart';

class LocalOnlyAuthService implements SpectrumAuthService {
  LocalOnlyAuthService();

  static const SpectrumUser _localUser = SpectrumUser(
    uid: 'local',
    displayName: 'Local user',
  );
  static const SpectrumAuthSnapshot _snapshot = SpectrumAuthSnapshot(
    state: SpectrumAuthState.signedIn,
    user: _localUser,
  );

  final StreamController<SpectrumAuthSnapshot> _controller =
      StreamController<SpectrumAuthSnapshot>.broadcast();

  @override
  Stream<SpectrumAuthSnapshot> get snapshotStream => _controller.stream;

  @override
  SpectrumAuthSnapshot get snapshot => _snapshot;

  @override
  SpectrumUser? get currentUser => _localUser;

  @override
  Future<String?> idToken() async => null;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> signIn() async {}

  @override
  Future<void> updateDisplayName(String displayName) async {}

  @override
  Future<void> signOut() async {}

  @override
  Future<void> dispose() async {
    await _controller.close();
  }
}

class LocalUserRoleService implements UserRoleService {
  @override
  Future<UserProfile> fetchOrCreateProfile({
    required String uid,
    String displayName = '',
    String? email,
  }) async => UserProfile(
    uid: uid,
    displayName: displayName,
    email: email,
    roles: const {UserRole.strategy},
  );

  @override
  Future<UserProfile?> fetchProfile(String uid) async => null;

  @override
  Future<void> updateDisplayName(String uid, String displayName) async {}

  @override
  Future<void> linkAccount({
    required String secondaryUid,
    required String primaryUid,
    required String secondaryEmail,
    required Set<UserRole> roles,
  }) async {}

  @override
  Future<void> unlinkAccount({
    required String secondaryUid,
    required String primaryUid,
    required String secondaryEmail,
  }) async {}

  @override
  Future<void> updateRoles(String targetUid, Set<UserRole> roles) async {}

  @override
  Stream<List<UserProfile>> streamAllProfiles() =>
      const Stream<List<UserProfile>>.empty();
}

class LocalOnlyScoutAssignmentSyncService
    implements ScoutAssignmentSyncService {
  @override
  Stream<List<ScoutAssignment>> watchAll() =>
      Stream<List<ScoutAssignment>>.value(const <ScoutAssignment>[]);

  @override
  Future<void> upsert(ScoutAssignment assignment) async {}

  @override
  Future<void> delete(String id) async {}

  @override
  Future<void> dispose() async {}
}

class LocalOnlyScoutShiftSyncService implements ScoutShiftSyncService {
  @override
  Stream<ScoutShiftSchedule?> get scheduleStream =>
      Stream<ScoutShiftSchedule?>.value(null);

  @override
  String? get currentUserUid => null;

  @override
  String? get currentUserDisplayName => null;

  @override
  Future<void> watch(String eventKey) async {}

  @override
  Future<void> push(ScoutShiftSchedule schedule) async {}

  @override
  Future<void> dispose() async {}
}

class LocalOnlyShiftTradeSyncService implements ShiftTradeSyncService {
  @override
  Stream<List<ShiftTrade>> get tradesStream =>
      Stream<List<ShiftTrade>>.value(const <ShiftTrade>[]);

  @override
  String? get currentUserUid => null;

  @override
  String? get currentUserDisplayName => null;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> create(ShiftTrade trade) async {}

  @override
  Future<void> respond(ShiftTrade trade, ShiftTradeStatus status) async {}

  @override
  Future<void> dispose() async {}
}
