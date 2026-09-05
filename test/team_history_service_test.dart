import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:statbotics_client/statbotics_client.dart';

import 'package:spectrumstrategy/src/services/statbotics/team_history_service.dart';

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('returns the current and previous season, newest first', () async {
    final client = _FakeClient({
      3847: [
        _season(2024, norm: 1500),
        _season(2026, norm: 1720),
        _season(2025, norm: 1600),
      ],
    });
    final service = TeamHistoryService(client: client);

    final seasons = await service.seasonsFor(3847);

    expect(seasons.map((s) => s.year).toList(), [2026, 2025]);
  });

  test('sorts newest first whatever order the API answers in', () async {
    final client = _FakeClient({
      3847: [_season(2011), _season(2012), _season(2026)],
    });

    final seasons = await TeamHistoryService(client: client)
        .seasonsFor(3847, seasons: 3);

    expect(seasons.map((s) => s.year).toList(), [2026, 2012, 2011]);
  });

  test('a wider request does not force a second fetch', () async {
    final client = _FakeClient({
      3847: [_season(2026), _season(2025), _season(2024), _season(2023)],
    });
    final service = TeamHistoryService(client: client);

    expect((await service.seasonsFor(3847)).length, 2);
    expect((await service.seasonsFor(3847, seasons: 4)).length, 4);
    expect(client.calls, 1);
  });

  test('a second look is served from memory', () async {
    final client = _FakeClient({
      3847: [_season(2026), _season(2025)],
    });
    final service = TeamHistoryService(client: client);

    await service.seasonsFor(3847);
    await service.seasonsFor(3847);

    expect(client.calls, 1);
  });

  test('a fresh cache on disk is served without a fetch', () async {
    final client = _FakeClient({
      3847: [_season(2026), _season(2025)],
    });
    final now = DateTime.utc(2026, 9, 2, 12);
    final first = TeamHistoryService(client: client, now: () => now);
    await first.seasonsFor(3847);
    expect(client.calls, 1);

    final second = TeamHistoryService(
      client: client,
      now: () => now.add(const Duration(hours: 1)),
    );
    final seasons = await second.seasonsFor(3847);

    expect(seasons.map((s) => s.year).toList(), [2026, 2025]);
    expect(client.calls, 1);
  });

  test('a stale cache is refetched', () async {
    final client = _FakeClient({
      3847: [_season(2026), _season(2025)],
    });
    final now = DateTime.utc(2026, 9, 2, 12);
    await TeamHistoryService(client: client, now: () => now).seasonsFor(3847);

    await TeamHistoryService(
      client: client,
      now: () =>
          now.add(TeamHistoryService.freshFor + const Duration(hours: 1)),
    ).seasonsFor(3847);

    expect(client.calls, 2);
  });

  test('a failed fetch falls back to the stale rows it already had', () async {
    final client = _FakeClient({
      3847: [_season(2026, norm: 1720), _season(2025, norm: 1600)],
    });
    final now = DateTime.utc(2026, 9, 2, 12);
    await TeamHistoryService(client: client, now: () => now).seasonsFor(3847);

    client.throwOnNextCall = true;
    final later = TeamHistoryService(
      client: client,
      now: () =>
          now.add(TeamHistoryService.freshFor + const Duration(hours: 1)),
    );

    final seasons = await later.seasonsFor(3847);

    expect(seasons.map((s) => s.year).toList(), [2026, 2025]);
    expect(client.calls, 2);
  });

  test('a failed fetch with nothing cached is empty, not an error', () async {
    final client = _FakeClient(const {})..throwOnNextCall = true;

    expect(await TeamHistoryService(client: client).seasonsFor(3847), isEmpty);
  });

  test('a team Statbotics has never heard of is empty', () async {
    final client = _FakeClient(const {});

    expect(await TeamHistoryService(client: client).seasonsFor(9999), isEmpty);
  });

  test('the kill switch skips the request entirely', () async {
    final client = _FakeClient({
      3847: [_season(2026)],
    });

    final seasons = await TeamHistoryService(
      client: client,
      statboticsEnabled: false,
    ).seasonsFor(3847);

    expect(seasons, isEmpty);
    expect(client.calls, 0);
  });

  test('the kill switch still serves whatever is already cached', () async {
    final client = _FakeClient({
      3847: [_season(2026, norm: 1720)],
    });
    final now = DateTime.utc(2026, 9, 2, 12);
    await TeamHistoryService(client: client, now: () => now).seasonsFor(3847);

    final switched = TeamHistoryService(
      client: client,
      statboticsEnabled: false,
      now: () => now.add(const Duration(days: 30)),
    );

    final seasons = await switched.seasonsFor(3847);

    expect(seasons.map((s) => s.year).toList(), [2026]);
    expect(client.calls, 1);
  });

  test('a corrupt cache entry reads as no entry', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'team_seasons_cache_v1:3847': 'not json at all',
    });
    final client = _FakeClient({
      3847: [_season(2026)],
    });

    final seasons = await TeamHistoryService(client: client).seasonsFor(3847);

    expect(seasons.map((s) => s.year).toList(), [2026]);
    expect(client.calls, 1);
  });

  test('a cache entry with no timestamp reads as no entry', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'team_seasons_cache_v1:3847': jsonEncode(<String, dynamic>{
        'seasons': <Map<String, dynamic>>[],
      }),
    });
    final client = _FakeClient({
      3847: [_season(2026)],
    });

    final seasons = await TeamHistoryService(client: client).seasonsFor(3847);

    expect(seasons.map((s) => s.year).toList(), [2026]);
  });

  test('the cached rows round-trip their measures', () async {
    final client = _FakeClient({
      3847: [
        StatboticsTeamYear(
          team: 3847,
          year: 2026,
          name: 'Spectrum',
          wins: 30,
          losses: 4,
          ties: 1,
          epaRank: 40,
          epaRankTeamCount: 3600,
          epa: const StatboticsEpa(
            totalPoints: 88.5,
            unitless: 1800,
            norm: 1720,
            autoPoints: 20.5,
            teleopPoints: 55,
            endgamePoints: 13,
          ),
        ),
      ],
    });
    final now = DateTime.utc(2026, 9, 2, 12);
    await TeamHistoryService(client: client, now: () => now).seasonsFor(3847);

    final restored = await TeamHistoryService(
      client: client,
      now: () => now.add(const Duration(hours: 1)),
    ).seasonsFor(3847);

    final season = restored.single;
    expect(client.calls, 1);
    expect(season.year, 2026);
    expect(season.wins, 30);
    expect(season.losses, 4);
    expect(season.ties, 1);
    expect(season.epaRank, 40);
    expect(season.epaRankTeamCount, 3600);
    expect(season.epa.totalPoints, 88.5);
    expect(season.epa.unitless, 1800);
    expect(season.epa.norm, 1720);
    expect(season.epa.autoPoints, 20.5);
    expect(season.epa.teleopPoints, 55);
    expect(season.epa.endgamePoints, 13);
  });

  test('two teams do not share a cache slot', () async {
    final client = _FakeClient({
      3847: [_season(2026, norm: 1720)],
      254: [_season(2026, norm: 1900)],
    });
    final service = TeamHistoryService(client: client);

    expect((await service.seasonsFor(3847)).single.epa.norm, 1720);
    expect((await service.seasonsFor(254)).single.epa.norm, 1900);
  });
}

StatboticsTeamYear _season(int year, {double? norm}) => StatboticsTeamYear(
  team: 3847,
  year: year,
  wins: 10,
  losses: 4,
  ties: 0,
  epa: StatboticsEpa(norm: norm),
);

class _FakeClient extends StatboticsClient {
  _FakeClient(this._seasons);

  final Map<int, List<StatboticsTeamYear>> _seasons;

  int calls = 0;
  bool throwOnNextCall = false;

  @override
  Future<List<StatboticsTeamYear>> getTeamYears(int team) async {
    calls++;
    if (throwOnNextCall) {
      throwOnNextCall = false;
      throw StatboticsApiException(500, '');
    }
    return _seasons[team] ?? const <StatboticsTeamYear>[];
  }
}
