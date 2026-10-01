import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:spectrumstrategy/src/services/tba/firestore_tba_config.dart';
import 'package:tba_client/tba_client.dart';

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('the team key wins over the compile-time key', () async {
    final team = FirestoreTbaConfig(
      remoteFetcher: () async => 'team-key',
      prefsLoader: SharedPreferences.getInstance,
      fallback: InMemoryTbaConfig('compile-time'),
    );

    expect(await team.resolveApiKey(), 'team-key');
  });

  test('a fetched key is mirrored so it survives going offline', () async {
    final team = FirestoreTbaConfig(
      remoteFetcher: () async => '  team-key  ',
      prefsLoader: SharedPreferences.getInstance,
    );

    expect(await team.teamKey(), 'team-key');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(FirestoreTbaConfig.prefsKey), 'team-key');
  });

  test('a fetch failure falls back to the offline mirror', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      FirestoreTbaConfig.prefsKey: 'mirrored',
    });
    final team = FirestoreTbaConfig(
      remoteFetcher: () async => throw StateError('signed out'),
      prefsLoader: SharedPreferences.getInstance,
      fallback: InMemoryTbaConfig('compile-time'),
    );

    expect(await team.resolveApiKey(), 'mirrored');
  });

  test('a fetch failure with no mirror uses the fallback', () async {
    final team = FirestoreTbaConfig(
      remoteFetcher: () async => throw StateError('offline'),
      prefsLoader: SharedPreferences.getInstance,
      fallback: InMemoryTbaConfig('compile-time'),
    );

    expect(await team.resolveApiKey(), 'compile-time');
  });

  test('an empty remote value clears the mirror', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      FirestoreTbaConfig.prefsKey: 'stale-mirror',
    });
    final team = FirestoreTbaConfig(
      remoteFetcher: () async => '',
      prefsLoader: SharedPreferences.getInstance,
      fallback: InMemoryTbaConfig('compile-time'),
    );

    expect(await team.teamKey(), isNull);
    expect(await team.resolveApiKey(), 'compile-time');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(FirestoreTbaConfig.prefsKey), isNull);
  });
}
