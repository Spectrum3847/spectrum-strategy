import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/trex_team_list.dart';
import 'spectrum_auth_service.dart';

abstract class TRexTeamListSyncService {
  Stream<TRexTeamList> get teamListStream;

  String? get currentUserUid;
  String? get currentUserDisplayName;

  Future<void> initialize();

  Future<void> push(TRexTeamList teamList);

  Future<void> dispose();
}

class FirestoreTRexTeamListSyncService implements TRexTeamListSyncService {
  FirestoreTRexTeamListSyncService({
    required this._authService,
    FirebaseFirestore? firestore,
  }) : _firestore = firestore ?? FirebaseFirestore.instance;

  static const String docPath = 'appConfig/trexTeamList';

  final SpectrumAuthService _authService;
  final FirebaseFirestore _firestore;

  final StreamController<TRexTeamList> _controller =
      StreamController<TRexTeamList>.broadcast();
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _docSub;
  StreamSubscription<SpectrumAuthSnapshot>? _authSub;

  @override
  Stream<TRexTeamList> get teamListStream => _controller.stream;

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
      _emit(TRexTeamList(updatedAt: _epoch));
    }
  }

  void _subscribe() {
    _docSub?.cancel();
    _docSub = _firestore
        .doc(docPath)
        .snapshots()
        .listen(
          (snapshot) => _emit(TRexTeamList.fromJson(snapshot.data())),

          onError: (Object _) => _emit(TRexTeamList(updatedAt: _epoch)),
        );
  }

  @override
  Future<void> push(TRexTeamList teamList) async {
    final payload = teamList.toJson()
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

  void _emit(TRexTeamList teamList) {
    if (!_controller.isClosed) _controller.add(teamList);
  }
}
