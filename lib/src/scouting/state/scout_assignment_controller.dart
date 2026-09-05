import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/scout_assignment.dart';
import '../services/scout_assignment_sync_service.dart';

class ScoutAssignmentController extends ChangeNotifier {
  ScoutAssignmentController({required this.syncService});

  final ScoutAssignmentSyncService syncService;

  List<ScoutAssignment> _assignments = <ScoutAssignment>[];
  List<ScoutAssignment> get assignments => List.unmodifiable(_assignments);

  bool _loading = true;
  bool get loading => _loading;

  Object? _error;
  Object? get error => _error;

  StreamSubscription<List<ScoutAssignment>>? _sub;

  void start() {
    _sub ??= syncService.watchAll().listen(
      (items) {
        _assignments = items;
        _loading = false;
        _error = null;
        notifyListeners();
      },
      onError: (Object e) {
        _loading = false;
        _error = e;
        notifyListeners();
      },
    );
  }

  List<ScoutAssignment> forMatch(String matchKey) {
    final list = _assignments.where((a) => a.matchKey == matchKey).toList()
      ..sort((a, b) {
        return kAllianceStations
            .indexOf(a.station)
            .compareTo(kAllianceStations.indexOf(b.station));
      });
    return list;
  }

  List<ScoutAssignment> forScouter(String uid) {
    final list = _assignments.where((a) => a.scouterUid == uid).toList()
      ..sort((a, b) => a.matchNumber.compareTo(b.matchNumber));
    return list;
  }

  Future<void> assign({
    required String matchKey,
    required int matchNumber,
    required String station,
    required String scouterUid,
    required String scouterName,
  }) {
    final assignment = ScoutAssignment(
      id: ScoutAssignment.idFor(matchKey, station),
      matchKey: matchKey,
      matchNumber: matchNumber,
      station: station,
      scouterUid: scouterUid,
      scouterName: scouterName,
    );
    return syncService.upsert(assignment);
  }

  Future<void> unassign(String matchKey, String station) {
    return syncService.delete(ScoutAssignment.idFor(matchKey, station));
  }

  @override
  void dispose() {
    _sub?.cancel();
    syncService.dispose();
    super.dispose();
  }
}
