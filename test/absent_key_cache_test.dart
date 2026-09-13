import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spectrumstrategy/src/services/assistant/firestore_assistant_config.dart';
import 'package:spectrumstrategy/src/services/tba/firestore_tba_config.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('assistant key', () {
    test('an absent key is read once, not once per call', () async {
      var reads = 0;
      final config = FirestoreAssistantConfig(
        remoteFetcher: () async {
          reads++;
          return null;
        },
      );

      for (var i = 0; i < 5; i++) {
        expect(await config.teamKey(), isNull);
      }

      expect(reads, 1);
    });

    test(
      'it re-reads once the window passes, so a console change lands',
      () async {
        var reads = 0;
        var now = DateTime.utc(2026, 8, 16, 12);
        final config = FirestoreAssistantConfig(
          remoteFetcher: () async {
            reads++;
            return reads == 1 ? null : 'set-later';
          },
        )..nowFn = () => now;

        expect(await config.teamKey(), isNull);
        expect(await config.teamKey(), isNull);
        expect(reads, 1);

        now = now.add(FirestoreAssistantConfig.absentTtl * 2);

        expect(await config.teamKey(), 'set-later');
        expect(reads, 2);
      },
    );

    test('a failed read is still not cached', () async {
      var reads = 0;
      final config = FirestoreAssistantConfig(
        remoteFetcher: () async {
          reads++;
          throw StateError('signed out');
        },
      );

      expect(await config.teamKey(), isNull);
      expect(await config.teamKey(), isNull);
      expect(reads, 2);
    });

    test('a found key short-circuits everything after it', () async {
      var reads = 0;
      final config = FirestoreAssistantConfig(
        remoteFetcher: () async {
          reads++;
          return 'the-key';
        },
      );

      expect(await config.teamKey(), 'the-key');
      expect(await config.teamKey(), 'the-key');
      expect(reads, 1);
    });
  });

  group('tba key', () {
    test('an absent key is read once, not once per call', () async {
      var reads = 0;
      final config = FirestoreTbaConfig(
        remoteFetcher: () async {
          reads++;
          return null;
        },
      );

      for (var i = 0; i < 5; i++) {
        expect(await config.teamKey(), isNull);
      }

      expect(reads, 1);
    });

    test('it re-reads once the window passes', () async {
      var reads = 0;
      var now = DateTime.utc(2026, 8, 16, 12);
      final config = FirestoreTbaConfig(
        remoteFetcher: () async {
          reads++;
          return reads == 1 ? null : 'set-later';
        },
      )..nowFn = () => now;

      expect(await config.teamKey(), isNull);
      expect(reads, 1);

      now = now.add(FirestoreTbaConfig.absentTtl * 2);

      expect(await config.teamKey(), 'set-later');
      expect(reads, 2);
    });
  });
}
