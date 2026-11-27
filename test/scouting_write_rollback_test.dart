import 'package:flutter_test/flutter_test.dart';

import 'package:spectrumstrategy/src/scouting/models/pit_scout_entry.dart';
import 'package:spectrumstrategy/src/scouting/models/scout_entry.dart';
import 'package:spectrumstrategy/src/scouting/state/pit_scouting_controller.dart';
import 'package:spectrumstrategy/src/scouting/state/scouting_controller.dart';

import 'support/fake_pit_scouting_storage.dart';
import 'support/fake_scouting_storage.dart';

class _FailingScoutingStorage extends FakeScoutingStorage {
  bool failSaves = false;
  bool failDeletes = false;

  bool Function(ScoutEntry entry)? failSaveWhen;

  @override
  Future<void> saveEntry(ScoutEntry entry) async {
    if (failSaves || (failSaveWhen?.call(entry) ?? false)) {
      throw StateError('disk full');
    }
    return super.saveEntry(entry);
  }

  @override
  Future<void> deleteEntry(String id) async {
    if (failDeletes) throw StateError('disk full');
    return super.deleteEntry(id);
  }
}

class _FailingPitStorage extends FakePitScoutingStorage {
  bool failSaves = false;
  bool failDeletes = false;

  @override
  Future<void> saveEntry(PitScoutEntry entry) async {
    if (failSaves) throw StateError('disk full');
    return super.saveEntry(entry);
  }

  @override
  Future<void> deleteEntry(String id) async {
    if (failDeletes) throw StateError('disk full');
    return super.deleteEntry(id);
  }
}

ScoutEntry _entry({
  String id = 'entry-1',
  int team = 3847,
  String notes = '',
}) => ScoutEntry(
  id: id,
  matchId: '2026txdri1_qm1',
  teamNumber: team,
  notes: notes,
);

void main() {
  group('ScoutingController', () {
    test(
      'a failed save is reported and the new entry is taken back out',
      () async {
        final storage = _FailingScoutingStorage()..failSaves = true;
        final controller = ScoutingController(storage: storage);
        await controller.bootstrap();

        final saved = await controller.saveEntry(_entry());

        expect(saved, isFalse);
        expect(controller.entries, isEmpty);
        expect(controller.lastError, contains('3847'));
        expect(storage.rawEntries, isEmpty);
      },
    );

    test('a failed edit puts the stored version back', () async {
      final storage = _FailingScoutingStorage();
      final controller = ScoutingController(storage: storage);
      await controller.bootstrap();
      expect(await controller.saveEntry(_entry(notes: 'first')), isTrue);

      storage.failSaves = true;
      final saved = await controller.saveEntry(_entry(notes: 'second'));

      expect(saved, isFalse);
      expect(controller.entries.single.notes, 'first');
    });

    test('a stale rollback does not overwrite a newer edit', () async {
      final storage = _FailingScoutingStorage();
      final controller = ScoutingController(storage: storage);
      await controller.bootstrap();
      expect(await controller.saveEntry(_entry(notes: 'first')), isTrue);

      storage.failSaveWhen = (ScoutEntry entry) => entry.notes == 'second';
      final failing = controller.saveEntry(_entry(notes: 'second'));
      final later = controller.saveEntry(_entry(notes: 'third'));

      expect(await failing, isFalse);
      expect(await later, isTrue);
      expect(controller.entries.single.notes, 'third');

      expect(controller.lastError, isNotNull);
    });

    test('a failed delete puts the entry back', () async {
      final storage = _FailingScoutingStorage();
      final controller = ScoutingController(storage: storage);
      await controller.bootstrap();
      expect(await controller.saveEntry(_entry()), isTrue);

      storage.failDeletes = true;
      final deleted = await controller.deleteEntry('entry-1');

      expect(deleted, isFalse);
      expect(controller.entries.single.id, 'entry-1');
      expect(controller.lastError, contains('3847'));
    });

    test('deleting an entry that is already gone is not a failure', () async {
      final controller = ScoutingController(
        storage: _FailingScoutingStorage()..failDeletes = true,
      );
      await controller.bootstrap();

      expect(await controller.deleteEntry('never-existed'), isTrue);
      expect(controller.lastError, isNull);
    });

    test('clearLastError clears it', () async {
      final controller = ScoutingController(
        storage: _FailingScoutingStorage()..failSaves = true,
      );
      await controller.bootstrap();
      await controller.saveEntry(_entry());
      expect(controller.lastError, isNotNull);

      controller.clearLastError();

      expect(controller.lastError, isNull);
    });
  });

  group('PitScoutingController', () {
    test('a failed save is reported and the entry is taken back out', () async {
      final storage = _FailingPitStorage()..failSaves = true;
      final controller = PitScoutingController(storage: storage);
      await controller.bootstrap();

      final saved = await controller.saveEntry(
        PitScoutEntry(id: 'pit-1', teamNumber: 3847),
      );

      expect(saved, isFalse);
      expect(controller.entries, isEmpty);
      expect(controller.lastError, contains('3847'));
    });

    test('a failed delete puts the entry back', () async {
      final storage = _FailingPitStorage();
      final controller = PitScoutingController(storage: storage);
      await controller.bootstrap();
      expect(
        await controller.saveEntry(
          PitScoutEntry(id: 'pit-1', teamNumber: 3847),
        ),
        isTrue,
      );

      storage.failDeletes = true;
      final deleted = await controller.deleteEntry('pit-1');

      expect(deleted, isFalse);
      expect(controller.entries.single.id, 'pit-1');
      expect(controller.lastError, contains('3847'));
    });
  });
}
