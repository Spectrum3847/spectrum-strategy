import 'dart:io';

import 'package:firestore_client/firestore_client.dart' as fc;

class UserScopedFirestoreCache implements fc.FirestoreCache {
  UserScopedFirestoreCache({required this.root, required this.currentUid});

  final Directory root;

  final String? Function() currentUid;

  static final RegExp _safeUid = RegExp(r'^[A-Za-z0-9_-]{1,64}$');

  fc.FileFirestoreCache? _cacheFor(String? uid) {
    if (uid == null || !_safeUid.hasMatch(uid)) return null;
    return fc.FileFirestoreCache(
      Directory('${root.path}${Platform.pathSeparator}$uid'),
    );
  }

  @override
  Future<String?> read(String key) async => _cacheFor(currentUid())?.read(key);

  @override
  Future<void> write(String key, String value) async =>
      _cacheFor(currentUid())?.write(key, value);

  @override
  Future<void> remove(String key) async => _cacheFor(currentUid())?.remove(key);

  @override
  Future<void> clear() async => _cacheFor(currentUid())?.clear();

  Future<void> clearForUid(String uid) async => _cacheFor(uid)?.clear();
}
