import 'package:flutter_test/flutter_test.dart';
import 'package:spectrumstrategy/src/models/trex_trait.dart';
import 'package:spectrumstrategy/src/models/trex_trait_report.dart';

void main() {
  group('TrexTrait', () {
    test('lists exactly the five traits from the spec doc, in order', () {
      expect(TrexTrait.values.map((t) => t.label).toList(), [
        'Autonomous',
        'Defense',
        'Driver skill',
        'Fuel scoring',
        'Passing/pushing/stealing',
      ]);
    });

    test('every trait carries non-empty instructions', () {
      for (final trait in TrexTrait.values) {
        expect(trait.instructions, isNotEmpty, reason: trait.key);
      }
    });

    test('byKey finds a trait by its stable key', () {
      expect(TrexTrait.byKey('driverSkill'), TrexTrait.driverSkill);
    });

    test('byKey returns null for an unknown key', () {
      expect(TrexTrait.byKey('stealth'), isNull);
      expect(TrexTrait.byKey(null), isNull);
    });
  });

  group('TrexTraitReport', () {
    test('round-trips through toJson/fromJson', () {
      final report = TrexTraitReport(
        id: 'r1',
        trait: TrexTrait.autonomous.key,
        teamNumber: 3847,
        matchNumber: 12,
        eventName: '2026miket',
        report: 'Fast, clean auton to the depot bump.',
        strokes: const [
          {
            'phase': 'auton',
            'colorValue': 0xFF000000,
            'points': [
              {'x': 0.1, 'y': 0.2},
            ],
          },
        ],
        authorUid: 'uid-1',
        authorDisplayName: 'Dana',
        updatedAt: DateTime.utc(2026, 8, 1),
      );

      final decoded = TrexTraitReport.fromJson(report.toJson());

      expect(decoded.id, 'r1');
      expect(decoded.trait, 'autonomous');
      expect(decoded.teamNumber, 3847);
      expect(decoded.matchNumber, 12);
      expect(decoded.eventName, '2026miket');
      expect(decoded.report, 'Fast, clean auton to the depot bump.');
      expect(decoded.strokes, hasLength(1));
      expect(decoded.authorUid, 'uid-1');
      expect(decoded.authorDisplayName, 'Dana');
      expect(decoded.updatedAt, DateTime.utc(2026, 8, 1));
    });

    test('generates a random id when none is given', () {
      final a = TrexTraitReport(
        trait: TrexTrait.defense.key,
        teamNumber: 254,
        matchNumber: 1,
        updatedAt: DateTime.utc(2026),
      );
      final b = TrexTraitReport(
        trait: TrexTrait.defense.key,
        teamNumber: 254,
        matchNumber: 1,
        updatedAt: DateTime.utc(2026),
      );
      expect(a.id, isNotEmpty);
      expect(a.id, isNot(b.id));
    });

    test('toJson omits strokes when empty', () {
      final report = TrexTraitReport(
        trait: TrexTrait.fuelScoring.key,
        teamNumber: 254,
        matchNumber: 1,
        updatedAt: DateTime.utc(2026),
      );
      expect(report.toJson().containsKey('strokes'), isFalse);
    });

    test('isEmpty is true with no report text, event name, or drawing', () {
      final report = TrexTraitReport(
        trait: TrexTrait.defense.key,
        teamNumber: 254,
        matchNumber: 1,
        updatedAt: DateTime.utc(2026),
      );
      expect(report.isEmpty, isTrue);
    });

    test('fromJson degrades a corrupt document instead of throwing', () {
      final decoded = TrexTraitReport.fromJson(const {
        'teamNumber': 'not a number',
        'strokes': 'not a list',
      });
      expect(decoded.teamNumber, 0);
      expect(decoded.strokes, isEmpty);
      expect(decoded.id, isNotEmpty);
    });

    test('copyWith stamps author without touching the rest', () {
      final base = TrexTraitReport(
        id: 'r1',
        trait: TrexTrait.driverSkill.key,
        teamNumber: 254,
        matchNumber: 1,
        report: 'Good decision making under pressure.',
        updatedAt: DateTime.utc(2026),
      );
      final stamped = base.copyWith(
        authorUid: 'uid-2',
        authorDisplayName: 'Sam',
      );
      expect(stamped.authorUid, 'uid-2');
      expect(stamped.authorDisplayName, 'Sam');
      expect(stamped.report, base.report);
      expect(stamped.id, base.id);
    });
  });
}
