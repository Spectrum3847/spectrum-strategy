import 'package:cloud_firestore/cloud_firestore.dart';

import '../../services/spectrum_auth_service.dart';
import '../models/scout_assignment.dart';

abstract class ScoutAssignmentSyncService {
  Stream<List<ScoutAssignment>> watchAll();

  Future<void> upsert(ScoutAssignment assignment);

  Future<void> delete(String id);

  Future<void> dispose();
}

class FirestoreScoutAssignmentSyncService
    implements ScoutAssignmentSyncService {
  FirestoreScoutAssignmentSyncService({
    required this._authService,
    FirebaseFirestore? firestore,
  }) : _firestore = firestore ?? FirebaseFirestore.instance;

  final SpectrumAuthService _authService;
  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection('scoutAssignments');

  @override
  Stream<List<ScoutAssignment>> watchAll() {
    return _collection.snapshots().map((snapshot) {
      final items = snapshot.docs
          .map((doc) {
            try {
              final data = doc.data();
              final assignment = ScoutAssignment.fromJson(data);

              final ts = data['updatedAtTs'];
              if (ts is Timestamp) {
                return assignment.copyWith(updatedAt: ts.toDate().toUtc());
              }
              return assignment;
            } catch (_) {
              return null;
            }
          })
          .whereType<ScoutAssignment>()
          .toList(growable: false);
      return items;
    });
  }

  @override
  Future<void> upsert(ScoutAssignment assignment) async {
    final user = _authService.currentUser;

    final stamped = assignment.copyWith(
      authorUid: assignment.authorUid.isEmpty
          ? (user?.uid ?? '')
          : assignment.authorUid,
      authorDisplayName: assignment.authorDisplayName.isEmpty
          ? (user?.displayName ?? '')
          : assignment.authorDisplayName,
      updatedAt: DateTime.now().toUtc(),
    );
    await _collection.doc(stamped.id).set(<String, dynamic>{
      ...stamped.toJson(),

      'updatedAtTs': Timestamp.fromDate(stamped.updatedAt.toUtc()),
    });
  }

  @override
  Future<void> delete(String id) async {
    await _collection.doc(id).delete();
  }

  @override
  Future<void> dispose() async {}
}
