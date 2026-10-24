import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../services/spectrum_auth_service.dart';
import '../models/accuracy_alert.dart';

abstract class AccuracyAlertService {
  Stream<List<AccuracyAlert>> get alertsStream;
  List<AccuracyAlert> get pendingAlerts;
  Future<void> initialize();
  Future<void> acknowledge(String entryId);
  Future<void> dispose();
}

class FirestoreAccuracyAlertService implements AccuracyAlertService {
  FirestoreAccuracyAlertService({
    required this._authService,
    FirebaseFirestore? firestore,
  }) : _firestore = firestore ?? FirebaseFirestore.instance;

  final SpectrumAuthService _authService;
  final FirebaseFirestore _firestore;

  final StreamController<List<AccuracyAlert>> _controller =
      StreamController<List<AccuracyAlert>>.broadcast();

  List<AccuracyAlert> _alerts = const <AccuracyAlert>[];
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
  _firestoreSubscription;
  StreamSubscription<SpectrumAuthSnapshot>? _authSubscription;

  @override
  Stream<List<AccuracyAlert>> get alertsStream => _controller.stream;

  @override
  List<AccuracyAlert> get pendingAlerts =>
      List<AccuracyAlert>.unmodifiable(_alerts);

  @override
  Future<void> initialize() async {
    _authSubscription = _authService.snapshotStream.listen(_onAuthChanged);
    _onAuthChanged(_authService.snapshot);
  }

  void _onAuthChanged(SpectrumAuthSnapshot snapshot) {
    _firestoreSubscription?.cancel();
    _firestoreSubscription = null;

    _alerts = const <AccuracyAlert>[];
    if (snapshot.state == SpectrumAuthState.signedIn && snapshot.user != null) {
      _emit(_alerts);
      _subscribeForUser(snapshot.user!.uid);
    } else {
      _emit(_alerts);
    }
  }

  void _subscribeForUser(String uid) {
    _firestoreSubscription = _firestore
        .collection('accuracyAlerts')
        .where('authorUid', isEqualTo: uid)
        .where('acknowledged', isEqualTo: false)
        .limit(20)
        .snapshots()
        .listen(
          (snapshot) {
            _alerts = snapshot.docs
                .map((doc) {
                  try {
                    return AccuracyAlert.fromJson(doc.data());
                  } catch (_) {
                    return null;
                  }
                })
                .whereType<AccuracyAlert>()
                .toList(growable: false);
            _emit(_alerts);
          },
          onError: (Object error) {
            // ignore: avoid_print
            print('AccuracyAlertService snapshot error: $error');
          },
        );
  }

  @override
  Future<void> acknowledge(String entryId) async {
    try {
      await _firestore.collection('accuracyAlerts').doc(entryId).update(
        <String, dynamic>{'acknowledged': true},
      );
    } on FirebaseException catch (e) {
      if (e.code == 'not-found' || e.code == 'permission-denied') {
        return;
      }
      rethrow;
    }
  }

  @override
  Future<void> dispose() async {
    await _firestoreSubscription?.cancel();
    await _authSubscription?.cancel();
    await _controller.close();
  }

  void _emit(List<AccuracyAlert> alerts) {
    if (!_controller.isClosed) {
      _controller.add(alerts);
    }
  }
}
