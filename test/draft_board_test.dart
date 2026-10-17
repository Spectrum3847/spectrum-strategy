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
