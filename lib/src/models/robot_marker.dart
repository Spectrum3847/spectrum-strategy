import 'strategy_point.dart';
import '../theme/strategy_palette.dart';

class RobotMarker {
  RobotMarker({
    required this.phase,
    required this.position,
    this.teamNumber,
    this.label,
    this.alliance = 'Red',
  });

  final StrategyPhase phase;
  final StrategyPoint position;
  final int? teamNumber;
  final String? label;
  final String alliance;

  String get displayLabel {
    if (teamNumber != null) {
      return 'Team $teamNumber';
    }
    return label ?? 'Robot';
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'phase': phase.name,
      'position': position.toJson(),
      'teamNumber': teamNumber,
      'label': label,
      'alliance': alliance,
    };
  }

  factory RobotMarker.fromJson(Map<String, dynamic> json) {
    final teamNumber = json['teamNumber'];
    final label = json['label'];
    final alliance = json['alliance'];
    return RobotMarker(
      phase: strategyPhaseByNameOrNull(json['phase']) ?? StrategyPhase.auton,
      position: StrategyPoint.fromJson(
        (json['position'] as Map).cast<String, dynamic>(),
      ),
      teamNumber: teamNumber is num ? teamNumber.toInt() : null,
      label: label is String ? label : null,
      alliance: alliance is String ? alliance : 'Red',
    );
  }
}
