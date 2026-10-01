import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/trex_assignments.dart';
import 'spectrum_auth_service.dart';

abstract class TRexAssignmentsSyncService {
  Stream<TRexAssignments> get assignmentsStream;

  String? get currentUserUid;
  String? get currentUserDisplayName;

  Future<void> initialize();

  Future<void> push(TRexAssignments assignments);

  Future<void> dispose();
}

class FirestoreTRexAssignmentsSyncService
    implements TRexAssignmentsSyncService {
  FirestoreTRexAssignmentsSyncService({
    required this._authService,
    FirebaseFirestore? firestore,
  }) : _firestore = firestore ?? FirebaseFirestore.instance;

  static const String docPath = 'appConfig/trexAssignments';

  final SpectrumAuthService _authService;
  final FirebaseFirestore _firestore;

  final StreamController<TRexAssignments> _controller =
      StreamController<TRexAssignments>.broadcast();
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _docSub;
  StreamSubscription<SpectrumAuthSnapshot>? _authSub;

  @override
  Stream<TRexAssignments> get assignmentsStream => _controller.stream;

  @override
  String? get currentUserUid => _authService.snapshot.user?.uid;

  @override
  String? get currentUserDisplayName => _authService.snapshot.user?.displayName;

  @override
  Future<void> initialize() async {
    _authSub = _authService.snapshotStream.listen(_onAuthChanged);
    _onAuthChanged(_authService.snapshot);
  }

  void _onAuthChanged(SpectrumAuthSnapshot snapshot) {
    if (snapshot.state == SpectrumAuthState.signedIn) {
      _subscribe();
    } else {
      _docSub?.cancel();
      _docSub = null;
      _emit(TRexAssignments(updatedAt: _epoch));
    }
  }

  void _subscribe() {
    _docSub?.cancel();
    _docSub = _firestore
        .doc(docPath)
        .snapshots()
        .listen(
          (snapshot) => _emit(TRexAssignments.fromJson(snapshot.data())),

          onError: (Object _) => _emit(TRexAssignments(updatedAt: _epoch)),
        );
  }

  @override
  Future<void> push(TRexAssignments assignments) async {
    final payload = assignments.toJson()
      ..['updatedAtTs'] = FieldValue.serverTimestamp();
    await _firestore.doc(docPath).set(payload);
  }

  @override
  Future<void> dispose() async {
    await _docSub?.cancel();
    await _authSub?.cancel();
    await _controller.close();
  }

  DateTime get _epoch => DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

  void _emit(TRexAssignments assignments) {
    if (!_controller.isClosed) _controller.add(assignments);
  }
}
