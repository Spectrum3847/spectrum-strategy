import 'package:flutter_test/flutter_test.dart';
import 'package:spectrumstrategy/src/scouting/models/prescout_entry.dart';

void main() {
  test('PrescoutEntry toJson/fromJson round-trips', () {
    final entry = PrescoutEntry(
      id: 'abc',
      teamNumber: 3847,
      eventKey: '2025flor',
      fieldValues: <String, dynamic>{
        'startingPosition': 'centerHub',
        'defense': true,
      },
      authorUid: 'uid-1',
      authorDisplayName: 'Scout',
      updatedAt: DateTime.utc(2026, 6, 27, 12, 0),
    );
    final round = PrescoutEntry.fromJson(entry.toJson());
    expect(round.id, 'abc');
    expect(round.teamNumber, 3847);
    expect(round.eventKey, '2025flor');
    expect(round.fieldValues['startingPosition'], 'centerHub');
    expect(round.fieldValues['defense'], true);
    expect(round.authorUid, 'uid-1');
    expect(round.authorDisplayName, 'Scout');
    expect(round.updatedAt, DateTime.utc(2026, 6, 27, 12, 0));
  });

  test(
    'PrescoutEntry toJson emits updatedAt as UTC ISO 8601 with Z suffix',
    () {
      final entry = PrescoutEntry(
        teamNumber: 1,
        updatedAt: DateTime.utc(2026, 1, 1, 0, 0, 0),
      );
      final json = entry.toJson();
      expect(json['updatedAt'] as String, endsWith('Z'));
    },
  );

  test('PrescoutEntry fromJson defaults missing fields', () {
    final entry = PrescoutEntry.fromJson(<String, dynamic>{
      'id': 'x',
      'teamNumber': 254,
      'updatedAt': '2026-01-01T00:00:00.000Z',
    });
    expect(entry.authorUid, '');
    expect(entry.authorDisplayName, '');
    expect(entry.eventKey, '');
    expect(entry.fieldValues, isEmpty);
  });

  test('PrescoutEntry constructor forces updatedAt to UTC', () {
    final local = DateTime(2026, 6, 27, 10, 0);
    final entry = PrescoutEntry(teamNumber: 1, updatedAt: local);
    expect(entry.updatedAt.isUtc, isTrue);
  });

  test('copyWith replaces only the given fields', () {
    final entry = PrescoutEntry(
      id: 'abc',
      teamNumber: 3847,
      eventKey: '2025flor',
      fieldValues: <String, dynamic>{'teleopFuelScored': 42},
      authorUid: 'uid-1',
      authorDisplayName: 'Scout',
      updatedAt: DateTime.utc(2026, 6, 27, 12, 0),
    );
    final copy = entry.copyWith(
      fieldValues: <String, dynamic>{'teleopFuelScored': 50},
      updatedAt: DateTime.utc(2026, 6, 27, 13, 0),
    );
    expect(copy.id, 'abc');
    expect(copy.teamNumber, 3847);
    expect(copy.eventKey, '2025flor');
    expect(copy.fieldValues['teleopFuelScored'], 50);
    expect(copy.authorUid, 'uid-1');
    expect(copy.authorDisplayName, 'Scout');
    expect(copy.updatedAt, DateTime.utc(2026, 6, 27, 13, 0));
  });
}
