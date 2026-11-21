import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'spectrum_auth_service.dart';

abstract class ActiveEventSyncService {
  Stream<String?> get eventKeyStream;
  Future<void> initialize();
  Future<void> push(String eventKey);
  Future<void> dispose();
}

class FirestoreActiveEventSyncService implements ActiveEventSyncService {
  FirestoreActiveEventSyncService({
    required this._authService,
    FirebaseFirestore? firestore,
  }) : _firestore = firestore ?? FirebaseFirestore.instance;

  final SpectrumAuthService _authService;
  final FirebaseFirestore _firestore;

  final StreamController<String?> _eventKeyController =
      StreamController<String?>.broadcast();
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _docSubscription;
  StreamSubscription<SpectrumAuthSnapshot>? _authSubscription;

  @override
  Stream<String?> get eventKeyStream => _eventKeyController.stream;

  @override
  Future<void> initialize() async {
    _authSubscription = _authService.snapshotStream.listen(_onAuthChanged);
    _onAuthChanged(_authService.snapshot);
  }

  void _onAuthChanged(SpectrumAuthSnapshot snapshot) {
    if (snapshot.state == SpectrumAuthState.signedIn) {
      _subscribe();
    } else {
      _docSubscription?.cancel();
      _docSubscription = null;
    }
  }

  void _subscribe() {
    _docSubscription?.cancel();
    _docSubscription = _doc().snapshots().listen(
      (snap) {
        if (!snap.exists || snap.data() == null) {
          _emit(null);
          return;
        }
        final raw = snap.data()!['eventKey'];
        if (raw is! String) {
          _emit(null);
          return;
        }
        _emit(raw);
      },
      onError: (Object error) {
        debugPrint('Active event sync error: $error');
      },
    );
  }

  @override
  Future<void> push(String eventKey) async {
    await _doc().set({
      'eventKey': eventKey,
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    });
  }

  @override
  Future<void> dispose() async {
    await _docSubscription?.cancel();
    await _authSubscription?.cancel();
    await _eventKeyController.close();
  }

  DocumentReference<Map<String, dynamic>> _doc() {
    return _firestore.collection('appConfig').doc('activeEvent');
  }

  void _emit(String? eventKey) {
    if (!_eventKeyController.isClosed) {
      _eventKeyController.add(eventKey);
    }
  }
}
