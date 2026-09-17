import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/usage_rollup.dart';

abstract class UsageRollupService {
  Future<UsageRollup> fetch();
}

class UsageRollupUnavailable implements Exception {
  const UsageRollupUnavailable(this.message);

  final String message;

  @override
  String toString() => message;
}

class FirestoreUsageRollupService implements UsageRollupService {
  FirestoreUsageRollupService({this._firestore});

  static const String docPath = 'telemetryRollup/current';

  final FirebaseFirestore? _firestore;

  FirebaseFirestore get _db => _firestore ?? FirebaseFirestore.instance;

  @override
  Future<UsageRollup> fetch() async {
    try {
      final snapshot = await _db.doc(docPath).get();
      final data = snapshot.data();
      if (!snapshot.exists || data == null) {
        throw const UsageRollupUnavailable(
          'No usage rollup yet. The daily job writes it; if this persists, '
          'check the Usage rollup cron workflow.',
        );
      }
      return UsageRollup.fromJson(data);
    } on FirebaseException catch (error) {
      if (error.code == 'permission-denied') {
        throw const UsageRollupUnavailable(
          'Usage data is limited to the developer role.',
        );
      }
      throw UsageRollupUnavailable(
        'Could not read usage data: ${error.message ?? error.code}',
      );
    }
  }
}
