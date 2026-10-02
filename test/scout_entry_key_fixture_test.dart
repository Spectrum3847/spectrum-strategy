import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:spectrumstrategy/src/scouting/models/scout_entry.dart';
import 'package:spectrumstrategy/src/theme/strategy_palette.dart';

void main() {
  test('a fully populated ScoutEntry.toJson(), plus updatedAtTs, matches the checked-in key fixture', () {
    final entry = ScoutEntry(
      matchId: 'm1',
      teamNumber: 1,
      alliance: 'Red',
      notes: 'fixture entry',
      authorUid: 'u1',
      authorDisplayName: 'Fixture Author',
      byPhase: <StrategyPhase, ScoutPhaseData>{
        for (final phase in StrategyPhase.values)
          phase: const ScoutPhaseData(
            score: 1,
            penalties: 1,
            notes: 'phase',
            counters: <String, int>{'c': 1},
          ),
      },
      fieldValues: const <String, dynamic>{'field': 'value'},
      tbaMatchKey: '2025test_qm1',
      strokesByPhase: const <String, dynamic>{'auton': <dynamic>[]},
      addedManually: true,
    );

    final keys = <String>{...entry.toJson().keys, 'updatedAtTs'};

    final fixtureFile = File(
      'scripts/cron-worker/test/fixtures/scout_entry_keys.json',
    );
    final fixtureKeys = (jsonDecode(fixtureFile.readAsStringSync()) as List)
        .cast<String>()
        .toSet();

    expect(keys, equals(fixtureKeys));
  });
}
