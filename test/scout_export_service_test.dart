import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:spectrumstrategy/src/scouting/models/scout_config.dart';
import 'package:spectrumstrategy/src/scouting/models/scout_entry.dart';
import 'package:spectrumstrategy/src/services/scout_export_service.dart';

ScoutConfig _config() => const ScoutConfig(
  title: 'Test',
  sections: [
    ScoutConfigSection(
      name: 'Match',
      fields: [
        ScoutConfigField(
          title: 'Station',
          type: ScoutFieldType.select,
          code: 'station',
          choices: {'R1': 'Red 1', 'B1': 'Blue 1'},
        ),
        ScoutConfigField(
          title: 'Coral scored',
          type: ScoutFieldType.counter,
          code: 'coral',
        ),
        ScoutConfigField(
          title: 'Climbed',
          type: ScoutFieldType.boolean,
          code: 'climbed',
        ),
        ScoutConfigField(
          title: 'Auto notes',
          type: ScoutFieldType.text,
          code: 'autoNotes',
        ),
      ],
    ),
  ],
);

ScoutEntry _entry({
  required String matchId,
  required int teamNumber,
  required Map<String, dynamic> fieldValues,
}) => ScoutEntry(
  matchId: matchId,
  teamNumber: teamNumber,
  fieldValues: fieldValues,
  authorUid: 'uid-123',
  authorDisplayName: 'Some Scouter',
  notes: 'Driver is Alex, plays defense hard',
  createdAt: DateTime.utc(2026, 9, 12, 10, 0),
  updatedAt: DateTime.utc(2026, 9, 12, 10, 5),
);

void main() {
  group('ScoutExportService.buildCsv', () {
    final service = ScoutExportService();

    test('header carries only core columns and redacted field types', () {
      final csv = service.buildCsv(
        config: _config(),
        entries: const [],
        eventKey: '2026test',
      );

      final header = csv.split('\r\n').first;
      expect(
        header,
        'Event,Match,Team,Station,Created (UTC),Updated (UTC),Station,'
        'Coral scored,Climbed',
      );

      expect(header, isNot(contains('Auto notes')));
    });

    test('drops author, notes and device identity from every row', () {
      final entry = _entry(
        matchId: 'qm12',
        teamNumber: 3847,
        fieldValues: {
          'station': 'R1',
          'coral': 4,
          'climbed': true,
          'autoNotes': 'Alex drove great',
        },
      );

      final csv = service.buildCsv(
        config: _config(),
        entries: [entry],
        eventKey: '2026test',
      );

      expect(csv, isNot(contains('Alex')));
      expect(csv, isNot(contains('uid-123')));
      expect(csv, isNot(contains('Some Scouter')));
      expect(csv, isNot(contains('defense')));
    });

    test('keeps team performance data in config field order', () {
      final entry = _entry(
        matchId: 'qm12',
        teamNumber: 3847,
        fieldValues: {'station': 'R1', 'coral': 4, 'climbed': true},
      );

      final csv = service.buildCsv(
        config: _config(),
        entries: [entry],
        eventKey: '2026test',
      );

      final row = csv.split('\r\n')[1];
      expect(
        row,
        '2026test,qm12,3847,R1,2026-09-12T10:00:00.000Z,'
        '2026-09-12T10:05:00.000Z,Red 1,4,true',
      );
    });

    test('quotes a cell that carries a comma', () {
      final config = ScoutConfig(
        title: 'Test',
        sections: [
          ScoutConfigSection(
            name: 'Match',
            fields: [
              ScoutConfigField(
                title: 'Notable, weird',
                type: ScoutFieldType.select,
                code: 'weird',
                choices: const {'a': 'has, comma'},
              ),
            ],
          ),
        ],
      );
      final entry = _entry(
        matchId: 'qm1',
        teamNumber: 1,
        fieldValues: const {'weird': 'a'},
      );

      final csv = service.buildCsv(
        config: config,
        entries: [entry],
        eventKey: '2026test',
      );

      expect(csv, contains('"has, comma"'));
      expect(csv, contains('"Notable, weird"'));
    });
  });

  group('ScoutExportService.writeCsv', () {
    test('writes the CSV to the injected export directory', () async {
      final tmp = await Directory.systemTemp.createTemp('scout-export');
      final service = ScoutExportService(
        exportDirResolver: () async =>
            (directory: tmp, description: 'Documents/SpectrumStrategy/exports'),
      );

      final result = await service.writeCsv(
        config: _config(),
        entries: [
          _entry(
            matchId: 'qm1',
            teamNumber: 3847,
            fieldValues: const {'station': 'R1', 'coral': 1, 'climbed': false},
          ),
        ],
        eventKey: '2026 Test Event!',
      );

      expect(result.file.path, contains('2026_test_event_scouting_export.csv'));
      expect(result.file.parent.path, tmp.path);
      expect(await result.file.exists(), isTrue);
      expect(result.locationDescription, 'Documents/SpectrumStrategy/exports');
      await tmp.delete(recursive: true);
    });
  });
}
