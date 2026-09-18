import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:spectrumstrategy/src/models/strategy_session.dart';
import 'package:spectrumstrategy/src/scouting/models/scout_entry.dart';
import 'package:spectrumstrategy/src/services/strategy_board_sync_service.dart';

void main() {
  final rules = File('firestore.rules').readAsStringSync();

  Set<String> whitelistOf(String function) {
    final start = rules.indexOf('function $function(');
    expect(start, isNot(-1), reason: '$function is not in firestore.rules');
    final body = rules.substring(start);
    final match = RegExp(r'hasOnly\(\[([^\]]*)\]\)').firstMatch(body);
    expect(match, isNotNull, reason: '$function has no hasOnly whitelist');
    return RegExp(r"'([^']+)'")
        .allMatches(match!.group(1)!)
        .map((m) => m.group(1)!)
        .toSet();
  }

  test('a scout entry with every field set fits isValidScoutEntry', () {
    final entry = ScoutEntry(
      matchId: 'qm1',
      teamNumber: 3847,
      alliance: 'Blue',
      notes: 'notes',
      authorUid: 'uid',
      authorDisplayName: 'Scouter',
      createdAt: DateTime.utc(2026, 4, 20, 14, 30),
      updatedAt: DateTime.utc(2026, 4, 20, 16),
      fieldValues: const {'auto_l1': 2},
      tbaMatchKey: '2026cc_qm1',
      strokesByPhase: {'auton': <Object>[]},
      addedManually: true,
    );

    final sent = {...entry.toJson().keys, 'updatedAtTs'};

    expect(sent, everyElement(isIn(whitelistOf('isValidScoutEntry'))));
  });

  test('a strategy board drawn for an event fits isValidStrategyBoard', () {
    final session = StrategySession.create(eventKey: '2026cc')
      ..selectedRobotTeam = 3847;
    final sent = prepareBoardPayload(session, 'uid', 'Lead', 'ts').keys;

    expect(sent, everyElement(isIn(whitelistOf('isValidStrategyBoard'))));
  });
}
