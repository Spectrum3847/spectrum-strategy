import 'dart:io';

import 'package:firestore_client/firestore_client.dart' as fc;
import 'package:path_provider/path_provider.dart';

import 'user_scoped_firestore_cache.dart';

Future<fc.FirestoreCache?> createDesktopFirestoreCache(
  String? Function() currentUid,
) async {
  final root = await _cacheRoot();
  if (root == null) return null;
  return UserScopedFirestoreCache(root: root, currentUid: currentUid);
}

Future<void> clearDesktopFirestoreCacheFor(String uid) async {
  final root = await _cacheRoot();
  if (root == null) return;
  await UserScopedFirestoreCache(
    root: root,
    currentUid: () => uid,
  ).clearForUid(uid);
}

Future<Directory?> _cacheRoot() async {
  try {
    final support = await getApplicationSupportDirectory();
    return Directory('${support.path}${Platform.pathSeparator}firestore_cache');
  } on Exception {
    return null;
  }
}
