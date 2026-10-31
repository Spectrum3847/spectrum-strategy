import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class ScoutDraft {
  const ScoutDraft({required this.values, this.strokes});

  final Map<String, dynamic> values;

  final Map<String, dynamic>? strokes;
}

class ScoutDraftStore {
  ScoutDraftStore({
    this.debounce = const Duration(milliseconds: 500),
    Future<SharedPreferences> Function()? prefs,
  }) : _prefs = prefs ?? SharedPreferences.getInstance;

  static const storageKey = 'scout_form_draft_v1';

  final Duration debounce;
  final Future<SharedPreferences> Function() _prefs;
  Timer? _timer;
  String? _pendingFormKey;
  ScoutDraft Function()? _pendingSnapshot;

  static String formKeyOf(String formShape) {
    var hash = 0x811c9dc5;
    for (final unit in formShape.codeUnits) {
      hash = ((hash ^ unit) * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16);
  }

  void save(String formKey, ScoutDraft Function() snapshot) {
    _pendingFormKey = formKey;
    _pendingSnapshot = snapshot;
    _timer?.cancel();
    _timer = Timer(debounce, flush);
  }

  Future<void> flush() async {
    _timer?.cancel();
    _timer = null;
    final formKey = _pendingFormKey;
    final snapshot = _pendingSnapshot;
    _pendingFormKey = null;
    _pendingSnapshot = null;
    if (formKey == null || snapshot == null) return;
    try {
      final draft = snapshot();
      final encoded = jsonEncode({
        'formKey': formKey,
        'values': draft.values,
        'strokes': draft.strokes,
      });
      await (await _prefs()).setString(storageKey, encoded);
    } catch (_) {}
  }

  Future<ScoutDraft?> load(String formKey) async {
    try {
      final raw = (await _prefs()).getString(storageKey);
      if (raw == null) return null;
      final json = jsonDecode(raw);
      if (json is! Map || json['formKey'] != formKey) return null;
      final values = json['values'];
      if (values is! Map) return null;
      final strokes = json['strokes'];
      return ScoutDraft(
        values: values.cast<String, dynamic>(),
        strokes: strokes is Map ? strokes.cast<String, dynamic>() : null,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> clear() async {
    _timer?.cancel();
    _timer = null;
    _pendingFormKey = null;
    _pendingSnapshot = null;
    try {
      await (await _prefs()).remove(storageKey);
    } catch (_) {}
  }

  void dispose() {
    unawaited(flush());
  }
}
