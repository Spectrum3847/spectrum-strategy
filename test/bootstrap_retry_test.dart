import 'package:flutter_test/flutter_test.dart';

import 'package:spectrumstrategy/src/scouting/models/pit_scout_entry.dart';
import 'package:spectrumstrategy/src/scouting/models/scout_config.dart';
import 'package:spectrumstrategy/src/scouting/models/scout_entry.dart';
import 'package:spectrumstrategy/src/scouting/services/pit_scouting_storage.dart';
import 'package:spectrumstrategy/src/scouting/services/scout_config_service.dart';
import 'package:spectrumstrategy/src/scouting/state/pit_scout_config_controller.dart';
import 'package:spectrumstrategy/src/scouting/state/pit_scouting_controller.dart';
import 'package:spectrumstrategy/src/scouting/state/scout_config_controller.dart';
import 'package:spectrumstrategy/src/scouting/state/scouting_controller.dart';

import 'support/fake_pit_scouting_storage.dart';
import 'support/fake_scout_config_service.dart';
import 'support/fake_scouting_storage.dart';

class _FailOnceScoutingStorage extends FakeScoutingStorage {
  bool failNext = true;

  @override
  Future<List<ScoutEntry>> loadAll() async {
    if (failNext) {
      failNext = false;
      throw StateError('simulated storage failure');
    }
    return super.loadAll();
  }
}

class _FailOncePitScoutingStorage implements PitScoutingStorage {
  _FailOncePitScoutingStorage() : _inner = FakePitScoutingStorage();

  final FakePitScoutingStorage _inner;
  bool failNext = true;

  @override
  Future<List<PitScoutEntry>> loadAll() async {
    if (failNext) {
      failNext = false;
      throw StateError('simulated storage failure');
    }
    return _inner.loadAll();
  }

  @override
  Future<void> saveEntry(PitScoutEntry entry) => _inner.saveEntry(entry);

  @override
  Future<void> deleteEntry(String id) => _inner.deleteEntry(id);

  @override
  Future<Set<String>> loadSyncedIds() => _inner.loadSyncedIds();

  @override
  Future<void> saveSyncedIds(Set<String> ids) => _inner.saveSyncedIds(ids);
}

class _FailOnceConfigService extends ScoutConfigService {
  _FailOnceConfigService() : _inner = FakeScoutConfigService();

  final FakeScoutConfigService _inner;
  bool failNext = true;

  @override
  Future<ScoutConfig?> loadStored() async {
    if (failNext) {
      failNext = false;
      throw StateError('simulated config failure');
    }
    return _inner.loadStored();
  }

  @override
  Future<void> save(ScoutConfig config) => _inner.save(config);
}

Future<void> _expectRetryRecovers(Future<void> Function() bootstrap) async {
  await expectLater(bootstrap(), throwsA(isA<StateError>()));

  await bootstrap();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('ScoutingController recovers on the second bootstrap', () async {
    final controller = ScoutingController(storage: _FailOnceScoutingStorage());
    await _expectRetryRecovers(controller.bootstrap);
  });

  test('PitScoutingController recovers on the second bootstrap', () async {
    final controller = PitScoutingController(
      storage: _FailOncePitScoutingStorage(),
    );
    await _expectRetryRecovers(controller.bootstrap);
  });

  test('ScoutConfigController recovers on the second bootstrap', () async {
    final controller = ScoutConfigController(service: _FailOnceConfigService());
    await _expectRetryRecovers(controller.bootstrap);
    expect(controller.config.allFields, isNotEmpty);
  });

  test('PitScoutConfigController recovers on the second bootstrap', () async {
    final controller = PitScoutConfigController(
      service: _FailOnceConfigService(),
    );
    await _expectRetryRecovers(controller.bootstrap);
  });
}
