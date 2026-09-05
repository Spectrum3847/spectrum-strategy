import 'package:flutter_test/flutter_test.dart';

import 'package:spectrumstrategy/src/scouting/models/scout_shift_schedule.dart';

List<ScoutShiftRosterEntry> _roster(int count) => [
  for (var i = 0; i < count; i++)
    ScoutShiftRosterEntry(uid: 'u$i', name: 'Scouter $i'),
];

bool _onDutyCount(ScoutShiftSchedule schedule, int match, int expected) =>
    schedule.rotations.where((r) => r.isOnDuty(match)).length == expected;

void main() {
  group('ScoutShiftSchedule.generate', () {
    test('an empty roster produces no rotation', () {
      final schedule = ScoutShiftSchedule.generate(
        eventKey: '2026miket',
        matchCount: 60,
        roster: const <ScoutShiftRosterEntry>[],
      );
      expect(schedule.isEmpty, isTrue);
      expect(schedule.rotations, isEmpty);
    });

    test('a non-positive match count produces no rotation', () {
      final schedule = ScoutShiftSchedule.generate(
        eventKey: '2026miket',
        matchCount: 0,
        roster: _roster(3),
      );
      expect(schedule.rotations, isEmpty);

      final negative = ScoutShiftSchedule.generate(
        eventKey: '2026miket',
        matchCount: -5,
        roster: _roster(3),
      );
      expect(negative.rotations, isEmpty);
      expect(negative.matchCount, 0);
    });

    test('a match count over kMaxMatchCount throws instead of generating', () {
      expect(
        () => ScoutShiftSchedule.generate(
          eventKey: '2026miket',
          matchCount: ScoutShiftSchedule.kMaxMatchCount + 1,
          roster: _roster(3),
        ),
        throwsArgumentError,
      );

      final atCap = ScoutShiftSchedule.generate(
        eventKey: '2026miket',
        matchCount: ScoutShiftSchedule.kMaxMatchCount,
        roster: _roster(3),
      );
      expect(atCap.matchCount, ScoutShiftSchedule.kMaxMatchCount);
    });

    test(
      'every shift block is exactly 6 matches long (except a tail fill)',
      () {
        final schedule = ScoutShiftSchedule.generate(
          eventKey: '2026miket',
          matchCount: 48,
          roster: _roster(18),
        );
        for (final rotation in schedule.rotations) {
          for (final shift in rotation.shifts) {
            final length = shift.endMatch - shift.startMatch + 1;
            expect(length, 6, reason: '${rotation.name}: $shift');
          }
        }
      },
    );

    test('exactly 6 people are on duty every match for a roster of 12', () {
      final schedule = ScoutShiftSchedule.generate(
        eventKey: '2026miket',
        matchCount: 24,
        roster: _roster(12),
      );
      for (var m = 1; m <= 24; m++) {
        expect(_onDutyCount(schedule, m, 6), isTrue, reason: 'match $m');
      }
    });

    test('exactly 6 people are on duty every match for a roster of 18', () {
      final schedule = ScoutShiftSchedule.generate(
        eventKey: '2026miket',
        matchCount: 36,
        roster: _roster(18),
      );
      for (var m = 1; m <= 36; m++) {
        expect(_onDutyCount(schedule, m, 6), isTrue, reason: 'match $m');
      }
    });

    test('breaks land on 6, 12, or 18 matches for 2, 3, and 4 groups', () {
      final twelve = ScoutShiftSchedule.generate(
        eventKey: '2026miket',
        matchCount: 24,
        roster: _roster(12),
      );
      final firstGroupMember = twelve.rotationFor('u0')!;
      expect(firstGroupMember.shifts.map((s) => (s.startMatch, s.endMatch)), [
        (1, 6),
        (13, 18),
      ]);

      final eighteen = ScoutShiftSchedule.generate(
        eventKey: '2026miket',
        matchCount: 36,
        roster: _roster(18),
      );
      expect(
        eighteen
            .rotationFor('u0')!
            .shifts
            .map((s) => (s.startMatch, s.endMatch)),
        [(1, 6), (19, 24)],
      );

      final twentyFour = ScoutShiftSchedule.generate(
        eventKey: '2026miket',
        matchCount: 48,
        roster: _roster(24),
      );
      expect(
        twentyFour
            .rotationFor('u0')!
            .shifts
            .map((s) => (s.startMatch, s.endMatch)),
        [(1, 6), (25, 30)],
      );
    });

    test('the last group to finish a full shift fills the remainder green', () {
      final schedule = ScoutShiftSchedule.generate(
        eventKey: '2026miket',
        matchCount: 15,
        roster: _roster(12),
      );
      expect(
        schedule
            .rotationFor('u0')!
            .shifts
            .map((s) => (s.startMatch, s.endMatch)),
        [(1, 6)],
      );
      expect(
        schedule
            .rotationFor('u6')!
            .shifts
            .map((s) => (s.startMatch, s.endMatch)),
        [(7, 15)],
      );
      for (var m = 13; m <= 15; m++) {
        expect(schedule.rotationFor('u6')!.isOnDuty(m), isTrue);
        expect(schedule.rotationFor('u0')!.isOnDuty(m), isFalse);
      }
    });

    test('an event shorter than one shift has group 0 cover every match', () {
      final schedule = ScoutShiftSchedule.generate(
        eventKey: '2026miket',
        matchCount: 4,
        roster: _roster(12),
      );
      expect(
        schedule
            .rotationFor('u0')!
            .shifts
            .map((s) => (s.startMatch, s.endMatch)),
        [(1, 4)],
      );
      expect(schedule.rotationFor('u6')!.shifts, isEmpty);
    });

    test('generation truncates at the entered match count', () {
      final schedule = ScoutShiftSchedule.generate(
        eventKey: '2026miket',
        matchCount: 10,
        roster: _roster(12),
      );
      for (final rotation in schedule.rotations) {
        for (final shift in rotation.shifts) {
          expect(shift.endMatch, lessThanOrEqualTo(10));
        }
      }
    });

    test(
      'a 12+ roster with matchCount in 7-11 only ever schedules group 0',
      () {
        final schedule = ScoutShiftSchedule.generate(
          eventKey: '2026miket',
          matchCount: 9,
          roster: _roster(12),
        );
        expect(
          schedule
              .rotationFor('u0')!
              .shifts
              .map((s) => (s.startMatch, s.endMatch)),
          [(1, 9)],
        );
        for (var i = 6; i < 12; i++) {
          expect(schedule.rotationFor('u$i')!.shifts, isEmpty);
        }
      },
    );

    group('fewer than 12 names', () {
      test('6 or fewer names: everyone scouts every match, no break', () {
        final schedule = ScoutShiftSchedule.generate(
          eventKey: '2026miket',
          matchCount: 30,
          roster: _roster(6),
        );
        for (var m = 1; m <= 30; m++) {
          expect(_onDutyCount(schedule, m, 6), isTrue, reason: 'match $m');
        }

        for (final rotation in schedule.rotations) {
          expect(rotation.shifts, hasLength(1));
          expect(rotation.shifts.single.startMatch, 1);
          expect(rotation.shifts.single.endMatch, 30);
        }
      });

      test('a single name scouts continuously with no break', () {
        final schedule = ScoutShiftSchedule.generate(
          eventKey: '2026miket',
          matchCount: 20,
          roster: _roster(1),
        );
        expect(
          schedule.rotations.single.shifts.map(
            (s) => (s.startMatch, s.endMatch),
          ),
          [(1, 20)],
        );
      });

      test('7-11 names: a 6-match break becomes possible again', () {
        final schedule = ScoutShiftSchedule.generate(
          eventKey: '2026miket',
          matchCount: 12,
          roster: _roster(8),
        );
        expect(
          schedule
              .rotationFor('u0')!
              .shifts
              .map((s) => (s.startMatch, s.endMatch)),
          [(1, 6)],
        );
        expect(
          schedule
              .rotationFor('u6')!
              .shifts
              .map((s) => (s.startMatch, s.endMatch)),
          [(7, 12)],
        );
        expect(_onDutyCount(schedule, 3, 6), isTrue);
        expect(_onDutyCount(schedule, 9, 2), isTrue);
      });
    });

    test('a roster not divisible by 6 gets one undersized tail group', () {
      final schedule = ScoutShiftSchedule.generate(
        eventKey: '2026miket',
        matchCount: 18,
        roster: _roster(14),
      );
      expect(_onDutyCount(schedule, 3, 6), isTrue);
      expect(_onDutyCount(schedule, 9, 6), isTrue);
      expect(_onDutyCount(schedule, 15, 2), isTrue);
      expect(schedule.rotationFor('u12')!.isOnDuty(15), isTrue);
      expect(schedule.rotationFor('u13')!.isOnDuty(15), isTrue);
    });

    test('is deterministic for the same inputs', () {
      final first = ScoutShiftSchedule.generate(
        eventKey: '2026miket',
        matchCount: 17,
        roster: _roster(14),
      );
      final second = ScoutShiftSchedule.generate(
        eventKey: '2026miket',
        matchCount: 17,
        roster: _roster(14),
      );

      expect(
        first.toJson()..remove('updatedAt'),
        second.toJson()..remove('updatedAt'),
      );
    });
  });

  test('model round-trips through JSON', () {
    final schedule = ScoutShiftSchedule.generate(
      eventKey: '2026miket',
      matchCount: 12,
      roster: _roster(2),
      authorUid: 'admin1',
      authorDisplayName: 'Admin',
    );
    final decoded = ScoutShiftSchedule.fromJson(schedule.toJson());
    expect(decoded.eventKey, '2026miket');
    expect(decoded.matchCount, 12);
    expect(decoded.roster.map((r) => r.uid), ['u0', 'u1']);
    expect(decoded.authorUid, 'admin1');
    expect(decoded.rotations, hasLength(2));
    expect(
      decoded.rotations.first.shifts.map((s) => (s.startMatch, s.endMatch)),
      schedule.rotations.first.shifts.map((s) => (s.startMatch, s.endMatch)),
    );
  });

  test('ScouterShiftRotation.upcomingShift finds the next shift', () {
    final rotation = ScouterShiftRotation(
      uid: 'u0',
      name: 'Scouter',
      shifts: const [
        ScoutShiftBlock(startMatch: 1, endMatch: 6),
        ScoutShiftBlock(startMatch: 13, endMatch: 18),
      ],
    );
    expect(rotation.upcomingShift(1)!.startMatch, 1);
    expect(rotation.upcomingShift(6)!.startMatch, 1);
    expect(rotation.upcomingShift(7)!.startMatch, 13);
    expect(rotation.upcomingShift(19), isNull);
  });

  group('cell overrides (grid edits)', () {
    test('colorFor defaults to green when on duty, white otherwise', () {
      final schedule = ScoutShiftSchedule.generate(
        eventKey: '2026miket',
        matchCount: 12,
        roster: _roster(6),
      );

      expect(schedule.colorFor(0, 1), ScheduleCellColor.green);

      final twoGroup = ScoutShiftSchedule.generate(
        eventKey: '2026miket',
        matchCount: 12,
        roster: _roster(12),
      );
      expect(twoGroup.colorFor(0, 1), ScheduleCellColor.green);
      expect(twoGroup.colorFor(0, 7), ScheduleCellColor.white);
    });

    test('withCellEdit overrides the color and text for one cell only', () {
      final schedule = ScoutShiftSchedule.generate(
        eventKey: '2026miket',
        matchCount: 12,
        roster: _roster(12),
      );
      final edited = schedule.withCellEdit(
        col: 0,
        match: 7,
        text: 'covering for u6',
        color: ScheduleCellColor.grey,
      );
      expect(edited.colorFor(0, 7), ScheduleCellColor.grey);
      expect(edited.textFor(0, 7), 'covering for u6');

      expect(edited.colorFor(0, 1), ScheduleCellColor.green);
      expect(edited.colorFor(1, 7), schedule.colorFor(1, 7));
    });

    test('an edit matching the generated default is not stored', () {
      final schedule = ScoutShiftSchedule.generate(
        eventKey: '2026miket',
        matchCount: 12,
        roster: _roster(12),
      );
      final edited = schedule
          .withCellEdit(
            col: 0,
            match: 7,
            text: 'note',
            color: ScheduleCellColor.grey,
          )
          .withCellEdit(col: 0, match: 7, text: '', color: null);
      expect(edited.cellOverrides, isEmpty);
      expect(edited.colorFor(0, 7), ScheduleCellColor.white);
    });

    test('withRenamedColumn updates both the roster and the rotation', () {
      final schedule = ScoutShiftSchedule.generate(
        eventKey: '2026miket',
        matchCount: 12,
        roster: _roster(2),
      );
      final renamed = schedule.withRenamedColumn(0, 'Alex');
      expect(renamed.roster[0].name, 'Alex');
      expect(renamed.roster[0].uid, 'u0');
      expect(renamed.rotations[0].name, 'Alex');
    });

    test('withRenamedColumn rebinds the column to the uid it is given', () {
      final schedule = ScoutShiftSchedule.generate(
        eventKey: '2026miket',
        matchCount: 12,
        roster: _roster(2),
      );

      final rebound = schedule.withRenamedColumn(0, 'Alex', uid: 'u9');
      expect(rebound.roster[0].uid, 'u9');
      expect(rebound.rotations[0].uid, 'u9');

      final unlinked = schedule.withRenamedColumn(0, 'Alex', uid: '');
      expect(unlinked.roster[0].uid, '');
      expect(unlinked.rotations[0].uid, '');
      expect(unlinked.rotations[0].shifts, schedule.rotations[0].shifts);
    });

    test('cellOverrides round-trip through JSON', () {
      final schedule =
          ScoutShiftSchedule.generate(
            eventKey: '2026miket',
            matchCount: 12,
            roster: _roster(12),
          ).withCellEdit(
            col: 3,
            match: 5,
            text: '42',
            color: ScheduleCellColor.red,
          );
      final decoded = ScoutShiftSchedule.fromJson(schedule.toJson());
      expect(decoded.colorFor(3, 5), ScheduleCellColor.red);
      expect(decoded.textFor(3, 5), '42');
    });

    test('regenerating drops any hand edits', () {
      final edited = ScoutShiftSchedule.generate(
        eventKey: '2026miket',
        matchCount: 12,
        roster: _roster(2),
      ).withCellEdit(col: 0, match: 1, text: 'x', color: ScheduleCellColor.red);
      expect(edited.cellOverrides, isNotEmpty);

      final regenerated = ScoutShiftSchedule.generate(
        eventKey: '2026miket',
        matchCount: 12,
        roster: _roster(2),
      );
      expect(regenerated.cellOverrides, isEmpty);
    });
  });
}
