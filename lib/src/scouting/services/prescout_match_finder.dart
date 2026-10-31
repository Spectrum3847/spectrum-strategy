import 'package:tba_client/tba_client.dart';

class PrescoutMatch {
  const PrescoutMatch({
    required this.matchKey,
    required this.eventKey,
    required this.eventName,
    required this.label,
    required this.isPlayoff,
    required this.videoUrl,
    this.playedAt,
  });

  final String matchKey;
  final String eventKey;
  final String eventName;

  final String label;
  final bool isPlayoff;

  final String videoUrl;
  final DateTime? playedAt;
}

class PrescoutMatchPlan {
  const PrescoutMatchPlan({required this.matches, this.note});

  final List<PrescoutMatch> matches;
  final String? note;
}

class PrescoutMatchFinder {
  PrescoutMatchFinder({
    required this._client,
    required this.year,
    this.excludeEventKey = '',
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  static const int quals = 3;
  static const int playoffs = 2;
  static const int wanted = quals + playoffs;

  static const int maxEvents = 6;

  final TbaClient _client;
  final DateTime Function() _now;

  final int year;

  final String excludeEventKey;

  final Map<int, Future<PrescoutMatchPlan>> _cache = {};

  Future<PrescoutMatchPlan> find(int team) {
    return _cache[team] ??= _find(team).catchError((Object error) {
      _cache.remove(team);
      throw error;
    });
  }

  Future<PrescoutMatchPlan> _find(int team) async {
    final today = _isoDate(_now());
    final events =
        (await _client.getTeamEvents(team, year))
            .where(
              (e) =>
                  e.key != excludeEventKey &&
                  !e.isPreseason &&
                  (e.startDate == null || e.startDate!.compareTo(today) <= 0),
            )
            .toList()
          ..sort((a, b) => (b.endDate ?? '').compareTo(a.endDate ?? ''));
    if (events.isEmpty) {
      return PrescoutMatchPlan(
        matches: const [],
        note: 'The Blue Alliance has no $year events for $team yet.',
      );
    }

    final picked = <PrescoutMatch>[];
    final skipped = <String>[];
    final used = <({String name, int quals, int playoffs})>[];
    for (final event in events.take(maxEvents)) {
      if (picked.length >= wanted) break;
      final matches = await _client.getTeamEventMatches(team, event.key);
      final withVideo =
          matches
              .where((m) => m.isPlayed && m.videos.any(_isWatchable))
              .toList()
            ..sort(_newestFirst);
      if (withVideo.isEmpty) {
        if (matches.any((m) => m.isPlayed)) skipped.add(event.name);
        continue;
      }
      final q = withVideo.where((m) => m.compLevel == 'qm').toList();
      final p = withVideo.where((m) => m.compLevel != 'qm').toList();
      final need = wanted - picked.length;
      final haveP = picked.where((m) => m.isPlayoff).length;
      final haveQ = picked.length - haveP;
      var takeP = _clamp(playoffs - haveP, need, p.length);
      var takeQ = _clamp(quals - haveQ, need - takeP, q.length);
      if (takeP + takeQ < need) takeQ = _clamp(need - takeP, need, q.length);
      if (takeP + takeQ < need) takeP = _clamp(need - takeQ, need, p.length);

      used.add((name: event.name, quals: takeQ, playoffs: takeP));
      final take = [...q.take(takeQ), ...p.take(takeP)]..sort(_newestFirst);
      for (final m in take.reversed) {
        picked.add(_toPrescoutMatch(m, event));
      }
    }

    return PrescoutMatchPlan(
      matches: List.unmodifiable(picked),
      note: _note(team, picked.length, skipped, used),
    );
  }

  String? _note(
    int team,
    int found,
    List<String> skipped,
    List<({String name, int quals, int playoffs})> used,
  ) {
    if (found == 0) {
      return 'The Blue Alliance has no match videos for $team in $year yet.';
    }
    final first = used.first;
    final note = [
      if (skipped.isNotEmpty) '${skipped.join(', ')} had no match videos',
      if (first.playoffs == 0 && first.quals > quals)
        '${first.name}: no playoff videos, so ${first.quals} quals instead'
      else if (first.quals != quals || first.playoffs != playoffs)
        '${first.name}: ${_count(first.quals, 'qual')} and '
            '${_count(first.playoffs, 'playoff')}',
      if (used.length > 1)
        'the rest from ${used.skip(1).map((u) => u.name).join(', ')}',
      if (found < wanted) 'only $found of $wanted matches have video',
    ].join('; ');
    return note.isEmpty ? null : note;
  }

  static PrescoutMatch _toPrescoutMatch(TbaScheduleMatch m, TbaEvent event) {
    final video = m.videos.firstWhere(_isWatchable);

    final parts = video.key.split('?');
    final start = parts.length > 1
        ? RegExp(r'(?:^|&)t=(\d+)').firstMatch(parts[1])?.group(1)
        : null;
    final url =
        'https://www.youtube.com/watch?v=${parts.first}'
        '${start == null ? '' : '&t=$start'}';
    return PrescoutMatch(
      matchKey: m.key,
      eventKey: event.key,
      eventName: event.name,
      label: matchLabel(m),
      isPlayoff: m.compLevel != 'qm',
      videoUrl: url,
      playedAt: m.actualTime,
    );
  }

  static String matchLabel(TbaScheduleMatch m) {
    switch (m.compLevel) {
      case 'qm':
        return 'Q${m.matchNumber}';
      case 'f':
        return 'Final ${m.matchNumber}';
      case 'sf' when m.matchNumber == 1:
        return 'Playoff ${m.setNumber}';
      default:
        return '${m.compLevel.toUpperCase()}${m.setNumber}-${m.matchNumber}';
    }
  }

  static bool _isWatchable(TbaMatchVideo v) =>
      v.isYoutube && v.key.split('?').first.isNotEmpty;

  static String _count(int n, String noun) => '$n $noun${n == 1 ? '' : 's'}';

  static int _newestFirst(TbaScheduleMatch a, TbaScheduleMatch b) {
    final at = a.actualTime ?? a.scheduledTime;
    final bt = b.actualTime ?? b.scheduledTime;
    if (at != null && bt != null && at != bt) return bt.compareTo(at);
    return _order(b).compareTo(_order(a));
  }

  static int _order(TbaScheduleMatch m) {
    const levels = ['qm', 'ef', 'qf', 'sf', 'f'];
    return (levels.indexOf(m.compLevel) * 100 + m.setNumber) * 1000 +
        m.matchNumber;
  }

  static int _clamp(int want, int room, int available) {
    if (want <= 0 || room <= 0) return 0;
    return [want, room, available].reduce((a, b) => a < b ? a : b);
  }

  static String _isoDate(DateTime t) =>
      '${t.year.toString().padLeft(4, '0')}-'
      '${t.month.toString().padLeft(2, '0')}-'
      '${t.day.toString().padLeft(2, '0')}';
}
