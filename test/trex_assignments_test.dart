import 'package:flutter_test/flutter_test.dart';
import 'package:spectrumstrategy/src/models/trex_assignments.dart';

void main() {
  group('TRexAssignments', () {
    test('round-trips through toJson/fromJson', () {
      final assignments = TRexAssignments(
        columns: const [
          TRexTraitColumn(key: 'k1', name: 'Defense', names: ['Alex', 'Sam']),
          TRexTraitColumn(key: 'k2', name: 'Driver skill', names: ['Jordan']),
        ],
        authorUid: 'uid-1',
        authorDisplayName: 'Lead',
        updatedAt: DateTime.utc(2026, 8, 19),
      );

      final decoded = TRexAssignments.fromJson(assignments.toJson());

      expect(decoded.columns.map((c) => c.key), ['k1', 'k2']);
      expect(decoded.columns.first.name, 'Defense');
      expect(decoded.columns.first.names, ['Alex', 'Sam']);
      expect(decoded.authorUid, 'uid-1');
      expect(decoded.authorDisplayName, 'Lead');
      expect(decoded.updatedAt, DateTime.utc(2026, 8, 19));
    });

    test('a missing document decodes as empty, not a crash', () {
      final decoded = TRexAssignments.fromJson(null);

      expect(decoded.isEmpty, isTrue);
      expect(decoded.columns, isEmpty);
    });

    test('drops a column with no key or no name', () {
      final decoded = TRexAssignments.fromJson({
        'columns': [
          {'key': 'k1', 'name': 'Defense', 'names': <String>[]},
          {'name': 'No key'},
          {'key': 'k2'},
          'not a map',
        ],
      });

      expect(decoded.columns.map((c) => c.key), ['k1']);
    });

    test('drops a blank name from the names list', () {
      final decoded = TRexAssignments.fromJson({
        'columns': [
          {
            'key': 'k1',
            'name': 'Defense',
            'names': ['Alex', '', '   ', 42],
          },
        ],
      });

      expect(decoded.columns.single.names, ['Alex']);
    });

    test('byKey finds the matching column', () {
      final assignments = TRexAssignments(
        columns: const [TRexTraitColumn(key: 'k1', name: 'Defense')],
        updatedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      );

      expect(assignments.byKey('k1')?.name, 'Defense');
      expect(assignments.byKey('missing'), isNull);
    });
  });
}
