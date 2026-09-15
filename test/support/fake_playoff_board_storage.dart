import 'package:spectrumstrategy/src/models/playoff_board.dart';
import 'package:spectrumstrategy/src/services/playoff_board_storage.dart';

class FakePlayoffBoardStorage implements PlayoffBoardStorage {
  FakePlayoffBoardStorage([Map<String, PlayoffBoard>? seed])
    : boards = <String, PlayoffBoard>{...?seed};

  final Map<String, PlayoffBoard> boards;
  int saves = 0;

  @override
  Future<Map<String, PlayoffBoard>> loadAll() async =>
      Map<String, PlayoffBoard>.from(boards);

  @override
  Future<void> save(String eventKey, PlayoffBoard board) async {
    saves++;
    boards[eventKey] = board;
  }
}
