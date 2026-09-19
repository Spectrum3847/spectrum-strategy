import 'package:firestore_client/firestore_client.dart' as fc;

Future<fc.FirestoreCache?> createDesktopFirestoreCache(
  String? Function() currentUid,
) async => null;

Future<void> clearDesktopFirestoreCacheFor(String uid) async {}
