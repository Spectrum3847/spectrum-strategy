const List<String> kAllianceStations = <String>[
  'red1',
  'red2',
  'red3',
  'blue1',
  'blue2',
  'blue3',
];

class ScoutAssignment {
  ScoutAssignment({
    required this.id,
    required this.matchKey,
    required this.matchNumber,
    required this.station,
    required this.scouterUid,
    required this.scouterName,
    this.authorUid = '',
    this.authorDisplayName = '',
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now().toUtc();

  final String id;

  final String matchKey;

  final int matchNumber;

  final String station;

  final String scouterUid;
  final String scouterName;

  final String authorUid;
  final String authorDisplayName;

  final DateTime updatedAt;

  static String idFor(String matchKey, String station) =>
      '${matchKey}__$station';

  bool get isRed => station.startsWith('red');

  ScoutAssignment copyWith({
    String? scouterUid,
    String? scouterName,
    String? authorUid,
    String? authorDisplayName,
    DateTime? updatedAt,
  }) {
    return ScoutAssignment(
      id: id,
      matchKey: matchKey,
      matchNumber: matchNumber,
      station: station,
      scouterUid: scouterUid ?? this.scouterUid,
      scouterName: scouterName ?? this.scouterName,
      authorUid: authorUid ?? this.authorUid,
      authorDisplayName: authorDisplayName ?? this.authorDisplayName,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'matchKey': matchKey,
    'matchNumber': matchNumber,
    'station': station,
    'scouterUid': scouterUid,
    'scouterName': scouterName,
    'authorUid': authorUid,
    'authorDisplayName': authorDisplayName,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };

  static ScoutAssignment fromJson(Map<String, dynamic> json) {
    final matchKey = json['matchKey'] as String? ?? '';
    final station = json['station'] as String? ?? '';
    return ScoutAssignment(
      id: json['id'] as String? ?? ScoutAssignment.idFor(matchKey, station),
      matchKey: matchKey,
      matchNumber: (json['matchNumber'] as num?)?.toInt() ?? 0,
      station: station,
      scouterUid: json['scouterUid'] as String? ?? '',
      scouterName: json['scouterName'] as String? ?? '',
      authorUid: json['authorUid'] as String? ?? '',
      authorDisplayName: json['authorDisplayName'] as String? ?? '',
      updatedAt:
          DateTime.tryParse(json['updatedAt'] as String? ?? '')?.toUtc() ??
          DateTime.now().toUtc(),
    );
  }
}
