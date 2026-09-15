import 'package:uuid/uuid.dart';

import '../theme/strategy_palette.dart';
import 'robot_marker.dart';
import 'strategy_stroke.dart';

const String kLatestFieldId = '2026-rebuilt';

class StrategySession {
  StrategySession.create({String? id, String? latestFieldId, String? eventKey})
    : id = id ?? const Uuid().v4(),
      eventKey = eventKey ?? '',
      eventName = '',
      matchNumber = 1,
      alliance = 'Red',
      teamNumbers = <int>[],
      selectedPhase = StrategyPhase.auton,
      selectedTool = StrategyTool.draw,
      selectedFieldId = latestFieldId ?? kLatestFieldId,
      selectedRobotTeam = null,
      updatedAt = DateTime.now(),
      authorUid = null,
      authorDisplayName = null,
      strokesByPhase = <StrategyPhase, List<StrategyStroke>>{
        for (final phase in StrategyPhase.values) phase: <StrategyStroke>[],
      },
      markersByPhase = <StrategyPhase, List<RobotMarker>>{
        for (final phase in StrategyPhase.values) phase: <RobotMarker>[],
      },
      notesByPhase = <StrategyPhase, String>{
        for (final phase in StrategyPhase.values) phase: '',
      };

  StrategySession.fromJson(Map<String, dynamic> json)
    : id = _asString(json['id'])?.trim().isNotEmpty == true
          ? json['id'] as String
          : const Uuid().v4(),
      eventKey = _asString(json['eventKey']) ?? '',
      eventName = _asString(json['eventName']) ?? '',
      matchNumber = _asInt(json['matchNumber']) ?? 1,
      alliance = _asString(json['alliance']) ?? 'Red',
      teamNumbers =
          (json['teamNumbers'] is List
                  ? json['teamNumbers'] as List<dynamic>
                  : const <dynamic>[])
              .whereType<num>()
              .map((value) => value.toInt())
              .toList(growable: true),
      selectedPhase =
          strategyPhaseByNameOrNull(json['selectedPhase']) ??
          StrategyPhase.auton,
      selectedTool =
          strategyToolByNameOrNull(json['selectedTool']) ?? StrategyTool.draw,
      selectedFieldId = _parseSelectedFieldId(json),
      selectedRobotTeam = _asInt(json['selectedRobotTeam']),
      updatedAt =
          DateTime.tryParse(_asString(json['updatedAt']) ?? '') ??
          DateTime.now(),
      authorUid = _asString(json['authorUid']),
      authorDisplayName = _asString(json['authorDisplayName']),
      strokesByPhase = <StrategyPhase, List<StrategyStroke>>{
        for (final phase in StrategyPhase.values) phase: <StrategyStroke>[],
      },
      markersByPhase = <StrategyPhase, List<RobotMarker>>{
        for (final phase in StrategyPhase.values) phase: <RobotMarker>[],
      },
      notesByPhase = <StrategyPhase, String>{
        for (final phase in StrategyPhase.values) phase: '',
      } {
    final strokes = json['strokesByPhase'];
    if (strokes is Map) {
      for (final entry in strokes.entries) {
        final phase = strategyPhaseByNameOrNull(entry.key);
        final rawList = entry.value;
        if (phase == null || rawList is! List) {
          continue;
        }
        final parsed = <StrategyStroke>[];
        for (final value in rawList) {
          if (value is! Map) {
            continue;
          }
          try {
            parsed.add(StrategyStroke.fromJson(value.cast<String, dynamic>()));
          } catch (_) {}
        }
        strokesByPhase[phase] = parsed;
      }
    }

    final markers = json['markersByPhase'];
    if (markers is Map) {
      for (final entry in markers.entries) {
        final phase = strategyPhaseByNameOrNull(entry.key);
        final rawList = entry.value;
        if (phase == null || rawList is! List) {
          continue;
        }
        final parsed = <RobotMarker>[];
        for (final value in rawList) {
          if (value is! Map) {
            continue;
          }
          try {
            parsed.add(RobotMarker.fromJson(value.cast<String, dynamic>()));
          } catch (_) {}
        }
        markersByPhase[phase] = parsed;
      }
    }

    final notes = json['notesByPhase'];
    if (notes is Map) {
      for (final entry in notes.entries) {
        final phase = strategyPhaseByNameOrNull(entry.key);
        if (phase == null) {
          continue;
        }
        notesByPhase[phase] = _asString(entry.value) ?? '';
      }
    }
  }

  final String id;

  String eventKey;
  String eventName;
  int matchNumber;
  String alliance;
  final List<int> teamNumbers;
  StrategyPhase selectedPhase;
  StrategyTool selectedTool;
  String selectedFieldId;
  int? selectedRobotTeam;
  DateTime updatedAt;
  final String? authorUid;
  final String? authorDisplayName;
  final Map<StrategyPhase, List<StrategyStroke>> strokesByPhase;
  final Map<StrategyPhase, List<RobotMarker>> markersByPhase;
  final Map<StrategyPhase, String> notesByPhase;

  static String? _asString(Object? value) => value is String ? value : null;

  static int? _asInt(Object? value) => value is num ? value.toInt() : null;

  static String _parseSelectedFieldId(Map<String, dynamic> json) {
    final selectedFieldId = _asString(json['selectedFieldId'])?.trim();
    if (selectedFieldId == null || selectedFieldId.isEmpty) {
      return kLatestFieldId;
    }
    return selectedFieldId;
  }

  List<StrategyStroke> strokesFor(StrategyPhase phase) =>
      strokesByPhase[phase] ?? <StrategyStroke>[];
  List<RobotMarker> markersFor(StrategyPhase phase) =>
      markersByPhase[phase] ?? <RobotMarker>[];
  String noteFor(StrategyPhase phase) => notesByPhase[phase] ?? '';

  String get title {
    if (eventName.trim().isEmpty) {
      return 'Match $matchNumber';
    }
    return '$eventName - Match $matchNumber';
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      if (eventKey.isNotEmpty) 'eventKey': eventKey,
      'eventName': eventName,
      'matchNumber': matchNumber,
      'alliance': alliance,
      'teamNumbers': teamNumbers,
      'selectedPhase': selectedPhase.name,
      'selectedTool': selectedTool.name,
      'selectedFieldId': selectedFieldId,
      'selectedRobotTeam': selectedRobotTeam,
      'updatedAt': updatedAt.toIso8601String(),
      if (authorUid != null && authorUid!.isNotEmpty) 'authorUid': authorUid,
      if (authorDisplayName != null && authorDisplayName!.isNotEmpty)
        'authorDisplayName': authorDisplayName,
      'strokesByPhase': {
        for (final entry in strokesByPhase.entries)
          entry.key.name: entry.value.map((value) => value.toJson()).toList(),
      },
      'markersByPhase': {
        for (final entry in markersByPhase.entries)
          entry.key.name: entry.value.map((value) => value.toJson()).toList(),
      },
      'notesByPhase': {
        for (final entry in notesByPhase.entries) entry.key.name: entry.value,
      },
    };
  }
}
