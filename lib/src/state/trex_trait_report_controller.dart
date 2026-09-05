import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/trex_trait_report.dart';
import '../services/trex_trait_report_storage.dart';
import '../services/trex_trait_report_sync_service.dart';
import 'failed_write_tracker.dart';

class TrexTraitReportController extends ChangeNotifier {
  TrexTraitReportController({
    TrexTraitReportStorage? storage,
    this._syncService,
  }) : _storage = storage ?? SharedPreferencesTrexTraitReportStorage();

  final TrexTraitReportStorage _storage;
  final TrexTraitReportSyncService? _syncService;

  Future<void>? _bootstrapFuture;
  Future<void> _saveQueue = Future<void>.value();
  final Map<String, TrexTraitReport> _reports = <String, TrexTraitReport>{};

  final FailedWriteTracker failedWrites = FailedWriteTracker();
  bool _ready = false;
  String? _lastError;

  StreamSubscription<List<TrexTraitReport>>? _remoteSubscription;
  StreamSubscription<TrexTraitReportSyncStatus>? _statusSubscription;
  TrexTraitReportSyncStatus _syncStatus = const TrexTraitReportSyncStatus(
    state: TrexTraitReportSyncState.signedOut,
  );

  bool get isReady => _ready;
  List<TrexTraitReport> get reports =>
      List<TrexTraitReport>.unmodifiable(_reports.values);
  TrexTraitReportSyncStatus get syncStatus => _syncStatus;

  String? get lastError => _lastError;

  void clearLastError() {
    if (_lastError == null) return;
    _lastError = null;
    notifyListeners();
  }

  Future<void> bootstrap() {
    return _bootstrapFuture ??= _bootstrap().onError<Object>((
      error,
      stackTrace,
    ) {
      _bootstrapFuture = null;
      Error.throwWithStackTrace(error, stackTrace);
    });
  }

  Future<void> _bootstrap() async {
    for (final report in await _storage.loadAll()) {
      _reports[report.id] = report;
    }
    _ready = true;
    notifyListeners();

    final sync = _syncService;
    if (sync == null) return;
    _statusSubscription = sync.statusStream.listen((status) {
      _syncStatus = status;
      notifyListeners();
    });
    _remoteSubscription = sync.remoteReportsStream.listen(_mergeRemote);
    _syncStatus = sync.status;
    try {
      await sync.initialize();
    } catch (_) {}
  }

  List<TrexTraitReport> reportsForTeam(int teamNumber) {
    final matches = _reports.values
        .where((report) => report.teamNumber == teamNumber)
        .toList();
    matches.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return matches;
  }

  Future<bool> submitReport(TrexTraitReport report) async {
    _reports[report.id] = report;
    final snapshot = TrexTraitReport.fromJson(report.toJson());
    final saved = _enqueueSave(snapshot);
    notifyListeners();
    if (!await saved) {
      _reports.remove(report.id);
      _lastError = 'Could not save the report for team ${report.teamNumber}.';
      notifyListeners();
      return false;
    }
    final sync = _syncService;
    if (sync != null) {
      unawaited(sync.push(snapshot));
    }
    return true;
  }

  Future<void> saveNow() async {
    await _saveQueue;
  }

  Future<void> syncNow() async {
    await _syncService?.syncNow();
  }

  void _mergeRemote(List<TrexTraitReport> remote) {
    var changed = false;
    for (final incoming in remote) {
      final existing = _reports[incoming.id];
      if (existing == null || incoming.updatedAt.isAfter(existing.updatedAt)) {
        _reports[incoming.id] = incoming;
        _enqueueSave(incoming);
        changed = true;
      }
    }
    if (changed) notifyListeners();
  }

  Future<bool> _enqueueSave(TrexTraitReport report) {
    final result = _saveQueue
        .then((_) => _storage.saveReport(report))
        .then(
          (_) {
            if (failedWrites.recordSuccess()) notifyListeners();
            return true;
          },
          onError: (Object e) {
            debugPrint('T-Rex trait report save failed: $e');
            failedWrites.recordFailure();
            notifyListeners();
            return false;
          },
        );
    _saveQueue = result;
    return result;
  }

  @override
  void dispose() {
    _remoteSubscription?.cancel();
    _statusSubscription?.cancel();
    _syncService?.dispose();
    super.dispose();
  }
}
