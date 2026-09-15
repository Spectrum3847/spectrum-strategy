import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/trait_config.dart';
import '../models/trait_table.dart';
import 'spectrum_auth_service.dart';

abstract class TraitTableSyncService {
  Stream<TraitTable?> get tableStream;

  Stream<TraitConfig> get configStream;

  String? get currentUserUid;
  String? get currentUserDisplayName;

  Future<void> watch({required String eventKey, required String matchId});

  Future<void> push(TraitTable table);

  Future<void> dispose();
}

class FirestoreTraitTableSyncService implements TraitTableSyncService {
  FirestoreTraitTableSyncService({
    required this._authService,
    FirebaseFirestore? firestore,
  }) : _firestore = firestore ?? FirebaseFirestore.instance;

  static const String collection = 'traitTables';
  static const String configPath = 'appConfig/traitConfig';

  final SpectrumAuthService _authService;
  final FirebaseFirestore _firestore;

  final StreamController<TraitTable?> _tableController =
      StreamController<TraitTable?>.broadcast();
  final StreamController<TraitConfig> _configController =
      StreamController<TraitConfig>.broadcast();

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _tableSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _configSub;

  String _eventKey = '';
  String _matchId = '';
  bool _configWatched = false;

  @override
  Stream<TraitTable?> get tableStream => _tableController.stream;

  @override
  Stream<TraitConfig> get configStream => _configController.stream;

  @override
  String? get currentUserUid => _authService.snapshot.user?.uid;

  @override
  String? get currentUserDisplayName => _authService.snapshot.user?.displayName;

  @override
  Future<void> watch({
    required String eventKey,
    required String matchId,
  }) async {
    _watchConfig();
    if (eventKey == _eventKey && matchId == _matchId && _tableSub != null) {
      return;
    }
    _eventKey = eventKey;
    _matchId = matchId;
    await _tableSub?.cancel();
    _tableSub = null;

    if (eventKey.isEmpty || matchId.isEmpty) {
      _tableController.add(null);
      return;
    }

    _tableSub = _firestore
        .doc('$collection/${TraitTable.idFor(eventKey, matchId)}')
        .snapshots()
        .listen((snapshot) {
          final data = snapshot.data();
          _tableController.add(
            snapshot.exists && data != null ? TraitTable.fromJson(data) : null,
          );
        }, onError: (Object _) => _tableController.add(null));
  }

  void _watchConfig() {
    if (_configWatched) return;
    _configWatched = true;
    _configSub = _firestore
        .doc(configPath)
        .snapshots()
        .listen(
          (snapshot) =>
              _configController.add(TraitConfig.fromJson(snapshot.data())),

          onError: (Object _) => _configController.add(TraitConfig.defaults),
        );
  }

  @override
  Future<void> push(TraitTable table) async {
    final payload = table.toJson()
      ..['updatedAtTs'] = FieldValue.serverTimestamp();
    await _firestore.doc('$collection/${table.id}').set(payload);
  }

  @override
  Future<void> dispose() async {
    await _tableSub?.cancel();
    await _configSub?.cancel();
    await _tableController.close();
    await _configController.close();
  }
}
