import 'package:cloud_firestore/cloud_firestore.dart';

abstract class AccuracyMappingService {
  Future<Map<String, dynamic>?> load();
  Future<void> save(Map<String, dynamic> data);
}

class FirestoreAccuracyMappingService implements AccuracyMappingService {
  FirestoreAccuracyMappingService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  static const String _path = 'appConfig/accuracyMapping';

  @override
  Future<Map<String, dynamic>?> load() async {
    final doc = await _firestore.doc(_path).get();
    return doc.exists ? doc.data() : null;
  }

  @override
  Future<void> save(Map<String, dynamic> data) {
    return _firestore.doc(_path).set(data);
  }
}
