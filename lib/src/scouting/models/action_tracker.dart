library;

enum ActionTrackerMode {
  tap,

  hold;

  static ActionTrackerMode fromString(String? raw) => raw == 'tap' ? tap : hold;
}

class TrackedAction {
  const TrackedAction({required this.code, required this.label, this.icon});

  factory TrackedAction.fromJson(Map<String, dynamic> json) {
    final code = (json['code'] as String?) ?? '';
    return TrackedAction(
      code: code,
      label: (json['label'] as String?)?.trim().isNotEmpty == true
          ? (json['label'] as String).trim()
          : code,
      icon: json['icon'] as String?,
    );
  }

  final String code;

  final String label;

  final String? icon;
}

class ActionTrackerEvent {
  const ActionTrackerEvent({
    required this.actionCode,
    required this.at,
    this.until,
  });

  final String actionCode;

  final double at;

  final double? until;

  bool get isSpan => until != null;
}

class ActionTrackerLog {
  const ActionTrackerLog({required this.fieldCode, required this.events});

  const ActionTrackerLog.empty(this.fieldCode)
    : events = const <ActionTrackerEvent>[];

  final String fieldCode;

  final List<ActionTrackerEvent> events;

  bool get isEmpty => events.isEmpty;

  ActionTrackerLog add(ActionTrackerEvent event) => ActionTrackerLog(
    fieldCode: fieldCode,
    events: <ActionTrackerEvent>[...events, event],
  );

  ActionTrackerLog undo() => events.isEmpty
      ? this
      : ActionTrackerLog(
          fieldCode: fieldCode,
          events: events.sublist(0, events.length - 1),
        );

  ActionTrackerLog clear() => ActionTrackerLog.empty(fieldCode);

  String countFieldFor(String actionCode) => '${fieldCode}_${actionCode}_count';

  String timesFieldFor(String actionCode) => '${fieldCode}_${actionCode}_times';

  Map<String, dynamic> toFieldValues(List<TrackedAction> actions) {
    final values = <String, dynamic>{};
    for (final action in actions) {
      final mine = events.where((e) => e.actionCode == action.code);
      values[countFieldFor(action.code)] = mine.length;
      values[timesFieldFor(action.code)] = mine
          .map(
            (e) => e.isSpan
                ? '${formatSeconds(e.at)}-${formatSeconds(e.until!)}'
                : formatSeconds(e.at),
          )
          .join(',');
    }
    return values;
  }

  static String formatSeconds(double seconds) {
    final fixed = seconds.toStringAsFixed(1);
    return fixed.endsWith('.0') ? fixed.substring(0, fixed.length - 2) : fixed;
  }
}
