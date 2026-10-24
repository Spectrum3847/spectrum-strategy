import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:spectrumstrategy/src/services/pending_push_queue.dart';

void main() {
  group('PendingPushQueue', () {
    late PendingPushQueue queue;

    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      queue = PendingPushQueue();
    });

    test('empty queue returns no pending ids', () async {
      expect(await queue.pending('scoutEntries'), isEmpty);
      expect(await queue.count('scoutEntries'), 0);
    });

    test('mark adds an id to the collection', () async {
      await queue.mark('scoutEntries', 'e1');
      expect(await queue.pending('scoutEntries'), {'e1'});
      expect(await queue.count('scoutEntries'), 1);
    });

    test('mark is idempotent', () async {
      await queue.mark('scoutEntries', 'e1');
      await queue.mark('scoutEntries', 'e1');
      expect(await queue.pending('scoutEntries'), {'e1'});
      expect(await queue.count('scoutEntries'), 1);
    });

    test('clear removes an id', () async {
      await queue.mark('scoutEntries', 'e1');
      await queue.clear('scoutEntries', 'e1');
      expect(await queue.pending('scoutEntries'), isEmpty);
    });

    test('clear is idempotent', () async {
      await queue.mark('scoutEntries', 'e1');
      await queue.clear('scoutEntries', 'e1');
      await queue.clear('scoutEntries', 'e1');
      expect(await queue.pending('scoutEntries'), isEmpty);
    });

    test('collectons are isolated', () async {
      await queue.mark('scoutEntries', 'e1');
      await queue.mark('pitScoutEntries', 'p1');
      expect(await queue.pending('scoutEntries'), {'e1'});
      expect(await queue.pending('pitScoutEntries'), {'p1'});
      expect(await queue.count('scoutEntries'), 1);
      expect(await queue.count('pitScoutEntries'), 1);

      await queue.clear('scoutEntries', 'e1');
      expect(await queue.pending('scoutEntries'), isEmpty);
      expect(await queue.pending('pitScoutEntries'), {'p1'});
    });

    test('multiple ids in one collection', () async {
      await queue.mark('scoutEntries', 'e1');
      await queue.mark('scoutEntries', 'e2');
      await queue.mark('scoutEntries', 'e3');
      expect(await queue.pending('scoutEntries'), {'e1', 'e2', 'e3'});
      expect(await queue.count('scoutEntries'), 3);

      await queue.clear('scoutEntries', 'e2');
      expect(await queue.pending('scoutEntries'), {'e1', 'e3'});
    });

    test('concurrent mark calls for the same collection do not race', () async {
      await Future.wait(<Future<void>>[
        queue.mark('scoutEntries', 'e1'),
        queue.mark('scoutEntries', 'e2'),
        queue.mark('scoutEntries', 'e3'),
      ]);
      expect(await queue.pending('scoutEntries'), {'e1', 'e2', 'e3'});
    });

    test(
      'a slow write in flight does not lose a concurrently marked id',
      () async {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        final firstWriteGate = Completer<void>();
        var writes = 0;
        final gatedQueue = PendingPushQueue(
          debugBeforeWrite: () async {
            writes++;
            if (writes == 1) await firstWriteGate.future;
          },
        );

        final first = gatedQueue.mark('scoutEntries', 'e1');

        await pumpEventQueue();
        expect(writes, 1);
        final second = gatedQueue.mark('scoutEntries', 'e2');
        await pumpEventQueue();
        firstWriteGate.complete();
        await Future.wait(<Future<void>>[first, second]);

        expect(writes, 2);
        expect(await gatedQueue.pending('scoutEntries'), {'e1', 'e2'});
      },
    );

    test('persists across queue instances', () async {
      const key = 'pending_push_scoutEntries_v1';
      SharedPreferences.setMockInitialValues(<String, Object>{
        key: '["e1","e2"]',
      });
      final queueA = PendingPushQueue();
      expect(await queueA.pending('scoutEntries'), {'e1', 'e2'});

      await queueA.mark('scoutEntries', 'e3');
      expect(await queueA.pending('scoutEntries'), {'e1', 'e2', 'e3'});

      final queueB = PendingPushQueue();
      expect(await queueB.pending('scoutEntries'), {'e1', 'e2', 'e3'});

      await queueB.clear('scoutEntries', 'e1');
      expect(await queueB.pending('scoutEntries'), {'e2', 'e3'});
    });
  });
}
