import 'pick_list.dart';

sealed class PickRow {
  const PickRow();
}

class TierRow extends PickRow {
  const TierRow(this.tier);
  final int tier;
}

class TeamRow extends PickRow {
  const TeamRow({required this.team, required this.tier, required this.rank});
  final int team;
  final int tier;

  final int rank;
}

class PickLayout {
  const PickLayout({required this.tiers, required this.dnp});

  factory PickLayout.of(PickList list) {
    final layout = list.layout;
    return PickLayout(tiers: layout.tiers, dnp: layout.dnp);
  }

  final List<PickTier> tiers;
  final List<DoNotPick> dnp;

  bool contains(int team) =>
      tiers.any((t) => t.teams.contains(team)) || isDnp(team);

  bool isDnp(int team) => dnp.any((d) => d.team == team);

  int? tierOf(int team) {
    for (var i = 0; i < tiers.length; i++) {
      if (tiers[i].teams.contains(team)) return i;
    }
    return null;
  }

  List<PickRow> get rows {
    final out = <PickRow>[];
    var rank = 0;
    for (var i = 0; i < tiers.length; i++) {
      out.add(TierRow(i));
      for (final team in tiers[i].teams) {
        out.add(TeamRow(team: team, tier: i, rank: ++rank));
      }
    }
    return out;
  }

  PickLayout _withTeams(List<List<int>> teams, [List<DoNotPick>? nextDnp]) {
    return PickLayout(
      tiers: <PickTier>[
        for (var i = 0; i < tiers.length; i++)
          tiers[i].copyWith(teams: teams[i]),
      ],
      dnp: nextDnp ?? dnp,
    );
  }

  List<List<int>> get _teams => <List<int>>[
    for (final tier in tiers) <int>[...tier.teams],
  ];

  PickLayout add(int team, {int tier = 0}) {
    final teams = <List<int>>[
      for (final t in _teams) t.where((x) => x != team).toList(),
    ];
    teams[tier.clamp(0, teams.length - 1)].add(team);
    return _withTeams(teams, <DoNotPick>[
      for (final d in dnp)
        if (d.team != team) d,
    ]);
  }

  PickLayout remove(int team) {
    return _withTeams(
      <List<int>>[for (final t in _teams) t.where((x) => x != team).toList()],
      <DoNotPick>[
        for (final d in dnp)
          if (d.team != team) d,
      ],
    );
  }

  PickLayout markDnp(int team, String reason) {
    final cleared = remove(team);
    return PickLayout(
      tiers: cleared.tiers,
      dnp: <DoNotPick>[
        ...cleared.dnp,
        DoNotPick(team: team, reason: reason),
      ],
    );
  }

  PickLayout setReason(int team, String reason) {
    return PickLayout(
      tiers: tiers,
      dnp: <DoNotPick>[
        for (final d in dnp) d.team == team ? d.copyWith(reason: reason) : d,
      ],
    );
  }

  PickLayout move(int team, int delta) {
    final rows = this.rows;
    final from = rows.indexWhere((r) => r is TeamRow && r.team == team);
    final target = from + delta;
    if (from < 0 || target < 0 || target >= rows.length) return this;
    return reorder(from, target);
  }

  PickLayout moveToTier(int team, int tier) => add(team, tier: tier);

  PickLayout reorder(int oldIndex, int newIndex) {
    final rows = this.rows;
    if (oldIndex < 0 || oldIndex >= rows.length) return this;
    final moved = rows[oldIndex];
    if (moved is! TeamRow) return this;
    final rest = <PickRow>[...rows]..removeAt(oldIndex);
    final at = newIndex.clamp(0, rest.length);
    var tier = 0;
    var position = 0;
    for (var i = 0; i < at; i++) {
      final row = rest[i];
      if (row is TierRow) {
        tier = row.tier;
        position = 0;
      } else {
        position++;
      }
    }
    final teams = <List<int>>[
      for (final t in _teams) t.where((x) => x != moved.team).toList(),
    ];
    teams[tier].insert(position, moved.team);
    return _withTeams(teams);
  }

  PickLayout renameTier(int tier, String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return this;
    return PickLayout(
      tiers: <PickTier>[
        for (var i = 0; i < tiers.length; i++)
          i == tier ? tiers[i].copyWith(name: trimmed) : tiers[i],
      ],
      dnp: dnp,
    );
  }

  PickLayout addTier(String name) {
    return PickLayout(
      tiers: <PickTier>[
        ...tiers,
        PickTier(name: name),
      ],
      dnp: dnp,
    );
  }

  PickLayout removeTier(int tier) {
    if (tiers.length < 2 || tiers[tier].teams.isNotEmpty) return this;
    return PickLayout(
      tiers: <PickTier>[
        for (var i = 0; i < tiers.length; i++)
          if (i != tier) tiers[i],
      ],
      dnp: dnp,
    );
  }
}
