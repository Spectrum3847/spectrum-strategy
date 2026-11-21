import 'package:flutter_test/flutter_test.dart';

import 'package:spectrumstrategy/src/scouting/models/scout_entry.dart';
import 'package:spectrumstrategy/src/scouting/services/entry_flags.dart';

ScoutEntry entry({
  required int team,
  required int match,
  String? station,
  String? id,
}) {
  return ScoutEntry(
    id: id,
    matchId: 'session-uuid',
    teamNumber: team,
    fieldValues: <String, dynamic>{'matchNumber': match, 'robot': ?station},
  );
}

void main() {
  group('duplicate team', () {
    test('two rows in one match naming the same team are both flagged', () {
      final a = entry(team: 3847, match: 1, station: 'Red 1', id: 'a');
      final b = entry(team: 3847, match: 1, station: 'Red 2', id: 'b');
      final flags = EntryFlags.detect([a, b]);

      expect(flags.worstFor(a)?.kind, EntryFlagKind.duplicateTeam);
      expect(flags.worstFor(b)?.kind, EntryFlagKind.duplicateTeam);
      expect(flags.flaggedEntryCount, 2);
    });

    test('the reason names the team and the match', () {
      final a = entry(team: 3847, match: 4, station: 'Red 1', id: 'a');
      final b = entry(team: 3847, match: 4, station: 'Red 2', id: 'b');
      final flags = EntryFlags.detect([a, b]);

      final reason = flags.worstFor(a)!.reason;
      expect(reason, contains('3847'));
      expect(reason, contains('Match 4'));
    });

    test('the same team in two different matches is not flagged', () {
      final a = entry(team: 3847, match: 1, station: 'Red 1', id: 'a');
      final b = entry(team: 3847, match: 2, station: 'Red 1', id: 'b');
      final flags = EntryFlags.detect([a, b]);

      expect(flags.isEmpty, isTrue);
    });

    test('entries with no team number do not collide with each other', () {
      final a = entry(team: 0, match: 1, station: 'Red 1', id: 'a');
      final b = entry(team: 0, match: 1, station: 'Red 2', id: 'b');
      final flags = EntryFlags.detect([a, b]);

      expect(flags.isEmpty, isTrue);
    });
  });

  group('duplicate station', () {
    test('two rows in one match sharing a station are both flagged', () {
      final a = entry(team: 3847, match: 1, station: 'Red 1', id: 'a');
      final b = entry(team: 1477, match: 1, station: 'Red 1', id: 'b');
      final flags = EntryFlags.detect([a, b]);

      expect(flags.worstFor(a)?.kind, EntryFlagKind.duplicateStation);
      expect(flags.worstFor(b)?.kind, EntryFlagKind.duplicateStation);
    });

    test('a station written two ways still collides', () {
      final a = entry(team: 3847, match: 1, station: 'Red 1', id: 'a');
      final b = entry(team: 1477, match: 1, station: 'r1', id: 'b');
      final flags = EntryFlags.detect([a, b]);

      expect(flags.worstFor(a)?.kind, EntryFlagKind.duplicateStation);
      expect(flags.worstFor(b)?.reason, contains('R1'));
    });

    test('different stations in one match are not flagged', () {
      final a = entry(team: 3847, match: 1, station: 'Red 1', id: 'a');
      final b = entry(team: 1477, match: 1, station: 'Blue 3', id: 'b');
      final flags = EntryFlags.detect([a, b]);

      expect(flags.isEmpty, isTrue);
    });

    test('entries with no station are not flagged', () {
      final a = entry(team: 3847, match: 1, id: 'a');
      final b = entry(team: 1477, match: 1, id: 'b');
      final flags = EntryFlags.detect([a, b]);

      expect(flags.isEmpty, isTrue);
    });
  });

  group('both flags on one row', () {
    test('the duplicate team leads and both reasons are kept', () {
      final a = entry(team: 3847, match: 1, station: 'Red 1', id: 'a');
      final b = entry(team: 3847, match: 1, station: 'Red 1', id: 'b');
      final flags = EntryFlags.detect([a, b]);

      expect(flags.forEntry(a), hasLength(2));
      expect(flags.forEntry(a).first.kind, EntryFlagKind.duplicateTeam);
      expect(flags.worstFor(a)?.kind, EntryFlagKind.duplicateTeam);
      expect(
        flags.forEntry(a).map((EntryFlag flag) => flag.kind),
        containsAll(<EntryFlagKind>[
          EntryFlagKind.duplicateTeam,
          EntryFlagKind.duplicateStation,
        ]),
      );
    });
  });

  group('match number off the schedule', () {
    ScoutEntry withKey({required int typed, required String key}) {
      return ScoutEntry(
        id: 'keyed',
        matchId: 'session-uuid',
        teamNumber: 3847,
        tbaMatchKey: key,
        fieldValues: <String, dynamic>{'matchNumber': typed},
      );
    }

    test('a typed number disagreeing with the TBA key is flagged', () {
      final off = withKey(typed: 4, key: '2026txhou_qm5');
      final flags = EntryFlags.detect([off]);

      expect(flags.worstFor(off)?.kind, EntryFlagKind.matchNumberOffSchedule);
      final reason = flags.worstFor(off)!.reason;
      expect(reason, contains('4'));
      expect(reason, contains('match 5'));
    });

    test('a typed number agreeing with the TBA key is not flagged', () {
      expect(
        EntryFlags.detect([withKey(typed: 5, key: '2026txhou_qm5')]).isEmpty,
        isTrue,
      );
    });

    test('a typed number the schedule does not have is flagged', () {
      final off = entry(team: 3847, match: 92, station: 'Red 1', id: 'off');
      final flags = EntryFlags.detect(
        [off],
        scheduledMatchNumbers: const <int>[1, 2, 3],
      );

      expect(flags.worstFor(off)?.kind, EntryFlagKind.matchNumberOffSchedule);
      expect(flags.worstFor(off)!.reason, contains('92'));
    });

    test('a typed number the schedule has is not flagged', () {
      final ok = entry(team: 3847, match: 2, station: 'Red 1', id: 'ok');
      final flags = EntryFlags.detect(
        [ok],
        scheduledMatchNumbers: const <int>[1, 2, 3],
      );

      expect(flags.isEmpty, isTrue);
    });

    test('no schedule and no key means nothing to judge against', () {
      final offline = entry(team: 3847, match: 92, station: 'Red 1', id: 'o');

      expect(EntryFlags.detect([offline]).isEmpty, isTrue);
    });

    test('an entry with no match number at all is not flagged', () {
      final bare = ScoutEntry(
        id: 'bare',
        matchId: 'session-uuid',
        teamNumber: 3847,
      );

      expect(
        EntryFlags.detect([bare], scheduledMatchNumbers: const [1]).isEmpty,
        isTrue,
      );
    });

    test('a duplicate team outranks a match number on the same row', () {
      final a = ScoutEntry(
        id: 'a',
        matchId: 'session-uuid',
        teamNumber: 3847,
        fieldValues: const <String, dynamic>{'matchNumber': 92, 'robot': 'R1'},
      );
      final b = ScoutEntry(
        id: 'b',
        matchId: 'session-uuid',
        teamNumber: 3847,
        fieldValues: const <String, dynamic>{'matchNumber': 92, 'robot': 'R1'},
      );
      final flags = EntryFlags.detect(
        [a, b],
        scheduledMatchNumbers: const <int>[1, 2, 3],
      );

      expect(flags.forEntry(a), hasLength(3));
      expect(flags.worstFor(a)?.kind, EntryFlagKind.duplicateTeam);
      expect(flags.forEntry(a).last.kind, EntryFlagKind.matchNumberOffSchedule);
    });
  });

  group('stationOfEntry', () {
    test('reads the label a select stores', () {
      expect(stationOfEntry(entry(team: 1, match: 1, station: 'Blue 2')), 'B2');
    });

    test('reads a TBA-team-and-robot map', () {
      final withMap = ScoutEntry(
        matchId: 'session-uuid',
        teamNumber: 3847,
        fieldValues: const <String, dynamic>{
          'robot': <String, dynamic>{'teamNumber': 3847, 'robotPosition': 'B3'},
        },
      );

      expect(stationOfEntry(withMap), 'B3');
    });

    test('two values that disagree read as no station', () {
      final conflicted = ScoutEntry(
        matchId: 'session-uuid',
        teamNumber: 3847,
        fieldValues: const <String, dynamic>{
          'robot': 'Red 1',
          'somethingElse': 'B2',
        },
      );

      expect(stationOfEntry(conflicted), isNull);
    });

    test('a value that is not a station reads as none', () {
      String? stationOf(String value) =>
          stationOfEntry(entry(team: 1, match: 1, station: value));

      expect(stationOf('Blue 12'), isNull);
      expect(stationOf('Depot'), isNull);
    });
  });

  test('an empty set of entries produces no flags', () {
    expect(EntryFlags.detect(const <ScoutEntry>[]).isEmpty, isTrue);
    expect(const EntryFlags.empty().isNotEmpty, isFalse);
  });
}
