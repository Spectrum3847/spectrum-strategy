import 'package:flutter_test/flutter_test.dart';

import 'package:spectrumstrategy/src/models/trex_assignments.dart';
import 'package:spectrumstrategy/src/services/trex_assignments_export.dart';

void main() {
  group('TRexAssignmentsExport.asText', () {
    test('renders each column heading with its names below', () {
      final assignments = TRexAssignments(
        columns: const [
          TRexTraitColumn(key: 'k1', name: 'Defense', names: ['Alex', 'Sam']),
          TRexTraitColumn(key: 'k2', name: 'Auton', names: ['Jordan']),
        ],
        updatedAt: DateTime.utc(2026, 8, 19),
      );

      final text = TRexAssignmentsExport.asText(assignments);

      expect(text, contains('Defense'));
      expect(text, contains('Alex'));
      expect(text, contains('Sam'));
      expect(text, contains('Auton'));
      expect(text, contains('Jordan'));

      expect(text.indexOf('Defense'), lessThan(text.indexOf('Auton')));
      expect(text.indexOf('Alex'), lessThan(text.indexOf('Sam')));
    });

    test(
      'an empty table renders a plain message rather than a blank string',
      () {
        final text = TRexAssignmentsExport.asText(
          TRexAssignments(
            updatedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
          ),
        );

        expect(text, contains('no traits added yet'));
      },
    );

    test('a column with no names says so instead of an empty gap', () {
      final assignments = TRexAssignments(
        columns: const [TRexTraitColumn(key: 'k1', name: 'Defense')],
        updatedAt: DateTime.utc(2026, 8, 19),
      );

      final text = TRexAssignmentsExport.asText(assignments);

      expect(text, contains('(unassigned)'));
    });
  });
}
