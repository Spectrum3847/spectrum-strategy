import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:spectrumstrategy/src/models/draft_board.dart';
import 'package:spectrumstrategy/src/state/draft_controller.dart';

final _ranking = List<int>.generate(12, (i) => i + 1);

DraftBoard _replay(List<DraftAction> actions) =>
    DraftBoard.replay(actions, _ranking);

void main() {
  test(
    'the top eight seeds start as captains and alliance 1 is on the clock',
    () {
      final board = _replay(const []);
      expect(
        [for (final a in board.alliances) a.captain],
        [1, 2, 3, 4, 5, 6, 7, 8],
      );
      expect(board.picking, 0);
      expect(board.round, 0);
    },
  );

  test('a pick goes to the alliance on the clock and the clock moves on', () {
    final board = _replay([const DraftAction.pick(9)]);
    expect(board.alliances[0].picks, [9]);
    expect(board.picking, 1);
    expect(board.canInvite(9), isFalse);
  });

  test('round two runs in reverse', () {
    final round1 = [for (var t = 20; t < 28; t++) DraftAction.pick(t)];
    final board = _replay([...round1, const DraftAction.pick(30)]);
    expect(board.alliances[7].picks, [27, 30]);
    expect(board.picking, 6);
    expect(board.round, 1);
    expect(_replay(round1).picking, 7);
  });

  test(
    'a captain who accepts leaves, alliances move up, a new captain is seated',
    () {
      final board = _replay([const DraftAction.pick(5)]);
      expect(
        [for (final a in board.alliances) a.captain],
        [1, 2, 3, 4, 6, 7, 8, 9],
      );
      expect(board.alliances[0].picks, [5]);
      expect(board.taken, contains(9));
      expect(board.picking, 1);
    },
  );

  test('only a captain below the clock who has not picked can be invited', () {
    final board = _replay(const []);
    expect(board.canInvite(1), isFalse);
    expect(board.canInvite(2), isTrue);
    expect(board.canInvite(12), isTrue);
    final after = _replay([const DraftAction.pick(12)]);

    expect(after.canInvite(1), isFalse);
    expect(after.canInvite(2), isFalse);
    expect(after.canInvite(3), isTrue);
  });

  test('a decline keeps the clock and the team cannot be asked again', () {
    final board = _replay([const DraftAction.decline(9)]);
    expect(board.picking, 0);
    expect(board.declined, contains(9));
    expect(board.canInvite(9), isFalse);
    expect(board.turn, 0);
  });

  test('an illegal action in the log is skipped', () {
    final board = _replay([
      const DraftAction.pick(1),
      const DraftAction.pick(9),
      const DraftAction.pick(9),
    ]);
    expect(board.alliances[0].picks, [9]);
    expect(board.turn, 1);
  });

  test('the draft ends after three rounds', () {
    final board = _replay([
      for (var t = 100; t < 124; t++) DraftAction.pick(t),
    ]);
    expect(board.isComplete, isTrue);
    expect(board.picking, isNull);
    expect(board.canInvite(200), isFalse);
  });

  group('rounds', () {
    List<DraftAction> fill(int round) => [
      for (var t = 0; t < 8; t++) DraftAction.pick(100 + round * 8 + t),
    ];
    DraftBoard replay(List<DraftAction> actions, {int rounds = 2}) =>
        DraftBoard.replay(actions, _ranking, rounds: rounds);

    test('three rounds is the default', () {
      expect(_replay(const []).rounds, 3);
      expect(_replay(const []).allianceSize, 4);
    });

    test('a two round draft completes after sixteen picks', () {
      final almost = replay([...fill(0), ...fill(1).take(7)]);
      expect(almost.isComplete, isFalse);
      expect(almost.picking, 0);
      final done = replay([...fill(0), ...fill(1)]);
      expect(done.isComplete, isTrue);
      expect(done.allianceSize, 3);
      expect([for (final a in done.alliances) a.picks.length], everyElement(2));
    });

    test('picks past the end of a two round draft are ignored', () {
      final board = replay([...fill(0), ...fill(1), ...fill(2)]);
      expect([
        for (final a in board.alliances) a.picks.length,
      ], everyElement(2));
    });

    test('picksUntil counts picks to the alliance across the snake', () {
      final start = replay(const []);
      expect(start.picksUntil(1), 0);
      expect(start.picksUntil(4), 3);
      expect(start.picksUntil(8), 7);

      final turned = replay(fill(0));
      expect(turned.picksUntil(8), 0);
      expect(turned.picksUntil(1), 7);
      expect(turned.picksUntil(5), 3);
    });

    test('picksUntil is null for a team off the board or a finished draft', () {
      expect(replay(const []).picksUntil(99), isNull);
      final done = replay([...fill(0), ...fill(1)]);
      expect(done.picksUntil(1), isNull);
    });

    test('picksUntil follows a picked team onto its alliance', () {
      final board = replay([const DraftAction.pick(12)]);
      expect(board.picksUntil(12), 14);
      expect(board.picksUntil(1), 14);
    });

    test('backups are the best free teams in rank order, top eight', () {
      final ranking = List<int>.generate(30, (i) => i + 1);
      final picks = [for (var t = 9; t < 17; t++) DraftAction.pick(t)];
      final second = [for (var t = 17; t < 25; t++) DraftAction.pick(t)];
      final board = DraftBoard.replay(
        [const DraftAction.decline(26), ...picks, ...second],
        ranking,
        rounds: 2,
      );
      expect(board.isComplete, isTrue);
      expect(board.backups(ranking), [25, 27, 28, 29, 30]);
    });

    test('backups stop at eight teams and skip captains and picks', () {
      final ranking = List<int>.generate(40, (i) => i + 1);
      final board = DraftBoard.replay(
        [for (var t = 9; t < 25; t++) DraftAction.pick(t)],
        ranking,
        rounds: 2,
      );
      expect(board.backups(ranking), [25, 26, 27, 28, 29, 30, 31, 32]);
    });

    test('no backups mid-draft, after three rounds, or without a ranking', () {
      final ranking = List<int>.generate(40, (i) => i + 1);
      final picks = [for (var t = 9; t < 25; t++) DraftAction.pick(t)];
      expect(
        DraftBoard.replay(
          picks.take(15).toList(),
          ranking,
          rounds: 2,
        ).backups(ranking),
        isEmpty,
      );
      expect(DraftBoard.replay(picks, ranking).backups(ranking), isEmpty);
      final two = DraftBoard.replay(picks, ranking, rounds: 2);
      expect(two.backups(const <int>[]), isEmpty);
    });
  });

  group('DraftController', () {
    setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

    test('undo removes the last action and reset clears the log', () async {
      final controller = DraftController();
      await controller.load('2026test');
      await controller.pick(9);
      await controller.decline(10);
      expect(controller.actions.length, 2);
      await controller.undo();
      expect(controller.actions.single.team, 9);
      await controller.reset();
      expect(controller.canUndo, isFalse);
    });

    test('rounds default to three and persist per event', () async {
      final first = DraftController();
      await first.load('2026test');
      expect(first.rounds, 3);
      await first.setRounds(2);
      await first.setRounds(5);
      expect(first.rounds, 2);

      final second = DraftController();
      await second.load('2026test');
      expect(second.rounds, 2);
      final other = DraftController();
      await other.load('2026other');
      expect(other.rounds, 3);
    });

    test('the log survives a restart and is kept per event', () async {
      final first = DraftController();
      await first.load('2026test');
      await first.pick(9);
      await first.decline(10);

      final second = DraftController();
      await second.load('2026test');
      expect(second.actions.map((a) => (a.team, a.declined)), [
        (9, false),
        (10, true),
      ]);

      final other = DraftController();
      await other.load('2026other');
      expect(other.actions, isEmpty);
    });
  });
}
