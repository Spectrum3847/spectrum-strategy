import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:spectrumstrategy/src/models/strategy_session.dart';
import 'package:spectrumstrategy/src/services/match_directory.dart';
import 'package:spectrumstrategy/src/state/strategy_controller.dart';
import 'package:spectrumstrategy/src/theme/strategy_palette.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Map<String, dynamic> validSessionJson(String id) =>
      (StrategySession.create(id: id)..eventName = 'Test Event').toJson();

  String boardKey(String id) => 'strategy_match_v3_$id';

  int stampFor(String raw) {
    var hash = 0x811c9dc5;
    for (var i = 0; i < raw.length; i++) {
      final unit = raw.codeUnitAt(i);
      hash ^= unit & 0xff;
      hash = (hash * 0x01000193) & 0xffffffff;
      hash ^= (unit >> 8) & 0xff;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash;
  }

  Map<String, dynamic> summaryEntry(MatchSummary summary, {int? stamp}) =>
      <String, dynamic>{
        'summary': summary.toJson(),
        'stamp': stamp ?? stampFor(jsonEncode(summary.toJson())),
      };

  test('unparseable board record reads as absent and stays writable', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      boardKey('anything'): 'not json at all {',
    });
    final directory = SharedPreferencesMatchDirectory();

    expect(await directory.loadMatch('anything'), isNull);
    expect(await directory.listMatches(), isEmpty);

    final session = StrategySession.create(id: 'fresh');
    await directory.saveMatch(session);
    expect((await directory.listMatches()).single.id, 'fresh');
  });

  test('non-map record is skipped by listMatches and loads as null', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      boardKey('good'): jsonEncode(validSessionJson('good')),
      boardKey('bad'): jsonEncode('this is not a session map'),
    });
    final directory = SharedPreferencesMatchDirectory();

    final summaries = await directory.listMatches();
    expect(summaries.single.id, 'good');
    expect(await directory.loadMatch('bad'), isNull);
    expect((await directory.loadMatch('good'))?.eventName, 'Test Event');
  });

  test(
    'record with corrupt fields loads with fallbacks, not a throw',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        boardKey('mangled'): jsonEncode(<String, dynamic>{
          'id': 'mangled',
          'eventName': 12345,
          'matchNumber': 'seven',
          'teamNumbers': <dynamic>[3847, 'oops', 2714],
          'selectedPhase': 'banana',
          'selectedTool': <String, dynamic>{},
          'strokesByPhase': <String, dynamic>{
            'notAPhase': <dynamic>[],
            'teleop': 'not a list',
          },
          'markersByPhase': <dynamic>['not', 'a', 'map'],
          'notesByPhase': <String, dynamic>{'auton': 99},
        }),
      });
      final directory = SharedPreferencesMatchDirectory();

      final session = await directory.loadMatch('mangled');
      expect(session, isNotNull);
      expect(session!.eventName, '');
      expect(session.matchNumber, 1);
      expect(session.teamNumbers, <int>[3847, 2714]);
      expect(session.selectedPhase, StrategyPhase.auton);
      expect(session.selectedTool, StrategyTool.draw);
      expect(session.strokesFor(StrategyPhase.teleop), isEmpty);
      expect(session.noteFor(StrategyPhase.auton), '');
    },
  );

  test(
    'listMatches builds the summary index from board keys on first read',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        boardKey('one'): jsonEncode(validSessionJson('one')),
        boardKey('two'): jsonEncode(validSessionJson('two')),
      });
      final directory = SharedPreferencesMatchDirectory();

      final summaries = await directory.listMatches();
      expect(summaries.map((s) => s.id), containsAll(<String>['one', 'two']));

      final prefs = await SharedPreferences.getInstance();
      final rawSummaries = prefs.getString('strategy_match_summaries_v2');
      expect(rawSummaries, isNotNull);
      final decoded = jsonDecode(rawSummaries!) as Map<String, dynamic>;
      expect(decoded.keys, containsAll(<String>['one', 'two']));
    },
  );

  test('listMatches trusts a summary entry whose stamp matches the current '
      'board instead of reparsing it', () async {
    final boardRaw = jsonEncode(validSessionJson('one'));
    SharedPreferences.setMockInitialValues(<String, Object>{
      boardKey('one'): boardRaw,
      'strategy_match_summaries_v2': jsonEncode(<String, dynamic>{
        'one': summaryEntry(
          MatchSummary.fromSession(
            StrategySession.create(id: 'one')..eventName = 'Cached label',
          ),
          stamp: stampFor(boardRaw),
        ),
      }),
    });
    final directory = SharedPreferencesMatchDirectory();

    final summaries = await directory.listMatches();
    expect(summaries.single.eventName, 'Cached label');
  });

  test('a summary entry whose stamp no longer matches the board is repaired, '
      'not trusted -- the real crash direction: the board write landed, the '
      'summary update did not', () async {
    final beforeJson = validSessionJson('one');
    beforeJson['eventName'] = 'Before the crash';
    final beforeRaw = jsonEncode(beforeJson);

    final updatedJson = validSessionJson('one');
    updatedJson['eventName'] = 'Updated after crash';
    final updatedRaw = jsonEncode(updatedJson);

    expect(beforeRaw.length, isNot(updatedRaw.length));

    SharedPreferences.setMockInitialValues(<String, Object>{
      boardKey('one'): updatedRaw,
      'strategy_match_summaries_v2': jsonEncode(<String, dynamic>{
        'one': summaryEntry(
          MatchSummary.fromSession(
            StrategySession.create(id: 'one')..eventName = 'Before the crash',
          ),
          stamp: stampFor(beforeRaw),
        ),
      }),
    });
    final directory = SharedPreferencesMatchDirectory();

    final summaries = await directory.listMatches();
    expect(summaries.single.eventName, 'Updated after crash');

    final prefs = await SharedPreferences.getInstance();
    final decoded = jsonDecode(
      prefs.getString('strategy_match_summaries_v2')!,
    ) as Map<String, dynamic>;
    final entry = decoded['one'] as Map<String, dynamic>;
    expect(entry['stamp'], stampFor(updatedRaw));
  });

  test(
    'a board key missing from the summary index is repaired, not hidden',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        boardKey('one'): jsonEncode(validSessionJson('one')),
        boardKey('two'): jsonEncode(validSessionJson('two')),
        'strategy_match_summaries_v2': jsonEncode(<String, dynamic>{
          'one': summaryEntry(
            MatchSummary.fromSession(
              StrategySession.create(id: 'one')..eventName = 'Test Event',
            ),
          ),
        }),
      });
      final directory = SharedPreferencesMatchDirectory();

      final summaries = await directory.listMatches();
      expect(summaries.map((s) => s.id), containsAll(<String>['one', 'two']));

      final prefs = await SharedPreferences.getInstance();
      final decoded = jsonDecode(
        prefs.getString('strategy_match_summaries_v2')!,
      ) as Map<String, dynamic>;
      expect(decoded.keys, containsAll(<String>['one', 'two']));
    },
  );

  test(
    'a summary entry with no matching board key is dropped, not resurrected',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        boardKey('one'): jsonEncode(validSessionJson('one')),
        'strategy_match_summaries_v2': jsonEncode(<String, dynamic>{
          'one': summaryEntry(
            MatchSummary.fromSession(
              StrategySession.create(id: 'one')..eventName = 'Test Event',
            ),
          ),
          'ghost': summaryEntry(
            MatchSummary.fromSession(
              StrategySession.create(id: 'ghost')..eventName = 'Gone',
            ),
          ),
        }),
      });
      final directory = SharedPreferencesMatchDirectory();

      final summaries = await directory.listMatches();
      expect(summaries.map((s) => s.id), <String>['one']);

      final prefs = await SharedPreferences.getInstance();
      final decoded = jsonDecode(
        prefs.getString('strategy_match_summaries_v2')!,
      ) as Map<String, dynamic>;
      expect(decoded.keys, isNot(contains('ghost')));
    },
  );

  test('saveMatch and deleteMatch keep the summary key in sync', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final directory = SharedPreferencesMatchDirectory();

    final session = StrategySession.create(id: 'fresh')..eventName = 'Regional';
    await directory.saveMatch(session);

    var summaries = await directory.listMatches();
    expect(summaries.single.eventName, 'Regional');

    session.eventName = 'Renamed';
    await directory.saveMatch(session);
    summaries = await directory.listMatches();
    expect(summaries.single.eventName, 'Renamed');

    final prefs = await SharedPreferences.getInstance();
    final decoded = jsonDecode(
      prefs.getString('strategy_match_summaries_v2')!,
    ) as Map<String, dynamic>;
    final entry = decoded['fresh'] as Map<String, dynamic>;
    expect(entry['stamp'], stampFor(prefs.getString(boardKey('fresh'))!));

    await directory.deleteMatch('fresh');
    summaries = await directory.listMatches();
    expect(summaries, isEmpty);
    expect(prefs.getString(boardKey('fresh')), isNull);
  });

  test(
    'a corrupt summary entry is skipped, not thrown, by listMatches',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        boardKey('good'): jsonEncode(validSessionJson('good')),
        'strategy_match_summaries_v2': jsonEncode(<String, dynamic>{
          'good': summaryEntry(
            MatchSummary.fromSession(
              StrategySession.create(id: 'good')..eventName = 'Good',
            ),
          ),
          'bad': 'this is not a summary entry',
        }),
      });
      final directory = SharedPreferencesMatchDirectory();

      final summaries = await directory.listMatches();
      expect(summaries.single.id, 'good');
    },
  );

  test('a board that becomes unreadable loses its stale summary row rather '
      'than pinning it in the picker forever', () async {
    final summary = MatchSummary(
      id: 'x',
      eventName: 'Stale Event',
      matchNumber: 7,
      alliance: 'red',
      updatedAt: DateTime.utc(2026),
    );
    SharedPreferences.setMockInitialValues(<String, Object>{
      boardKey('x'): '{not valid json',
      'strategy_match_summaries_v2': jsonEncode(<String, dynamic>{
        'x': summaryEntry(summary, stamp: 12345),
      }),
    });
    final directory = SharedPreferencesMatchDirectory();

    expect(await directory.listMatches(), isEmpty);
    expect(await directory.loadMatch('x'), isNull);

    expect(await directory.listMatches(), isEmpty);
    final prefs = await SharedPreferences.getInstance();
    final decoded = jsonDecode(
      prefs.getString('strategy_match_summaries_v2')!,
    ) as Map<String, dynamic>;
    expect(decoded.containsKey('x'), isFalse);
  });

  test('an equal-length edit still invalidates the stamp', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final directory = SharedPreferencesMatchDirectory();
    final session = StrategySession.create(id: 'eq')..eventName = 'AAAA';
    await directory.saveMatch(session);
    expect((await directory.listMatches()).single.eventName, 'AAAA');

    final prefs = await SharedPreferences.getInstance();
    final before = prefs.getString(boardKey('eq'))!;
    final edited = before.replaceFirst(
      '"eventName":"AAAA"',
      '"eventName":"BBBB"',
    );
    expect(edited.length, before.length);
    expect(edited, isNot(before));
    await prefs.setString(boardKey('eq'), edited);

    expect((await directory.listMatches()).single.eventName, 'BBBB');
  });

  group('concurrent summary writes (PR #1506 review finding)', () {
    test('a listMatches racing a saveMatch does not lose the save', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final directory = SharedPreferencesMatchDirectory();
      await directory.saveMatch(
        StrategySession.create(id: 'a')..eventName = 'Before',
      );

      final renamed = StrategySession.create(id: 'a')..eventName = 'After';
      final save = directory.saveMatch(renamed);
      final list = directory.listMatches();
      await Future.wait<void>([save, list]);

      final prefs = await SharedPreferences.getInstance();
      final decoded = jsonDecode(
        prefs.getString('strategy_match_summaries_v2')!,
      ) as Map<String, dynamic>;
      final entry = decoded['a'] as Map<String, dynamic>;
      expect(entry['stamp'], stampFor(prefs.getString(boardKey('a'))!));
      expect((entry['summary'] as Map<String, dynamic>)['eventName'], 'After');
      expect((await directory.listMatches()).single.eventName, 'After');
    });

    test(
      'a listMatches racing a deleteMatch does not resurrect the board',
      () async {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        final directory = SharedPreferencesMatchDirectory();
        await directory.saveMatch(
          StrategySession.create(id: 'doomed')..eventName = 'Regional',
        );

        final delete = directory.deleteMatch('doomed');
        final list = directory.listMatches();
        await Future.wait<void>([delete, list]);

        final prefs = await SharedPreferences.getInstance();
        final decoded = jsonDecode(
          prefs.getString('strategy_match_summaries_v2')!,
        ) as Map<String, dynamic>;
        expect(decoded.containsKey('doomed'), isFalse);
        expect(prefs.getString(boardKey('doomed')), isNull);
        expect(await directory.listMatches(), isEmpty);
      },
    );

    test('overlapping saves of different boards both survive', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final directory = SharedPreferencesMatchDirectory();

      await Future.wait<void>([
        for (var i = 0; i < 8; i++)
          directory.saveMatch(
            StrategySession.create(id: 'b$i')..eventName = 'Event $i',
          ),
      ]);

      final summaries = await directory.listMatches();
      expect(summaries.length, 8);
      expect(summaries.map((s) => s.eventName).toSet(), {
        for (var i = 0; i < 8; i++) 'Event $i',
      });
    });
  });

  test('MatchSummary.fromJson rejects a record missing an id, not a throw', () {
    expect(
      () => MatchSummary.fromJson(<String, dynamic>{'eventName': 'X'}),
      throwsFormatException,
    );
  });

  test(
    'controller bootstrap falls back when the active match is bad',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        boardKey('good'): jsonEncode(validSessionJson('good')),
        boardKey('bad'): jsonEncode('this is not a session map'),
        'strategy_active_match_id': 'bad',
      });
      final controller = StrategyController(
        directory: SharedPreferencesMatchDirectory(),
      );

      await controller.bootstrap();

      expect(controller.isReady, isTrue);
      expect(controller.session.id, 'good');
    },
  );

  group('legacy whole-directory blob migration (#1478 item 3)', () {
    test(
      'copies every board into its own key and drops the legacy keys',
      () async {
        final matchesJson = jsonEncode(<String, dynamic>{
          'one': validSessionJson('one'),
          'two': validSessionJson('two'),
        });
        SharedPreferences.setMockInitialValues(<String, Object>{
          'strategy_matches_v2': matchesJson,
          'strategy_match_summaries_v1': jsonEncode(<String, dynamic>{
            'stamp': stampFor(matchesJson),
            'entries': <String, dynamic>{},
          }),
        });
        final directory = SharedPreferencesMatchDirectory();

        final summaries = await directory.listMatches();
        expect(summaries.map((s) => s.id), containsAll(<String>['one', 'two']));

        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString(boardKey('one')), isNotNull);
        expect(prefs.getString(boardKey('two')), isNotNull);
        expect(prefs.getString('strategy_matches_v2'), isNull);
        expect(prefs.getString('strategy_match_summaries_v1'), isNull);
      },
    );

    test('a kill mid-migration is repeated safely on next read', () async {
      final freshOne = validSessionJson('one');
      freshOne['eventName'] = 'Saved since migration attempt';
      final staleOneInBlob = validSessionJson('one');
      staleOneInBlob['eventName'] = 'Stale legacy copy';
      final matchesJson = jsonEncode(<String, dynamic>{
        'one': staleOneInBlob,
        'two': validSessionJson('two'),
      });
      SharedPreferences.setMockInitialValues(<String, Object>{
        boardKey('one'): jsonEncode(freshOne),
        'strategy_matches_v2': matchesJson,
      });
      final directory = SharedPreferencesMatchDirectory();

      final summaries = await directory.listMatches();
      expect(
        summaries.firstWhere((s) => s.id == 'one').eventName,
        'Saved since migration attempt',
      );
      expect(summaries.map((s) => s.id), containsAll(<String>['one', 'two']));

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('strategy_matches_v2'), isNull);
    });

    test(
      'a malformed legacy board is copied verbatim and skipped on read',
      () async {
        final matchesJson = jsonEncode(<String, dynamic>{
          'good': validSessionJson('good'),
          'bad': 'this is not a session map',
        });
        SharedPreferences.setMockInitialValues(<String, Object>{
          'strategy_matches_v2': matchesJson,
        });
        final directory = SharedPreferencesMatchDirectory();

        final summaries = await directory.listMatches();
        expect(summaries.single.id, 'good');
        expect(await directory.loadMatch('bad'), isNull);

        final prefs = await SharedPreferences.getInstance();

        expect(prefs.getString(boardKey('bad')), isNotNull);
        expect(prefs.getString('strategy_matches_v2'), isNull);
      },
    );
  });

  group('legacy single-session draft migration', () {
    test('migrates the legacy single-blob draft into its own key', () async {
      final legacySession = StrategySession.create()..eventName = 'Legacy';
      SharedPreferences.setMockInitialValues(<String, Object>{
        'strategy_session_draft': jsonEncode(legacySession.toJson()),
      });
      final directory = SharedPreferencesMatchDirectory();

      final summaries = await directory.listMatches();
      expect(summaries.single.id, legacySession.id);
      expect(summaries.single.eventName, 'Legacy');
      expect(await directory.getActiveMatchId(), legacySession.id);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('strategy_session_draft'), isNull);
      expect(prefs.getString(boardKey(legacySession.id)), isNotNull);
    });
  });
}
