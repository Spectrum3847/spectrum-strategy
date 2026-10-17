import 'dart:convert' show jsonEncode;

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:match13_client/match13_client.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spectrumstrategy/src/services/firestore_api_key_config.dart';
import 'package:spectrumstrategy/src/services/match13/match13_ratings_service.dart';
import 'package:spectrumstrategy/src/services/match13/match13_worker_config.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  Map<String, dynamic> teamRow(
    int team, {
    required double xpEnd,
    double? xAuto,
    double? xTele,
    double? xEnd,
  }) => <String, dynamic>{
    'teamNumber': team,
    'xpStart': 0,
    'xpEnd': xpEnd,
    'xpMean': null,
    'xpMax': null,
    'xVar': 0,
    'xAuto': xAuto,
    'xTele': xTele,
    'xEnd': xEnd,
    'xRp1': null,
    'xRp2': null,
    'xRp3': null,
    'sos': null,
    'components': <String, dynamic>{},
    'epa': null,
    'opr': null,
    'dpr': null,
    'districtPoints': null,
    'regionalPoints': null,
  };

  Match13RatingsService serviceWith(
    Future<http.Response> Function(http.Request) handler, {
    String? teamKey = 'm13_live_test',
    bool isWeb = false,
    String? workerOrigin,
    void Function(http.Request)? onRequest,
  }) => Match13RatingsService(
    config: FirestoreApiKeyConfig.match13(remoteFetcher: () async => teamKey),
    workerConfig: Match13WorkerConfig(remoteFetcher: () async => workerOrigin),
    isWeb: isWeb,
    clientFactory: (apiKey) => Match13Client(
      apiKey: apiKey,
      sleep: (_) async {},
      httpClient: MockClient((request) {
        onRequest?.call(request);
        return handler(request);
      }),
    ),
    proxyClientFactory: (baseUrl) => Match13Client(
      apiKey: null,
      baseUrl: baseUrl,
      sleep: (_) async {},
      httpClient: MockClient((request) {
        onRequest?.call(request);
        return handler(request);
      }),
    ),
  );

  test('maps xP onto the EPA fields the app already reads', () async {
    final service = serviceWith(
      (_) async => http.Response(
        jsonEncode(<String, dynamic>{
          'eventKey': '2026txhou',
          'year': 2026,
          'teams': <dynamic>[
            teamRow(3847, xpEnd: 81.5, xAuto: 19.0, xTele: 54.25, xEnd: 8.25),
            teamRow(118, xpEnd: 110.75),
          ],
        }),
        200,
      ),
    );

    final ratings = await service.ratingsFor('2026txhou');

    expect(ratings, hasLength(2));
    expect(ratings![3847]!.totalPoints, 81.5);
    expect(ratings[3847]!.autoPoints, 19.0);
    expect(ratings[3847]!.teleopPoints, 54.25);
    expect(ratings[3847]!.endgamePoints, 8.25);
    expect(ratings[118]!.totalPoints, 110.75);
    expect(
      ratings[118]!.autoPoints,
      isNull,
      reason: 'a null phase stays null rather than becoming a zero',
    );
  });

  test('sends the team key as a bearer token', () async {
    final seen = <http.Request>[];
    final service = serviceWith(
      (_) async => http.Response(
        jsonEncode(<String, dynamic>{
          'eventKey': '2026txhou',
          'year': 2026,
          'teams': <dynamic>[],
        }),
        200,
      ),
      teamKey: 'm13_live_fromfirestore',
      onRequest: seen.add,
    );

    await service.ratingsFor('2026txhou');

    expect(seen, hasLength(1));
    expect(
      seen.single.headers['Authorization'],
      'Bearer m13_live_fromfirestore',
    );
    expect(seen.single.url.path, '/v1/events/2026txhou/teams');
  });

  test('asks for nothing at all with no key set', () async {
    var called = false;
    final service = serviceWith((_) async {
      called = true;
      return http.Response('{}', 200);
    }, teamKey: null);

    expect(await service.ratingsFor('2026txhou'), isNull);
    expect(called, isFalse, reason: 'no key means no request to make');
  });

  test('asks for nothing on web, which cannot read the API', () async {
    var called = false;
    final service = serviceWith((_) async {
      called = true;
      return http.Response('{}', 200);
    }, isWeb: true);

    expect(await service.ratingsFor('2026txhou'), isNull);
    expect(
      called,
      isFalse,
      reason: 'the API sends no CORS headers, so a browser can never read it',
    );
  });

  test(
    'on web with a Worker origin, requests go through it with no key',
    () async {
      final seen = <http.Request>[];
      final service = serviceWith(
        (_) async => http.Response(
          jsonEncode(<String, dynamic>{
            'eventKey': '2026txhou',
            'year': 2026,
            'teams': <dynamic>[teamRow(3847, xpEnd: 81.5)],
          }),
          200,
        ),
        isWeb: true,
        workerOrigin: 'https://spectrumstrategy-match13.example.workers.dev',
        onRequest: seen.add,
      );

      final ratings = await service.ratingsFor('2026txhou');

      expect(ratings, hasLength(1));
      expect(seen, hasLength(1));
      expect(
        seen.single.url.toString(),
        'https://spectrumstrategy-match13.example.workers.dev/v1/events/2026txhou/teams',
      );
      expect(
        seen.single.headers.containsKey('Authorization'),
        isFalse,
        reason: 'the Worker adds the key server-side',
      );
    },
  );

  test('an event match13 does not carry answers empty, not null', () async {
    final service = serviceWith(
      (_) async => http.Response(
        jsonEncode(<String, dynamic>{
          'type': 'https://match13.com/docs/api#not-found',
          'title': 'Not found',
          'status': 404,
          'detail': 'No resource at this path.',
        }),
        404,
      ),
    );

    expect(
      await service.ratingsFor('2026txdri1'),
      isEmpty,
      reason: 'match13 answered; it simply holds nothing for this event',
    );
  });

  test('a revoked key answers null instead of throwing', () async {
    final service = serviceWith(
      (_) async => http.Response(
        jsonEncode(<String, dynamic>{
          'title': 'Unauthorized',
          'status': 401,
          'detail': 'Present an API key as `Authorization: Bearer ...`.',
        }),
        401,
      ),
    );

    expect(await service.ratingsFor('2026txhou'), isNull);
  });

  test('an outage answers null instead of throwing', () async {
    final service = serviceWith((_) async => http.Response('', 500));

    expect(
      await service.ratingsFor('2026txhou'),
      isNull,
      reason: 'a ratings source being down must not break the whole fetch',
    );
  });

  test('an empty event key asks for nothing', () async {
    var called = false;
    final service = serviceWith((_) async {
      called = true;
      return http.Response('{}', 200);
    });

    expect(await service.ratingsFor(''), isNull);
    expect(called, isFalse);
  });
}
