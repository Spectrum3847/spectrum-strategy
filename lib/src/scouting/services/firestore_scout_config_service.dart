import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../services/spectrum_auth_service.dart';
import '../models/scout_config.dart';

abstract class ScoutConfigSyncService {
  Stream<ScoutConfig?> get configStream;
  Future<void> initialize();
  Future<void> push(ScoutConfig config);
  Future<void> dispose();
}

class FirestoreScoutConfigSyncService implements ScoutConfigSyncService {
  FirestoreScoutConfigSyncService({
    required this._authService,
    FirebaseFirestore? firestore,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _docId = 'scoutConfig';

  FirestoreScoutConfigSyncService.pit({
    required this._authService,
    FirebaseFirestore? firestore,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _docId = 'pitScoutConfig';

  FirestoreScoutConfigSyncService.prescout({
    required this._authService,
    FirebaseFirestore? firestore,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _docId = 'prescoutConfig';

  final SpectrumAuthService _authService;
  final FirebaseFirestore _firestore;
  final String _docId;

  final StreamController<ScoutConfig?> _configController =
      StreamController<ScoutConfig?>.broadcast();
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _docSubscription;
  StreamSubscription<SpectrumAuthSnapshot>? _authSubscription;

  @override
  Stream<ScoutConfig?> get configStream => _configController.stream;

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
        try {
          _emit(_decode(snap.data()!));
        } catch (e, st) {
          debugPrint('Failed to decode Firestore scout config: $e\n$st');
        }
      },
      onError: (Object error) {
        debugPrint('Scout config sync error: $error');
      },
    );
  }

  @override
  Future<void> push(ScoutConfig config) async {
    await _doc().set(_encode(config));
  }

  @override
  Future<void> dispose() async {
    await _docSubscription?.cancel();
    await _authSubscription?.cancel();
    await _configController.close();
  }

  DocumentReference<Map<String, dynamic>> _doc() {
    return _firestore.collection('appConfig').doc(_docId);
  }

  static Map<String, dynamic> _encode(ScoutConfig config) {
    return {
      'configJson': jsonEncode(config.toJson()),
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    };
  }

  static ScoutConfig _decode(Map<String, dynamic> data) {
    final raw = data['configJson'];
    if (raw is! String) throw const FormatException('Missing configJson field');
    return ScoutConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  void _emit(ScoutConfig? config) {
    if (!_configController.isClosed) {
      _configController.add(config);
    }
  }
}
