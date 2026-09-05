import 'dart:async';

import 'package:flutter/material.dart';

import '../models/robot_marker.dart';
import '../models/strategy_point.dart';
import '../models/strategy_session.dart';
import '../models/strategy_stroke.dart';
import '../services/match_directory.dart';
import '../services/strategy_board_sync_service.dart';
import '../services/team_loader.dart';
import '../theme/strategy_palette.dart';
import 'failed_write_tracker.dart';

class StrategyController extends ChangeNotifier with WidgetsBindingObserver {
  StrategyController({
    MatchDirectory? directory,
    this._latestFieldIdLoader,
    this._syncService,
  }) : _directory = directory ?? SharedPreferencesMatchDirectory();

  final MatchDirectory _directory;

  final Future<String> Function()? _latestFieldIdLoader;
  String _latestFieldId = kLatestFieldId;

  final StrategyBoardSyncService? _syncService;

  Future<void>? _bootstrapFuture;
  Future<void> _saveQueue = Future<void>.value();

  final FailedWriteTracker failedWrites = FailedWriteTracker();
  StrategySession _session = StrategySession.create();
  bool _ready = false;
  bool _lifecycleObserverRegistered = false;
  StrategyStroke? _activeStroke;

  StreamSubscription<List<StrategySession>>? _remoteSubscription;
  StreamSubscription<StrategyBoardSyncStatus>? _statusSubscription;
  StrategyBoardSyncStatus _syncStatus = const StrategyBoardSyncStatus(
    state: StrategyBoardSyncState.signedOut,
  );
  List<StrategySession> _remoteBoards = <StrategySession>[];
  List<StrategySession> _remotePending = <StrategySession>[];

  final Map<String, ({Timer timer, StrategySession snapshot})> _pendingUploads =
      {};
  Future<void>? _remoteWriteQueue;
  static const _syncDebounce = Duration(milliseconds: 500);

  final Map<String, ({Timer timer, StrategySession snapshot})>
  _pendingLocalSaves = {};
  static const _localSaveDebounce = Duration(milliseconds: 500);

  StrategySession get session => _session;
  bool get isReady => _ready;
  StrategyBoardSyncStatus get syncStatus => _syncStatus;
  List<StrategySession> get remoteBoards =>
      List<StrategySession>.unmodifiable(_remoteBoards);

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
    final loader = _latestFieldIdLoader;
    if (loader != null) {
      try {
        final resolved = (await loader()).trim();
        if (resolved.isNotEmpty) {
          _latestFieldId = resolved;
        }
      } catch (_) {}
    }

    final activeId = await _directory.getActiveMatchId();
    StrategySession? loaded;
    if (activeId != null) {
      loaded = await _directory.loadMatch(activeId);
    }

    if (loaded == null) {
      final matches = await _directory.listMatches();
      if (matches.isNotEmpty) {
        loaded = await _directory.loadMatch(matches.first.id);
      }
      loaded ??= StrategySession.create(latestFieldId: _latestFieldId);
      await _directory.saveMatch(loaded);
      await _directory.setActiveMatchId(loaded.id);
    }

    _session = loaded;
    _activeStroke = null;
    _ready = true;
    notifyListeners();

    if (!_lifecycleObserverRegistered) {
      try {
        WidgetsBinding.instance.addObserver(this);
        _lifecycleObserverRegistered = true;
      } catch (_) {}
    }

    final sync = _syncService;
    if (sync != null) {
      _statusSubscription = sync.statusStream.listen((status) {
        _syncStatus = status;
        notifyListeners();
      });
      _remoteSubscription = sync.remoteBoardsStream.listen((boards) {
        for (final pending in _remotePending) {
          final idx = boards.indexWhere((b) => b.id == pending.id);
          if (idx < 0) {
            boards = [...boards, pending];
          }
        }
        _remotePending.clear();
        _remoteBoards = boards;
        notifyListeners();
      });
      _syncStatus = sync.status;
      try {
        await sync.initialize();
      } catch (_) {}
    }
  }

  Future<List<MatchSummary>> listMatches() => _directory.listMatches();

  Future<StrategySession> createMatch({
    String? eventName,
    String? eventKey,
    int? matchNumber,
    String alliance = 'Red',
  }) async {
    await _flushLocalSave(_session.id);

    final created = StrategySession.create(latestFieldId: _latestFieldId);
    if (eventName != null) {
      created.eventName = eventName.trim();
    }
    if (eventKey != null) {
      created.eventKey = eventKey.trim();
    }
    if (matchNumber != null && matchNumber >= 1) {
      created.matchNumber = matchNumber;
    }
    created.alliance = alliance;
    created.updatedAt = DateTime.now();

    await _enqueueDirectoryWrite(() async {
      await _directory.saveMatch(created);
      await _directory.setActiveMatchId(created.id);
    });

    final snapshot = StrategySession.fromJson(created.toJson());
    _enqueueRemoteWrite(() => _pushToFirestore(snapshot));

    _session = created;
    _activeStroke = null;
    notifyListeners();
    return created;
  }

  Future<void> openMatch(String id) async {
    if (id == _session.id) {
      return;
    }

    await _flushLocalSave(_session.id);

    final loaded = await _directory.loadMatch(id);
    if (loaded == null) {
      return;
    }

    await _enqueueDirectoryWrite(() => _directory.setActiveMatchId(loaded.id));
    _session = loaded;
    _activeStroke = null;
    notifyListeners();
  }

  Future<void> deleteMatch(String id) async {
    _pendingLocalSaves.remove(id)?.timer.cancel();

    await _enqueueDirectoryWrite(() => _directory.deleteMatch(id));
    _pendingUploads.remove(id)?.timer.cancel();
    final sync = _syncService;
    if (sync != null) {
      _enqueueRemoteWrite(() => sync.delete(StrategySession.create(id: id)));
    }

    if (_session.id != id) {
      notifyListeners();
      return;
    }

    final remaining = await _directory.listMatches();
    if (remaining.isNotEmpty) {
      final next = await _directory.loadMatch(remaining.first.id);
      if (next != null) {
        await _enqueueDirectoryWrite(
          () => _directory.setActiveMatchId(next.id),
        );
        _session = next;
        _activeStroke = null;
        notifyListeners();
        return;
      }
    }

    final fresh = StrategySession.create(latestFieldId: _latestFieldId);
    await _enqueueDirectoryWrite(() async {
      await _directory.saveMatch(fresh);
      await _directory.setActiveMatchId(fresh.id);
    });
    _session = fresh;
    _activeStroke = null;
    notifyListeners();
  }

  void setEventName(String value) {
    _session.eventName = value.trim();
    _touch(persist: true);
  }

  void setEventKey(String value) {
    final trimmed = value.trim();
    if (_session.eventKey == trimmed) return;
    _session.eventKey = trimmed;
    _touch(persist: true);
  }

  void setMatchNumber(String value) {
    final parsed = int.tryParse(value.trim());
    if (parsed == null || parsed < 1) {
      return;
    }
    _session.matchNumber = parsed;
    _touch(persist: true);
  }

  void setAlliance(String alliance) {
    _session.alliance = alliance;
    _touch(persist: true);
  }

  void selectPhase(StrategyPhase phase) {
    _session.selectedPhase = phase;

    _activeStroke = null;
    _touch(persist: false);
  }

  void selectTool(StrategyTool tool) {
    _session.selectedTool = tool;
    if (tool != StrategyTool.draw) {
      _activeStroke = null;
    }
    _touch(persist: false);
  }

  void setSelectedRobotTeam(int? teamNumber) {
    _session.selectedRobotTeam = teamNumber;
    _touch(persist: true);
  }

  void selectField(String fieldId) {
    final trimmed = fieldId.trim();
    if (trimmed.isEmpty || _session.selectedFieldId == trimmed) {
      return;
    }
    _session.selectedFieldId = trimmed;
    _touch(persist: true);
  }

  void importTeams(Iterable<int> teams) {
    final deduped = teams.toSet().toList()..sort();
    _session.teamNumbers
      ..clear()
      ..addAll(deduped);
    if (_session.selectedRobotTeam != null &&
        !_session.teamNumbers.contains(_session.selectedRobotTeam)) {
      _session.selectedRobotTeam = _session.teamNumbers.isEmpty
          ? null
          : _session.teamNumbers.first;
    }
    _touch(persist: true);
  }

  void loadTeamsFromText(String text) {
    importTeams(TeamLoader.parseTeamNumbers(text));
  }

  void addTeam(int teamNumber) {
    if (_session.teamNumbers.contains(teamNumber)) {
      return;
    }
    _session.teamNumbers.add(teamNumber);
    _session.teamNumbers.sort();
    _touch(persist: true);
  }

  void removeTeam(int teamNumber) {
    _session.teamNumbers.remove(teamNumber);
    if (_session.selectedRobotTeam == teamNumber) {
      _session.selectedRobotTeam = _session.teamNumbers.isEmpty
          ? null
          : _session.teamNumbers.first;
    }
    _touch(persist: true);
  }

  void clearTeams() {
    _session.teamNumbers.clear();
    _session.selectedRobotTeam = null;
    _touch(persist: true);
  }

  void updateNote(String note) {
    _session.notesByPhase[_session.selectedPhase] = note;
    _touch(persist: true);
  }

  void startStroke(StrategyPoint point) {
    if (_session.selectedTool != StrategyTool.draw) {
      return;
    }
    final phase = _session.selectedPhase;
    final stroke = StrategyStroke(
      phase: phase,
      points: <StrategyPoint>[point],

      colorValue: StrategyPalette.auton.toARGB32(),
    );
    _session.strokesByPhase[phase]!.add(stroke);
    _activeStroke = stroke;
    notifyListeners();
  }

  void extendStroke(StrategyPoint point) {
    if (_session.selectedTool != StrategyTool.draw || _activeStroke == null) {
      return;
    }
    final points = _activeStroke!.points;
    if (points.isNotEmpty &&
        points.last.x == point.x &&
        points.last.y == point.y) {
      return;
    }
    points.add(point);
    notifyListeners();
  }

  void finishStroke() {
    if (_activeStroke == null) {
      return;
    }
    _activeStroke = null;
    _touch(persist: true);
  }

  Set<int> teamsPlacedInPhase(StrategyPhase phase) => _session
      .markersByPhase[phase]!
      .map((marker) => marker.teamNumber)
      .whereType<int>()
      .toSet();

  List<int> teamsAvailableInPhase(StrategyPhase phase) {
    final placed = teamsPlacedInPhase(phase);
    return _session.teamNumbers
        .where((team) => !placed.contains(team))
        .toList(growable: false);
  }

  void placeRobot(StrategyPoint point) {
    if (_session.selectedTool != StrategyTool.robot) {
      return;
    }
    final team = _session.selectedRobotTeam;

    if (team != null &&
        teamsPlacedInPhase(_session.selectedPhase).contains(team)) {
      return;
    }
    final marker = RobotMarker(
      phase: _session.selectedPhase,
      position: point,
      teamNumber: team,
      alliance: _session.alliance,
    );
    _session.markersByPhase[_session.selectedPhase]!.add(marker);

    _draggingMarker = marker;

    if (team != null) {
      final placed = teamsPlacedInPhase(_session.selectedPhase);
      int? next;
      for (final candidate in _session.teamNumbers) {
        if (!placed.contains(candidate)) {
          next = candidate;
          break;
        }
      }
      _session.selectedRobotTeam = next;
    }
    _touch(persist: true);
  }

  static const double _markerHitHalfExtent = 20.0;
  static const double _strokeHitTolerance = 16.0;

  RobotMarker? _draggingMarker;

  bool startMarkerDragAt(Offset position, Size size) {
    if (_session.selectedTool != StrategyTool.robot) {
      return false;
    }
    final markers = _session.markersByPhase[_session.selectedPhase]!;
    for (var i = markers.length - 1; i >= 0; i--) {
      final center = markers[i].position.toOffset(size);
      if ((position.dx - center.dx).abs() <= _markerHitHalfExtent &&
          (position.dy - center.dy).abs() <= _markerHitHalfExtent) {
        _draggingMarker = markers[i];
        return true;
      }
    }
    return false;
  }

  void updateMarkerDrag(StrategyPoint point) {
    final dragging = _draggingMarker;
    if (dragging == null) {
      return;
    }
    final markers = _session.markersByPhase[_session.selectedPhase]!;
    final index = markers.indexOf(dragging);
    if (index < 0) {
      _draggingMarker = null;
      return;
    }
    final moved = RobotMarker(
      phase: dragging.phase,
      position: point,
      teamNumber: dragging.teamNumber,
      label: dragging.label,
      alliance: dragging.alliance,
    );
    markers[index] = moved;
    _draggingMarker = moved;
    notifyListeners();
  }

  void finishMarkerDrag() {
    if (_draggingMarker == null) {
      return;
    }
    _draggingMarker = null;
    _touch(persist: true);
  }

  bool eraseAt(Offset position, Size size) {
    if (_session.selectedTool != StrategyTool.delete) {
      return false;
    }

    final phase = _session.selectedPhase;
    final markers = _session.markersByPhase[phase]!;
    for (var i = markers.length - 1; i >= 0; i--) {
      final center = markers[i].position.toOffset(size);
      if ((position.dx - center.dx).abs() <= _markerHitHalfExtent &&
          (position.dy - center.dy).abs() <= _markerHitHalfExtent) {
        markers.removeAt(i);
        _touch(persist: true);
        return true;
      }
    }

    final strokes = _session.strokesByPhase[phase]!;
    for (var i = strokes.length - 1; i >= 0; i--) {
      if (_strokeHitsPoint(strokes[i], position, size)) {
        strokes.removeAt(i);
        _touch(persist: true);
        return true;
      }
    }
    return false;
  }

  bool _strokeHitsPoint(StrategyStroke stroke, Offset position, Size size) {
    final points = stroke.points;
    if (points.isEmpty) {
      return false;
    }
    var previous = points.first.toOffset(size);
    if (points.length == 1) {
      return (position - previous).distance <= _strokeHitTolerance;
    }
    for (final point in points.skip(1)) {
      final next = point.toOffset(size);
      if (_distanceToSegment(position, previous, next) <= _strokeHitTolerance) {
        return true;
      }
      previous = next;
    }
    return false;
  }

  static double _distanceToSegment(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final lengthSquared = ab.dx * ab.dx + ab.dy * ab.dy;
    if (lengthSquared == 0) {
      return (p - a).distance;
    }
    final ap = p - a;
    final t = ((ap.dx * ab.dx + ap.dy * ab.dy) / lengthSquared).clamp(0.0, 1.0);
    final closest = a + ab * t;
    return (p - closest).distance;
  }

  void autoPlaceTeams() {
    final phase = _session.selectedPhase;
    final teams = _session.teamNumbers;
    if (teams.isEmpty) return;

    _session.markersByPhase[phase]!.clear();

    final isRed = _session.alliance == 'Red';
    final allianceX = isRed ? 0.125 : 0.875;
    final oppositeX = isRed ? 0.875 : 0.125;
    const yPositions = [0.2, 0.5, 0.8];

    for (var i = 0; i < teams.length && i < 6; i++) {
      final x = i < 3 ? allianceX : oppositeX;
      final alliance = i < 3 ? _session.alliance : (isRed ? 'Blue' : 'Red');
      _session.markersByPhase[phase]!.add(
        RobotMarker(
          phase: phase,
          position: StrategyPoint(x, yPositions[i % 3]),
          teamNumber: teams[i],
          alliance: alliance,
        ),
      );
    }
    _touch(persist: true);
  }

  void clearSelectedPhase() {
    _activeStroke = null;
    _session.strokesByPhase[_session.selectedPhase]!.clear();
    _session.markersByPhase[_session.selectedPhase]!.clear();
    _session.notesByPhase[_session.selectedPhase] = '';

    _touch(persist: true);
  }

  void clearAll() {
    _activeStroke = null;
    for (final phase in StrategyPhase.values) {
      _session.strokesByPhase[phase]!.clear();
      _session.markersByPhase[phase]!.clear();
      _session.notesByPhase[phase] = '';
    }
    _touch(persist: true);
  }

  StrategySession captureSnapshot() =>
      StrategySession.fromJson(_session.toJson());

  void restoreSnapshot(StrategySession snapshot) {
    if (snapshot.id != _session.id) {
      return;
    }
    _activeStroke = null;
    _session = StrategySession.fromJson(snapshot.toJson());
    _touch(persist: true);
  }

  Future<void> saveNow() async {
    final boardId = _session.id;
    _pendingUploads.remove(boardId)?.timer.cancel();
    _pendingLocalSaves.remove(boardId)?.timer.cancel();
    final snapshot = StrategySession.fromJson(_session.toJson());
    await _enqueueDirectoryWrite(() => _directory.saveMatch(snapshot));
    _enqueueRemoteWrite(() => _pushToFirestore(snapshot));
  }

  void _touch({required bool persist}) {
    _session.updatedAt = DateTime.now();
    if (persist) {
      final boardId = _session.id;
      final snapshot = StrategySession.fromJson(_session.toJson());

      _pendingLocalSaves[boardId]?.timer.cancel();
      _pendingLocalSaves[boardId] = (
        timer: Timer(_localSaveDebounce, () {
          _pendingLocalSaves.remove(boardId);
          _enqueueDirectoryWrite(() => _directory.saveMatch(snapshot));
        }),
        snapshot: snapshot,
      );

      _pendingUploads[boardId]?.timer.cancel();
      _pendingUploads[boardId] = (
        timer: Timer(_syncDebounce, () {
          _pendingUploads.remove(boardId);
          _enqueueRemoteWrite(() => _pushToFirestore(snapshot));
        }),
        snapshot: snapshot,
      );
    }
    notifyListeners();
  }

  Future<void> _flushLocalSave(String boardId) {
    final pending = _pendingLocalSaves.remove(boardId);
    if (pending == null) {
      return _saveQueue;
    }
    pending.timer.cancel();
    return _enqueueDirectoryWrite(() => _directory.saveMatch(pending.snapshot));
  }

  Future<void> _enqueueDirectoryWrite(Future<void> Function() op) {
    _saveQueue = _saveQueue
        .then((_) => op())
        .then((_) {
          if (failedWrites.recordSuccess()) notifyListeners();
        })
        .catchError((Object e) {
          debugPrint('Strategy save failed: $e');
          failedWrites.recordFailure();
          notifyListeners();
        });
    return _saveQueue;
  }

  Future<void> _enqueueRemoteWrite(Future<void> Function() op) {
    _remoteWriteQueue = (_remoteWriteQueue ?? Future<void>.value())
        .then((_) => op())
        .catchError((Object e) {
          debugPrint('Strategy remote write failed: $e');
        });
    return _remoteWriteQueue!;
  }

  Future<void> _pushToFirestore(StrategySession snapshot) async {
    final sync = _syncService;
    if (sync == null) {
      return;
    }
    try {
      await sync.push(snapshot);
    } catch (e) {
      debugPrint('Strategy board push failed: $e');
    }
  }

  Future<void> openRemoteBoard(String id) async {
    if (id == _session.id) {
      return;
    }
    final found = _remoteBoards.where((b) => b.id == id);
    if (found.isEmpty) {
      return;
    }
    final board = found.first;

    await _flushLocalSave(_session.id);
    final copy = StrategySession.fromJson(board.toJson());
    copy.updatedAt = DateTime.now();
    await _enqueueDirectoryWrite(() async {
      await _directory.saveMatch(copy);
      await _directory.setActiveMatchId(copy.id);
    });

    _remotePending = [..._remotePending.where((b) => b.id != id), copy];
    _session = copy;
    _activeStroke = null;
    notifyListeners();
  }

  Future<void> syncNow() async => _syncService?.syncNow();

  void _flushAllPendingLocalSaves() {
    final pendingSaves = _pendingLocalSaves.values.toList();
    _pendingLocalSaves.clear();
    for (final save in pendingSaves) {
      save.timer.cancel();
      _enqueueDirectoryWrite(() => _directory.saveMatch(save.snapshot));
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _flushAllPendingLocalSaves();
    }
  }

  @override
  void dispose() {
    _flushAllPendingLocalSaves();
    final pending = _pendingUploads.values.toList();
    _pendingUploads.clear();
    for (final upload in pending) {
      upload.timer.cancel();
      _enqueueRemoteWrite(() => _pushToFirestore(upload.snapshot));
    }
    _remoteSubscription?.cancel();
    _statusSubscription?.cancel();
    if (_lifecycleObserverRegistered) {
      try {
        WidgetsBinding.instance.removeObserver(this);
      } catch (_) {}
    }
    final sync = _syncService;
    if (sync != null) {
      (_remoteWriteQueue ?? Future<void>.value()).whenComplete(sync.dispose);
    }
    super.dispose();
  }
}
