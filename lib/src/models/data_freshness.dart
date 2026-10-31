String shortAgo(DateTime? at, DateTime now) {
  if (at == null) return '';
  final elapsed = now.difference(at);
  if (elapsed.inMinutes < 1) return 'just now';
  if (elapsed.inMinutes < 60) return '${elapsed.inMinutes}m';
  if (elapsed.inHours < 48) return '${elapsed.inHours}h';
  return '${elapsed.inDays}d';
}

String longAgo(DateTime? at, DateTime now) {
  if (at == null) return 'never';
  final elapsed = now.difference(at);
  if (elapsed.inMinutes < 1) return 'just now';
  String unit(int n, String word) => '$n $word${n == 1 ? '' : 's'} ago';
  if (elapsed.inMinutes < 60) return unit(elapsed.inMinutes, 'minute');
  if (elapsed.inHours < 48) return unit(elapsed.inHours, 'hour');
  return unit(elapsed.inDays, 'day');
}

enum FreshnessLevel { ok, idle, attention }

class FreshnessSource {
  const FreshnessSource({
    required this.name,
    required this.status,
    required this.level,
    this.updatedAt,
  });

  final String name;
  final String status;
  final FreshnessLevel level;
  final DateTime? updatedAt;
}

class DataFreshness {
  const DataFreshness({
    required this.headline,
    required this.sources,
    this.unsynced = 0,
    this.rejected = 0,
  });

  final String headline;
  final List<FreshnessSource> sources;

  final int unsynced;

  final int rejected;

  FreshnessLevel get level {
    var level = FreshnessLevel.ok;
    for (final source in sources) {
      if (source.level == FreshnessLevel.attention) {
        return FreshnessLevel.attention;
      }
      if (source.level == FreshnessLevel.idle) level = FreshnessLevel.idle;
    }
    return unsynced > 0 ? FreshnessLevel.attention : level;
  }

  String get pillLabel =>
      unsynced > 0 ? '$headline · $unsynced unsynced' : headline;

  String get answer {
    if (rejected > 0) {
      final noun = rejected == 1 ? 'entry was' : 'entries were';
      return 'Not yet. $rejected $noun refused by the server and '
          'will not send until that is fixed.';
    }
    if (unsynced > 0) {
      final noun = unsynced == 1 ? 'entry' : 'entries';
      return 'Not yet. $unsynced scouting $noun on this device '
          'has not reached the team database.';
    }
    return switch (level) {
      FreshnessLevel.ok => 'Yes. This device is in sync.',
      FreshnessLevel.idle =>
        'Nothing is out of date, but this device is not syncing right now.',
      FreshnessLevel.attention =>
        'Not sure. A source below is offline or failing, so this device '
            'may be behind.',
    };
  }
}
