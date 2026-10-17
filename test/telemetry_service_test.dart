import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spectrumstrategy/src/services/debug_info.dart';
import 'package:spectrumstrategy/src/services/telemetry_service.dart';

const _allowedKeys = {
  'id',
  'type',
  'deviceId',
  'appVersion',
  'platform',
  'osVersion',
  'locale',
  'detail',
  'createdAt',
};

const _info = DebugInfo(
  appVersion: '1.2.3',
  buildNumber: '7',
  platform: 'linux',
  osVersion: 'Linux test',
  device: 'Test PC',
  gitCommit: 'abc1234',
  gitBranch: 'master',
  buildDate: '',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('logEvent writes a telemetry doc within the rules whitelist', () async {
    final firestore = FakeFirebaseFirestore();
    final service = TelemetryService(
      firestore: firestore,
      debugInfo: () async => _info,
    );

    await service.logEvent('app_open');

    final snap = await firestore.collection('telemetry').get();
    expect(snap.docs, hasLength(1));
    final data = snap.docs.single.data();

    expect(data.keys.every(_allowedKeys.contains), isTrue);
    expect(data['type'], 'app_open');
    expect(data['deviceId'], isNotEmpty);
    expect(data['platform'], 'linux');
    expect(data['appVersion'], contains('1.2.3'));
    expect(data['id'], snap.docs.single.id);
    expect(data.containsKey('detail'), isFalse);
    final createdAt = data['createdAt'] as String;
    expect(DateTime.tryParse(createdAt), isNotNull);
  });

  test('logEvent is a no-op when telemetry is disabled', () async {
    final firestore = FakeFirebaseFirestore();
    final service = TelemetryService(
      firestore: firestore,
      debugInfo: () async => _info,
    );

    await service.setEnabled(false);
    await service.logEvent('app_open');

    expect((await firestore.collection('telemetry').get()).docs, isEmpty);
  });

  test('the device id is stable across events and persists', () async {
    final firestore = FakeFirebaseFirestore();
    TelemetryService make() =>
        TelemetryService(firestore: firestore, debugInfo: () async => _info);

    await make().logEvent('app_open');
    await make().logEvent('tab_open', detail: 'Strategy');

    final docs = (await firestore.collection('telemetry').get()).docs;
    expect(docs, hasLength(2));
    final ids = docs.map((d) => d.data()['deviceId']).toSet();

    expect(ids, hasLength(1));
  });

  test('concurrent first events share one device id', () async {
    final firestore = FakeFirebaseFirestore();
    final service = TelemetryService(
      firestore: firestore,
      debugInfo: () async => _info,
    );

    await Future.wait(<Future<void>>[
      service.logEvent('app_open'),
      service.logEvent('tab_open', detail: 'Strategy'),
    ]);

    final docs = (await firestore.collection('telemetry').get()).docs;
    expect(docs, hasLength(2));
    expect(docs.map((d) => d.data()['deviceId']).toSet(), hasLength(1));
  });

  test('setEnabled persists and gates a later instance', () async {
    await TelemetryService().setEnabled(false);
    expect(await TelemetryService().isEnabled(), isFalse);
  });

  test('an injected REST writer gets the same doc and detail', () async {
    String? path;
    Map<String, dynamic>? written;
    final service = TelemetryService(
      debugInfo: () async => _info,
      write: (docPath, data) async {
        path = docPath;
        written = data;
      },
    );

    await service.logEvent('tab_open', detail: 'Prematch');

    expect(path, 'telemetry/${written!['id']}');
    expect(written!['type'], 'tab_open');
    expect(written!['detail'], 'Prematch');
  });
}
