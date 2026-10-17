import 'dart:async';
import 'dart:convert';

import 'package:spectrumstrategy/src/models/cycle_log.dart';
import 'package:spectrumstrategy/src/services/cycle_log_storage.dart';

class FakeCycleLogStorage implements CycleLogStorage {
  final List<CycleLog> savedLogs = <CycleLog>[];
  final List<String> deletedKeys = <String>[];
  final Map<String, String> _logs = <String, String>{};
  Completer<void>? firstSaveGate;

  Object? failNextSave;

  @override
  Future<List<CycleLog>> loadAll() async {
    return _logs.values
        .map(
          (raw) => CycleLog.fromJson(jsonDecode(raw) as Map<String, dynamic>),
        )
        .toList();
  }

  @override
  Future<void> save(CycleLog log) async {
    final failure = failNextSave;
    if (failure != null) {
      failNextSave = null;
      throw failure;
    }
    savedLogs.add(CycleLog.fromJson(log.toJson()));
    _logs[log.key] = jsonEncode(log.toJson());
    final gate = firstSaveGate;
    if (gate != null) {
      firstSaveGate = null;
      await gate.future;
    }
  }

  @override
  Future<void> delete(String key) async {
    deletedKeys.add(key);
    _logs.remove(key);
  }
}
