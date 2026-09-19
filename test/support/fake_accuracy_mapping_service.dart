import 'package:spectrumstrategy/src/scouting/services/accuracy_mapping_service.dart';

class FakeAccuracyMappingService implements AccuracyMappingService {
  FakeAccuracyMappingService({Map<String, dynamic>? initial})
    : _mapping = initial;

  Map<String, dynamic>? _mapping;

  Object? loadError;
  Object? saveError;

  int loadCalls = 0;
  int saveCalls = 0;
  Map<String, dynamic>? lastSaved;

  @override
  Future<Map<String, dynamic>?> load() async {
    loadCalls++;
    final error = loadError;
    if (error != null) throw error;
    return _mapping;
  }

  @override
  Future<void> save(Map<String, dynamic> data) async {
    saveCalls++;
    final error = saveError;
    if (error != null) throw error;
    _mapping = data;
    lastSaved = data;
  }
}
