import 'package:flutter_test/flutter_test.dart';

import 'package:spectrumstrategy/src/models/strategy_session.dart';
import 'package:spectrumstrategy/src/services/board_event_scope.dart';
import 'package:spectrumstrategy/src/services/match_directory.dart';
import 'package:spectrumstrategy/src/state/strategy_controller.dart';

import 'support/fake_match_directory.dart';

bool scoped({
  String selected = '2026txdri1',
  required String board,
  bool only = true,
}) => boardInScope(
  selectedEventKey: selected,
  boardEventKey: board,
  thisEventOnly: only,
);

void main() {
  group('boardInScope', () {
    test('a board for the selected event is in scope', () {
      expect(scoped(board: '2026txdri1'), isTrue);
    });

    test('a board for another event is out of scope', () {
      expect(scoped(board: '2026txcmp'), isFalse);
    });

    test('a board with no key stays in scope', () {
      expect(scoped(board: ''), isTrue);
    });

    test('nothing is filtered when the toggle is off', () {
      expect(scoped(board: '2026txcmp', only: false), isTrue);
    });

    test('nothing is filtered when no event is selected', () {
      expect(scoped(selected: '', board: '2026txcmp'), isTrue);
    });
  });

  group('scopeBoardLists', () {
    MatchSummary summary(String id, {String eventKey = '', int number = 1}) =>
        MatchSummary(
          id: id,
          eventKey: eventKey,
          eventName: '',
          matchNumber: number,
          alliance: 'Red',
          updatedAt: DateTime.utc(2026, 8, 5),
        );

    StrategySession remote(String id, {String eventKey = ''}) =>
        StrategySession.create(id: id, eventKey: eventKey);

    test('keeps this event and the unkeyed boards, drops another event', () {
      final lists = scopeBoardLists(
        allMatches: <MatchSummary>[
          summary('a', eventKey: '2026txdri1'),
          summary('b', eventKey: 'other'),
          summary('c'),
        ],
        remoteBoards: <StrategySession>[
          remote('d', eventKey: '2026txdri1'),
          remote('e', eventKey: 'other'),
        ],
        selectedEventKey: '2026txdri1',
        thisEventOnly: true,
      );

      expect(lists.matches.map((MatchSummary m) => m.id), <String>['a', 'c']);
      expect(lists.teamBoards.map((StrategySession b) => b.id), <String>['d']);
      expect(lists.hidden, 2);
      expect(lists.isEmpty, isFalse);
    });

    test('a team board is deduplicated against every local id', () {
      final lists = scopeBoardLists(
        allMatches: <MatchSummary>[summary('a', eventKey: 'other')],
        remoteBoards: <StrategySession>[remote('a', eventKey: '2026txdri1')],
        selectedEventKey: '2026txdri1',
        thisEventOnly: true,
      );

      expect(lists.teamBoards, isEmpty);
      expect(lists.matches, isEmpty);
      expect(lists.hidden, 1, reason: 'the local copy is the hidden one');
    });

    test('the filter off shows everything and hides nothing', () {
      final lists = scopeBoardLists(
        allMatches: <MatchSummary>[
          summary('a', eventKey: '2026txdri1'),
          summary('b', eventKey: 'other'),
        ],
        remoteBoards: <StrategySession>[remote('c', eventKey: 'other')],
        selectedEventKey: '2026txdri1',
        thisEventOnly: false,
      );

      expect(lists.matches, hasLength(2));
      expect(lists.teamBoards, hasLength(1));
      expect(lists.hidden, 0);
    });

    test('an empty result still reports what it hid', () {
      final lists = scopeBoardLists(
        allMatches: <MatchSummary>[summary('a', eventKey: 'other')],
        remoteBoards: <StrategySession>[remote('b', eventKey: 'other')],
        selectedEventKey: '2026txdri1',
        thisEventOnly: true,
      );

      expect(lists.isEmpty, isTrue);
      expect(
        lists.hidden,
        2,
        reason: 'the empty state says "none for this event", not "none at all"',
      );
    });
  });

  test('a board keeps the key it was created with', () async {
    final controller = StrategyController(directory: FakeMatchDirectory());
    await controller.bootstrap();

    await controller.createMatch(
      eventName: 'Test Event',
      eventKey: '2026txdri1',
      matchNumber: 12,
    );
    await controller.saveNow();

    expect(controller.session.eventKey, '2026txdri1');
    final List<MatchSummary> stored = await controller.listMatches();
    expect(
      stored.firstWhere((MatchSummary s) => s.matchNumber == 12).eventKey,
      '2026txdri1',
      reason: 'the picker filters on the summary, so the key has to reach it',
    );
  });

  test('a fresh session has no key, which is the unplaceable case', () {
    expect(StrategySession.create().eventKey, isEmpty);
  });
}
