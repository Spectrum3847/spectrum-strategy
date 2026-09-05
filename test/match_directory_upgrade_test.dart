import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spectrumstrategy/src/models/strategy_point.dart';
import 'package:spectrumstrategy/src/models/strategy_session.dart';
import 'package:spectrumstrategy/src/models/strategy_stroke.dart';
import 'package:spectrumstrategy/src/services/match_directory.dart';
import 'package:spectrumstrategy/src/theme/strategy_palette.dart';

import 'support/legacy_match_directory.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  StrategySession board(int i) {
    final session = StrategySession.create(id: 'm$i')
      ..eventName = 'Event $i'
      ..eventKey = '2026txhou'
      ..matchNumber = i
      ..alliance = i.isEven ? 'red' : 'blue';
    for (final phase in StrategyPhase.values) {
      session.notesByPhase[phase] =
          'Board $i ${phase.name} notes, with length.';
      session
          .strokesFor(phase)
          .add(
            StrategyStroke(
              phase: phase,
              colorValue: 0xFF3C0060,
              points: <StrategyPoint>[
                for (var p = 0; p < 25; p++)
                  StrategyPoint(p / 25, (p * i % 25) / 25),
              ],
            ),
          );
    }
    return session;
  }

  Future<Map<String, Object>> legacyState(
    Future<void> Function(LegacyMatchDirectory legacy) write,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    await write(LegacyMatchDirectory(preferences: prefs));
    final captured = <String, Object>{};
    for (final key in prefs.getKeys()) {
      final value = prefs.get(key);
      if (value != null) captured[key] = value;
    }
    return captured;
  }

  Map<String, Object> asMockValues(Map<String, Object> state) =>
      <String, Object>{
        for (final entry in state.entries) 'flutter.${entry.key}': entry.value,
      };

  test('an upgrade preserves every board, with its full payload', () async {
    const count = 25;
    final state = await legacyState((legacy) async {
      for (var i = 0; i < count; i++) {
        await legacy.saveMatch(board(i));
      }
      await legacy.setActiveMatchId('m7');
    });

    expect(state.containsKey('strategy_matches_v2'), isTrue);
    expect(
      state.keys.where((k) => k.startsWith('strategy_match_v3_')),
      isEmpty,
    );

    SharedPreferences.setMockInitialValues(asMockValues(state));
    final upgraded = SharedPreferencesMatchDirectory();

    final summaries = await upgraded.listMatches();
    expect(summaries.length, count, reason: 'every board must survive');

    for (var i = 0; i < count; i++) {
      final loaded = await upgraded.loadMatch('m$i');
      expect(loaded, isNotNull, reason: 'board m$i disappeared');
      final original = board(i);
      expect(loaded!.eventName, original.eventName);
      expect(loaded.matchNumber, original.matchNumber);
      expect(loaded.alliance, original.alliance);
      for (final phase in StrategyPhase.values) {
        expect(
          loaded.noteFor(phase),
          original.noteFor(phase),
          reason: 'board m\$i lost its \${phase.name} note',
        );
      }
      for (final phase in StrategyPhase.values) {
        expect(
          loaded.strokesFor(phase).length,
          original.strokesFor(phase).length,
          reason: 'board m$i lost strokes in $phase',
        );
        expect(
          loaded.strokesFor(phase).first.points.length,
          original.strokesFor(phase).first.points.length,
          reason: 'board m$i lost stroke points in $phase',
        );
      }
    }

    expect(await upgraded.getActiveMatchId(), 'm7');

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('strategy_matches_v2'), isNull);
    expect(prefs.getString('strategy_match_summaries_v1'), isNull);
  });

  test('a force quit mid-migration loses nothing on the next launch', () async {
    const count = 12;
    final state = await legacyState((legacy) async {
      for (var i = 0; i < count; i++) {
        await legacy.saveMatch(board(i));
      }
    });

    final interrupted = Map<String, Object>.of(state);
    final legacyMap = jsonDecode(
      state['strategy_matches_v2']! as String,
    ) as Map<String, dynamic>;
    for (var i = 0; i < 5; i++) {
      interrupted['strategy_match_v3_m$i'] = jsonEncode(legacyMap['m$i']);
    }

    SharedPreferences.setMockInitialValues(asMockValues(interrupted));
    final relaunched = SharedPreferencesMatchDirectory();

    expect((await relaunched.listMatches()).length, count);
    for (var i = 0; i < count; i++) {
      final loaded = await relaunched.loadMatch('m$i');
      expect(loaded, isNotNull, reason: 'board m$i lost to the interruption');
      expect(
        loaded!.noteFor(StrategyPhase.teleop),
        board(i).noteFor(StrategyPhase.teleop),
      );
    }
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('strategy_matches_v2'), isNull);
  });

  test('a board saved after the kill is not clobbered by the retry', () async {
    final state = await legacyState((legacy) async {
      await legacy.saveMatch(board(1));
      await legacy.saveMatch(board(2));
    });

    final legacyMap = jsonDecode(
      state['strategy_matches_v2']! as String,
    ) as Map<String, dynamic>;
    final edited = board(1);
    edited.notesByPhase[StrategyPhase.teleop] = 'Edited after the interruption';
    final interrupted = Map<String, Object>.of(state)
      ..['strategy_match_v3_m1'] = jsonEncode(edited.toJson());
    expect(legacyMap.containsKey('m1'), isTrue);

    SharedPreferences.setMockInitialValues(asMockValues(interrupted));
    final relaunched = SharedPreferencesMatchDirectory();

    expect(
      (await relaunched.loadMatch('m1'))!.noteFor(StrategyPhase.teleop),
      'Edited after the interruption',
    );
    expect(
      (await relaunched.loadMatch('m2'))!.noteFor(StrategyPhase.teleop),
      board(2).noteFor(StrategyPhase.teleop),
    );
  });

  test('the legacy single-session draft still upgrades', () async {
    final state = await legacyState((legacy) async {
      await legacy.saveMatch(board(3));
    });

    final legacyMap = jsonDecode(
      state['strategy_matches_v2']! as String,
    ) as Map<String, dynamic>;
    SharedPreferences.setMockInitialValues(<String, Object>{
      'flutter.strategy_session_draft': jsonEncode(legacyMap['m3']),
    });

    final upgraded = SharedPreferencesMatchDirectory();
    expect((await upgraded.listMatches()).single.id, 'm3');
    expect(
      (await upgraded.loadMatch('m3'))!.noteFor(StrategyPhase.auton),
      board(3).noteFor(StrategyPhase.auton),
    );
  });
}
