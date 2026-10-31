import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:spectrumstrategy/src/scouting/services/prescout_match_finder.dart';
import 'package:tba_client/tba_client.dart';

import 'support/fake_tba_prescout.dart';

PrescoutMatchFinder _finder(TbaClient client) => PrescoutMatchFinder(
  client: client,
  year: 2026,
  excludeEventKey: '2026zzz',
  now: () => DateTime(2026, 10, 27),
);

List<Map<String, dynamic>> _played(
  String event, {
  int quals = 0,
  int playoffs = 0,
  int start = 1000,
}) => [
  for (var i = 1; i <= quals; i++)
    tbaMatch('${event}_qm$i', time: start + i * 60, video: 'q${i}xxxxxxxxx'),
  for (var i = 1; i <= playoffs; i++)
    tbaMatch(
      '${event}_sf${i}m1',
      time: start + 10000 + i * 60,
      video: 'p${i}xxxxxxxxx',
    ),
];

void main() {
  test('takes the last 3 quals and last 2 playoffs of the newest event, in '
      'the order they were played', () async {
    final plan = await _finder(
      fakePrescoutTba(
        events: [
          tbaEvent(
            '2026aaa',
            'Event A',
            start: '2026-03-01',
            end: '2026-03-03',
          ),
          tbaEvent(
            '2026bbb',
            'Event B',
            start: '2026-09-18',
            end: '2026-09-20',
          ),
        ],
        matchesByEvent: {
          '2026bbb': _played('2026bbb', quals: 6, playoffs: 4),
          '2026aaa': _played('2026aaa', quals: 9, playoffs: 2),
        },
      ),
    ).find(1234);

    expect(plan.matches.map((m) => m.label), [
      'Q4',
      'Q5',
      'Q6',
      'Playoff 3',
      'Playoff 4',
    ]);
    expect(plan.matches.every((m) => m.eventName == 'Event B'), isTrue);
    expect(plan.note, isNull);
  });

  test(
    'skips our own event, preseason events and events not started',
    () async {
      final log = <String>[];
      final plan = await _finder(
        fakePrescoutTba(
          log: log,
          events: [
            tbaEvent(
              '2026zzz',
              'Our Event',
              start: '2026-10-01',
              end: '2026-10-02',
            ),
            tbaEvent(
              '2026ppp',
              'Event P',
              start: '2026-02-01',
              end: '2026-02-01',
              type: 100,
            ),
            tbaEvent(
              '2026sss',
              'Event S',
              start: '2026-11-07',
              end: '2026-11-08',
            ),
            tbaEvent(
              '2026lll',
              'Event L',
              start: '2026-09-01',
              end: '2026-09-02',
            ),
          ],
          matchesByEvent: {
            '2026lll': _played('2026lll', quals: 3, playoffs: 2),
          },
        ),
      ).find(1234);

      expect(plan.matches, hasLength(5));
      expect(log.where((p) => p.contains('/matches')), [
        '/api/v3/team/frc1234/event/2026lll/matches',
      ]);
    },
  );

  test('a team that missed playoffs gets 5 quals, and says so', () async {
    final plan = await _finder(
      fakePrescoutTba(
        events: [
          tbaEvent(
            '2026aaa',
            'Event A',
            start: '2026-03-20',
            end: '2026-03-22',
          ),
        ],
        matchesByEvent: {'2026aaa': _played('2026aaa', quals: 10)},
      ),
    ).find(1234);

    expect(plan.matches.map((m) => m.label), ['Q6', 'Q7', 'Q8', 'Q9', 'Q10']);
    expect(plan.note, 'Event A: no playoff videos, so 5 quals instead');
  });

  test('an event with no videos is skipped for the one before it', () async {
    final plan = await _finder(
      fakePrescoutTba(
        events: [
          tbaEvent(
            '2026bbb',
            'Event B',
            start: '2026-10-23',
            end: '2026-10-25',
          ),
          tbaEvent(
            '2026aaa',
            'Event A',
            start: '2026-09-18',
            end: '2026-09-20',
          ),
        ],
        matchesByEvent: {
          '2026bbb': [tbaMatch('2026bbb_qm1', time: 5000)],
          '2026aaa': _played('2026aaa', quals: 4, playoffs: 3),
        },
      ),
    ).find(1234);

    expect(plan.matches, hasLength(5));
    expect(plan.matches.every((m) => m.eventKey == '2026aaa'), isTrue);
    expect(plan.note, 'Event B had no match videos');
  });

  test('a short event is topped up from the event before it', () async {
    final plan = await _finder(
      fakePrescoutTba(
        events: [
          tbaEvent(
            '2026bbb',
            'Event B',
            start: '2026-04-01',
            end: '2026-04-03',
          ),
          tbaEvent(
            '2026aaa',
            'Event A',
            start: '2026-03-01',
            end: '2026-03-03',
          ),
        ],
        matchesByEvent: {
          '2026bbb': _played('2026bbb', quals: 1, playoffs: 1),
          '2026aaa': _played('2026aaa', quals: 5, playoffs: 2),
        },
      ),
    ).find(1234);

    expect(plan.matches.map((m) => '${m.eventKey} ${m.label}'), [
      '2026bbb Q1',
      '2026bbb Playoff 1',
      '2026aaa Q4',
      '2026aaa Q5',
      '2026aaa Playoff 2',
    ]);
    expect(plan.note, 'Event B: 1 qual and 1 playoff; the rest from Event A');
  });

  test('no videos anywhere is an empty plan with a note', () async {
    final plan = await _finder(
      fakePrescoutTba(
        events: [
          tbaEvent(
            '2026aaa',
            'Event A',
            start: '2026-03-01',
            end: '2026-03-03',
          ),
        ],
        matchesByEvent: {
          '2026aaa': [tbaMatch('2026aaa_qm1', time: 1)],
        },
      ),
    ).find(1234);

    expect(plan.matches, isEmpty);
    expect(plan.note, contains('no match videos for 1234'));
  });

  test('a match not yet played is not offered, even with a video', () async {
    final plan = await _finder(
      fakePrescoutTba(
        events: [
          tbaEvent(
            '2026aaa',
            'Event A',
            start: '2026-03-01',
            end: '2026-03-03',
          ),
        ],
        matchesByEvent: {
          '2026aaa': [
            tbaMatch('2026aaa_qm1', time: 1, video: 'q1xxxxxxxxx'),
            tbaMatch(
              '2026aaa_qm2',
              time: 2,
              video: 'q2xxxxxxxxx',
              played: false,
            ),
          ],
        },
      ),
    ).find(1234);

    expect(plan.matches.map((m) => m.label), ['Q1']);
  });

  test('the video link keeps TBA\'s start offset', () async {
    final plan = await _finder(
      fakePrescoutTba(
        events: [
          tbaEvent(
            '2026aaa',
            'Event A',
            start: '2026-03-01',
            end: '2026-03-03',
          ),
        ],
        matchesByEvent: {
          '2026aaa': [
            tbaMatch('2026aaa_f1m2', time: 1, video: 'abcdefghijk?t=95'),
          ],
        },
      ),
    ).find(1234);

    expect(plan.matches.single.label, 'Final 2');
    expect(
      plan.matches.single.videoUrl,
      'https://www.youtube.com/watch?v=abcdefghijk&t=95',
    );
  });

  test(
    'a failed lookup is retried on the next call, a good one is cached',
    () async {
      var calls = 0;
      var fail = true;
      final client = TbaClient(
        config: InMemoryTbaConfig('test-key'),
        httpClient: MockClient((request) async {
          calls++;
          if (fail) return http.Response('boom', 500);
          return http.Response('[]', 200);
        }),
      );
      final finder = _finder(client);

      await expectLater(finder.find(1234), throwsA(isA<TbaApiException>()));
      fail = false;
      await finder.find(1234);
      await finder.find(1234);

      expect(calls, 2);
    },
  );

  test('a match list that fails to load fails the lookup, so it is retried '
      'rather than cached short', () async {
    var fail = true;
    final client = TbaClient(
      config: InMemoryTbaConfig('test-key'),
      httpClient: MockClient((request) async {
        if (request.url.path.contains('/events/')) {
          return http.Response(
            jsonEncode([
              tbaEvent(
                '2026aaa',
                'Event A',
                start: '2026-03-01',
                end: '2026-03-03',
              ),
            ]),
            200,
          );
        }
        if (fail) return http.Response('boom', 500);
        return http.Response(
          jsonEncode(_played('2026aaa', quals: 3, playoffs: 2)),
          200,
        );
      }),
    );
    final finder = _finder(client);

    await expectLater(finder.find(1234), throwsA(isA<TbaApiException>()));
    fail = false;
    expect((await finder.find(1234)).matches, hasLength(5));
  });

  test('a video with no id is not offered', () async {
    final plan = await _finder(
      fakePrescoutTba(
        events: [
          tbaEvent(
            '2026aaa',
            'Event A',
            start: '2026-03-01',
            end: '2026-03-03',
          ),
        ],
        matchesByEvent: {
          '2026aaa': [
            tbaMatch('2026aaa_qm1', time: 1, video: ''),
            tbaMatch('2026aaa_qm2', time: 2, video: 'abcdefghijk?t=%zz'),
          ],
        },
      ),
    ).find(1234);

    expect(plan.matches.map((m) => m.label), ['Q2']);
    expect(
      plan.matches.single.videoUrl,
      'https://www.youtube.com/watch?v=abcdefghijk',
    );
  });
}
