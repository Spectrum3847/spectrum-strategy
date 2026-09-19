import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/trex_assignments.dart';
import '../services/name_list_parse.dart';
import '../services/trex_assignments_sync_service.dart';
import 'failed_write_tracker.dart';

class TRexAssignmentsController extends ChangeNotifier {
  TRexAssignmentsController({required this._syncService, Uuid? uuid})
    : _uuid = uuid ?? const Uuid();

  final TRexAssignmentsSyncService _syncService;
  final Uuid _uuid;

  Future<void> _saveQueue = Future<void>.value();

  final FailedWriteTracker failedWrites = FailedWriteTracker();

  StreamSubscription<TRexAssignments>? _sub;
  TRexAssignments _assignments = TRexAssignments(
    updatedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
  );
  bool _loading = true;

  TRexAssignments get assignments => _assignments;

  bool get isLoading => _loading;

  Future<void> bootstrap() async {
    _sub ??= _syncService.assignmentsStream.listen((assignments) {
      _assignments = assignments;
      _loading = false;
      notifyListeners();
    });
    await _syncService.initialize();
  }

  Future<void> addColumn(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return Future<void>.value();
    return _apply(
      (current) => current.copyWith(
        columns: [
          ...current.columns,
          TRexTraitColumn(key: _uuid.v4(), name: trimmed),
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
      final columns = List<TRexTraitColumn>.of(current.columns);
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

  Future<void> addName(String columnKey, String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return Future<void>.value();
    return _apply(
      (current) => current.copyWith(
        columns: [
          for (final column in current.columns)
            if (column.key == columnKey)
              column.copyWith(names: [...column.names, trimmed])
            else
              column,
        ],
      ),
    );
  }

  Future<void> addNames(String columnKey, List<String> names) {
    final incoming = names
        .map((n) => n.trim())
        .where((n) => n.isNotEmpty)
        .toList(growable: false);
    if (incoming.isEmpty) return Future<void>.value();
    return _apply(
      (current) => current.copyWith(
        columns: [
          for (final column in current.columns)
            if (column.key == columnKey)
              column.copyWith(names: appendNewEntries(column.names, incoming))
            else
              column,
        ],
      ),
    );
  }

  Future<void> renameName(String columnKey, int index, String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return Future<void>.value();
    return _apply(
      (current) => current.copyWith(
        columns: [
          for (final column in current.columns)
            if (column.key == columnKey &&
                index >= 0 &&
                index < column.names.length)
              column.copyWith(
                names: [
                  for (var i = 0; i < column.names.length; i++)
                    i == index ? trimmed : column.names[i],
                ],
              )
            else
              column,
        ],
      ),
    );
  }

  Future<void> removeName(String columnKey, int index) {
    return _apply(
      (current) => current.copyWith(
        columns: [
          for (final column in current.columns)
            if (column.key == columnKey &&
                index >= 0 &&
                index < column.names.length)
              column.copyWith(
                names: [
                  for (var i = 0; i < column.names.length; i++)
                    if (i != index) column.names[i],
                ],
              )
            else
              column,
        ],
      ),
    );
  }

  Future<void> reorderNames(String columnKey, int oldIndex, int newIndex) {
    return _apply((current) {
      final columns = <TRexTraitColumn>[];
      for (final column in current.columns) {
        if (column.key != columnKey) {
          columns.add(column);
          continue;
        }
        final names = List<String>.of(column.names);
        if (oldIndex < 0 ||
            oldIndex >= names.length ||
            newIndex < 0 ||
            newIndex > names.length) {
          columns.add(column);
          continue;
        }
        final moving = names.removeAt(oldIndex);
        final target = newIndex > oldIndex ? newIndex - 1 : newIndex;
        names.insert(target, moving);
        columns.add(column.copyWith(names: names));
      }
      return current.copyWith(columns: columns);
    });
  }

  Future<void> _apply(TRexAssignments Function(TRexAssignments) mutate) {
    final authorUid = _syncService.currentUserUid ?? '';
    final updated = mutate(_assignments).copyWith(
      updatedAt: DateTime.now().toUtc(),
      authorUid: authorUid,
      authorDisplayName: _syncService.currentUserDisplayName ?? '',
    );
    _assignments = updated;
    notifyListeners();

    if (authorUid.isEmpty) return Future<void>.value();

    final snapshot = TRexAssignments.fromJson(updated.toJson());
    return _enqueue(() => _syncService.push(snapshot));
  }

  Future<void> _enqueue(Future<void> Function() op) {
    _saveQueue = _saveQueue
        .then((_) => op())
        .then((_) {
          if (failedWrites.recordSuccess()) notifyListeners();
        })
        .catchError((Object error) {
          debugPrint('T-Rex assignments save failed: $error');
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
