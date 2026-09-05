import 'package:flutter_test/flutter_test.dart';

import 'package:spectrumstrategy/src/scouting/models/scout_entry.dart';
import 'package:spectrumstrategy/src/scouting/state/scouting_controller.dart';

import 'support/fake_scouting_storage.dart';

void main() {
  group('ScoutEntry.contentSignature', () {
    test('ignores id, author, and timestamp', () {
      final a = ScoutEntry(
        matchId: 'qm12',
        teamNumber: 3847,
        alliance: 'Blue',
        fieldValues: const {'auto': 3, 'teleop': 10},
        authorUid: 'u1',
        authorDisplayName: 'One',
        updatedAt: DateTime.utc(2026, 1, 1),
      );
      final b = ScoutEntry(
        matchId: 'qm12',
        teamNumber: 3847,
        alliance: 'Blue',

        fieldValues: const {'teleop': 10, 'auto': 3},
        authorUid: 'u2',
        authorDisplayName: 'Two',
        updatedAt: DateTime.utc(2026, 6, 1),
      );
      expect(a.contentSignature, b.contentSignature);
    });

    test('differs when the data differs', () {
      final a = ScoutEntry(
        matchId: 'qm12',
        teamNumber: 3847,
        fieldValues: const {'auto': 3},
      );
      final b = ScoutEntry(
        matchId: 'qm12',
        teamNumber: 3847,
        fieldValues: const {'auto': 4},
      );
      expect(a.contentSignature, isNot(b.contentSignature));
    });
  });

  group('ScoutingController.importScannedEntry', () {
    test('imports once, then reports duplicates without re-adding', () async {
      final controller = ScoutingController(storage: FakeScoutingStorage());
      addTearDown(controller.dispose);

      ScoutEntry scanned() => ScoutEntry(
        matchId: 'qm12',
        teamNumber: 3847,
        alliance: 'Blue',
        fieldValues: const {'auto': 3, 'teleop': 10},
      );

      final first = await controller.importScannedEntry(scanned());
      expect(first, ScanImportResult.imported);
      expect(controller.entries, hasLength(1));

      final second = await controller.importScannedEntry(scanned());
      expect(second, ScanImportResult.duplicate);
      expect(controller.entries, hasLength(1));
    });

    test('a genuinely different submission is imported', () async {
      final controller = ScoutingController(storage: FakeScoutingStorage());
      addTearDown(controller.dispose);

      await controller.importScannedEntry(
        ScoutEntry(
          matchId: 'qm12',
          teamNumber: 3847,
          fieldValues: const {'a': 1},
        ),
      );
      final other = await controller.importScannedEntry(
        ScoutEntry(
          matchId: 'qm12',
          teamNumber: 254,
          fieldValues: const {'a': 1},
        ),
      );
      expect(other, ScanImportResult.imported);
      expect(controller.entries, hasLength(2));
    });
  });
}
