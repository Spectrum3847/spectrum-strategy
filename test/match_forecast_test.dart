import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spectrumstrategy/src/models/match_forecast.dart';
import 'package:spectrumstrategy/src/state/event_controller.dart';
import 'package:statbotics_client/statbotics_client.dart';
import 'package:tba_client/tba_client.dart';

import 'support/fake_match13_ratings_service.dart';

class _FakeStatboticsClient extends StatboticsClient {
  @override
  Future<StatboticsEvent?> getEvent(String eventKey) async =>
      StatboticsEvent(key: eventKey, name: 'Test Event', year: 2026);

  @override
  Future<List<StatboticsTeamEvent>> getEventTeams(String eventKey) async =>
      const <StatboticsTeamEvent>[];

  @override
  Future<List<StatboticsMatch>> getEventMatches(String eventKey) async =>
      const <StatboticsMatch>[];
}

class _FakeTbaClient extends TbaClient {
  _FakeTbaClient({this.predictions, this.fail = false})
    : super(config: InMemoryTbaConfig('test-key'));

  final Map<String, TbaMatchPrediction>? predictions;
  final bool fail;
  int calls = 0;

  @override
  Future<Map<String, TbaMatchPrediction>> getEventPredictions(
    String eventKey,
  ) async {
    calls++;
    if (fail) throw TbaApiException(500, 'boom');
    return predictions ?? const <String, TbaMatchPrediction>{};
  }
}

MatchForecast _match13Forecast(
  String key, {
  double red = 100,
  double blue = 90,
  double redWinProbability = 0.6,
}) => MatchForecast(
  matchKey: key,
  source: MatchForecastSource.match13,
  redScore: red,
  blueScore: blue,
  redWinProbability: redWinProbability,
);

Future<EventController> _controller({
  _FakeTbaClient? tba,
  FakeMatch13RatingsService? match13,
}) async {
  final controller = EventController(
    client: _FakeStatboticsClient(),
    tbaClient: tba,
    match13: match13,
  );
  await controller.setEventKey('2026test');
  return controller;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  group('MatchForecast', () {
    test('reads a percent and a fraction as the same probability', () {
      expect(MatchForecast.normalizeProbability(0.65), closeTo(0.65, 1e-9));
      expect(MatchForecast.normalizeProbability(65), closeTo(0.65, 1e-9));
      expect(MatchForecast.normalizeProbability(140), 1);
      expect(MatchForecast.normalizeProbability(-3), 0);
    });

    test('names the favored alliance and its chance', () {
      final red = _match13Forecast('2026test_qm1', redWinProbability: 0.72);
      expect(red.redFavored, isTrue);
      expect(red.favoredWinProbability, closeTo(0.72, 1e-9));

      final blue = _match13Forecast('2026test_qm1', redWinProbability: 0.3);
      expect(blue.redFavored, isFalse);
      expect(blue.favoredWinProbability, closeTo(0.7, 1e-9));
    });
  });

  group('EventController.loadForecasts', () {
    test('merges both sources under one match key', () async {
      final match13 =
          FakeMatch13RatingsService(<String, Map<int, StatboticsEpa>?>{})
            ..forecasts = <String, Map<String, MatchForecast>?>{
              '2026test': <String, MatchForecast>{
                '2026test_qm1': _match13Forecast('2026test_qm1'),
              },
            };
      final controller = await _controller(
        tba: _FakeTbaClient(
          predictions: <String, TbaMatchPrediction>{
            '2026test_qm1': const TbaMatchPrediction(
              matchKey: '2026test_qm1',
              redScore: 120,
              blueScore: 95,
              winningAlliance: 'red',
              probability: 0.8,
            ),
          },
        ),
        match13: match13,
      );

      await controller.loadForecasts();

      final forecasts = controller.forecastsFor('2026test_qm1');
      expect(forecasts.map((f) => f.source), <MatchForecastSource>[
        MatchForecastSource.tba,
        MatchForecastSource.match13,
      ]);
      expect(forecasts.first.redScore, 120);
      expect(forecasts.first.redWinProbability, closeTo(0.8, 1e-9));
      expect(controller.forecastSourcesMissing, isEmpty);
    });

    test('flips a blue call into red\'s chance', () async {
      final controller = await _controller(
        tba: _FakeTbaClient(
          predictions: <String, TbaMatchPrediction>{
            '2026test_qm1': const TbaMatchPrediction(
              matchKey: '2026test_qm1',
              redScore: 80,
              blueScore: 110,
              winningAlliance: 'blue',
              probability: 0.75,
            ),
          },
        ),
      );

      await controller.loadForecasts();

      final forecast = controller.forecastsFor('2026test_qm1').single;
      expect(forecast.redWinProbability, closeTo(0.25, 1e-9));
      expect(forecast.redFavored, isFalse);
      expect(forecast.favoredWinProbability, closeTo(0.75, 1e-9));
    });

    test('keeps one source when the other fails, and names the gap', () async {
      final match13 =
          FakeMatch13RatingsService(<String, Map<int, StatboticsEpa>?>{})
            ..forecasts = <String, Map<String, MatchForecast>?>{
              '2026test': <String, MatchForecast>{
                '2026test_qm1': _match13Forecast('2026test_qm1'),
              },
            };
      final controller = await _controller(
        tba: _FakeTbaClient(fail: true),
        match13: match13,
      );

      await controller.loadForecasts();

      expect(
        controller.forecastsFor('2026test_qm1').single.source,
        MatchForecastSource.match13,
      );
      expect(controller.forecastSourcesMissing, <String>{
        MatchForecastSource.tba.label,
      });
    });

    test('loads once per event until forced', () async {
      final tba = _FakeTbaClient();
      final controller = await _controller(tba: tba);

      await controller.loadForecasts();
      await controller.loadForecasts();
      expect(tba.calls, 1);

      await controller.loadForecasts(force: true);
      expect(tba.calls, 2);
    });

    test('drops forecasts when the event changes', () async {
      final controller = await _controller(
        tba: _FakeTbaClient(
          predictions: <String, TbaMatchPrediction>{
            '2026test_qm1': const TbaMatchPrediction(
              matchKey: '2026test_qm1',
              redScore: 120,
              blueScore: 95,
              winningAlliance: 'red',
              probability: 0.8,
            ),
          },
        ),
      );
      await controller.loadForecasts();
      expect(controller.forecastsFor('2026test_qm1'), isNotEmpty);

      await controller.setEventKey('2026other');

      expect(controller.forecastsFor('2026test_qm1'), isEmpty);
      expect(controller.forecastsLoading, isFalse);
    });
  });
}
