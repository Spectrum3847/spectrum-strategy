import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/trait_config.dart';
import '../models/trait_table.dart';
import '../scouting/models/team_analysis.dart';
import '../services/assistant/assistant_backend.dart';
import '../services/assistant/assistant_service.dart';
import '../services/assistant/trait_draft.dart';
import '../services/trait_table_sync_service.dart';
import 'failed_write_tracker.dart';

class TraitTableController extends ChangeNotifier {
  TraitTableController({required this._syncService, this.assistant});

  final TraitTableSyncService _syncService;

  final AssistantService? assistant;

  Future<void> _saveQueue = Future<void>.value();

  final FailedWriteTracker failedWrites = FailedWriteTracker();
  StreamSubscription<TraitTable?>? _tableSub;
  StreamSubscription<TraitConfig>? _configSub;

  String _eventKey = '';
  String _matchId = '';
  TraitTable? _table;
  TraitConfig _config = TraitConfig.defaults;
  bool _loading = false;

  final Map<int, Map<String, String>> _drafts = <int, Map<String, String>>{};

  final Map<int, String> _draftErrors = <int, String>{};

  bool _generatingDrafts = false;

  String get eventKey => _eventKey;
  String get matchId => _matchId;
  TraitConfig get config => _config;

  bool get isLoading => _loading;

  bool get hasMatch => _eventKey.isNotEmpty && _matchId.isNotEmpty;

  bool get canGenerateDrafts => assistant != null;

  bool get isGeneratingDrafts => _generatingDrafts;

  String? draftFor(int teamNumber, String traitKey) =>
      _drafts[teamNumber]?[traitKey];

  String? draftErrorFor(int teamNumber) => _draftErrors[teamNumber];

  Iterable<int> get draftErrorTeams => _draftErrors.keys;

  TraitTable get table =>
      _table ??
      TraitTable(
        id: TraitTable.idFor(_eventKey, _matchId),
        eventKey: _eventKey,
        matchId: _matchId,
        updatedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      );

  Future<void> bootstrap() async {
    _configSub ??= _syncService.configStream.listen((config) {
      _config = config;
      notifyListeners();
    });
    _tableSub ??= _syncService.tableStream.listen((table) {
      if (table != null && table.matchId != _matchId) return;
      _table = table;
      _loading = false;
      notifyListeners();
    });
  }

  Future<void> selectMatch({
    required String eventKey,
    required String matchId,
  }) async {
    if (eventKey == _eventKey && matchId == _matchId) return;
    await _saveQueue;

    _eventKey = eventKey;
    _matchId = matchId;
    _table = null;
    _loading = eventKey.isNotEmpty && matchId.isNotEmpty;

    _drafts.clear();
    _draftErrors.clear();
    notifyListeners();

    await _syncService.watch(eventKey: eventKey, matchId: matchId);
  }

  String valueFor(int teamNumber, String traitKey) =>
      table.valueFor(teamNumber, traitKey);

  Future<void> setCell({
    required int teamNumber,
    required String traitKey,
    required String value,
  }) async {
    if (!hasMatch) return;

    final authorUid = _syncService.currentUserUid ?? '';
    final updated = table.withCell(
      teamNumber: teamNumber,
      traitKey: traitKey,
      value: value,
      updatedAt: DateTime.now().toUtc(),
      authorUid: authorUid,
      authorDisplayName: _syncService.currentUserDisplayName ?? '',
    );
    _table = updated;

    _drafts[teamNumber]?.remove(traitKey);
    notifyListeners();

    if (authorUid.isEmpty) return;

    final snapshot = TraitTable.fromJson(updated.toJson());
    return _enqueue(() => _syncService.push(snapshot));
  }

  Future<void> generateDrafts({
    required List<int> teamNumbers,
    required Map<int, TeamAnalysis> analyses,
    Map<int, List<TeamNote>> notesByTeam = const {},
  }) async {
    if (!hasMatch || _generatingDrafts) return;

    _generatingDrafts = true;
    _draftErrors.clear();
    notifyListeners();

    try {
      final qualitative = _config.traits
          .where((t) => t.source == TraitSource.none)
          .toList();

      for (final teamNumber in teamNumbers) {
        final analysis = analyses[teamNumber];

        for (final trait in _config.traits) {
          if (trait.source == TraitSource.none) continue;
          if (valueFor(teamNumber, trait.key).isNotEmpty) continue;
          final draft = TraitDraft.numericDraft(trait, analysis);
          if (draft == null) continue;
          (_drafts[teamNumber] ??= <String, String>{})[trait.key] = draft;
        }
        notifyListeners();

        final currentAssistant = assistant;
        if (currentAssistant == null ||
            analysis == null ||
            qualitative.isEmpty) {
          continue;
        }
        final pending = qualitative
            .where((t) => valueFor(teamNumber, t.key).isEmpty)
            .toList();
        if (pending.isEmpty) continue;

        final request = TraitDraft.request(
          eventKey: _eventKey,
          matchId: _matchId,
          teamNumber: teamNumber,
          qualitativeTraits: pending,
          analysis: analysis,
          notes: notesByTeam[teamNumber] ?? const <TeamNote>[],
        );
        if (request == null) continue;

        try {
          final summary = await currentAssistant.generate(request);
          final parsed = TraitDraft.parse(summary.text, pending);
          if (parsed.isNotEmpty) {
            final row = _drafts[teamNumber] ??= <String, String>{};
            for (final entry in parsed.entries) {
              if (valueFor(teamNumber, entry.key).isNotEmpty) continue;
              row[entry.key] = entry.value;
            }
          }
        } on AssistantUnavailable catch (error) {
          _draftErrors[teamNumber] = error.reason;
        } catch (error) {
          _draftErrors[teamNumber] = 'Could not reach the assistant: $error';
        }
        notifyListeners();
      }
    } finally {
      _generatingDrafts = false;
      notifyListeners();
    }
  }

  Future<void> acceptDraft({
    required int teamNumber,
    required String traitKey,
  }) {
    final draft = _drafts[teamNumber]?[traitKey];
    if (draft == null) return Future<void>.value();
    return setCell(teamNumber: teamNumber, traitKey: traitKey, value: draft);
  }

  void dismissDraft({required int teamNumber, required String traitKey}) {
    final row = _drafts[teamNumber];
    if (row == null || row.remove(traitKey) == null) return;
    if (row.isEmpty) _drafts.remove(teamNumber);
    notifyListeners();
  }

  Future<void> _enqueue(Future<void> Function() op) {
    _saveQueue = _saveQueue
        .then((_) => op())
        .then((_) {
          if (failedWrites.recordSuccess()) notifyListeners();
        })
        .catchError((Object error) {
          debugPrint('Trait table save failed: $error');
          failedWrites.recordFailure();
          notifyListeners();
        });
    return _saveQueue;
  }

  @override
  void dispose() {
    _tableSub?.cancel();
    _configSub?.cancel();
    super.dispose();
  }
}
