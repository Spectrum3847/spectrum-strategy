const List<String> kDefaultPickTierNames = <String>[
  '1st pick',
  '2nd pick',
  'Defense/role',
  'Backup',
];

class PickTier {
  const PickTier({required this.name, this.teams = const <int>[]});

  final String name;
  final List<int> teams;

  PickTier copyWith({String? name, List<int>? teams}) =>
      PickTier(name: name ?? this.name, teams: teams ?? this.teams);

  Map<String, dynamic> toJson() => <String, dynamic>{
    'name': name,
    'teams': teams,
  };

  factory PickTier.fromJson(Map<String, dynamic> json) => PickTier(
    name: (json['name'] as String?) ?? '',
    teams: _teamsFrom(json['teams']),
  );

  @override
  bool operator ==(Object other) =>
      other is PickTier && other.name == name && _sameInts(other.teams, teams);

  @override
  int get hashCode => Object.hash(name, Object.hashAll(teams));
}

class DoNotPick {
  const DoNotPick({required this.team, this.reason = ''});

  final int team;
  final String reason;

  DoNotPick copyWith({String? reason}) =>
      DoNotPick(team: team, reason: reason ?? this.reason);

  Map<String, dynamic> toJson() => <String, dynamic>{
    'team': team,
    'reason': reason,
  };

  static DoNotPick? tryFromJson(Object? raw) {
    if (raw is! Map) return null;
    final team = raw['team'];
    if (team is! num || team < 1 || team > 99999) return null;
    return DoNotPick(
      team: team.toInt(),
      reason: (raw['reason'] as String?) ?? '',
    );
  }

  @override
  bool operator ==(Object other) =>
      other is DoNotPick && other.team == team && other.reason == reason;

  @override
  int get hashCode => Object.hash(team, reason);
}

bool _sameInts(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

List<int> _teamsFrom(Object? raw) => raw is! List
    ? const <int>[]
    : raw
          .whereType<num>()
          .map((e) => e.toInt())
          .where((n) => n >= 1 && n <= 99999)
          .toList(growable: false);

class PickList {
  const PickList({
    required this.id,
    required this.name,
    required this.teamNumbers,
    required this.updatedAt,
    this.authorUid = '',
    this.authorDisplayName = '',
    this.tiers = const <PickTier>[],
    this.dnp = const <DoNotPick>[],
  });

  final String id;
  final String name;
  final List<int> teamNumbers;
  final DateTime updatedAt;
  final String authorUid;
  final String authorDisplayName;

  final List<PickTier> tiers;
  final List<DoNotPick> dnp;

  ({List<PickTier> tiers, List<DoNotPick> dnp}) get layout {
    final base = tiers.isEmpty
        ? <PickTier>[
            for (final name in kDefaultPickTierNames) PickTier(name: name),
          ]
        : tiers;
    final wanted = teamNumbers.toSet();
    final seen = <int>{};
    final merged = <PickTier>[
      for (final tier in base)
        tier.copyWith(
          teams: <int>[
            for (final team in tier.teams)
              if (wanted.contains(team) && seen.add(team)) team,
          ],
        ),
    ];
    final extra = <int>[
      for (final team in teamNumbers)
        if (seen.add(team)) team,
    ];
    if (extra.isNotEmpty) {
      merged[0] = merged[0].copyWith(
        teams: <int>[...merged[0].teams, ...extra],
      );
    }
    return (
      tiers: merged,
      dnp: <DoNotPick>[
        for (final entry in dnp)
          if (!wanted.contains(entry.team)) entry,
      ],
    );
  }

  PickList copyWith({
    String? name,
    List<int>? teamNumbers,
    DateTime? updatedAt,
    String? authorUid,
    String? authorDisplayName,
    List<PickTier>? tiers,
    List<DoNotPick>? dnp,
  }) {
    return PickList(
      id: id,
      name: name ?? this.name,
      teamNumbers: teamNumbers ?? this.teamNumbers,
      updatedAt: updatedAt ?? this.updatedAt,
      authorUid: authorUid ?? this.authorUid,
      authorDisplayName: authorDisplayName ?? this.authorDisplayName,
      tiers: tiers ?? this.tiers,
      dnp: dnp ?? this.dnp,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'name': name,
    'teamNumbers': teamNumbers,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'authorUid': authorUid,
    'authorDisplayName': authorDisplayName,
    if (tiers.isNotEmpty) 'tiers': tiers.map((t) => t.toJson()).toList(),
    if (dnp.isNotEmpty) 'dnp': dnp.map((d) => d.toJson()).toList(),
  };

  factory PickList.fromJson(Map<String, dynamic> json) {
    return PickList(
      id: json['id'] as String,
      name: (json['name'] as String?) ?? '',
      teamNumbers: _teamsFrom(json['teamNumbers']),
      updatedAt:
          DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      authorUid: (json['authorUid'] as String?) ?? '',
      authorDisplayName: (json['authorDisplayName'] as String?) ?? '',
      tiers: <PickTier>[
        for (final raw in (json['tiers'] as List?) ?? const <dynamic>[])
          if (raw is Map) PickTier.fromJson(Map<String, dynamic>.from(raw)),
      ],
      dnp: <DoNotPick>[
        for (final raw in (json['dnp'] as List?) ?? const <dynamic>[])
          ?DoNotPick.tryFromJson(raw),
      ],
    );
  }
}
