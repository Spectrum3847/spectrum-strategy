import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../services/spectrum_auth_service.dart';
import '../models/scout_shift_schedule.dart';

abstract class ScoutShiftSyncService {
  Stream<ScoutShiftSchedule?> get scheduleStream;

  String? get currentUserUid;
  String? get currentUserDisplayName;

  Future<void> watch(String eventKey);

  Future<void> push(ScoutShiftSchedule schedule);

  Future<void> dispose();
}

class FirestoreScoutShiftSyncService implements ScoutShiftSyncService {
  FirestoreScoutShiftSyncService({
    required this._authService,
    FirebaseFirestore? firestore,
  }) : _firestore = firestore ?? FirebaseFirestore.instance;

  static const String collection = 'scoutShifts';

  final SpectrumAuthService _authService;
  final FirebaseFirestore _firestore;

  final StreamController<ScoutShiftSchedule?> _controller =
      StreamController<ScoutShiftSchedule?>.broadcast();
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sub;
  String _eventKey = '';

  @override
  Stream<ScoutShiftSchedule?> get scheduleStream => _controller.stream;

  @override
  String? get currentUserUid => _authService.currentUser?.uid;

  @override
  String? get currentUserDisplayName => _authService.currentUser?.displayName;

  @override
  Future<void> watch(String eventKey) async {
    if (eventKey == _eventKey && _sub != null) return;
    _eventKey = eventKey;
    await _sub?.cancel();
    _sub = null;

    if (eventKey.isEmpty) {
      _controller.add(null);
      return;
    }

    _sub = _firestore.doc('$collection/$eventKey').snapshots().listen((
      snapshot,
    ) {
      final data = snapshot.data();
      if (!snapshot.exists || data == null) {
        _controller.add(null);
        return;
      }
      final ts = data['updatedAtTs'];
      final schedule = ScoutShiftSchedule.fromJson(data);
      _controller.add(
        ts is Timestamp
            ? ScoutShiftSchedule(
                eventKey: schedule.eventKey,
                matchCount: schedule.matchCount,
                roster: schedule.roster,
                rotations: schedule.rotations,
                cellOverrides: schedule.cellOverrides,
                authorUid: schedule.authorUid,
                authorDisplayName: schedule.authorDisplayName,
                updatedAt: ts.toDate().toUtc(),
              )
            : schedule,
      );
    }, onError: (Object _) => _controller.add(null));
  }

  @override
  Future<void> push(ScoutShiftSchedule schedule) async {
    final user = _authService.currentUser;
    final stamped = ScoutShiftSchedule(
      eventKey: schedule.eventKey,
      matchCount: schedule.matchCount,
      roster: schedule.roster,
      rotations: schedule.rotations,
      cellOverrides: schedule.cellOverrides,
      authorUid: schedule.authorUid.isEmpty
          ? (user?.uid ?? '')
          : schedule.authorUid,
      authorDisplayName: schedule.authorDisplayName.isEmpty
          ? (user?.displayName ?? '')
          : schedule.authorDisplayName,
      updatedAt: DateTime.now().toUtc(),
    );
    await _firestore.doc('$collection/${stamped.eventKey}').set(
      <String, dynamic>{
        ...stamped.toJson(),
        'updatedAtTs': Timestamp.fromDate(stamped.updatedAt.toUtc()),
      },
    );
  }

  @override
  Future<void> dispose() async {
    await _sub?.cancel();
    await _controller.close();
  }
}
