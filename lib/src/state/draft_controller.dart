import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/draft_board.dart';

class DraftController extends ChangeNotifier {
  String _eventKey = '';
  List<DraftAction> _actions = const <DraftAction>[];

  List<DraftAction> get actions => _actions;
  bool get canUndo => _actions.isNotEmpty;

  static String _prefsKey(String eventKey) => 'draft_actions_v1_$eventKey';

  Future<void> load(String eventKey) async {
    if (eventKey == _eventKey) return;
    _eventKey = eventKey;
    _actions = const <DraftAction>[];
    notifyListeners();
    if (eventKey.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    if (_eventKey != eventKey) return;
    _actions = _decode(prefs.getString(_prefsKey(eventKey)));
    notifyListeners();
  }

  Future<void> pick(int team) => _append(DraftAction.pick(team));

  Future<void> decline(int team) => _append(DraftAction.decline(team));

  Future<void> undo() async {
    if (_actions.isEmpty) return;
    await _set(_actions.sublist(0, _actions.length - 1));
  }

  Future<void> reset() => _set(const <DraftAction>[]);

  Future<void> restore(List<DraftAction> actions) => _set(actions);

  Future<void> _append(DraftAction action) =>
      _set(<DraftAction>[..._actions, action]);

  Future<void> _set(List<DraftAction> next) async {
    _actions = List<DraftAction>.unmodifiable(next);
    notifyListeners();
    if (_eventKey.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsKey(_eventKey),
      jsonEncode(<Map<String, dynamic>>[for (final a in next) a.toJson()]),
    );
  }

  static List<DraftAction> _decode(String? raw) {
    if (raw == null) return const <DraftAction>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const <DraftAction>[];
      return <DraftAction>[
        for (final item in decoded) ?DraftAction.tryFromJson(item),
      ];
    } on FormatException {
      return const <DraftAction>[];
    }
  }
}
