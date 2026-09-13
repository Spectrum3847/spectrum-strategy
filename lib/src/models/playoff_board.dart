import 'dart:convert';

class PlayoffBoard {
  const PlayoffBoard({
    this.columnLabels = defaultColumnLabels,
    this.meetingCells = const <String, String>{},
    this.meetingCellStyles = const <String, PlayoffCellStyle>{},
    this.allianceCells = const <String, String>{},
    this.matchInfoOverrides = const <String, String>{},
  });

  static const int meetingRowCount = 13;
  static const int meetingColumnCount = 5;

  static const int allianceRowCount = 8;
  static const int allianceColumnCount = 4;

  static const List<String> defaultColumnLabels = <String>[
    'Tier 1',
    'Tier 2',
    'Tier 3',
    'Tier 4',
    'Tier 5',
  ];

  static const List<String> allianceColumnLabels = <String>[
    'Team captain',
    'Second',
    'Third',
    'Fourth',
  ];

  final List<String> columnLabels;

  final Map<String, String> meetingCells;

  final Map<String, PlayoffCellStyle> meetingCellStyles;

  final Map<String, String> allianceCells;

  final Map<String, String> matchInfoOverrides;

  static String cellKey(int row, int column) => '$row,$column';

  static String overrideKey({
    required String tableId,
    required int teamNumber,
    required String columnCode,
  }) => '$tableId|$teamNumber|$columnCode';

  bool get isEmpty =>
      meetingCells.isEmpty &&
      meetingCellStyles.isEmpty &&
      allianceCells.isEmpty &&
      matchInfoOverrides.isEmpty &&
      _listEquals(columnLabels, defaultColumnLabels);

  String meetingCell(int row, int column) =>
      meetingCells[cellKey(row, column)] ?? '';

  PlayoffCellStyle meetingCellStyle(int row, int column) =>
      meetingCellStyles[cellKey(row, column)] ?? const PlayoffCellStyle();

  String allianceCell(int row, int column) =>
      allianceCells[cellKey(row, column)] ?? '';

  String columnLabel(int column) => column < columnLabels.length
      ? columnLabels[column]
      : defaultColumnLabels[column];

  List<int> get meetingTeamsInReadingOrder {
    final teams = <int>[];
    for (var row = 0; row < meetingRowCount; row++) {
      for (var column = 0; column < meetingColumnCount; column++) {
        final team = int.tryParse(meetingCell(row, column).trim());
        if (team != null) teams.add(team);
      }
    }
    return teams;
  }

  Set<int> get placedTeamNumbers {
    final placed = <int>{};
    for (final value in allianceCells.values) {
      final team = int.tryParse(value.trim());
      if (team != null) placed.add(team);
    }
    return placed;
  }

  PlayoffBoard withMeetingCell(int row, int column, String value) =>
      copyWith(meetingCells: _withCell(meetingCells, row, column, value));

  PlayoffBoard withMeetingCellStyle(
    int row,
    int column,
    PlayoffCellStyle style,
  ) {
    final styles = Map<String, PlayoffCellStyle>.from(meetingCellStyles);
    if (style.isDefault) {
      styles.remove(cellKey(row, column));
    } else {
      styles[cellKey(row, column)] = style;
    }
    return copyWith(meetingCellStyles: styles);
  }

  PlayoffBoard withAllianceCell(int row, int column, String value) =>
      copyWith(allianceCells: _withCell(allianceCells, row, column, value));

  PlayoffBoard withColumnLabel(int column, String label) {
    final labels = List<String>.from(columnLabels);
    while (labels.length < meetingColumnCount) {
      labels.add(defaultColumnLabels[labels.length]);
    }
    labels[column] = label;
    return copyWith(columnLabels: labels);
  }

  PlayoffBoard withMatchInfoOverride(String key, String value) {
    final overrides = Map<String, String>.from(matchInfoOverrides);
    if (value.trim().isEmpty) {
      overrides.remove(key);
    } else {
      overrides[key] = value;
    }
    return copyWith(matchInfoOverrides: overrides);
  }

  PlayoffBoard copyWith({
    List<String>? columnLabels,
    Map<String, String>? meetingCells,
    Map<String, PlayoffCellStyle>? meetingCellStyles,
    Map<String, String>? allianceCells,
    Map<String, String>? matchInfoOverrides,
  }) => PlayoffBoard(
    columnLabels: columnLabels ?? this.columnLabels,
    meetingCells: meetingCells ?? this.meetingCells,
    meetingCellStyles: meetingCellStyles ?? this.meetingCellStyles,
    allianceCells: allianceCells ?? this.allianceCells,
    matchInfoOverrides: matchInfoOverrides ?? this.matchInfoOverrides,
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'columnLabels': columnLabels,
    'meetingCells': meetingCells,
    'meetingCellStyles': <String, dynamic>{
      for (final entry in meetingCellStyles.entries)
        entry.key: entry.value.toJson(),
    },
    'allianceCells': allianceCells,
    'matchInfoOverrides': matchInfoOverrides,
  };

  factory PlayoffBoard.fromJson(Map<String, dynamic> json) {
    final labels = <String>[
      for (final label in (json['columnLabels'] as List?) ?? const []) '$label',
    ];
    return PlayoffBoard(
      columnLabels: labels.length == meetingColumnCount
          ? labels
          : defaultColumnLabels,
      meetingCells: _stringMap(json['meetingCells']),
      meetingCellStyles: _cellStyleMap(json['meetingCellStyles']),
      allianceCells: _stringMap(json['allianceCells']),
      matchInfoOverrides: _stringMap(json['matchInfoOverrides']),
    );
  }

  PlayoffBoard snapshot() => PlayoffBoard.fromJson(
    jsonDecode(jsonEncode(toJson())) as Map<String, dynamic>,
  );

  static Map<String, String> _withCell(
    Map<String, String> cells,
    int row,
    int column,
    String value,
  ) {
    final next = Map<String, String>.from(cells);
    if (value.trim().isEmpty) {
      next.remove(cellKey(row, column));
    } else {
      next[cellKey(row, column)] = value;
    }
    return next;
  }

  static Map<String, String> _stringMap(Object? raw) {
    if (raw is! Map) return const <String, String>{};
    return <String, String>{
      for (final entry in raw.entries) '${entry.key}': '${entry.value}',
    };
  }

  static Map<String, PlayoffCellStyle> _cellStyleMap(Object? raw) {
    if (raw is! Map) return const <String, PlayoffCellStyle>{};
    final styles = <String, PlayoffCellStyle>{};
    for (final entry in raw.entries) {
      final value = entry.value;
      if (value is! Map) continue;
      styles['${entry.key}'] = PlayoffCellStyle.fromJson(
        value.map((key, v) => MapEntry('$key', v)),
      );
    }
    return styles;
  }

  static bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

class PlayoffCellStyle {
  const PlayoffCellStyle({this.highlighted = false, this.italic = false});

  final bool highlighted;
  final bool italic;

  bool get isDefault => !highlighted && !italic;

  PlayoffCellStyle copyWith({bool? highlighted, bool? italic}) =>
      PlayoffCellStyle(
        highlighted: highlighted ?? this.highlighted,
        italic: italic ?? this.italic,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'highlighted': highlighted,
    'italic': italic,
  };

  factory PlayoffCellStyle.fromJson(Map<String, dynamic> json) =>
      PlayoffCellStyle(
        highlighted: json['highlighted'] == true,
        italic: json['italic'] == true,
      );

  @override
  bool operator ==(Object other) =>
      other is PlayoffCellStyle &&
      other.highlighted == highlighted &&
      other.italic == italic;

  @override
  int get hashCode => Object.hash(highlighted, italic);
}
