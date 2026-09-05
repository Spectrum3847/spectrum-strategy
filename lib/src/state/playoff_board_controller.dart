import 'package:flutter/foundation.dart';

import '../models/playoff_board.dart';
import '../services/playoff_board_storage.dart';

class PlayoffBoardController extends ChangeNotifier {
  PlayoffBoardController({required this.storage});

  final PlayoffBoardStorage storage;

  final Map<String, PlayoffBoard> _boards = <String, PlayoffBoard>{};
  Future<void> _saveQueue = Future<void>.value();
  Future<void>? _bootstrapFuture;

  Future<void> bootstrap() => _bootstrapFuture ??= _bootstrap();

  Future<void> _bootstrap() async {
    _boards.addAll(await storage.loadAll());
    notifyListeners();
  }

  PlayoffBoard boardFor(String eventKey) =>
      _boards[eventKey] ?? const PlayoffBoard();

  void setMeetingCell(String eventKey, int row, int column, String value) =>
      _update(eventKey, (board) => board.withMeetingCell(row, column, value));

  void setAllianceCell(String eventKey, int row, int column, String value) =>
      _update(eventKey, (board) => board.withAllianceCell(row, column, value));

  void setColumnLabel(String eventKey, int column, String label) =>
      _update(eventKey, (board) => board.withColumnLabel(column, label));

  void setMatchInfoOverride(String eventKey, String key, String value) =>
      _update(eventKey, (board) => board.withMatchInfoOverride(key, value));

  void _update(String eventKey, PlayoffBoard Function(PlayoffBoard) change) {
    if (eventKey.isEmpty) return;
    final next = change(boardFor(eventKey));
    _boards[eventKey] = next;
    notifyListeners();
    _enqueueSave(eventKey, next.snapshot());
  }

  void _enqueueSave(String eventKey, PlayoffBoard snapshot) {
    _saveQueue = _saveQueue
        .then((_) => storage.save(eventKey, snapshot))
        .catchError((Object e) {
          debugPrint('Playoff board save failed: $e');
        });
  }

  Future<void> get pendingWrites => _saveQueue;
}
