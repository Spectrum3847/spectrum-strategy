import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:spectrumstrategy/src/scouting/models/scout_config.dart';
import 'package:spectrumstrategy/src/scouting/services/firestore_scout_config_service.dart';
import 'package:spectrumstrategy/src/scouting/services/scout_config_service.dart';
import 'package:spectrumstrategy/src/scouting/state/scout_config_controller.dart';

import 'support/fake_scout_config_service.dart';

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

  group('ScoutConfigController.loadFromJsonString', () {
    late ScoutConfigController controller;

    setUp(() {
      controller = ScoutConfigController(service: FakeScoutConfigService());
    });

    tearDown(() => controller.dispose());

    test('accepts a select field with unique option values', () async {
      await controller.bootstrap();
      const json = '''
{
  "title": "Custom",
  "page_title": "",
  "delimiter": "\\t",
  "sections": [
    {
      "name": "Auto",
      "fields": [
        {
          "title": "Start",
          "type": "select",
          "required": false,
          "code": "start",
          "formResetBehavior": "reset",
          "choices": {"Left": "L", "Right": "R"}
        }
      ]
    }
  ]
}
''';
      await controller.loadFromJsonString(json);
      expect(controller.config.sections.first.fields.first.code, 'start');
    });

    test('rejects a select field whose options share a value', () async {
      await controller.bootstrap();
      const json = '''
{
  "title": "Bad",
  "page_title": "",
  "delimiter": "\\t",
  "sections": [
    {
      "name": "Auto",
      "fields": [
        {
          "title": "Start",
          "type": "select",
          "required": false,
          "code": "start",
          "formResetBehavior": "reset",
          "choices": {"Left": "same", "Right": "same"}
        }
      ]
    }
  ]
}
''';
      expect(
        () => controller.loadFromJsonString(json),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('seeding the remote config when it is absent', () {
    test('a null remote pushes the active config', () async {
      final sync = _RecordingSyncService();
      final controller = ScoutConfigController(
        service: FakeScoutConfigService(),
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
      final controller = ScoutConfigController(
        service: FakeScoutConfigService(),
        syncService: sync,
      );
      await controller.bootstrap();

      sync.emit(controller.config);
      await pumpEventQueue();

      expect(sync.pushed, isEmpty);

      controller.dispose();
    });

    test('a repeated null seeds only once', () async {
      final sync = _RecordingSyncService();
      final controller = ScoutConfigController(
        service: FakeScoutConfigService(),
        syncService: sync,
      );
      await controller.bootstrap();

      sync.emit(null);
      await pumpEventQueue();
      sync.emit(null);
      sync.emit(null);
      await pumpEventQueue();

      expect(sync.pushed, hasLength(1));

      controller.dispose();
    });

    test('a refused push does not throw or retry', () async {
      final sync = _RecordingSyncService()..refusePush = true;
      final controller = ScoutConfigController(
        service: FakeScoutConfigService(),
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
    test('a higher bundled revision supersedes a lower stored one', () async {
      final bundled = await ScoutConfigService().loadDefault();
      final staleStored = bundled.copyWith(
        title: 'Stale',
        revision: bundled.revision - 1,
      );
      final service = FakeScoutConfigService(stored: staleStored);
      final sync = _RecordingSyncService();
      final controller = ScoutConfigController(
        service: service,
        syncService: sync,
      );

      await controller.bootstrap();

      expect(controller.config.revision, bundled.revision);
      expect(controller.config.title, bundled.title);

      expect(service.stored?.revision, bundled.revision);
      expect(sync.pushed, hasLength(1));
      expect(sync.pushed.single.revision, bundled.revision);

      controller.dispose();
    });

    test(
      'a lead\'s edit outranks the bundled default and is preserved',
      () async {
        final bundled = await ScoutConfigService().loadDefault();
        final editedStored = bundled.copyWith(
          title: 'Lead edit',
          revision: bundled.revision + 5,
        );
        final service = FakeScoutConfigService(stored: editedStored);
        final controller = ScoutConfigController(service: service);

        await controller.bootstrap();

        expect(controller.config.title, 'Lead edit');
        expect(controller.config.revision, bundled.revision + 5);

        controller.dispose();
      },
    );

    test(
      'a tie keeps the stored copy rather than flipping to bundled',
      () async {
        final bundled = await ScoutConfigService().loadDefault();
        final tiedStored = bundled.copyWith(
          title: 'Tied but stored',
          revision: bundled.revision,
        );
        final service = FakeScoutConfigService(stored: tiedStored);
        final controller = ScoutConfigController(service: service);

        await controller.bootstrap();

        expect(controller.config.title, 'Tied but stored');

        controller.dispose();
      },
    );

    test('updateConfig stamps a revision above the bundled default', () async {
      final bundled = await ScoutConfigService().loadDefault();
      final controller = ScoutConfigController(
        service: FakeScoutConfigService(),
      );
      await controller.bootstrap();

      expect(controller.config.revision, bundled.revision);

      await controller.updateConfig(
        controller.config.copyWith(title: 'Edited'),
      );

      expect(controller.config.revision, greaterThan(bundled.revision));
    });

    test('remote outranks local: the remote copy replaces it', () async {
      final sync = _RecordingSyncService();
      final controller = ScoutConfigController(
        service: FakeScoutConfigService(),
        syncService: sync,
      );
      await controller.bootstrap();

      final higher = controller.config.copyWith(
        title: 'From remote',
        revision: controller.config.revision + 1,
      );
      sync.emit(higher);
      await pumpEventQueue();

      expect(controller.config.title, 'From remote');
      expect(controller.config.revision, higher.revision);

      controller.dispose();
    });

    test('local outranks remote: local wins and is pushed back up', () async {
      final sync = _RecordingSyncService();
      final controller = ScoutConfigController(
        service: FakeScoutConfigService(),
        syncService: sync,
      );
      await controller.bootstrap();

      final lower = controller.config.copyWith(
        title: 'Stale remote',
        revision: controller.config.revision - 1,
      );
      sync.emit(lower);
      await pumpEventQueue();

      expect(controller.config.title, isNot('Stale remote'));
      expect(sync.pushed, isNotEmpty);
      expect(sync.pushed.last.revision, controller.config.revision);

      controller.dispose();
    });

    test('a higher-revision but invalid remote config is ignored', () async {
      final sync = _RecordingSyncService();
      final controller = ScoutConfigController(
        service: FakeScoutConfigService(),
        syncService: sync,
      );
      await controller.bootstrap();
      final before = controller.config;

      final broken = ScoutConfig(
        title: 'Broken remote',
        revision: before.revision + 1,
        sections: const [
          ScoutConfigSection(
            name: 'Auto',
            fields: [
              ScoutConfigField(
                title: 'Start',
                type: ScoutFieldType.select,
                code: 'start',
                choices: {'Left': 'same', 'Right': 'same'},
              ),
            ],
          ),
        ],
      );
      sync.emit(broken);
      await pumpEventQueue();

      expect(controller.config.title, before.title);
      expect(controller.config.revision, before.revision);

      controller.dispose();
    });
  });
}
