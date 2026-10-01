import 'package:firestore_client/firestore_client.dart' as fc;

import 'accuracy_mapping_service.dart';

class DesktopAccuracyMappingService implements AccuracyMappingService {
  DesktopAccuracyMappingService({required this._firestore});

  final fc.Firestore _firestore;

  static const String _path = 'appConfig/accuracyMapping';

  @override
  Future<Map<String, dynamic>?> load() async {
    final doc = await _firestore.getDocument(_path);
    return doc?.fields;
  }

  @override
  Future<void> save(Map<String, dynamic> data) {
    return _firestore.setDocument(_path, data);
  }
}
