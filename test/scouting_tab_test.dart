import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:spectrumstrategy/src/scouting/models/pit_scout_entry.dart';
import 'package:spectrumstrategy/src/scouting/models/scout_entry.dart';
import 'package:spectrumstrategy/src/scouting/services/scout_draft_store.dart';
import 'package:spectrumstrategy/src/scouting/services/scouting_sync_service.dart';
import 'package:spectrumstrategy/src/scouting/state/pit_scout_config_controller.dart';
import 'package:spectrumstrategy/src/scouting/state/pit_scouting_controller.dart';
import 'package:spectrumstrategy/src/scouting/state/scout_config_controller.dart';
import 'package:spectrumstrategy/src/scouting/state/scouting_controller.dart';
import 'package:statbotics_client/statbotics_client.dart';
import 'package:spectrumstrategy/src/state/event_controller.dart';
import 'package:spectrumstrategy/src/state/strategy_controller.dart';
import 'package:spectrumstrategy/src/ui/scouting_tab.dart';

import 'support/fake_match_directory.dart';
import 'support/fake_pit_scout_config_service.dart';
import 'support/fake_pit_scouting_storage.dart';
import 'support/fake_scout_config_service.dart';
import 'support/fake_scouting_storage.dart';
import 'support/fake_scouting_sync_service.dart';

const _testEventKey = '2026test';

Future<ScoutingController> _pumpTab(
  WidgetTester tester, {
  ScoutingSyncService? syncService,
  ScoutConfigController? configController,
  ScoutingController? scoutingController,
  bool loadSchedule = true,
  StatboticsClient? client,
  bool resetPrefs = true,
}) async {
  if (resetPrefs) SharedPreferences.setMockInitialValues(<String, Object>{});
  tester.view.physicalSize = const Size(1600, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final strategy = StrategyController(directory: FakeMatchDirectory());
  final scouting =
      scoutingController ??
      ScoutingController(
        storage: FakeScoutingStorage(),
        syncService: syncService,
      );
  final config =
      configController ??
      ScoutConfigController(service: FakeScoutConfigService());
  final event = EventController(
    client:
        client ??
        (loadSchedule
            ? _FakeStatboticsClient()
            : _FakeStatboticsClientNoMatches()),
  );

  await Future.wait(<Future<void>>[
    strategy.bootstrap(),
    scouting.bootstrap(),
    config.bootstrap(),
    event.setEventKey(_testEventKey),
  ]);

  await tester.pumpWidget(
    MaterialApp(
      home: ScoutingTab(
        strategyController: strategy,
        scoutingController: scouting,
        configController: config,
        eventController: event,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return scouting;
}

Future<ScoutingController> _pumpTabAndSaveEntry(
  WidgetTester tester, {
  bool loadSchedule = true,
  ScoutingSyncService? syncService,
}) async {
  final scouting = await _pumpTab(
    tester,
    loadSchedule: loadSchedule,
    syncService: syncService,
  );

  await tester.enterText(
    find.byKey(const ValueKey<String>('scout-field-matchNumber')),
    '1',
  );
  await tester.enterText(
    find.byKey(const ValueKey<String>('scout-field-pTnumber')),
    '3847',
  );
  await tester.pumpAndSettle();

  await tester.drag(find.byType(ListView), const Offset(0, -3200));
  await tester.pumpAndSettle();

  await _tapSave(tester);

  return scouting;
}

Future<void> _tapSave(WidgetTester tester) async {
  await tester.tap(find.text('Save entry'));
  await tester.pumpAndSettle();
  final anyway = find.text('Save anyway');
  if (anyway.evaluate().isNotEmpty) {
    await tester.tap(anyway);
    await tester.pumpAndSettle();
  }
}

Future<void> _jumpTo(WidgetTester tester, {required bool top}) async {
  final scrollable = find.descendant(
    of: find.byType(ListView),
    matching: find.byType(Scrollable),
  );

  for (var i = 0; i < 2; i++) {
    final position = tester.state<ScrollableState>(scrollable.first).position;
    position.jumpTo(top ? 0 : position.maxScrollExtent);
    await tester.pumpAndSettle();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> saveAgain(WidgetTester tester, String match) async {
    await _jumpTo(tester, top: true);
    await tester.enterText(
      find.byKey(const ValueKey<String>('scout-field-matchNumber')),
      match,
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('scout-field-pTnumber')),
      '3847',
    );
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -3200));
    await tester.pumpAndSettle();
    await _tapSave(tester);
  }

  testWidgets('the same team in a later match keeps both entries', (
    tester,
  ) async {
    final scouting = await _pumpTabAndSaveEntry(tester);
    final first = scouting.entries.single;

    await saveAgain(tester, '2');

    expect(scouting.entries, hasLength(2));
    expect(scouting.entryById(first.id)?.fieldValues['matchNumber'], '1');
  });

  testWidgets('saving the same match again edits its entry', (tester) async {
    final scouting = await _pumpTabAndSaveEntry(tester);
    final first = scouting.entries.single;

    await saveAgain(tester, '1');

    expect(scouting.entries.single.id, first.id);
  });

  testWidgets('save entry resolves tbaMatchKey for quarterfinal match', (
    tester,
  ) async {
    final scouting = await _pumpTabAndSaveEntry(tester);

    expect(scouting.entries, hasLength(1));
    expect(scouting.entries.single.teamNumber, 3847);
    expect(scouting.entries.single.tbaMatchKey, '${_testEventKey}_qf1m1');
  });

  testWidgets(
    'save entry still saves with no tbaMatchKey when the schedule has not '
    'loaded, carrying the typed match number as its identity',
    (tester) async {
      final scouting = await _pumpTabAndSaveEntry(tester, loadSchedule: false);

      expect(scouting.entries, hasLength(1));
      expect(scouting.entries.single.teamNumber, 3847);
      expect(scouting.entries.single.tbaMatchKey, isNull);
      expect(scouting.entries.single.fieldValues['matchNumber'], '1');
    },
  );

  testWidgets('save entry refuses only when no match number was typed at all', (
    tester,
  ) async {
    final scouting = await _pumpTab(tester, loadSchedule: false);

    await tester.enterText(
      find.byKey(const ValueKey<String>('scout-field-matchNumber')),
      '',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('scout-field-pTnumber')),
      '3847',
    );
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -3200));
    await tester.pumpAndSettle();
    await _tapSave(tester);

    expect(scouting.entries, isEmpty);
    expect(
      find.textContaining('Enter the match number before saving'),
      findsOneWidget,
    );
  });

  testWidgets(
    'an entry saved before the schedule loaded backfills its tbaMatchKey '
    'once the schedule arrives, with no action from the scouter',
    (tester) async {
      final scouting = await _pumpTabAndSaveEntry(tester, loadSchedule: false);
      expect(scouting.entries.single.tbaMatchKey, isNull);

      await scouting.backfillMatchKeys(<StatboticsMatch>[
        StatboticsMatch(
          key: '${_testEventKey}_qf1m1',
          event: _testEventKey,
          matchNumber: 1,
          compLevel: 'qf',
          redTeams: const <int>[3847, 2714, 245],
          blueTeams: const <int>[33, 67, 111],
        ),
      ]);

      expect(scouting.entries.single.tbaMatchKey, '${_testEventKey}_qf1m1');
    },
  );

  group('schedule-anchored match number', () {
    Future<ScoutingController> seededB2AtMatch1() async {
      final scouting = ScoutingController(storage: FakeScoutingStorage());
      await scouting.bootstrap();
      await scouting.saveEntry(
        ScoutEntry(
          matchId: 'seed',
          teamNumber: 67,
          tbaMatchKey: '${_testEventKey}_qm1',
          fieldValues: <String, dynamic>{'robot': 'B2', 'matchNumber': '1'},
        ),
      );
      return scouting;
    }

    Future<void> pickStation(WidgetTester tester, String label) async {
      await tester.tap(find.text('Red 1').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text(label).last);
      await tester.pumpAndSettle();
    }

    Future<String?> saveAndReadMatchNumber(
      WidgetTester tester,
      ScoutingController scouting,
      String station,
    ) async {
      await tester.drag(find.byType(ListView), const Offset(0, -3200));
      await tester.pumpAndSettle();
      await _tapSave(tester);
      return scouting.entries
          .where(
            (e) => e.matchId != 'seed' && e.fieldValues['robot'] == station,
          )
          .single
          .fieldValues['matchNumber']
          ?.toString();
    }

    testWidgets(
      'picking the real station after a relaunch re-anchors a match number '
      'the schedule chose',
      (tester) async {
        final scouting = await _pumpTab(
          tester,
          client: _FakeStatboticsClientQm(),
          scoutingController: await seededB2AtMatch1(),
        );
        await pickStation(tester, 'Blue 2');

        expect(await saveAndReadMatchNumber(tester, scouting, 'B2'), '3');
      },
    );

    testWidgets('a station change never replaces a match the scout picked', (
      tester,
    ) async {
      final scouting = await _pumpTab(
        tester,
        client: _FakeStatboticsClientQm(),
        scoutingController: await seededB2AtMatch1(),
      );
      await tester.tap(find.text('Match 1').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Match 4').last);
      await tester.pumpAndSettle();
      await pickStation(tester, 'Blue 2');

      expect(await saveAndReadMatchNumber(tester, scouting, 'B2'), '4');
    });

    testWidgets(
      'defaults the match number to the first scheduled match, needing no '
      'typing',
      (tester) async {
        final scouting = await _pumpTab(
          tester,
          client: _FakeStatboticsClientQm(),
        );

        await tester.enterText(
          find.byKey(const ValueKey<String>('scout-field-pTnumber')),
          '3847',
        );
        await tester.pumpAndSettle();
        await tester.drag(find.byType(ListView), const Offset(0, -3200));
        await tester.pumpAndSettle();
        await _tapSave(tester);

        expect(scouting.entries.single.fieldValues['matchNumber'], '1');
      },
    );

    testWidgets(
      'advances to the next scheduled match for the station after saving, '
      'skipping a number the schedule does not have',
      (tester) async {
        final scouting = await _pumpTab(
          tester,
          client: _FakeStatboticsClientQm(),
        );

        Future<void> saveOnce() async {
          await tester.drag(find.byType(ListView), const Offset(0, 5000));
          await tester.pumpAndSettle();
          await tester.enterText(
            find.byKey(const ValueKey<String>('scout-field-pTnumber')),
            '3847',
          );
          await tester.pumpAndSettle();
          await tester.drag(find.byType(ListView), const Offset(0, -3200));
          await tester.pumpAndSettle();
          await _tapSave(tester);
        }

        await saveOnce();
        expect(scouting.entries.single.fieldValues['matchNumber'], '1');

        await saveOnce();
        expect(
          scouting.entries.map((e) => e.fieldValues['matchNumber']),
          unorderedEquals(<String>['1', '3']),
        );
      },
    );

    testWidgets(
      'a scout can still record an out-of-band match number even with a '
      'schedule loaded',
      (tester) async {
        final scouting = await _pumpTab(
          tester,
          client: _FakeStatboticsClientQm(),
        );

        await tester.tap(find.text('Record an out-of-band match instead'));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const ValueKey<String>('scout-field-matchNumber')),
          '999',
        );
        await tester.enterText(
          find.byKey(const ValueKey<String>('scout-field-pTnumber')),
          '3847',
        );
        await tester.pumpAndSettle();
        await tester.drag(find.byType(ListView), const Offset(0, -3200));
        await tester.pumpAndSettle();
        await _tapSave(tester);

        expect(scouting.entries, hasLength(1));
        expect(scouting.entries.single.fieldValues['matchNumber'], '999');
      },
    );
  });

  group('empty required fields', () {
    Future<ScoutingController> pumpWithTeamOnly(WidgetTester tester) async {
      final scouting = await _pumpTab(tester);
      await tester.enterText(
        find.byKey(const ValueKey<String>('scout-field-pTnumber')),
        '3847',
      );
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView), const Offset(0, -3200));
      await tester.pumpAndSettle();
      return scouting;
    }

    testWidgets('Save lists them and Go back keeps the form unsaved', (
      tester,
    ) async {
      final scouting = await pumpWithTeamOnly(tester);

      await tester.tap(find.text('Save entry'));
      await tester.pumpAndSettle();

      expect(find.text('Required fields are empty'), findsOneWidget);
      expect(find.text('- Scouter Name'), findsOneWidget);
      expect(find.text('- Robot Starting Position'), findsOneWidget);
      expect(find.text('- Team Number'), findsNothing);

      await tester.tap(find.text('Go back'));
      await tester.pumpAndSettle();
      expect(scouting.entries, isEmpty);
    });

    testWidgets('Save anyway saves the entry', (tester) async {
      final scouting = await pumpWithTeamOnly(tester);

      await tester.tap(find.text('Save entry'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save anyway'));
      await tester.pumpAndSettle();

      expect(scouting.entries, hasLength(1));
    });
  });

  group('form draft', () {
    const scouterField = ValueKey<String>('scout-field-scouter');

    Future<void> remount(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      await _pumpTab(tester, resetPrefs: false);
    }

    testWidgets('a typed value is restored after the tab is rebuilt', (
      tester,
    ) async {
      await _pumpTab(tester);
      await tester.enterText(find.byKey(scouterField), 'Alex');
      await tester.pump(const Duration(seconds: 1));

      await remount(tester);

      final field = tester.widget<TextField>(find.byKey(scouterField));
      expect(field.controller!.text, 'Alex');
    });

    testWidgets('saving an entry clears the draft', (tester) async {
      await _pumpTab(tester);
      await tester.enterText(find.byKey(scouterField), 'Alex');
      await tester.enterText(
        find.byKey(const ValueKey<String>('scout-field-pTnumber')),
        '3847',
      );
      await tester.pump(const Duration(seconds: 1));
      await tester.drag(find.byType(ListView), const Offset(0, -3200));
      await tester.pumpAndSettle();
      await _tapSave(tester);
      await tester.pump(const Duration(seconds: 1));

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(ScoutDraftStore.storageKey), isNull);
    });

    testWidgets('a draft from a different form is not restored', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        ScoutDraftStore.storageKey:
            '{"formKey":"other-form","values":{"scouter":"Alex"}}',
      });
      await _pumpTab(tester, resetPrefs: false);

      final field = tester.widget<TextField>(find.byKey(scouterField));
      expect(field.controller!.text, isEmpty);
    });
  });

  testWidgets('the report drawing card follows the config switch', (
    tester,
  ) async {
    final config = ScoutConfigController(service: FakeScoutConfigService());
    await _pumpTab(tester, configController: config);
    await tester.drag(find.byType(ListView), const Offset(0, -3200));
    await tester.pumpAndSettle();
    expect(find.text('Report drawing'), findsOneWidget);

    await config.updateConfig(config.config.copyWith(reportDrawing: false));
    await tester.pumpAndSettle();
    expect(find.text('Report drawing'), findsNothing);
  });

  testWidgets('flipping the report drawing switch keeps typed values', (
    tester,
  ) async {
    final config = ScoutConfigController(service: FakeScoutConfigService());
    await _pumpTab(tester, configController: config);
    final matchField = find.byKey(
      const ValueKey<String>('scout-field-matchNumber'),
    );
    await tester.enterText(matchField, '17');
    await tester.pumpAndSettle();

    await config.updateConfig(config.config.copyWith(reportDrawing: false));
    await tester.pumpAndSettle();

    expect(find.text('17'), findsOneWidget);
  });

  testWidgets('deleting an entry asks for confirmation first', (tester) async {
    final scouting = await _pumpTabAndSaveEntry(tester);
    expect(scouting.entries, hasLength(1));

    Future<void> tapDelete() async {
      final icon = find.byIcon(Icons.delete_outline_rounded);

      await tester.scrollUntilVisible(
        icon,
        300,
        scrollable: find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      await tester.tap(icon);
      await tester.pumpAndSettle();
    }

    await tapDelete();
    expect(find.text('Delete entry?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(scouting.entries, hasLength(1));

    await tapDelete();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(scouting.entries, isEmpty);
  });

  group('delivery status', () {
    testWidgets('a saved entry with no sync stays on this device', (
      tester,
    ) async {
      await _pumpTabAndSaveEntry(tester);
      await _jumpTo(tester, top: false);

      expect(find.text('Team 3847 saved'), findsOneWidget);
      expect(find.text('Saved on this device'), findsOneWidget);
      expect(
        find.text('Sign in with a team account to send entries.'),
        findsOneWidget,
      );

      await _jumpTo(tester, top: true);
      expect(find.text('1 entry is not in the database yet'), findsOneWidget);
    });

    testWidgets('the banner clears once the database shows the entry back', (
      tester,
    ) async {
      final sync = FakeScoutingSyncService();
      final scouting = await _pumpTabAndSaveEntry(tester, syncService: sync);
      await _jumpTo(tester, top: false);
      expect(find.text('The team database accepted it.'), findsOneWidget);

      await _jumpTo(tester, top: true);
      expect(find.text('1 entry is not in the database yet'), findsOneWidget);

      sync.emitRemote(<ScoutEntry>[scouting.entries.single]);
      await tester.pumpAndSettle();
      expect(find.text('1 entry is not in the database yet'), findsNothing);

      await _jumpTo(tester, top: false);
      expect(find.text('The database holds this version.'), findsOneWidget);
    });

    testWidgets('a refused entry shows as rejected with the reason', (
      tester,
    ) async {
      final sync = FakeScoutingSyncService()..simulateRejection = true;
      await _pumpTabAndSaveEntry(tester, syncService: sync);
      await _jumpTo(tester, top: false);

      expect(
        find.text(
          'The team database refused it: permission-denied: push rejected',
        ),
        findsOneWidget,
      );

      await _jumpTo(tester, top: true);
      expect(find.text('1 entry is not in the database yet'), findsOneWidget);
      expect(find.text('1 not accepted by the database'), findsOneWidget);
    });

    testWidgets('Next match dismisses the confirmation', (tester) async {
      await _pumpTabAndSaveEntry(tester);
      await _jumpTo(tester, top: false);

      final nextMatch = find.text('Next match');
      await tester.ensureVisible(nextMatch);
      await tester.pumpAndSettle();
      await tester.tap(nextMatch);
      await tester.pumpAndSettle();

      expect(find.text('Team 3847 saved'), findsNothing);
      expect(find.text('1 entry is not in the database yet'), findsOneWidget);
    });
  });

  testWidgets('sync status pill names each connection state', (tester) async {
    await _pumpTab(
      tester,
      syncService: FakeScoutingSyncService(
        initialState: ScoutingSyncState.signedOut,
      ),
    );
    expect(find.text('Not signed in to sync'), findsOneWidget);

    await _pumpTab(
      tester,
      syncService: FakeScoutingSyncService(
        initialState: ScoutingSyncState.noAccess,
      ),
    );
    expect(find.text('No team access yet'), findsOneWidget);

    await _pumpTab(
      tester,
      syncService: FakeScoutingSyncService(
        initialState: ScoutingSyncState.offline,
      ),
    );
    expect(find.text('Offline'), findsOneWidget);

    await _pumpTab(
      tester,
      syncService: FakeScoutingSyncService(
        initialState: ScoutingSyncState.rejected,
      ),
    );
    expect(find.text('Not accepted'), findsOneWidget);
  });

  testWidgets('opens the pit report for the team entered in the match form', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    tester.view.physicalSize = const Size(1600, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final strategy = StrategyController(directory: FakeMatchDirectory());
    final scouting = ScoutingController(storage: FakeScoutingStorage());
    final config = ScoutConfigController(service: FakeScoutConfigService());
    final event = EventController(client: _FakeStatboticsClient());
    final pitScouting = PitScoutingController(
      storage: FakePitScoutingStorage(),
    );
    final pitConfig = PitScoutConfigController(
      service: FakePitScoutConfigService(),
    );

    await Future.wait(<Future<void>>[
      strategy.bootstrap(),
      scouting.bootstrap(),
      config.bootstrap(),
      event.setEventKey(_testEventKey),
      pitScouting.bootstrap(),
      pitConfig.bootstrap(),
    ]);
    await pitScouting.saveEntry(
      PitScoutEntry(
        teamNumber: 3847,
        fieldValues: const <String, dynamic>{'maxFuelCapacity': '12'},
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ScoutingTab(
          strategyController: strategy,
          scoutingController: scouting,
          configController: config,
          eventController: event,
          pitScoutingController: pitScouting,
          pitScoutConfigController: pitConfig,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Pit report -- Team 3847'), findsNothing);

    await tester.enterText(
      find.byKey(const ValueKey<String>('scout-field-pTnumber')),
      '3847',
    );
    await tester.pumpAndSettle();

    expect(find.text('Pit report -- Team 3847'), findsOneWidget);

    expect(find.text('Team 3847'), findsNothing);

    await tester.tap(find.text('Pit report -- Team 3847'));
    await tester.pumpAndSettle();

    expect(find.text('Team 3847'), findsOneWidget);
  });
}

class _FakeStatboticsClient extends StatboticsClient {
  @override
  Future<StatboticsEvent?> getEvent(String eventKey) async {
    return StatboticsEvent(key: eventKey, name: 'Test Event', year: 2026);
  }

  @override
  Future<List<StatboticsTeamEvent>> getEventTeams(String eventKey) async {
    return const <StatboticsTeamEvent>[];
  }

  @override
  Future<List<StatboticsMatch>> getEventMatches(String eventKey) async {
    return <StatboticsMatch>[
      StatboticsMatch(
        key: '${eventKey}_qf1m1',
        event: eventKey,
        matchNumber: 1,
        compLevel: 'qf',
        redTeams: const <int>[3847, 2714, 245],
        blueTeams: const <int>[33, 67, 111],
      ),
    ];
  }

  @override
  Future<List<StatboticsTeamBasic>> getEventTeamsBasic(String eventKey) async {
    return const <StatboticsTeamBasic>[];
  }
}

class _FakeStatboticsClientQm extends StatboticsClient {
  @override
  Future<StatboticsEvent?> getEvent(String eventKey) async {
    return StatboticsEvent(key: eventKey, name: 'Test Event', year: 2026);
  }

  @override
  Future<List<StatboticsTeamEvent>> getEventTeams(String eventKey) async {
    return const <StatboticsTeamEvent>[];
  }

  @override
  Future<List<StatboticsMatch>> getEventMatches(String eventKey) async {
    return <StatboticsMatch>[
      for (final number in <int>[1, 3, 4])
        StatboticsMatch(
          key: '${eventKey}_qm$number',
          event: eventKey,
          matchNumber: number,
          compLevel: 'qm',
          redTeams: const <int>[3847, 2714, 245],
          blueTeams: const <int>[33, 67, 111],
        ),
    ];
  }

  @override
  Future<List<StatboticsTeamBasic>> getEventTeamsBasic(String eventKey) async {
    return const <StatboticsTeamBasic>[];
  }
}

class _FakeStatboticsClientNoMatches extends StatboticsClient {
  @override
  Future<StatboticsEvent?> getEvent(String eventKey) async {
    return StatboticsEvent(key: eventKey, name: 'Test Event', year: 2026);
  }

  @override
  Future<List<StatboticsTeamEvent>> getEventTeams(String eventKey) async {
    return const <StatboticsTeamEvent>[];
  }

  @override
  Future<List<StatboticsMatch>> getEventMatches(String eventKey) async {
    return const <StatboticsMatch>[];
  }

  @override
  Future<List<StatboticsTeamBasic>> getEventTeamsBasic(String eventKey) async {
    return const <StatboticsTeamBasic>[];
  }
}
