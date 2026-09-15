import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../../theme/strategy_palette.dart';

const Object _unsetStrokesByPhase = Object();

class ScoutPhaseData {
  const ScoutPhaseData({
    this.score = 0,
    this.penalties = 0,
    this.notes = '',
    Map<String, int>? counters,
  }) : counters = counters ?? const <String, int>{};

  final int score;
  final int penalties;
  final String notes;
  final Map<String, int> counters;

  ScoutPhaseData copyWith({
    int? score,
    int? penalties,
    String? notes,
    Map<String, int>? counters,
  }) {
    return ScoutPhaseData(
      score: score ?? this.score,
      penalties: penalties ?? this.penalties,
      notes: notes ?? this.notes,
      counters: counters ?? this.counters,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'score': score,
      'penalties': penalties,
      'notes': notes,
      'counters': counters,
    };
  }

  factory ScoutPhaseData.fromJson(Map<String, dynamic> json) {
    final rawCounters =
        (json['counters'] as Map?)?.cast<String, dynamic>() ??
        <String, dynamic>{};
    final counters = <String, int>{
      for (final entry in rawCounters.entries)
        entry.key: (entry.value as num?)?.toInt() ?? 0,
    };
    return ScoutPhaseData(
      score: (json['score'] as num?)?.toInt() ?? 0,
      penalties: (json['penalties'] as num?)?.toInt() ?? 0,
      notes: (json['notes'] as String?) ?? '',
      counters: counters,
    );
  }
}

String? allianceFromStationValue(Object? value) {
  if (value is! String) return null;
  final station = value.trim().toUpperCase();
  if (station.length != 2) return null;
  final position = station[1];
  if (position != '1' && position != '2' && position != '3') return null;
  switch (station[0]) {
    case 'R':
      return 'Red';
    case 'B':
      return 'Blue';
    default:
      return null;
  }
}

class ScoutEntry {
  ScoutEntry({
    String? id,
    required this.matchId,
    required this.teamNumber,
    this.alliance = 'Red',
    Map<StrategyPhase, ScoutPhaseData>? byPhase,
    this.notes = '',
    this.authorUid = '',
    this.authorDisplayName = '',
    DateTime? updatedAt,
    DateTime? createdAt,
    Map<String, dynamic>? fieldValues,
    this.tbaMatchKey,
    this.strokesByPhase,
    this.addedManually = false,
  }) : id = id ?? const Uuid().v4(),
       byPhase =
           byPhase ??
           <StrategyPhase, ScoutPhaseData>{
             for (final phase in StrategyPhase.values)
               phase: const ScoutPhaseData(),
           },
       fieldValues = fieldValues ?? const <String, dynamic>{},
       updatedAt = updatedAt ?? DateTime.now().toUtc(),

       createdAt = createdAt ?? updatedAt ?? DateTime.now().toUtc();

  final String id;

  final DateTime createdAt;
  final String matchId;
  final int teamNumber;

  final String alliance;
  final Map<StrategyPhase, ScoutPhaseData> byPhase;

  final Map<String, dynamic> fieldValues;
  final String notes;

  String get effectiveAlliance {
    String? found;
    for (final value in fieldValues.values) {
      final alliance = allianceFromStationValue(value);
      if (alliance == null) continue;
      if (found != null && found != alliance) return this.alliance;
      found ??= alliance;
    }
    return found ?? alliance;
  }

  final String authorUid;

  final String authorDisplayName;
  final DateTime updatedAt;

  final String? tbaMatchKey;

  final Map<String, dynamic>? strokesByPhase;

  final bool addedManually;

  ScoutPhaseData phaseData(StrategyPhase phase) =>
      byPhase[phase] ?? const ScoutPhaseData();

  String get contentSignature {
    final sortedFields = Map<String, dynamic>.fromEntries(
      fieldValues.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
    );
    return jsonEncode(<String, dynamic>{
      'matchId': matchId,
      'tbaMatchKey': tbaMatchKey ?? '',
      'teamNumber': teamNumber,
      'alliance': alliance,
      'notes': notes,
      'fieldValues': sortedFields,
      'byPhase': <String, dynamic>{
        for (final phase in StrategyPhase.values)
          phase.name: phaseData(phase).toJson(),
      },
    });
  }

  ScoutEntry copyWith({
    String? id,
    String? matchId,
    int? teamNumber,
    String? alliance,
    Map<StrategyPhase, ScoutPhaseData>? byPhase,
    Map<String, dynamic>? fieldValues,
    String? notes,
    String? authorUid,
    String? authorDisplayName,
    DateTime? updatedAt,
    DateTime? createdAt,
    String? tbaMatchKey,
    Object? strokesByPhase = _unsetStrokesByPhase,
    bool? addedManually,
  }) {
    return ScoutEntry(
      id: id ?? this.id,
      matchId: matchId ?? this.matchId,
      teamNumber: teamNumber ?? this.teamNumber,
      alliance: alliance ?? this.alliance,
      byPhase: byPhase ?? this.byPhase,
      fieldValues: fieldValues ?? this.fieldValues,
      notes: notes ?? this.notes,
      authorUid: authorUid ?? this.authorUid,
      authorDisplayName: authorDisplayName ?? this.authorDisplayName,
      updatedAt: updatedAt ?? this.updatedAt,
      createdAt: createdAt ?? this.createdAt,
      tbaMatchKey: tbaMatchKey ?? this.tbaMatchKey,
      strokesByPhase: identical(strokesByPhase, _unsetStrokesByPhase)
          ? this.strokesByPhase
          : strokesByPhase as Map<String, dynamic>?,
      addedManually: addedManually ?? this.addedManually,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'matchId': matchId,
      'teamNumber': teamNumber,
      'alliance': alliance,
      'notes': notes,
      'authorUid': authorUid,
      'authorDisplayName': authorDisplayName,
      'updatedAt': updatedAt.toIso8601String(),
      'createdAt': createdAt.toIso8601String(),
      'byPhase': <String, dynamic>{
        for (final entry in byPhase.entries)
          entry.key.name: entry.value.toJson(),
      },
      if (fieldValues.isNotEmpty) 'fieldValues': fieldValues,
      if (tbaMatchKey != null) 'tbaMatchKey': tbaMatchKey,
      if (strokesByPhase != null && strokesByPhase!.isNotEmpty)
        'strokesByPhase': strokesByPhase,
      if (addedManually) 'addedManually': true,
    };
  }

  factory ScoutEntry.fromJson(Map<String, dynamic> json) {
    final rawByPhase =
        (json['byPhase'] as Map?)?.cast<String, dynamic>() ??
        <String, dynamic>{};
    final byPhase = <StrategyPhase, ScoutPhaseData>{
      for (final phase in StrategyPhase.values) phase: const ScoutPhaseData(),
    };
    for (final entry in rawByPhase.entries) {
      try {
        final phase = StrategyPhase.values.byName(entry.key);
        byPhase[phase] = ScoutPhaseData.fromJson(
          (entry.value as Map).cast<String, dynamic>(),
        );
      } catch (_) {}
    }
    final rawFieldValues =
        (json['fieldValues'] as Map?)?.cast<String, dynamic>() ??
        <String, dynamic>{};

    return ScoutEntry(
      id: json['id'] as String?,
      matchId: json['matchId'] as String? ?? '',
      teamNumber: (json['teamNumber'] as num?)?.toInt() ?? 0,
      alliance: (json['alliance'] as String?) ?? 'Red',
      notes: (json['notes'] as String?) ?? '',
      authorUid: (json['authorUid'] as String?) ?? '',
      authorDisplayName: (json['authorDisplayName'] as String?) ?? '',
      updatedAt:
          DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.now().toUtc(),

      createdAt: DateTime.tryParse(
        json['createdAt'] is String ? json['createdAt'] as String : '',
      ),
      byPhase: byPhase,
      fieldValues: rawFieldValues,
      tbaMatchKey: json['tbaMatchKey'] as String?,
      strokesByPhase: (json['strokesByPhase'] as Map?)?.cast<String, dynamic>(),
      addedManually: json['addedManually'] as bool? ?? false,
    );
  }
}
