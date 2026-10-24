import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/trex_team_list.dart';
import '../services/name_list_parse.dart';
import '../services/trex_team_list_sync_service.dart';
import 'failed_write_tracker.dart';

class TRexTeamListController extends ChangeNotifier {
  TRexTeamListController({required this._syncService, Uuid? uuid})
    : _uuid = uuid ?? const Uuid();

  final TRexTeamListSyncService _syncService;
  final Uuid _uuid;

  Future<void> _saveQueue = Future<void>.value();

  final FailedWriteTracker failedWrites = FailedWriteTracker();

  StreamSubscription<TRexTeamList>? _sub;
  TRexTeamList _teamList = TRexTeamList(
    updatedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
  );
  bool _loading = true;

  TRexTeamList get teamList => _teamList;

  bool get isLoading => _loading;

  Future<void> bootstrap() async {
    _sub ??= _syncService.teamListStream.listen((teamList) {
      _teamList = teamList;
      _loading = false;
      notifyListeners();
    });
    await _syncService.initialize();
  }

  Future<void> setTitle(String title) {
    return _apply((current) => current.copyWith(title: title));
  }

  Future<void> addColumn(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return Future<void>.value();
    return _apply(
      (current) => current.copyWith(
        columns: [
          ...current.columns,
          TRexTeamListColumn(key: _uuid.v4(), name: trimmed),
        ],
      ),
    );
  }

  Future<void> renameColumn(String columnKey, String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return Future<void>.value();
    return _apply(
      (current) => current.copyWith(
        columns: [
          for (final column in current.columns)
            if (column.key == columnKey)
              column.copyWith(name: trimmed)
            else
              column,
        ],
      ),
    );
  }

  Future<void> removeColumn(String columnKey) {
    return _apply(
      (current) => current.copyWith(
        columns: current.columns.where((c) => c.key != columnKey).toList(),
      ),
    );
  }

  Future<void> reorderColumns(int oldIndex, int newIndex) {
    return _apply((current) {
      final columns = List<TRexTeamListColumn>.of(current.columns);
      if (oldIndex < 0 ||
          oldIndex >= columns.length ||
          newIndex < 0 ||
          newIndex > columns.length) {
        return current;
      }
      final moving = columns.removeAt(oldIndex);
      final target = newIndex > oldIndex ? newIndex - 1 : newIndex;
      columns.insert(target, moving);
      return current.copyWith(columns: columns);
    });
  }

  Future<void> addTeam(String columnKey, String team) {
    final trimmed = team.trim();
    if (trimmed.isEmpty) return Future<void>.value();
    return _apply(
      (current) => current.copyWith(
        columns: [
          for (final column in current.columns)
            if (column.key == columnKey)
              column.copyWith(teams: [...column.teams, trimmed])
            else
              column,
        ],
      ),
    );
  }

  Future<void> addTeams(String columnKey, List<String> teams) {
    final incoming = teams
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList(growable: false);
    if (incoming.isEmpty) return Future<void>.value();
    return _apply(
      (current) => current.copyWith(
        columns: [
          for (final column in current.columns)
            if (column.key == columnKey)
              column.copyWith(teams: appendNewEntries(column.teams, incoming))
            else
              column,
        ],
      ),
    );
  }

  Future<void> renameTeam(String columnKey, int index, String team) {
    final trimmed = team.trim();
    if (trimmed.isEmpty) return Future<void>.value();
    return _apply(
      (current) => current.copyWith(
        columns: [
          for (final column in current.columns)
            if (column.key == columnKey &&
                index >= 0 &&
                index < column.teams.length)
              column.copyWith(
                teams: [
                  for (var i = 0; i < column.teams.length; i++)
                    i == index ? trimmed : column.teams[i],
                ],
              )
            else
              column,
        ],
      ),
    );
  }

  Future<void> removeTeam(String columnKey, int index) {
    return _apply(
      (current) => current.copyWith(
        columns: [
          for (final column in current.columns)
            if (column.key == columnKey &&
                index >= 0 &&
                index < column.teams.length)
              column.copyWith(
                teams: [
                  for (var i = 0; i < column.teams.length; i++)
                    if (i != index) column.teams[i],
                ],
              )
            else
              column,
        ],
      ),
    );
  }

  Future<void> reorderTeams(String columnKey, int oldIndex, int newIndex) {
    return _apply((current) {
      final columns = <TRexTeamListColumn>[];
      for (final column in current.columns) {
        if (column.key != columnKey) {
          columns.add(column);
          continue;
        }
        final teams = List<String>.of(column.teams);
        if (oldIndex < 0 ||
            oldIndex >= teams.length ||
            newIndex < 0 ||
            newIndex > teams.length) {
          columns.add(column);
          continue;
        }
        final moving = teams.removeAt(oldIndex);
        final target = newIndex > oldIndex ? newIndex - 1 : newIndex;
        teams.insert(target, moving);
        columns.add(column.copyWith(teams: teams));
      }
      return current.copyWith(columns: columns);
    });
  }

  Future<void> _apply(TRexTeamList Function(TRexTeamList) mutate) {
    final authorUid = _syncService.currentUserUid ?? '';
    final updated = mutate(_teamList).copyWith(
      updatedAt: DateTime.now().toUtc(),
      authorUid: authorUid,
      authorDisplayName: _syncService.currentUserDisplayName ?? '',
    );
    _teamList = updated;
    notifyListeners();

    if (authorUid.isEmpty) return Future<void>.value();

    final snapshot = TRexTeamList.fromJson(updated.toJson());
    return _enqueue(() => _syncService.push(snapshot));
  }

  Future<void> _enqueue(Future<void> Function() op) {
    _saveQueue = _saveQueue
        .then((_) => op())
        .then((_) {
          if (failedWrites.recordSuccess()) notifyListeners();
        })
        .catchError((Object error) {
          debugPrint('T-Rex team list save failed: $error');
          failedWrites.recordFailure();
          notifyListeners();
        });
    return _saveQueue;
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
