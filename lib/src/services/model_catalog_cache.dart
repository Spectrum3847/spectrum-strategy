import 'dart:convert';
import 'dart:io';

import 'llama_runtime_service.dart' show AssistantModel;

typedef ModelCatalogCacheEntry = ({
  List<AssistantModel> models,
  DateTime fetchedAt,
});

class ModelCatalogCache {
  ModelCatalogCache(this._file);

  final File _file;

  Future<ModelCatalogCacheEntry?> load() async {
    if (!await _file.exists()) return null;
    try {
      final json =
          jsonDecode(await _file.readAsString()) as Map<String, dynamic>;
      final fetchedAt = DateTime.parse(json['fetchedAt'] as String);
      final models = (json['models'] as List)
          .cast<Map<String, dynamic>>()
          .map(AssistantModel.fromJson)
          .toList();
      return (models: models, fetchedAt: fetchedAt);
    } catch (_) {
      return null;
    }
  }

  Future<void> save(List<AssistantModel> models, DateTime fetchedAt) async {
    await _file.parent.create(recursive: true);
    final temp = File('${_file.path}.tmp');
    await temp.writeAsString(
      jsonEncode(<String, dynamic>{
        'fetchedAt': fetchedAt.toIso8601String(),
        'models': [for (final model in models) model.toJson()],
      }),
      flush: true,
    );
    await temp.rename(_file.path);
  }
}
