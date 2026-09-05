import 'package:flutter_test/flutter_test.dart';

import 'package:spectrumstrategy/src/scouting/models/scout_entry.dart';

void main() {
  test('createdAt defaults to updatedAt, not to now', () {
    final captured = DateTime.utc(2026, 4, 20, 14, 30);
    final entry = ScoutEntry(
      matchId: 'qm1',
      teamNumber: 3847,
      updatedAt: captured,
    );

    expect(entry.createdAt, captured);
  });

  test('an edit moves updatedAt and leaves createdAt alone', () {
    final entry = ScoutEntry(
      matchId: 'qm1',
      teamNumber: 3847,
      updatedAt: DateTime.utc(2026, 4, 20, 14, 30),
    );

    final edited = entry.copyWith(
      notes: 'fixed a typo',
      updatedAt: DateTime.utc(2026, 4, 20, 16, 0),
    );

    expect(edited.createdAt, DateTime.utc(2026, 4, 20, 14, 30));
    expect(edited.updatedAt, DateTime.utc(2026, 4, 20, 16, 0));
  });

  test('it round-trips through JSON', () {
    final entry = ScoutEntry(
      matchId: 'qm1',
      teamNumber: 3847,
      createdAt: DateTime.utc(2026, 4, 20, 14, 30),
      updatedAt: DateTime.utc(2026, 4, 20, 16, 0),
    );

    final again = ScoutEntry.fromJson(entry.toJson());

    expect(again.createdAt, entry.createdAt);
    expect(again.updatedAt, entry.updatedAt);
  });

  test('an entry stored before this field falls back to updatedAt', () {
    final legacy = ScoutEntry(
      matchId: 'qm1',
      teamNumber: 3847,
      updatedAt: DateTime.utc(2026, 4, 20, 16, 0),
    ).toJson()..remove('createdAt');

    expect(
      ScoutEntry.fromJson(legacy).createdAt,
      DateTime.utc(2026, 4, 20, 16, 0),
    );
  });

  test('a wrong-typed createdAt falls back rather than throwing', () {
    final json = ScoutEntry(
      matchId: 'qm1',
      teamNumber: 3847,
      updatedAt: DateTime.utc(2026, 4, 20, 16, 0),
    ).toJson();
    json['createdAt'] = 42;

    expect(
      ScoutEntry.fromJson(json).createdAt,
      DateTime.utc(2026, 4, 20, 16, 0),
    );
  });
}
