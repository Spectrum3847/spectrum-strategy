import 'package:flutter_test/flutter_test.dart';

import 'package:spectrumstrategy/src/models/match_brief.dart';
import 'package:spectrumstrategy/src/state/match_brief_controller.dart';

import 'support/fake_match_brief_storage.dart';
import 'support/fake_match_brief_sync_service.dart';

void main() {
  setUp(TestWidgetsFlutterBinding.ensureInitialized);

  test('a save lands in storage, then on the server', () async {
    final storage = FakeMatchBriefStorage();
    final sync = FakeMatchBriefSyncService();
    final controller = MatchBriefController(
      storage: storage,
      syncService: sync,
    );
    await controller.bootstrap();

    final saved = await controller.save(
      eventKey: '2026miket',
      matchId: 'qm14',
      robotPlans: <int, String>{3847: 'Defend'},
      keyPoints: 'Climb early',
    );

    expect(saved, isTrue);
    final brief = controller.briefFor('2026miket', 'qm14');
    expect(brief.id, '2026miket_qm14');
    expect(brief.planFor(3847), 'Defend');
    expect(brief.ready, isFalse);
    expect(brief.authorUid, 'lead-uid');
    expect(storage.saved.single.keyPoints, 'Climb early');
    expect(sync.pushes.single.id, '2026miket_qm14');
  });

  test('a later save keeps the parts it was not given', () async {
    final controller = MatchBriefController(storage: FakeMatchBriefStorage());
    await controller.bootstrap();

    await controller.save(
      eventKey: 'e',
      matchId: 'qm1',
      robotPlans: <int, String>{1: 'a'},
      keyPoints: 'points',
    );
    await controller.save(eventKey: 'e', matchId: 'qm1', ready: true);

    final brief = controller.briefFor('e', 'qm1');
    expect(brief.ready, isTrue);
    expect(brief.keyPoints, 'points');
    expect(brief.planFor(1), 'a');
  });

  test('a failed local write is rolled back and reported', () async {
    final storage = FakeMatchBriefStorage();
    final sync = FakeMatchBriefSyncService();
    final controller = MatchBriefController(
      storage: storage,
      syncService: sync,
    );
    await controller.bootstrap();
    storage.failNextSave = StateError('disk full');

    final saved = await controller.save(
      eventKey: 'e',
      matchId: 'qm1',
      keyPoints: 'lost',
    );

    expect(saved, isFalse);
    expect(controller.briefFor('e', 'qm1').isEmpty, isTrue);
    expect(controller.failedWrites.hasFailures, isTrue);
    expect(sync.pushes, isEmpty);
  });

  test('only a newer remote brief replaces the local one', () async {
    final sync = FakeMatchBriefSyncService();
    final controller = MatchBriefController(
      storage: FakeMatchBriefStorage(),
      syncService: sync,
    );
    await controller.bootstrap();
    await controller.save(eventKey: 'e', matchId: 'qm1', keyPoints: 'mine');
    final mine = controller.briefFor('e', 'qm1');

    sync.emitRemote(<MatchBrief>[
      mine.copyWith(
        keyPoints: 'old',
        updatedAt: mine.updatedAt.subtract(const Duration(minutes: 1)),
      ),
    ]);
    await Future<void>.delayed(Duration.zero);
    expect(controller.briefFor('e', 'qm1').keyPoints, 'mine');

    sync.emitRemote(<MatchBrief>[
      mine.copyWith(
        keyPoints: 'theirs',
        updatedAt: mine.updatedAt.add(const Duration(minutes: 1)),
      ),
    ]);
    await Future<void>.delayed(Duration.zero);
    expect(controller.briefFor('e', 'qm1').keyPoints, 'theirs');
  });

  test('an older remote copy does not confirm a pending local edit', () async {
    final storage = FakeMatchBriefStorage();
    final sync = FakeMatchBriefSyncService();
    final controller = MatchBriefController(
      storage: storage,
      syncService: sync,
    );
    await controller.bootstrap();
    await controller.save(eventKey: 'e', matchId: 'qm1', keyPoints: 'mine');
    final mine = controller.briefFor('e', 'qm1');
    await Future<void>.delayed(Duration.zero);
    expect(await storage.loadPendingIds(), contains(mine.id));

    sync.emitRemote(<MatchBrief>[
      mine.copyWith(
        keyPoints: 'old',
        updatedAt: mine.updatedAt.subtract(const Duration(minutes: 1)),
      ),
    ]);
    await Future<void>.delayed(Duration.zero);
    expect(await storage.loadPendingIds(), contains(mine.id));

    sync.emitRemote(<MatchBrief>[mine]);
    await Future<void>.delayed(Duration.zero);
    expect(await storage.loadPendingIds(), isNot(contains(mine.id)));
  });

  test('briefs persist across a relaunch', () async {
    final storage = FakeMatchBriefStorage();
    final first = MatchBriefController(storage: storage);
    await first.bootstrap();
    await first.save(eventKey: 'e', matchId: 'qm1', keyPoints: 'kept');

    final second = MatchBriefController(storage: storage);
    await second.bootstrap();

    expect(second.briefFor('e', 'qm1').keyPoints, 'kept');
  });

  test('the json round trip keeps plans keyed by team', () {
    final brief = MatchBrief(
      id: 'e_qm1',
      eventKey: 'e',
      matchId: 'qm1',
      robotPlans: const <int, String>{3847: 'Defend', 254: 'Score'},
      keyPoints: 'k',
      ready: true,
      updatedAt: DateTime.utc(2026, 3, 1),
    );

    final copy = MatchBrief.fromJson(brief.toJson());

    expect(copy.robotPlans, brief.robotPlans);
    expect(copy.ready, isTrue);
    expect(copy.updatedAt, brief.updatedAt);
  });

  test('role answers round trip beside the plans', () {
    final brief = MatchBrief(
      id: 'e_qm1',
      eventKey: 'e',
      matchId: 'qm1',
      robotPlans: const <int, String>{3847: 'Defend'},
      robotRoles: const <int, RobotRoles>{
        3847: RobotRoles(<RobotRole, String>{
          RobotRole.start: 'Left',
          RobotRole.auto: 'Two fuel',
        }),
      },
      updatedAt: DateTime.utc(2026, 3, 1),
    );

    final json = brief.toJson();
    final copy = MatchBrief.fromJson(json);

    expect(json['robotPlans'], <String, String>{'3847': 'Defend'});
    expect(json['robotRoles'], <String, dynamic>{
      '3847': <String, String>{'start': 'Left', 'auto': 'Two fuel'},
    });
    expect(copy.rolesFor(3847).of(RobotRole.start), 'Left');
    expect(copy.rolesFor(3847).of(RobotRole.auto), 'Two fuel');
    expect(copy.rolesFor(3847).of(RobotRole.endgame), '');
    expect(copy.rolesFor(254).isEmpty, isTrue);
  });

  test('a brief with no role answers writes no robotRoles key', () {
    final brief = MatchBrief(
      id: 'e_qm1',
      eventKey: 'e',
      matchId: 'qm1',
      robotRoles: const <int, RobotRoles>{3847: RobotRoles()},
      updatedAt: DateTime.utc(2026, 3, 1),
    );

    expect(brief.toJson().containsKey('robotRoles'), isFalse);
    expect(brief.isEmpty, isTrue);
  });

  test('an old brief without robotRoles loads with none', () {
    final copy = MatchBrief.fromJson(<String, dynamic>{
      'eventKey': 'e',
      'matchId': 'qm1',
      'robotPlans': <String, String>{'3847': 'Defend'},
    });

    expect(copy.robotRoles, isEmpty);
    expect(copy.planFor(3847), 'Defend');
  });
}
