import 'package:flutter_test/flutter_test.dart';

import 'package:spectrumstrategy/src/scouting/models/scout_entry.dart';

void main() {
  test('defaults to false', () {
    final entry = ScoutEntry(matchId: 'qm1', teamNumber: 3847);

    expect(entry.addedManually, isFalse);
  });

  test('round-trips through JSON when true', () {
    final entry = ScoutEntry(
      matchId: 'qm1',
      teamNumber: 3847,
      addedManually: true,
    );

    final again = ScoutEntry.fromJson(entry.toJson());

    expect(again.addedManually, isTrue);
  });

  test('is omitted from JSON when false, so old data needs no migration', () {
    final entry = ScoutEntry(matchId: 'qm1', teamNumber: 3847);

    expect(entry.toJson().containsKey('addedManually'), isFalse);
  });

  test('a stored entry with no addedManually key reads as false', () {
    final legacy = ScoutEntry(matchId: 'qm1', teamNumber: 3847).toJson();

    expect(legacy.containsKey('addedManually'), isFalse);
    expect(ScoutEntry.fromJson(legacy).addedManually, isFalse);
  });

  test('copyWith preserves addedManually when not overridden', () {
    final entry = ScoutEntry(
      matchId: 'qm1',
      teamNumber: 3847,
      addedManually: true,
    );

    final edited = entry.copyWith(notes: 'fixed a typo');

    expect(edited.addedManually, isTrue);
  });

  test('copyWith can flip addedManually explicitly', () {
    final entry = ScoutEntry(
      matchId: 'qm1',
      teamNumber: 3847,
      addedManually: true,
    );

    final edited = entry.copyWith(addedManually: false);

    expect(edited.addedManually, isFalse);
  });
}
