import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PendingPushQueue {
  PendingPushQueue({
    this._preferences,
    @visibleForTesting this._debugBeforeWrite,
  });

  final SharedPreferences? _preferences;

  final Future<void> Function()? _debugBeforeWrite;

  final Map<String, Future<void>> _chains = <String, Future<void>>{};

  Future<SharedPreferences> get _prefs async =>
      _preferences ?? SharedPreferences.getInstance();

  Future<Set<String>> pending(String collection) async {
    final prefs = await _prefs;
    return _read(prefs, collection);
  }

  Set<String> _read(SharedPreferences prefs, String collection) {
    final raw = prefs.getString(_key(collection));
    if (raw == null || raw.isEmpty) return <String>{};
    final decoded = jsonDecode(raw);
    if (decoded is List) {
      return decoded.map((e) => e.toString()).toSet();
    }
    return <String>{};
  }

  Future<void> mark(String collection, String id) {
    return _serialized(collection, () async {
      final prefs = await _prefs;
      final ids = _read(prefs, collection);
      if (ids.add(id)) {
        await _write(prefs, collection, ids);
      }
    });
  }

  Future<void> clear(String collection, String id) {
    return _serialized(collection, () async {
      final prefs = await _prefs;
      final ids = _read(prefs, collection);
      if (ids.remove(id)) {
        await _write(prefs, collection, ids);
      }
    });
  }

  Future<int> count(String collection) async {
    final ids = await pending(collection);
    return ids.length;
  }

  Future<void> _write(
    SharedPreferences prefs,
    String collection,
    Set<String> ids,
  ) async {
    if (_debugBeforeWrite != null) await _debugBeforeWrite();
    final encoded = jsonEncode(ids.toList());

    for (var attempt = 0; attempt < 3; attempt++) {
      if (attempt > 0) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      if (await prefs.setString(_key(collection), encoded)) return;
    }
    debugPrint(
      'PendingPushQueue: failed to persist the retry set for $collection',
    );
  }

  Future<void> _serialized(String collection, Future<void> Function() action) {
    final prior = _chains[collection] ?? Future<void>.value();
    final result = prior.then((_) => action());
    _chains[collection] = result.catchError((_) {});
    return result;
  }

  static String _key(String collection) => 'pending_push_${collection}_v1';
}
