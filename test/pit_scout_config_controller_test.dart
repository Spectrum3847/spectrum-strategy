import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:spectrumstrategy/src/scouting/models/scout_config.dart';
import 'package:spectrumstrategy/src/scouting/services/firestore_scout_config_service.dart';
import 'package:spectrumstrategy/src/scouting/services/scout_config_service.dart';
import 'package:spectrumstrategy/src/scouting/state/pit_scout_config_controller.dart';

class _FakePitScoutConfigService extends ScoutConfigService {
  _FakePitScoutConfigService() : super.pit();

  ScoutConfig? _saved;

  @override
  Future<ScoutConfig?> loadStored() async => _saved;

  @override
  Future<void> save(ScoutConfig config) async {
    _saved = config;
  }
}

class _RecordingSyncService implements ScoutConfigSyncService {
  final _controller = StreamController<ScoutConfig?>.broadcast();
  final List<ScoutConfig> pushed = <ScoutConfig>[];
  bool refusePush = false;

  void emit(ScoutConfig? config) => _controller.add(config);

  @override
  Stream<ScoutConfig?> get configStream => _controller.stream;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> push(ScoutConfig config) async {
    if (refusePush) throw StateError('no permission');
    pushed.add(config);
  }

  @override
  Future<void> dispose() async => _controller.close();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PitScoutConfigController', () {
    late _FakePitScoutConfigService service;
    late PitScoutConfigController controller;

    setUp(() {
      service = _FakePitScoutConfigService();
      controller = PitScoutConfigController(service: service);
    });

    tearDown(() => controller.dispose());

    test('bootstrap loads the default config from the asset', () async {
      await controller.bootstrap();
      expect(controller.config.sections, isNotEmpty);

      expect(controller.config.sections.length, greaterThanOrEqualTo(1));
    });

    test('bootstrap is idempotent (returns the same future)', () async {
      final f1 = controller.bootstrap();
      final f2 = controller.bootstrap();
      expect(identical(f1, f2), isTrue);
      await f1;
    });

    test('updateConfig persists the new config', () async {
      await controller.bootstrap();
      final updated = controller.config.copyWith(title: 'My Pit Form');
      await controller.updateConfig(updated);
      expect(controller.config.title, 'My Pit Form');
      expect(service._saved?.title, 'My Pit Form');
    });

    test('loadFromJsonString parses a valid JSON config', () async {
      await controller.bootstrap();
      const json = '''
{
  "title": "Custom Pit",
  "page_title": "",
  "delimiter": "\\t",
  "sections": [
    {
      "name": "Robot",
      "fields": [
        {
          "title": "Weight",
          "type": "number",
          "required": false,
          "code": "weight",
          "formResetBehavior": "reset",
          "defaultValue": 0
        }
      ]
    }
  ]
}
''';
      await controller.loadFromJsonString(json);
      expect(controller.config.title, 'Custom Pit');
      expect(controller.config.sections.first.name, 'Robot');
    });

    test(
      'loadFromJsonString throws FormatException for empty sections',
      () async {
        await controller.bootstrap();
        const json =
            '{"title":"Empty","page_title":"","delimiter":"\\t","sections":[]}';
        expect(
          () => controller.loadFromJsonString(json),
          throwsA(isA<FormatException>()),
        );
      },
    );

    test(
      'loadFromJsonString throws FormatException for non-object JSON',
      () async {
        await controller.bootstrap();
        expect(
          () => controller.loadFromJsonString('[]'),
          throwsA(isA<FormatException>()),
        );
      },
    );
  });

  test('the pit variant of loadDefault parses the bundled asset', () async {
    final config = await ScoutConfigService.pit().loadDefault();
    expect(config.sections, isNotEmpty);

    final sectionNames = config.sections.map((s) => s.name).toList();
    expect(sectionNames, contains('Drivetrain'));
  });

  group('seeding the remote pit config when it is absent', () {
    test('a null remote pushes the active config', () async {
      final sync = _RecordingSyncService();
      final controller = PitScoutConfigController(
        service: _FakePitScoutConfigService(),
        syncService: sync,
      );
      await controller.bootstrap();

      sync.emit(null);
      await pumpEventQueue();

      expect(sync.pushed, hasLength(1));
      expect(sync.pushed.single.title, controller.config.title);

      controller.dispose();
    });

    test('a real remote config is not overwritten', () async {
      final sync = _RecordingSyncService();
      final controller = PitScoutConfigController(
        service: _FakePitScoutConfigService(),
        syncService: sync,
      );
      await controller.bootstrap();

      sync.emit(controller.config);
      await pumpEventQueue();

      expect(sync.pushed, isEmpty);

      controller.dispose();
    });

    test('a refused push does not throw or retry', () async {
      final sync = _RecordingSyncService()..refusePush = true;
      final controller = PitScoutConfigController(
        service: _FakePitScoutConfigService(),
        syncService: sync,
      );
      await controller.bootstrap();

      sync.emit(null);
      await pumpEventQueue();
      sync.emit(null);
      await pumpEventQueue();

      expect(sync.pushed, isEmpty);
      expect(controller.config, isNotNull);

      controller.dispose();
    });
  });

  group('revision merge', () {
    test(
      'a lead\'s edit outranks the bundled default and is preserved',
      () async {
        final bundled = await ScoutConfigService.pit().loadDefault();
        final service = _FakePitScoutConfigService();
        final controller = PitScoutConfigController(service: service);
        await controller.bootstrap();

        await controller.updateConfig(
          controller.config.copyWith(title: 'Lead-edited pit form'),
        );

        expect(controller.config.title, 'Lead-edited pit form');
        expect(controller.config.revision, greaterThan(bundled.revision));

        controller.dispose();
      },
    );

    test('a higher bundled revision supersedes a lower stored one', () async {
      final bundled = await ScoutConfigService.pit().loadDefault();
      final service = _FakePitScoutConfigService()
        .._saved = bundled.copyWith(
          title: 'Stale pit form',
          revision: bundled.revision - 1,
        );
      final sync = _RecordingSyncService();
      final controller = PitScoutConfigController(
        service: service,
        syncService: sync,
      );

      await controller.bootstrap();

      expect(controller.config.title, bundled.title);
      expect(controller.config.revision, bundled.revision);
      expect(sync.pushed, hasLength(1));

      controller.dispose();
    });
  });
}
