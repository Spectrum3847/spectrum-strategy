import 'package:firestore_client/firestore_client.dart' as fc;

import '../models/usage_rollup.dart';
import 'usage_rollup_service.dart';

class DesktopUsageRollupService implements UsageRollupService {
  DesktopUsageRollupService({required this._firestore});

  final fc.Firestore _firestore;

  @override
  Future<UsageRollup> fetch() async {
    try {
      final doc = await _firestore.getDocument(
        FirestoreUsageRollupService.docPath,
      );
      if (doc == null) throw const UsageRollupUnavailable(usageRollupMissing);
      return UsageRollup.fromJson(doc.fields);
    } on fc.FirestoreApiException catch (error) {
      if (error.statusCode == 403 || error.status == 'PERMISSION_DENIED') {
        throw const UsageRollupUnavailable(usageRollupDenied);
      }
      throw UsageRollupUnavailable('Could not read usage data: $error');
    }
  }
}
