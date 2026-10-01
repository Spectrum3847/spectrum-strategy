import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:spectrumstrategy/src/services/user_scoped_firestore_cache.dart';

void main() {
  late Directory root;
  String? uid;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('firestore_cache_test');
    uid = null;
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  UserScopedFirestoreCache cache() =>
      UserScopedFirestoreCache(root: root, currentUid: () => uid);

  test('a read comes back for the user who wrote it', () async {
    uid = 'userA';
    final subject = cache();
    await subject.write('doc/teams/1234', '{"a":1}');

    expect(await subject.read('doc/teams/1234'), '{"a":1}');
  });

  test('a second account is not served the first account data', () async {
    final subject = cache();
    uid = 'userA';
    await subject.write('doc/teams/1234', '{"a":1}');

    uid = 'userB';
    expect(await subject.read('doc/teams/1234'), isNull);

    uid = 'userA';
    expect(await subject.read('doc/teams/1234'), '{"a":1}');
  });

  test('nothing is cached while nobody is signed in', () async {
    final subject = cache();
    await subject.write('doc/teams/1234', '{"a":1}');

    expect(await subject.read('doc/teams/1234'), isNull);
    expect(root.listSync(), isEmpty);
  });

  test('a uid that could escape the root gets no cache', () async {
    final subject = cache();
    uid = '../elsewhere';
    await subject.write('doc/teams/1234', '{"a":1}');

    expect(await subject.read('doc/teams/1234'), isNull);
    expect(root.listSync(), isEmpty);
  });

  test('clear drops only the signed-in account', () async {
    final subject = cache();
    uid = 'userA';
    await subject.write('doc/teams/1234', '{"a":1}');
    uid = 'userB';
    await subject.write('doc/teams/1234', '{"b":2}');

    uid = 'userA';
    await subject.clear();

    expect(await subject.read('doc/teams/1234'), isNull);
    uid = 'userB';
    expect(await subject.read('doc/teams/1234'), '{"b":2}');
  });

  test('clearForUid drops a user who is no longer the current one', () async {
    final subject = cache();
    uid = 'userA';
    await subject.write('doc/teams/1234', '{"a":1}');

    uid = null;
    await subject.clearForUid('userA');

    uid = 'userA';
    expect(await subject.read('doc/teams/1234'), isNull);
  });

  test('remove drops one key and leaves the rest', () async {
    uid = 'userA';
    final subject = cache();
    await subject.write('doc/teams/1234', '{"a":1}');
    await subject.write('doc/teams/5678', '{"b":2}');

    await subject.remove('doc/teams/1234');

    expect(await subject.read('doc/teams/1234'), isNull);
    expect(await subject.read('doc/teams/5678'), '{"b":2}');
  });
}
