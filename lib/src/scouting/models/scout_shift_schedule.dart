library;

enum ScheduleCellColor {
  green,
  white,
  grey,
  red;

  static ScheduleCellColor? byNameOrNull(Object? name) {
    for (final color in ScheduleCellColor.values) {
      if (color.name == name) return color;
    }
    return null;
  }
}

class ScoutShiftRosterEntry {
  const ScoutShiftRosterEntry({required this.uid, required this.name});

  final String uid;
  final String name;

  Map<String, dynamic> toJson() => <String, dynamic>{'uid': uid, 'name': name};

  static ScoutShiftRosterEntry fromJson(Map<String, dynamic> json) =>
      ScoutShiftRosterEntry(
        uid: json['uid'] as String? ?? '',
        name: json['name'] as String? ?? '',
      );
}

class ScoutShiftBlock {
  const ScoutShiftBlock({required this.startMatch, required this.endMatch});

  final int startMatch;
  final int endMatch;

  bool covers(int matchNumber) =>
      matchNumber >= startMatch && matchNumber <= endMatch;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'startMatch': startMatch,
    'endMatch': endMatch,
  };

  static ScoutShiftBlock fromJson(Map<String, dynamic> json) => ScoutShiftBlock(
    startMatch: (json['startMatch'] as num?)?.toInt() ?? 0,
    endMatch: (json['endMatch'] as num?)?.toInt() ?? 0,
  );
}

class ScouterShiftRotation {
  const ScouterShiftRotation({
    required this.uid,
    required this.name,
    required this.shifts,
  });

  final String uid;
  final String name;
  final List<ScoutShiftBlock> shifts;

  bool isOnDuty(int matchNumber) => shifts.any((s) => s.covers(matchNumber));

  ScoutShiftBlock? upcomingShift(int matchNumber) {
    for (final shift in shifts) {
      if (shift.endMatch >= matchNumber) return shift;
    }
    return null;
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'uid': uid,
    'name': name,
    'shifts': shifts.map((s) => s.toJson()).toList(growable: false),
  };

  static ScouterShiftRotation fromJson(Map<String, dynamic> json) {
    final rawShifts = json['shifts'];
    return ScouterShiftRotation(
      uid: json['uid'] as String? ?? '',
      name: json['name'] as String? ?? '',
      shifts: rawShifts is List
          ? rawShifts
                .whereType<Map>()
                .map((s) => ScoutShiftBlock.fromJson(s.cast<String, dynamic>()))
                .toList(growable: false)
          : const <ScoutShiftBlock>[],
    );
  }
}

class ScheduleCellEdit {
  const ScheduleCellEdit({
    required this.col,
    required this.match,
    this.text = '',
    this.color,
  });

  final int col;
  final int match;

  final String text;

  final ScheduleCellColor? color;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'col': col,
    'match': match,
    'text': text,
    if (color != null) 'color': color!.name,
  };

  static ScheduleCellEdit fromJson(Map<String, dynamic> json) =>
      ScheduleCellEdit(
        col: (json['col'] as num?)?.toInt() ?? 0,
        match: (json['match'] as num?)?.toInt() ?? 0,
        text: json['text'] as String? ?? '',
        color: ScheduleCellColor.byNameOrNull(json['color']),
      );
}

class ScoutShiftSchedule {
  ScoutShiftSchedule({
    required this.eventKey,
    required this.matchCount,
    required this.roster,
    required this.rotations,
    this.cellOverrides = const <ScheduleCellEdit>[],
    this.authorUid = '',
    this.authorDisplayName = '',
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now().toUtc();

  static const int kShiftLength = 6;

  static const int kMaxMatchCount = 999;

  final String eventKey;

  final int matchCount;

  final List<ScoutShiftRosterEntry> roster;

  final List<ScouterShiftRotation> rotations;

  final List<ScheduleCellEdit> cellOverrides;

  final String authorUid;
  final String authorDisplayName;
  final DateTime updatedAt;

  bool get isEmpty => rotations.isEmpty;

  static ScoutShiftSchedule empty(String eventKey) => ScoutShiftSchedule(
    eventKey: eventKey,
    matchCount: 0,
    roster: const <ScoutShiftRosterEntry>[],
    rotations: const <ScouterShiftRotation>[],
  );

  ScouterShiftRotation? rotationFor(String uid) {
    for (final rotation in rotations) {
      if (rotation.uid == uid) return rotation;
    }
    return null;
  }

  ScheduleCellEdit? _editAt(int col, int match) {
    for (final edit in cellOverrides) {
      if (edit.col == col && edit.match == match) return edit;
    }
    return null;
  }

  ScheduleCellColor colorFor(int col, int match) {
    final overrideColor = _editAt(col, match)?.color;
    if (overrideColor != null) return overrideColor;
    if (col < 0 || col >= rotations.length) return ScheduleCellColor.white;
    return rotations[col].isOnDuty(match)
        ? ScheduleCellColor.green
        : ScheduleCellColor.white;
  }

  String textFor(int col, int match) => _editAt(col, match)?.text ?? '';

  ScoutShiftSchedule withCellEdit({
    required int col,
    required int match,
    required String text,
    required ScheduleCellColor? color,
  }) {
    final next = cellOverrides
        .where((e) => !(e.col == col && e.match == match))
        .toList();
    if (text.isNotEmpty || color != null) {
      next.add(
        ScheduleCellEdit(col: col, match: match, text: text, color: color),
      );
    }
    return ScoutShiftSchedule(
      eventKey: eventKey,
      matchCount: matchCount,
      roster: roster,
      rotations: rotations,
      cellOverrides: List<ScheduleCellEdit>.unmodifiable(next),
      authorUid: authorUid,
      authorDisplayName: authorDisplayName,
      updatedAt: DateTime.now().toUtc(),
    );
  }

  ScoutShiftSchedule withRenamedColumn(int col, String name, {String? uid}) {
    if (col < 0 || col >= roster.length) return this;
    final newRoster = [...roster];
    newRoster[col] = ScoutShiftRosterEntry(
      uid: uid ?? roster[col].uid,
      name: name,
    );
    final newRotations = [...rotations];
    if (col < newRotations.length) {
      final rotation = newRotations[col];
      newRotations[col] = ScouterShiftRotation(
        uid: uid ?? rotation.uid,
        name: name,
        shifts: rotation.shifts,
      );
    }
    return ScoutShiftSchedule(
      eventKey: eventKey,
      matchCount: matchCount,
      roster: List<ScoutShiftRosterEntry>.unmodifiable(newRoster),
      rotations: List<ScouterShiftRotation>.unmodifiable(newRotations),
      cellOverrides: cellOverrides,
      authorUid: authorUid,
      authorDisplayName: authorDisplayName,
      updatedAt: DateTime.now().toUtc(),
    );
  }

  static ScoutShiftSchedule generate({
    required String eventKey,
    required int matchCount,
    required List<ScoutShiftRosterEntry> roster,
    String authorUid = '',
    String authorDisplayName = '',
  }) {
    if (matchCount > kMaxMatchCount) {
      throw ArgumentError.value(
        matchCount,
        'matchCount',
        'must not exceed $kMaxMatchCount',
      );
    }
    return ScoutShiftSchedule(
      eventKey: eventKey,
      matchCount: matchCount < 0 ? 0 : matchCount,
      roster: List<ScoutShiftRosterEntry>.unmodifiable(roster),
      rotations: _buildRotations(matchCount: matchCount, roster: roster),
      authorUid: authorUid,
      authorDisplayName: authorDisplayName,
    );
  }

  static List<ScouterShiftRotation> _buildRotations({
    required int matchCount,
    required List<ScoutShiftRosterEntry> roster,
  }) {
    if (roster.isEmpty || matchCount <= 0) {
      return const <ScouterShiftRotation>[];
    }

    final groups = <List<int>>[];
    for (var i = 0; i < roster.length; i += kShiftLength) {
      groups.add([
        for (var j = i; j < i + kShiftLength && j < roster.length; j++) j,
      ]);
    }
    final numGroups = groups.length;
    final shiftsByIndex = List.generate(
      roster.length,
      (_) => <ScoutShiftBlock>[],
    );

    final fullRounds = matchCount ~/ kShiftLength;
    final remainder = matchCount % kShiftLength;

    for (var round = 0; round < fullRounds; round++) {
      final start = round * kShiftLength + 1;
      final end = start + kShiftLength - 1;
      for (final idx in groups[round % numGroups]) {
        shiftsByIndex[idx].add(
          ScoutShiftBlock(startMatch: start, endMatch: end),
        );
      }
    }

    if (remainder > 0) {
      final tailRound = fullRounds > 0 ? fullRounds - 1 : 0;
      final tailGroup = groups[tailRound % numGroups];
      for (final idx in tailGroup) {
        if (fullRounds > 0) {
          final last = shiftsByIndex[idx].removeLast();
          shiftsByIndex[idx].add(
            ScoutShiftBlock(startMatch: last.startMatch, endMatch: matchCount),
          );
        } else {
          shiftsByIndex[idx].add(
            ScoutShiftBlock(startMatch: 1, endMatch: matchCount),
          );
        }
      }
    }

    for (var i = 0; i < shiftsByIndex.length; i++) {
      shiftsByIndex[i] = _mergeAdjacent(shiftsByIndex[i]);
    }

    return List<ScouterShiftRotation>.unmodifiable([
      for (var i = 0; i < roster.length; i++)
        ScouterShiftRotation(
          uid: roster[i].uid,
          name: roster[i].name,
          shifts: shiftsByIndex[i],
        ),
    ]);
  }

  static List<ScoutShiftBlock> _mergeAdjacent(List<ScoutShiftBlock> blocks) {
    if (blocks.length <= 1) return blocks;
    final merged = <ScoutShiftBlock>[blocks.first];
    for (final block in blocks.skip(1)) {
      final last = merged.last;
      if (block.startMatch == last.endMatch + 1) {
        merged[merged.length - 1] = ScoutShiftBlock(
          startMatch: last.startMatch,
          endMatch: block.endMatch,
        );
      } else {
        merged.add(block);
      }
    }
    return merged;
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': eventKey,
    'eventKey': eventKey,
    'matchCount': matchCount,
    'roster': roster.map((r) => r.toJson()).toList(growable: false),
    'rotations': rotations.map((r) => r.toJson()).toList(growable: false),
    'cellOverrides': cellOverrides
        .map((e) => e.toJson())
        .toList(growable: false),
    'authorUid': authorUid,
    'authorDisplayName': authorDisplayName,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };

  static ScoutShiftSchedule fromJson(Map<String, dynamic> json) {
    final eventKey = json['eventKey'] as String? ?? '';
    final rawRoster = json['roster'];
    final rawRotations = json['rotations'];
    final rawOverrides = json['cellOverrides'];
    return ScoutShiftSchedule(
      eventKey: eventKey,
      matchCount: (json['matchCount'] as num?)?.toInt() ?? 0,
      roster: rawRoster is List
          ? rawRoster
                .whereType<Map>()
                .map(
                  (r) =>
                      ScoutShiftRosterEntry.fromJson(r.cast<String, dynamic>()),
                )
                .toList(growable: false)
          : const <ScoutShiftRosterEntry>[],
      rotations: rawRotations is List
          ? rawRotations
                .whereType<Map>()
                .map(
                  (r) =>
                      ScouterShiftRotation.fromJson(r.cast<String, dynamic>()),
                )
                .toList(growable: false)
          : const <ScouterShiftRotation>[],
      cellOverrides: rawOverrides is List
          ? rawOverrides
                .whereType<Map>()
                .map(
                  (e) => ScheduleCellEdit.fromJson(e.cast<String, dynamic>()),
                )
                .toList(growable: false)
          : const <ScheduleCellEdit>[],
      authorUid: json['authorUid'] as String? ?? '',
      authorDisplayName: json['authorDisplayName'] as String? ?? '',
      updatedAt:
          DateTime.tryParse(json['updatedAt'] as String? ?? '')?.toUtc() ??
          DateTime.now().toUtc(),
    );
  }
}
