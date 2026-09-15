import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/playoff_board.dart';

abstract class PlayoffBoardStorage {
  Future<Map<String, PlayoffBoard>> loadAll();

  Future<void> save(String eventKey, PlayoffBoard board);
}

class SharedPreferencesPlayoffBoardStorage implements PlayoffBoardStorage {
  SharedPreferencesPlayoffBoardStorage({this.preferences});

  static const String _key = 'playoff_boards_v1';

  final SharedPreferences? preferences;

  Future<SharedPreferences> get _prefs async =>
      preferences ?? SharedPreferences.getInstance();

  Future<Map<String, dynamic>> _read(SharedPreferences prefs) async {
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return <String, dynamic>{};
    final decoded = jsonDecode(raw);
    return decoded is Map
        ? decoded.cast<String, dynamic>()
        : <String, dynamic>{};
  }

  @override
  Future<Map<String, PlayoffBoard>> loadAll() async {
    final prefs = await _prefs;
    final map = await _read(prefs);
    final boards = <String, PlayoffBoard>{};
    for (final entry in map.entries) {
      final value = entry.value;
      if (value is! Map) continue;
      try {
        boards[entry.key] = PlayoffBoard.fromJson(
          value.cast<String, dynamic>(),
        );
      } catch (_) {}
    }
    return boards;
  }

  @override
  Future<void> save(String eventKey, PlayoffBoard board) async {
    final prefs = await _prefs;
    final map = await _read(prefs);
    map[eventKey] = board.toJson();
    await prefs.setString(_key, jsonEncode(map));
  }
}
