import 'package:flutter_test/flutter_test.dart';

import 'package:spectrumstrategy/src/models/strategy_session.dart';
import 'package:spectrumstrategy/src/services/strategy_board_sync_service.dart';

void main() {
  Map<String, dynamic> boardJson(Object? opponents) {
    final json = StrategySession.create().toJson();
    json['teamNumbers'] = <int>[1111, 2222, 3333];
    json['opponentTeams'] = opponents;
    return json;
  }

  test('a fresh session has no opponents and leaves the field out', () {
    final session = StrategySession.create();

    expect(session.opponentTeams, isEmpty);
    expect(session.toJson().containsKey('opponentTeams'), isFalse);
  });

  test('opponents round-trip through JSON', () {
    final again = StrategySession.fromJson(boardJson(<int>[2222, 3333]));

    expect(again.opponentTeams, <int>[2222, 3333]);
    expect(again.toJson()['opponentTeams'], <int>[2222, 3333]);
  });

  test('a stored board from before this field still loads', () {
    final legacy = boardJson(null);
    legacy.remove('opponentTeams');

    expect(StrategySession.fromJson(legacy).opponentTeams, isEmpty);
  });

  test('a wrong-typed field falls back to empty', () {
    expect(StrategySession.fromJson(boardJson('nope')).opponentTeams, isEmpty);
  });

  test('a bad item is skipped and the rest stay', () {
    final session = StrategySession.fromJson(boardJson(<Object?>[2222, 'x']));

    expect(session.opponentTeams, <int>[2222]);
  });

  test('the push payload keeps the field', () {
    final session = StrategySession.fromJson(boardJson(<int>[2222]));

    final payload = prepareBoardPayload(session, 'uid-1', 'Lead A', 'stamp');

    expect(payload['opponentTeams'], <int>[2222]);
  });
}
