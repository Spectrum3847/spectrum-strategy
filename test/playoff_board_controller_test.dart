import 'package:flutter_test/flutter_test.dart';
import 'package:spectrumstrategy/src/models/playoff_board.dart';
import 'package:spectrumstrategy/src/state/playoff_board_controller.dart';

import 'support/fake_playoff_board_storage.dart';

void main() {
  group('PlayoffBoard', () {
    test('reads meeting teams top-left first, then across, then down', () {
      const board = PlayoffBoard(
        meetingCells: <String, String>{
          '1,0': '118',
          '0,2': '254',
          '0,0': '971',
          '2,4': 'not a team',
        },
      );

      expect(board.meetingTeamsInReadingOrder, <int>[971, 254, 118]);
    });

    test('clearing a cell removes it rather than storing an empty string', () {
      final board = const PlayoffBoard()
          .withMeetingCell(0, 0, '3847')
          .withMeetingCell(0, 0, '   ');

      expect(board.meetingCells, isEmpty);
    });

    test('clearing an override falls back to the computed value', () {
      final board = const PlayoffBoard()
          .withMatchInfoOverride('k', '12')
          .withMatchInfoOverride('k', '');

      expect(board.matchInfoOverrides.containsKey('k'), isFalse);
    });

    test('round-trips through json', () {
      final board = const PlayoffBoard()
          .withMeetingCell(3, 2, '1678')
          .withAllianceCell(0, 0, '3847')
          .withColumnLabel(1, 'Second look')
          .withMatchInfoOverride('a|118|iqmAuto', '9');

      final restored = PlayoffBoard.fromJson(board.toJson());

      expect(restored.meetingCell(3, 2), '1678');
      expect(restored.allianceCell(0, 0), '3847');
      expect(restored.columnLabel(1), 'Second look');
      expect(restored.matchInfoOverrides['a|118|iqmAuto'], '9');
    });

    test('a stored label list of the wrong length falls back to defaults', () {
      final restored = PlayoffBoard.fromJson(<String, dynamic>{
        'columnLabels': <String>['only one'],
      });

      expect(restored.columnLabels, PlayoffBoard.defaultColumnLabels);
    });
  });

  group('PlayoffBoardController', () {
    test('boards are kept per event key', () async {
      final controller = PlayoffBoardController(
        storage: FakePlayoffBoardStorage(),
      );
      await controller.bootstrap();

      controller.setAllianceCell('2026txhou', 0, 0, '3847');
      await controller.pendingWrites;

      expect(controller.boardFor('2026txhou').allianceCell(0, 0), '3847');
      expect(controller.boardFor('2026txdal').allianceCell(0, 0), '');
    });

    test('bootstrap restores what was stored', () async {
      final storage = FakePlayoffBoardStorage(<String, PlayoffBoard>{
        '2026txhou': const PlayoffBoard(
          meetingCells: <String, String>{'0,0': '3847'},
        ),
      });
      final controller = PlayoffBoardController(storage: storage);
      await controller.bootstrap();

      expect(controller.boardFor('2026txhou').meetingCell(0, 0), '3847');
    });

    test('writes land in call order', () async {
      final storage = FakePlayoffBoardStorage();
      final controller = PlayoffBoardController(storage: storage);
      await controller.bootstrap();

      controller.setMeetingCell('e', 0, 0, '1');
      controller.setMeetingCell('e', 0, 0, '12');
      controller.setMeetingCell('e', 0, 0, '123');
      await controller.pendingWrites;

      expect(storage.saves, 3);
      expect(storage.boards['e']!.meetingCell(0, 0), '123');
    });

    test('a later keystroke cannot change an already-queued write', () async {
      final storage = _RecordingStorage();
      final controller = PlayoffBoardController(storage: storage);
      await controller.bootstrap();

      controller.setMeetingCell('e', 0, 0, 'first');
      controller.setMeetingCell('e', 0, 0, 'second');
      await controller.pendingWrites;

      expect(storage.written, <String>['first', 'second']);
    });

    test('an event key of empty string is ignored', () async {
      final storage = FakePlayoffBoardStorage();
      final controller = PlayoffBoardController(storage: storage);
      await controller.bootstrap();

      controller.setMeetingCell('', 0, 0, '3847');
      await controller.pendingWrites;

      expect(storage.saves, 0);
    });

    test('a failed write does not poison later ones', () async {
      final storage = _FailOnceStorage();
      final controller = PlayoffBoardController(storage: storage);
      await controller.bootstrap();

      controller.setMeetingCell('e', 0, 0, 'one');
      controller.setMeetingCell('e', 0, 1, 'two');
      await controller.pendingWrites;

      expect(storage.succeeded, 1);
    });
  });
}

class _RecordingStorage extends FakePlayoffBoardStorage {
  final List<String> written = <String>[];

  @override
  Future<void> save(String eventKey, PlayoffBoard board) async {
    await Future<void>.delayed(Duration.zero);
    written.add(board.meetingCell(0, 0));
    await super.save(eventKey, board);
  }
}

class _FailOnceStorage extends FakePlayoffBoardStorage {
  bool _failed = false;
  int succeeded = 0;

  @override
  Future<void> save(String eventKey, PlayoffBoard board) async {
    if (!_failed) {
      _failed = true;
      throw StateError('disk full');
    }
    succeeded++;
    await super.save(eventKey, board);
  }
}
