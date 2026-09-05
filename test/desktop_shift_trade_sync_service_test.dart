import 'dart:convert';

import 'package:firestore_client/firestore_client.dart' as fc;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:spectrumstrategy/src/scouting/models/scout_shift_schedule.dart';
import 'package:spectrumstrategy/src/scouting/models/shift_trade.dart';
import 'package:spectrumstrategy/src/scouting/services/desktop_shift_trade_sync_service.dart';
import 'package:spectrumstrategy/src/services/spectrum_auth_service.dart';

import 'support/fake_spectrum_auth_service.dart';

fc.Firestore _firestore(MockClient client) => fc.Firestore(
  projectId: 'demo',
  idTokenProvider: () async => 'tok',
  httpClient: client,
);

FakeSpectrumAuthService _signedInAuth() => FakeSpectrumAuthService(
  initialUser: const SpectrumUser(uid: 'uid-1', displayName: 'Dana'),
);

ShiftTrade _trade(String id, {DateTime? updatedAt}) => ShiftTrade(
  id: id,
  eventKey: '2026txhou',
  requesterUid: 'uid-1',
  requesterDisplayName: 'Dana',
  targetUid: 'uid-2',
  targetDisplayName: 'Rae',
  requesterBlock: const ScoutShiftBlock(startMatch: 1, endMatch: 6),
  createdAt: DateTime.utc(2026, 7, 8, 12),
  updatedAt: updatedAt ?? DateTime.utc(2026, 7, 8, 12),
);

String _doc(ShiftTrade trade, {DateTime? serverTs}) => jsonEncode({
  'name': 'projects/demo/databases/(default)/documents/shiftTrades/${trade.id}',
  'fields': fc.FirestoreValueCodec.encodeFields(<String, dynamic>{
    ...trade.toJson(),
    'updatedAtTs': ?serverTs,
  }),
});

Future<void> _waitUntil(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition() && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  test('the first poll fetches the collection; the next ones query '
      'updatedAtTs', () async {
    final fields = <String>[];
    final service = DesktopShiftTradeSyncService(
      authService: _signedInAuth(),
      firestore: _firestore(
        MockClient((request) async {
          if (request.url.path.endsWith(':runQuery')) {
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            final where = ((body['structuredQuery'] as Map)['where'] as Map)
                .cast<String, dynamic>();
            final filter = (where['fieldFilter'] as Map)
                .cast<String, dynamic>();
            fields.add((filter['field'] as Map)['fieldPath'] as String);
            return http.Response(jsonEncode(<dynamic>[]), 200);
          }
          fields.add('(listDocuments)');
          final trade = _trade('t1');
          return http.Response(
            jsonEncode({
              'documents': [jsonDecode(_doc(trade, serverTs: trade.updatedAt))],
            }),
            200,
          );
        }),
      ),
      pollInterval: const Duration(milliseconds: 10),
    );
    addTearDown(service.dispose);

    await service.initialize();
    await _waitUntil(() => fields.length >= 3);

    expect(fields.first, '(listDocuments)');
    expect(fields.skip(1).take(2), everyElement('updatedAtTs'));
  });

  test('a delta poll emits the merged cache, not just the delta', () async {
    final first = _trade('t1');
    final second = _trade('t2', updatedAt: DateTime.utc(2026, 7, 9));
    final service = DesktopShiftTradeSyncService(
      authService: _signedInAuth(),
      firestore: _firestore(
        MockClient((request) async {
          if (request.url.path.endsWith(':runQuery')) {
            return http.Response(
              jsonEncode([
                {
                  'document': jsonDecode(
                    _doc(second, serverTs: second.updatedAt),
                  ),
                },
              ]),
              200,
            );
          }
          return http.Response(
            jsonEncode({
              'documents': [jsonDecode(_doc(first, serverTs: first.updatedAt))],
            }),
            200,
          );
        }),
      ),
      pollInterval: const Duration(milliseconds: 10),
    );
    addTearDown(service.dispose);

    final snapshots = <List<ShiftTrade>>[];
    final sub = service.tradesStream.listen(snapshots.add);
    addTearDown(sub.cancel);
    await service.initialize();
    await _waitUntil(() => snapshots.any((s) => s.length == 2));

    expect(snapshots.first.map((t) => t.id), ['t1']);
    expect(snapshots.last.map((t) => t.id), ['t1', 't2']);
  });

  test('a full collection fetch recurs, so a trade deleted elsewhere and one '
      'the cursor passed are both recovered', () async {
    final fields = <String>[];
    final service = DesktopShiftTradeSyncService(
      authService: _signedInAuth(),
      firestore: _firestore(
        MockClient((request) async {
          if (request.url.path.endsWith(':runQuery')) {
            fields.add('delta');
            return http.Response(jsonEncode(<dynamic>[]), 200);
          }
          fields.add('full');
          final trade = _trade('t1');
          return http.Response(
            jsonEncode({
              'documents': [jsonDecode(_doc(trade, serverTs: trade.updatedAt))],
            }),
            200,
          );
        }),
      ),
      pollInterval: const Duration(milliseconds: 5),
    );
    addTearDown(service.dispose);

    await service.initialize();
    await _waitUntil(() => fields.where((f) => f == 'full').length >= 2);

    expect(
      fields.where((f) => f == 'full').length,
      greaterThanOrEqualTo(2),
      reason: 'the full fetch must recur, not just happen once at startup',
    );

    expect(fields.where((f) => f == 'delta').length, greaterThan(4));
  });

  test('a document that fails to decode does not advance the cursor', () async {
    final cursors = <String>[];
    final service = DesktopShiftTradeSyncService(
      authService: _signedInAuth(),
      firestore: _firestore(
        MockClient((request) async {
          if (request.url.path.endsWith(':runQuery')) {
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            final where = ((body['structuredQuery'] as Map)['where'] as Map)
                .cast<String, dynamic>();
            final filter = (where['fieldFilter'] as Map)
                .cast<String, dynamic>();
            cursors.add((filter['value'] as Map)['timestampValue'] as String);
            return http.Response(
              jsonEncode([
                {
                  'document': {
                    'name':
                        'projects/demo/databases/(default)/documents/'
                        'shiftTrades/broken',
                    'fields': fc.FirestoreValueCodec.encodeFields(
                      <String, dynamic>{
                        'requesterBlock': 'not-a-map',
                        'updatedAtTs': DateTime.utc(2027),
                      },
                    ),
                  },
                },
              ]),
              200,
            );
          }
          final trade = _trade('t1');
          return http.Response(
            jsonEncode({
              'documents': [jsonDecode(_doc(trade, serverTs: trade.updatedAt))],
            }),
            200,
          );
        }),
      ),
      pollInterval: const Duration(milliseconds: 10),
    );
    addTearDown(service.dispose);

    await service.initialize();
    await _waitUntil(() => cursors.length >= 2);

    expect(cursors.last, cursors.first);
  });

  test('a create shows up without waiting for a poll', () async {
    final service = DesktopShiftTradeSyncService(
      authService: _signedInAuth(),
      firestore: _firestore(
        MockClient((request) async {
          if (request.method == 'PATCH' ||
              request.url.path.endsWith('documents:commit')) {
            return http.Response(
              _doc(_trade('t-new', updatedAt: DateTime.utc(2026, 8))),
              200,
            );
          }
          if (request.url.path.endsWith(':runQuery')) {
            return http.Response(jsonEncode(<dynamic>[]), 200);
          }
          return http.Response(jsonEncode({'documents': <dynamic>[]}), 200);
        }),
      ),
      pollInterval: const Duration(seconds: 30),
    );
    addTearDown(service.dispose);

    await service.initialize();
    final snapshots = <List<ShiftTrade>>[];
    final sub = service.tradesStream.listen(snapshots.add);
    addTearDown(sub.cancel);

    await service.create(_trade('t-new', updatedAt: DateTime.utc(2026, 8)));
    await _waitUntil(() => snapshots.any((s) => s.length == 1));

    expect(snapshots.last.single.id, 't-new');
  });

  test(
    'a create sends updatedAtTs so other devices can cursor on it',
    () async {
      Map<String, dynamic>? written;
      final service = DesktopShiftTradeSyncService(
        authService: _signedInAuth(),
        firestore: _firestore(
          MockClient((request) async {
            if (request.method == 'PATCH') {
              written = (jsonDecode(request.body) as Map<String, dynamic>)
                  .cast<String, dynamic>();
              return http.Response(_doc(_trade('t-new')), 200);
            }
            if (request.url.path.endsWith(':runQuery')) {
              return http.Response(jsonEncode(<dynamic>[]), 200);
            }
            return http.Response(jsonEncode({'documents': <dynamic>[]}), 200);
          }),
        ),
        pollInterval: const Duration(seconds: 30),
      );
      addTearDown(service.dispose);

      await service.initialize();
      await service.create(_trade('t-new'));

      final fields = (written!['fields'] as Map).cast<String, dynamic>();
      expect(fields['updatedAtTs'], isNotNull);
    },
  );

  test('signing out clears the cache and the cursor', () async {
    final auth = _signedInAuth();
    var fulls = 0;
    final service = DesktopShiftTradeSyncService(
      authService: auth,
      firestore: _firestore(
        MockClient((request) async {
          if (request.url.path.endsWith(':runQuery')) {
            return http.Response(jsonEncode(<dynamic>[]), 200);
          }
          fulls++;
          final trade = _trade('t1');
          return http.Response(
            jsonEncode({
              'documents': [jsonDecode(_doc(trade, serverTs: trade.updatedAt))],
            }),
            200,
          );
        }),
      ),
      pollInterval: const Duration(seconds: 30),
    );
    addTearDown(service.dispose);

    final snapshots = <List<ShiftTrade>>[];
    final sub = service.tradesStream.listen(snapshots.add);
    addTearDown(sub.cancel);

    await service.initialize();
    await _waitUntil(() => fulls >= 1);
    await auth.signOut();
    await _waitUntil(() => snapshots.isNotEmpty && snapshots.last.isEmpty);
    auth.emit(
      const SpectrumAuthSnapshot(
        state: SpectrumAuthState.signedIn,
        user: SpectrumUser(uid: 'uid-9', displayName: 'Other'),
      ),
    );

    await _waitUntil(() => fulls >= 2);

    expect(fulls, greaterThanOrEqualTo(2));
  });
}
