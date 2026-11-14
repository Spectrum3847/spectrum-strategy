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

  group('ScoutShiftSchedule.blank', () {
    test('stores the roster and match count with no shifts', () {
      final schedule = ScoutShiftSchedule.blank(
        eventKey: '2026miket',
        matchCount: 12,
        roster: _roster(3),
      );
      expect(schedule.matchCount, 12);
      expect(schedule.roster, hasLength(3));
      expect(schedule.rotations, hasLength(3));
      expect(schedule.hasRotationShifts, isFalse);
      for (var m = 1; m <= 12; m++) {
        expect(schedule.colorFor(0, m), ScheduleCellColor.white);
      }
    });

    test('an empty roster is isEmpty, a non-empty one is not', () {
      expect(
        ScoutShiftSchedule.blank(
          eventKey: '2026miket',
          matchCount: 12,
          roster: const <ScoutShiftRosterEntry>[],
        ).isEmpty,
        isTrue,
      );
      expect(
        ScoutShiftSchedule.blank(
          eventKey: '2026miket',
          matchCount: 12,
          roster: _roster(3),
        ).isEmpty,
        isFalse,
      );
    });

    test('a match count over kMaxMatchCount throws', () {
      expect(
        () => ScoutShiftSchedule.blank(
          eventKey: '2026miket',
          matchCount: ScoutShiftSchedule.kMaxMatchCount + 1,
          roster: _roster(3),
        ),
        throwsArgumentError,
      );
    });
  });

  group('ScoutShiftSchedule.hasRotationShifts', () {
    test('false for blank, true once generated', () {
      final blank = ScoutShiftSchedule.blank(
        eventKey: '2026miket',
        matchCount: 12,
        roster: _roster(3),
      );
      expect(blank.hasRotationShifts, isFalse);

      final generated = ScoutShiftSchedule.generate(
        eventKey: '2026miket',
        matchCount: 12,
        roster: _roster(3),
      );
      expect(generated.hasRotationShifts, isTrue);
    });

    test('false when generate produces no rotation at all', () {
      final generated = ScoutShiftSchedule.generate(
        eventKey: '2026miket',
        matchCount: 0,
        roster: _roster(3),
      );
      expect(generated.hasRotationShifts, isFalse);
    });
  });

  group('generate around red cells', () {
    ScheduleCellEdit red(int col, int match) =>
        ScheduleCellEdit(col: col, match: match, color: ScheduleCellColor.red);

    test('a column red for a whole round sits out that round', () {
      final schedule = ScoutShiftSchedule.generate(
        eventKey: '2026miket',
        matchCount: 12,
        roster: _roster(12),
        cellOverrides: [for (var m = 1; m <= 6; m++) red(0, m)],
      );
      expect(schedule.rotationFor('u0')!.isOnDuty(1), isFalse);

      expect(_onDutyCount(schedule, 1, 6), isTrue);
      expect(_onDutyCount(schedule, 12, 6), isTrue);
    });

    test('red cells and text notes survive generation', () {
      final blank = ScoutShiftSchedule.blank(
        eventKey: '2026miket',
        matchCount: 12,
        roster: _roster(12),
      );
      final painted = blank
          .withCellEdit(
            col: 0,
            match: 1,
            text: '',
            color: ScheduleCellColor.red,
          )
          .withCellEdit(col: 1, match: 2, text: 'lunch', color: null);

      final generated = ScoutShiftSchedule.generate(
        eventKey: painted.eventKey,
        matchCount: painted.matchCount,
        roster: painted.roster,
        cellOverrides: painted.cellOverrides,
      );

      expect(generated.colorFor(0, 1), ScheduleCellColor.red);
      expect(generated.textFor(1, 2), 'lunch');

      expect(generated.rotationFor('u0')!.isOnDuty(1), isFalse);
    });

    test('prefers whoever has had the longest break', () {
      final schedule = ScoutShiftSchedule.generate(
        eventKey: '2026miket',
        matchCount: 18,
        roster: _roster(8),
        cellOverrides: [for (var m = 7; m <= 12; m++) red(0, m)],
      );
      for (var i = 0; i < 6; i++) {
        expect(schedule.rotationFor('u$i')!.isOnDuty(1), isTrue);
      }
      expect(schedule.rotationFor('u6')!.isOnDuty(1), isFalse);
      expect(schedule.rotationFor('u7')!.isOnDuty(1), isFalse);

      expect(schedule.rotationFor('u0')!.isOnDuty(7), isFalse);
      expect(schedule.rotationFor('u6')!.isOnDuty(7), isTrue);
      expect(schedule.rotationFor('u7')!.isOnDuty(7), isTrue);
      for (var i = 1; i <= 4; i++) {
        expect(schedule.rotationFor('u$i')!.isOnDuty(7), isTrue);
      }
      expect(schedule.rotationFor('u5')!.isOnDuty(7), isFalse);
    });

    test('keeps the tail-fill rule for the final partial round', () {
      final schedule = ScoutShiftSchedule.generate(
        eventKey: '2026miket',
        matchCount: 15,
        roster: _roster(12),
        cellOverrides: [red(0, 1)],
      );
      final tailCoverers = schedule.rotations
          .where((r) => r.isOnDuty(15))
          .map((r) => r.uid)
          .toSet();
      expect(tailCoverers, hasLength(6));

      final round1Coverers = schedule.rotations
          .where((r) => r.isOnDuty(7))
          .map((r) => r.uid)
          .toSet();
      expect(tailCoverers, round1Coverers);
    });

    test('a round with fewer than 6 non-red columns runs short-handed', () {
      final schedule = ScoutShiftSchedule.generate(
        eventKey: '2026miket',
        matchCount: 6,
        roster: _roster(6),
        cellOverrides: [red(0, 3), red(1, 3), red(2, 3)],
      );
      expect(_onDutyCount(schedule, 3, 3), isTrue);
    });

    test('non-red overrides do not block a round', () {
      final schedule = ScoutShiftSchedule.generate(
        eventKey: '2026miket',
        matchCount: 12,
        roster: _roster(12),
        cellOverrides: [
          ScheduleCellEdit(
            col: 0,
            match: 1,
            text: '',
            color: ScheduleCellColor.grey,
          ),
        ],
      );

      expect(schedule.rotationFor('u0')!.isOnDuty(1), isTrue);
    });

    test('is deterministic for the same inputs', () {
      final overrides = [red(0, 1), red(3, 8)];
      final first = ScoutShiftSchedule.generate(
        eventKey: '2026miket',
        matchCount: 18,
        roster: _roster(12),
        cellOverrides: overrides,
      );
      final second = ScoutShiftSchedule.generate(
        eventKey: '2026miket',
        matchCount: 18,
        roster: _roster(12),
        cellOverrides: overrides,
      );
      expect(
        first.toJson()..remove('updatedAt'),
        second.toJson()..remove('updatedAt'),
      );
    });
  });

  group('stations', () {
    List<String?> stationsOnDuty(ScoutShiftSchedule schedule, int match) => [
      for (var col = 0; col < schedule.roster.length; col++)
        if (schedule.rotations[col].isOnDuty(match))
          schedule.stationFor(col, match),
    ];

    List<String?> blockStations(ScoutShiftSchedule schedule, String uid) =>
        schedule.rotationFor(uid)!.shifts.map((s) => s.station).toList();

    void expectDistinctEveryMatch(ScoutShiftSchedule schedule) {
      for (var m = 1; m <= schedule.matchCount; m++) {
        final stations = stationsOnDuty(schedule, m);
        expect(stations, everyElement(isNotNull), reason: 'match $m');
        expect(
          stations.toSet(),
          hasLength(stations.length),
          reason: 'match $m',
        );
      }
    }

    test('one scouter per station in every match', () {
      expectDistinctEveryMatch(
        ScoutShiftSchedule.generate(
          eventKey: '2026miket',
          matchCount: 36,
          roster: _roster(12),
        ),
      );
      expect(
        stationsOnDuty(
          ScoutShiftSchedule.generate(
            eventKey: '2026miket',
            matchCount: 6,
            roster: _roster(6),
          ),
          1,
        ),
        ScoutShiftBlock.stations,
      );
    });

    test('each scouter moves one station per block', () {
      final schedule = ScoutShiftSchedule.generate(
        eventKey: '2026miket',
        matchCount: 72,
        roster: _roster(12),
      );
      expect(blockStations(schedule, 'u0'), [
        'R1',
        'R2',
        'R3',
        'B1',
        'B2',
        'B3',
      ]);
      expect(blockStations(schedule, 'u1'), [
        'R2',
        'R3',
        'B1',
        'B2',
        'B3',
        'R1',
      ]);
    });

    test('a single group keeps its stations for the whole event', () {
      final schedule = ScoutShiftSchedule.generate(
        eventKey: '2026miket',
        matchCount: 36,
        roster: _roster(6),
      );
      expect(blockStations(schedule, 'u0'), ['R1']);
      expect(blockStations(schedule, 'u5'), ['B3']);
    });

    test('a group counts only its own blocks', () {
      final schedule = ScoutShiftSchedule.generate(
        eventKey: '2026miket',
        matchCount: 36,
        roster: _roster(12),
      );
      expect(blockStations(schedule, 'u0'), ['R1', 'R2', 'R3']);
      expect(blockStations(schedule, 'u1'), ['R2', 'R3', 'B1']);
      expect(blockStations(schedule, 'u6'), ['R1', 'R2', 'R3']);
    });

    test('a short tail group still gets distinct stations', () {
      final schedule = ScoutShiftSchedule.generate(
        eventKey: '2026miket',
        matchCount: 18,
        roster: _roster(14),
      );
      expectDistinctEveryMatch(schedule);
      expect(blockStations(schedule, 'u12'), ['R1']);
      expect(blockStations(schedule, 'u13'), ['R2']);
    });

    test('a tail fill keeps the station of the block it extends', () {
      final schedule = ScoutShiftSchedule.generate(
        eventKey: '2026miket',
        matchCount: 15,
        roster: _roster(12),
      );
      final block = schedule.rotationFor('u6')!.shifts.single;
      expect((block.startMatch, block.endMatch, block.station), (7, 15, 'R1'));
    });

    test('an event shorter than one shift still names stations', () {
      final schedule = ScoutShiftSchedule.generate(
        eventKey: '2026miket',
        matchCount: 4,
        roster: _roster(8),
      );
      expectDistinctEveryMatch(schedule);
    });

    test('red cells keep one scouter per station and rotate each scouter', () {
      final schedule = ScoutShiftSchedule.generate(
        eventKey: '2026miket',
        matchCount: 36,
        roster: _roster(12),
        cellOverrides: [
          for (var m = 1; m <= 6; m++)
            ScheduleCellEdit(col: 0, match: m, color: ScheduleCellColor.red),
        ],
      );
      expectDistinctEveryMatch(schedule);
      expect(schedule.stationFor(1, 1), 'R1');
      for (final rotation in schedule.rotations) {
        final stations = rotation.shifts.map((s) => s.station).toList();
        for (var i = 1; i < stations.length; i++) {
          expect(stations[i], isNot(stations[i - 1]), reason: rotation.uid);
        }
      }
    });

    test('rotation JSON stores the station and trade JSON does not', () {
      const block = ScoutShiftBlock(startMatch: 1, endMatch: 6, station: 'B2');
      expect(block.toJson().keys, unorderedEquals(['startMatch', 'endMatch']));
      expect(block.toRotationJson(), {
        'startMatch': 1,
        'endMatch': 6,
        'station': 'B2',
      });
      const none = ScoutShiftBlock(startMatch: 1, endMatch: 6);
      expect(none.toRotationJson().containsKey('station'), isFalse);
    });

    test('the station round-trips through the schedule JSON', () {
      final schedule = ScoutShiftSchedule.generate(
        eventKey: '2026miket',
        matchCount: 12,
        roster: _roster(8),
      );
      final json = schedule.toJson();
      final shifts =
          ((json['rotations'] as List).first as Map)['shifts'] as List;
      expect((shifts.first as Map)['station'], 'R1');
      final decoded = ScoutShiftSchedule.fromJson(json);
      expect(blockStations(decoded, 'u1'), ['R2']);
    });

    test('a schedule saved without stations reads as none', () {
      final block = ScoutShiftBlock.fromJson(<String, dynamic>{
        'startMatch': 1,
        'endMatch': 6,
      });
      expect(block.station, isNull);
      final odd = ScoutShiftBlock.fromJson(<String, dynamic>{
        'startMatch': 1,
        'endMatch': 6,
        'station': 'R9',
      });
      expect(odd.station, isNull);
    });

    test('stationFor is null for a hand-painted green cell', () {
      final schedule = ScoutShiftSchedule.generate(
        eventKey: '2026miket',
        matchCount: 12,
        roster: _roster(12),
      );
      final painted = schedule.withCellEdit(
        col: 0,
        match: 8,
        text: '',
        color: ScheduleCellColor.green,
      );
      expect(painted.colorFor(0, 8), ScheduleCellColor.green);
      expect(painted.stationFor(0, 8), isNull);
      expect(painted.stationFor(0, 3), 'R1');
      expect(painted.stationFor(99, 3), isNull);
    });
  });
}
