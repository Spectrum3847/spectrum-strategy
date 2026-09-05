import 'dart:convert';

import 'package:flutter/services.dart';

class FieldMapDefinition {
  const FieldMapDefinition({
    required this.id,
    required this.game,
    required this.imageAsset,
    required this.jsonAsset,
    required this.fieldSize,
    required this.fieldUnit,
    required this.cornersTopLeft,
    required this.cornersBottomRight,
  });

  final String id;
  final String game;
  final String imageAsset;
  final String jsonAsset;
  final List<double> fieldSize;
  final String fieldUnit;
  final List<int> cornersTopLeft;
  final List<int> cornersBottomRight;

  double get aspectRatio {
    if (fieldSize.length < 2 || fieldSize[1] == 0) {
      return 2.0;
    }
    return fieldSize[0] / fieldSize[1];
  }
}

class FieldMapCatalog {
  static const String manifestAsset = 'assets/fields/wpilib/MANIFEST.json';

  static Future<FieldMapCatalogData>? _shared;

  static Future<FieldMapCatalogData> shared() =>
      _shared ??= FieldMapCatalog().load();

  Future<FieldMapCatalogData> load() async {
    final manifestRaw = await rootBundle.loadString(manifestAsset);
    final manifest = jsonDecode(manifestRaw) as Map<String, dynamic>;
    final latest = (manifest['latest'] as String?)?.trim();
    final fields = (manifest['fields'] as List<dynamic>? ?? <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .toList(growable: false);

    final definitions = <FieldMapDefinition>[];
    for (final entry in fields) {
      final id = (entry['id'] as String?)?.trim();
      final jsonAsset = (entry['json'] as String?)?.trim();
      if (id == null || id.isEmpty || jsonAsset == null || jsonAsset.isEmpty) {
        continue;
      }
      final jsonRaw = await rootBundle.loadString(jsonAsset);
      final jsonData = jsonDecode(jsonRaw) as Map<String, dynamic>;
      final imageName = (jsonData['field-image'] as String?)?.trim() ?? '';
      final game = (jsonData['game'] as String?)?.trim();
      final fieldSize =
          (jsonData['field-size'] as List<dynamic>? ?? <dynamic>[])
              .whereType<num>()
              .map((value) => value.toDouble())
              .toList(growable: false);
      final corners =
          (jsonData['field-corners'] as Map<String, dynamic>?) ??
          <String, dynamic>{};
      final topLeft = (corners['top-left'] as List<dynamic>? ?? <dynamic>[])
          .whereType<num>()
          .map((value) => value.toInt())
          .toList(growable: false);
      final bottomRight =
          (corners['bottom-right'] as List<dynamic>? ?? <dynamic>[])
              .whereType<num>()
              .map((value) => value.toInt())
              .toList(growable: false);
      if (imageName.isEmpty || game == null || game.isEmpty) {
        continue;
      }
      definitions.add(
        FieldMapDefinition(
          id: id,
          game: game,
          imageAsset: 'assets/fields/wpilib/$imageName',
          jsonAsset: jsonAsset,
          fieldSize: fieldSize,
          fieldUnit: (jsonData['field-unit'] as String?) ?? '',
          cornersTopLeft: topLeft,
          cornersBottomRight: bottomRight,
        ),
      );
    }

    final sorted = definitions.toList(growable: false)
      ..sort((a, b) => a.id.compareTo(b.id));
    final latestId = (latest != null && latest.isNotEmpty)
        ? latest
        : (sorted.isNotEmpty ? sorted.last.id : '');

    return FieldMapCatalogData(fields: sorted, latestId: latestId);
  }
}

class FieldMapCatalogData {
  FieldMapCatalogData({required this.fields, required this.latestId})
    : _byId = <String, FieldMapDefinition>{
        for (final field in fields) field.id: field,
      };

  final List<FieldMapDefinition> fields;
  final String latestId;
  final Map<String, FieldMapDefinition> _byId;

  FieldMapDefinition? find(String id) => _byId[id];

  FieldMapDefinition? fallbackFor(String selectedFieldId) {
    final selected = find(selectedFieldId);
    if (selected != null) {
      return selected;
    }
    final latest = find(latestId);
    if (latest != null) {
      return latest;
    }
    if (fields.isNotEmpty) {
      return fields.last;
    }
    return null;
  }
}
