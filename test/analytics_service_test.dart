import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:spectrumstrategy/src/services/analytics_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('NoopAnalyticsService', () {
    test('every call is a no-op and never throws', () async {
      const service = NoopAnalyticsService();
      await service.start();
      service.screen('Strategy');
      service.capture('scout_entry_saved');
      service.identify('uid-1');
      service.reset();
    });
  });

  group('PostHogAnalyticsService, empty key (this repo today)', () {
    test('never starts, so every call after start stays a no-op', () async {
      final service = PostHogAnalyticsService();
      await service.start();

      expect(() => service.capture('scout_entry_saved'), returnsNormally);
    });

    test('start completes without arming a plugin or HTTP call', () async {
      var sent = 0;
      final service = PostHogAnalyticsService(
        debugForceHttpFallback: true,
        sender: (url, body) async => sent++,
      );
      await service.start();
      service.capture('scout_entry_saved');
      service.screen('Strategy');
      expect(sent, 0);
    });

    test('capture, screen, identify and reset before start are no-ops', () {
      final service = PostHogAnalyticsService();
      expect(() => service.screen('Strategy'), returnsNormally);
      expect(() => service.capture('sync_succeeded'), returnsNormally);
      expect(() => service.identify('uid-1'), returnsNormally);
      expect(() => service.reset(), returnsNormally);
    });
  });

  group('PostHogAnalyticsService, web/Linux/Windows HTTP fallback', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('capture posts the documented capture-API body shape', () async {
      final posted = <(Uri, Map<String, Object?>)>[];
      final service = PostHogAnalyticsService(
        debugApiKey: 'phc_test_key',
        debugForceHttpFallback: true,
        sender: (url, body) async => posted.add((url, body)),
      );
      await service.start();

      service.capture('scout_entry_saved', properties: {'teamNumber': 3847});

      expect(posted, hasLength(1));
      final (url, body) = posted.single;
      expect(url, Uri.parse('https://us.i.posthog.com/i/v0/e/'));
      expect(body['api_key'], 'phc_test_key');
      expect(body['event'], 'scout_entry_saved');
      expect(body['distinct_id'], isA<String>());
      expect(body['properties'], containsPair('teamNumber', 3847));
      expect((body['properties'] as Map)['\$lib'], 'spectrum-strategy-dart');
      expect(body['timestamp'], isA<String>());
    });

    test('screen posts a \$screen event with \$screen_name', () async {
      final posted = <(Uri, Map<String, Object?>)>[];
      final service = PostHogAnalyticsService(
        debugApiKey: 'phc_test_key',
        debugForceHttpFallback: true,
        sender: (url, body) async => posted.add((url, body)),
      );
      await service.start();

      service.screen('Strategy');

      expect(posted.single.$2['event'], '\$screen');
      expect(
        (posted.single.$2['properties'] as Map)['\$screen_name'],
        'Strategy',
      );
    });

    test(
      'identify switches the distinct id used by later events, and persists it',
      () async {
        final posted = <(Uri, Map<String, Object?>)>[];
        final service = PostHogAnalyticsService(
          debugApiKey: 'phc_test_key',
          debugForceHttpFallback: true,
          sender: (url, body) async => posted.add((url, body)),
        );
        await service.start();

        service.identify('uid-1');
        service.capture('scout_entry_saved');

        expect(posted.first.$2['event'], '\$identify');
        expect(posted.last.$2['distinct_id'], 'uid-1');

        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('analytics_distinct_id'), 'uid-1');
      },
    );

    test('reset generates a fresh anonymous id for later events', () async {
      final posted = <(Uri, Map<String, Object?>)>[];
      final service = PostHogAnalyticsService(
        debugApiKey: 'phc_test_key',
        debugForceHttpFallback: true,
        sender: (url, body) async => posted.add((url, body)),
      );
      await service.start();
      final before = (await SharedPreferences.getInstance()).getString(
        'analytics_distinct_id',
      );

      service.reset();
      service.capture('scout_entry_saved');

      final after = posted.single.$2['distinct_id'];
      expect(after, isNot(before));
    });
  });
}
