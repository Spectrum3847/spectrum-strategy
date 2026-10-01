import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spectrumstrategy/src/models/playoff_board.dart';
import 'package:spectrumstrategy/src/services/playoff_board_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test('a saved board reads back under its event key', () async {
    final storage = SharedPreferencesPlayoffBoardStorage();
    await storage.save(
      '2026txhou',
      const PlayoffBoard().withMeetingCell(0, 0, '3847'),
    );

    final boards = await storage.loadAll();

    expect(boards.keys, <String>['2026txhou']);
    expect(boards['2026txhou']!.meetingCell(0, 0), '3847');
  });

  test('saving one event leaves another events board alone', () async {
    final storage = SharedPreferencesPlayoffBoardStorage();
    await storage.save('a', const PlayoffBoard().withAllianceCell(0, 0, '1'));
    await storage.save('b', const PlayoffBoard().withAllianceCell(0, 0, '2'));

    final boards = await storage.loadAll();

    expect(boards['a']!.allianceCell(0, 0), '1');
    expect(boards['b']!.allianceCell(0, 0), '2');
  });

  test('nothing stored reads as no boards', () async {
    expect(await SharedPreferencesPlayoffBoardStorage().loadAll(), isEmpty);
  });

  test('an unreadable entry is skipped rather than failing the load', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'playoff_boards_v1': '{"a": "not a board", "b": {"meetingCells":{}}}',
    });

    final boards = await SharedPreferencesPlayoffBoardStorage().loadAll();

    expect(boards.keys, <String>['b']);
  });
}
