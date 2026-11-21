import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:spectrumstrategy/src/services/field_map_catalog.dart';

void main() {
  final fieldsDir = Directory('assets/fields/wpilib');

  test('every field JSON points at an image that exists', () {
    final jsonFiles =
        fieldsDir
            .listSync()
            .whereType<File>()
            .where(
              (f) =>
                  f.path.endsWith('.json') && !f.path.endsWith('MANIFEST.json'),
            )
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    expect(jsonFiles, isNotEmpty, reason: 'Expected synced field JSON files.');

    final missing = <String>[];
    for (final jsonFile in jsonFiles) {
      final data =
          jsonDecode(jsonFile.readAsStringSync()) as Map<String, dynamic>;
      final imageName = (data['field-image'] as String?)?.trim() ?? '';
      expect(
        imageName,
        isNotEmpty,
        reason: '${jsonFile.path} has no field-image.',
      );
      final image = File('${fieldsDir.path}/$imageName');
      if (!image.existsSync()) missing.add(image.path);
    }
    expect(missing, isEmpty, reason: 'Missing field images: $missing');
  });

  test('MANIFEST.json points at field JSON files that exist', () {
    final manifest = jsonDecode(
      File('${fieldsDir.path}/MANIFEST.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final fields = (manifest['fields'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
    expect(fields, isNotEmpty);
    final missing = fields
        .map((f) => f['json'] as String)
        .where((p) => !File(p).existsSync())
        .toList();
    expect(missing, isEmpty, reason: 'Missing field JSON: $missing');
  });

  test('every referenceImageAsset in a bundled config exists', () {
    final configs = Directory('assets')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.json'));
    final referenced = <String>{};
    for (final config in configs) {
      final pattern = RegExp(r'"referenceImageAsset":\s*"([^"]+)"');
      for (final match in pattern.allMatches(config.readAsStringSync())) {
        final path = match.group(1)!;
        if (path.isNotEmpty) referenced.add(path);
      }
    }
    expect(
      referenced,
      isNotEmpty,
      reason: 'Expected a bundled config to carry a reference image.',
    );
    final missing = referenced.where((p) => !File(p).existsSync()).toList()
      ..sort();
    expect(missing, isEmpty, reason: 'Missing reference images: $missing');
  });

  group('a board saved against a season that is no longer bundled', () {
    final catalog = FieldMapCatalogData(
      fields: const [
        FieldMapDefinition(
          id: '2026-rebuilt',
          game: '2026 FRC Rebuilt',
          imageAsset: 'assets/fields/wpilib/2026-rebuilt.png',
          jsonAsset: 'assets/fields/wpilib/2026-rebuilt.json',
          fieldSize: [54.269, 26.474],
          fieldUnit: 'foot',
          cornersTopLeft: [254, 121],
          cornersBottomRight: [3951, 1917],
        ),
      ],
      latestId: '2026-rebuilt',
    );

    test('falls back to the current field', () {
      expect(catalog.fallbackFor('2025-reefscape')?.id, '2026-rebuilt');
      expect(catalog.fallbackFor('2024-crescendo')?.id, '2026-rebuilt');
    });

    test('falls back for a session with no saved field id', () {
      expect(catalog.fallbackFor('')?.id, '2026-rebuilt');
    });
  });
}
