library;

class UsageCount {
  const UsageCount(this.name, this.count);

  final String name;
  final int count;

  static UsageCount? fromJson(Object? json) {
    if (json is! Map) return null;
    final name = json['name'];
    if (name is! String || name.isEmpty) return null;
    return UsageCount(name, _asInt(json['count']));
  }

  @override
  String toString() => '$name: $count';
}

class UsageDay {
  const UsageDay(this.date, this.count);

  final String date;
  final int count;

  static UsageDay? fromJson(Object? json) {
    if (json is! Map) return null;
    final date = json['date'];
    if (date is! String || date.isEmpty) return null;
    return UsageDay(date, _asInt(json['count']));
  }
}

class UsageRollup {
  const UsageRollup({
    required this.updatedAt,
    required this.windowDays,
    required this.eventsCounted,
    required this.deviceCount,
    required this.tabs,
    required this.platforms,
    required this.appVersions,
    required this.daily,
  });

  final DateTime? updatedAt;

  final int windowDays;
  final int eventsCounted;
  final int deviceCount;

  final List<UsageCount> tabs;
  final List<UsageCount> platforms;
  final List<UsageCount> appVersions;

  final List<UsageDay> daily;

  static const empty = UsageRollup(
    updatedAt: null,
    windowDays: 0,
    eventsCounted: 0,
    deviceCount: 0,
    tabs: [],
    platforms: [],
    appVersions: [],
    daily: [],
  );

  bool get isEmpty => eventsCounted == 0;

  static UsageRollup fromJson(Map<String, dynamic> json) => UsageRollup(
    updatedAt: DateTime.tryParse(
      json['updatedAt'] is String ? json['updatedAt'] as String : '',
    )?.toUtc(),
    windowDays: _asInt(json['windowDays']),
    eventsCounted: _asInt(json['eventsCounted']),
    deviceCount: _asInt(json['deviceCount']),
    tabs: _list(json['tabs'], UsageCount.fromJson),
    platforms: _list(json['platforms'], UsageCount.fromJson),
    appVersions: _list(json['appVersions'], UsageCount.fromJson),
    daily: _list(json['daily'], UsageDay.fromJson),
  );

  int get busiestDay =>
      daily.fold(0, (max, day) => day.count > max ? day.count : max);
}

List<T> _list<T>(Object? json, T? Function(Object?) parse) {
  if (json is! List) return const [];
  final out = <T>[];
  for (final entry in json) {
    final parsed = parse(entry);
    if (parsed != null) out.add(parsed);
  }
  return out;
}

int _asInt(Object? value) => switch (value) {
  int() => value,
  double() => value.round(),
  String() => int.tryParse(value) ?? 0,
  _ => 0,
};
