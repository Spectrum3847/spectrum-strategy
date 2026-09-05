library;

enum TraitSource {
  none,

  iqmTotalScore,

  phaseScore,

  scoreStdDev,

  avgPenalties,

  matchCount;

  static TraitSource fromName(String? value) {
    for (final source in TraitSource.values) {
      if (source.name == value) return source;
    }
    return TraitSource.none;
  }
}

class TraitDefinition {
  const TraitDefinition({
    required this.key,
    required this.label,
    this.hint = '',
    this.source = TraitSource.none,
    this.phase = '',
  });

  final String key;

  final String label;

  final String hint;

  final TraitSource source;

  final String phase;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'key': key,
    'label': label,
    if (hint.isNotEmpty) 'hint': hint,
    if (source != TraitSource.none) 'source': source.name,
    if (phase.isNotEmpty) 'phase': phase,
  };

  static TraitDefinition? fromJson(Object? json) {
    if (json is! Map) return null;
    final key = json['key'];
    final label = json['label'];
    if (key is! String || key.isEmpty) return null;
    if (label is! String || label.isEmpty) return null;
    return TraitDefinition(
      key: key,
      label: label,
      hint: json['hint'] is String ? json['hint'] as String : '',
      source: TraitSource.fromName(json['source'] as String?),
      phase: json['phase'] is String ? json['phase'] as String : '',
    );
  }
}

class TraitConfig {
  const TraitConfig({required this.traits, this.updatedAt});

  final List<TraitDefinition> traits;
  final DateTime? updatedAt;

  static const defaults = TraitConfig(
    traits: [
      TraitDefinition(
        key: 'teleopScoring',
        label: 'Teleop scoring',
        hint: 'What they put up in a normal match',
        source: TraitSource.phaseScore,
        phase: 'teleop',
      ),
      TraitDefinition(
        key: 'autonScoring',
        label: 'Auton',
        hint: 'What they reliably do in the first 15 seconds',
        source: TraitSource.phaseScore,
        phase: 'auton',
      ),
      TraitDefinition(
        key: 'endgame',
        label: 'Endgame',
        hint: 'Climb, park, or nothing, and how often it works',
        source: TraitSource.phaseScore,
        phase: 'endgame',
      ),
      TraitDefinition(
        key: 'cycleTime',
        label: 'Cycle time',
        hint: 'Seconds per cycle, and whether it holds up under pressure',
      ),
      TraitDefinition(
        key: 'defense',
        label: 'Defense',
        hint: 'Do they play it, and are they any good at it',
      ),
      TraitDefinition(
        key: 'reliability',
        label: 'Reliability',
        hint: 'Do they break, tip, or go dead',
        source: TraitSource.scoreStdDev,
      ),
      TraitDefinition(
        key: 'driverSkill',
        label: 'Driver skill',
        hint: 'How they handle traffic and a bad situation',
      ),
    ],
  );

  bool get isEmpty => traits.isEmpty;

  TraitDefinition? byKey(String key) {
    for (final trait in traits) {
      if (trait.key == key) return trait;
    }
    return null;
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'traits': [for (final trait in traits) trait.toJson()],
    if (updatedAt != null) 'updatedAt': updatedAt!.toUtc().toIso8601String(),
  };

  static TraitConfig fromJson(Map<String, dynamic>? json) {
    if (json == null) return defaults;
    final raw = json['traits'];
    if (raw is! List) return defaults;
    final traits = <TraitDefinition>[];
    final seen = <String>{};
    for (final entry in raw) {
      final trait = TraitDefinition.fromJson(entry);

      if (trait == null || !seen.add(trait.key)) continue;
      traits.add(trait);
    }
    if (traits.isEmpty) return defaults;
    return TraitConfig(
      traits: traits,
      updatedAt: DateTime.tryParse(
        json['updatedAt'] is String ? json['updatedAt'] as String : '',
      )?.toUtc(),
    );
  }
}
