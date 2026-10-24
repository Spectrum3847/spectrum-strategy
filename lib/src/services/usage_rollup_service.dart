import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firestore_client/firestore_client.dart' as fc;

import '../models/usage_rollup.dart';
import 'desktop_usage_rollup_service.dart';

abstract class UsageRollupService {
  Future<UsageRollup> fetch();
}

class UsageRollupUnavailable implements Exception {
  const UsageRollupUnavailable(this.message);

  final String message;

  @override
  String toString() => message;
}

const usageRollupMissing =
    'No usage rollup yet. The daily job writes it; if this persists, '
    'check the Usage rollup cron workflow.';

const usageRollupDenied = 'Usage data is limited to the developer role.';

UsageRollupService usageRollupServiceFor({fc.Firestore? rest}) => rest == null
    ? FirestoreUsageRollupService()
    : DesktopUsageRollupService(firestore: rest);

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
        throw const UsageRollupUnavailable(usageRollupMissing);
      }
      return UsageRollup.fromJson(data);
    } on FirebaseException catch (error) {
      if (error.code == 'permission-denied') {
        throw const UsageRollupUnavailable(usageRollupDenied);
      }
      throw UsageRollupUnavailable(
        'Could not read usage data: ${error.message ?? error.code}',
      );
    }
  }
}
