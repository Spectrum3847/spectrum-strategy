library;

class PitShiftMirror {
  const PitShiftMirror({
    required this.eventKey,
    required this.competition,
    required this.shifts,
    required this.syncedAt,
  });

  final String eventKey;

  final String competition;
  final List<MirroredPitShift> shifts;
  final DateTime syncedAt;

  bool get isEmpty => shifts.isEmpty;

  List<MirroredPitShift> shiftsFor(String uid) =>
      shifts.where((s) => s.includes(uid)).toList(growable: false);

  Map<String, dynamic> toJson() => <String, dynamic>{
    'eventKey': eventKey,
    'competition': competition,
    'shifts': shifts.map((s) => s.toJson()).toList(),
    'syncedAt': syncedAt.toUtc().toIso8601String(),
  };

  static PitShiftMirror fromJson(Map<String, dynamic> json) => PitShiftMirror(
    eventKey: json['eventKey'] as String? ?? '',
    competition: json['competition'] as String? ?? '',
    shifts: [
      for (final raw in json['shifts'] as List<dynamic>? ?? const [])
        if (raw is Map)
          MirroredPitShift.fromJson(Map<String, dynamic>.from(raw)),
    ],
    syncedAt:
        DateTime.tryParse(json['syncedAt'] as String? ?? '')?.toUtc() ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
  );
}

class MirroredPitShift {
  const MirroredPitShift({
    required this.id,
    required this.label,
    required this.kind,
    required this.assignees,
    this.startMatch,
    this.endMatch,
    this.startsAt,
    this.endsAt,
    this.notes,
  });

  final String id;
  final String label;
  final String kind;
  final List<MirroredAssignee> assignees;
  final int? startMatch;
  final int? endMatch;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final String? notes;

  bool includes(String uid) => assignees.any((a) => a.uid == uid);

  String rangeText() {
    final start = startMatch;
    final end = endMatch;
    if (start != null) {
      return end == null || end == start ? 'Q$start' : 'Q$start-$end';
    }
    final from = startsAt?.toLocal();
    final to = endsAt?.toLocal();
    if (from == null) return '';
    final fromText = _clock(from);
    return to == null ? fromText : '$fromText-${_clock(to)}';
  }

  static String _clock(DateTime t) {
    final hour = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final minute = t.minute.toString().padLeft(2, '0');
    return '$hour:$minute ${t.hour < 12 ? 'am' : 'pm'}';
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'label': label,
    'kind': kind,
    'assignees': assignees.map((a) => a.toJson()).toList(),
    if (startMatch != null) 'startMatch': startMatch,
    if (endMatch != null) 'endMatch': endMatch,
    if (startsAt != null) 'startsAt': startsAt!.toUtc().toIso8601String(),
    if (endsAt != null) 'endsAt': endsAt!.toUtc().toIso8601String(),
    if (notes != null) 'notes': notes,
  };

  static MirroredPitShift fromJson(Map<String, dynamic> json) =>
      MirroredPitShift(
        id: json['id'] as String? ?? '',
        label: json['label'] as String? ?? '',
        kind: json['kind'] as String? ?? '',
        assignees: [
          for (final raw in json['assignees'] as List<dynamic>? ?? const [])
            if (raw is Map)
              MirroredAssignee.fromJson(Map<String, dynamic>.from(raw)),
        ],
        startMatch: (json['startMatch'] as num?)?.toInt(),
        endMatch: (json['endMatch'] as num?)?.toInt(),
        startsAt: DateTime.tryParse(json['startsAt'] as String? ?? '')?.toUtc(),
        endsAt: DateTime.tryParse(json['endsAt'] as String? ?? '')?.toUtc(),
        notes: json['notes'] as String?,
      );
}

class MirroredAssignee {
  const MirroredAssignee({required this.name, this.uid});

  final String name;

  final String? uid;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'name': name,
    if (uid != null) 'uid': uid,
  };

  static MirroredAssignee fromJson(Map<String, dynamic> json) =>
      MirroredAssignee(
        name: json['name'] as String? ?? '',
        uid: (json['uid'] as String?)?.isEmpty ?? true
            ? null
            : json['uid'] as String,
      );
}
