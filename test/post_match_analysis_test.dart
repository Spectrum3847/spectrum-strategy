import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tba_client/tba_client.dart';

import 'package:spectrumstrategy/src/models/post_match_report.dart';
import 'package:spectrumstrategy/src/services/assistant/assistant_backend.dart';
import 'package:spectrumstrategy/src/services/assistant/assistant_cache.dart';
import 'package:spectrumstrategy/src/services/assistant/assistant_service.dart';
import 'package:spectrumstrategy/src/services/assistant/post_match_analysis.dart';
import 'package:spectrumstrategy/src/ui/post_match_analysis_card.dart';

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('the request', () {
    test('is not built when the report is empty', () {
      expect(
        PostMatchAnalysis.request(
          eventKey: '2026miket',
          matchId: 'qm14',
          report: _report(),
        ),
        isNull,
      );
    });

    test('is built once there is an account written down', () {
      final request = PostMatchAnalysis.request(
        eventKey: '2026miket',
        matchId: 'qm14',
        report: _report(notes: 'Broke down mid-teleop.'),
      );

      expect(request, isNotNull);
      expect(request!.cacheKey, 'post-match-analysis:2026miket_qm14');
      expect(request.prompt, contains('Broke down mid-teleop.'));
    });

    test('the same match at two events does not share a summary', () {
      expect(
        PostMatchAnalysis.cacheKeyFor(eventKey: '2026miket', matchId: 'qm14'),
        isNot(
          PostMatchAnalysis.cacheKeyFor(eventKey: '2026txhou', matchId: 'qm14'),
        ),
      );
    });

    test('carries every filled-in phase into the prompt', () {
      final request = PostMatchAnalysis.request(
        eventKey: '2026miket',
        matchId: 'qm14',
        report: _report(
          auto: 'Scored two, missed the third.',
          teleop: 'Cycled steadily.',
          endgame: 'Climbed with five seconds left.',
          notes: 'Broke down mid-teleop.',
        ),
      )!;

      expect(request.prompt, contains('Scored two, missed the third.'));
      expect(request.prompt, contains('Cycled steadily.'));
      expect(request.prompt, contains('Climbed with five seconds left.'));
      expect(request.prompt, contains('Broke down mid-teleop.'));
    });

    test('a blank phase is left out of the prompt', () {
      final request = PostMatchAnalysis.request(
        eventKey: '2026miket',
        matchId: 'qm14',
        report: _report(notes: 'Broke down mid-teleop.'),
      )!;

      expect(request.prompt, isNot(contains('Auto:')));
      expect(request.prompt, isNot(contains('Teleop:')));
      expect(request.prompt, isNot(contains('Endgame:')));
    });

    test('folds in the TBA result once it has posted', () {
      final request = PostMatchAnalysis.request(
        eventKey: '2026miket',
        matchId: 'qm14',
        report: _report(notes: 'Broke down mid-teleop.'),
        tbaMatch: const TbaScheduleMatch(
          key: '2026miket_qm14',
          compLevel: 'qm',
          matchNumber: 14,
          redTeams: <int>[3847, 111, 222],
          blueTeams: <int>[254, 333, 444],
          redScore: 120,
          blueScore: 98,
          winningAlliance: 'red',
        ),
        myTeamNumber: 3847,
      )!;

      expect(request.prompt, contains('Won 120 - 98'));
    });

    test('an unplayed TBA match is left out of the prompt', () {
      final request = PostMatchAnalysis.request(
        eventKey: '2026miket',
        matchId: 'qm14',
        report: _report(notes: 'Broke down mid-teleop.'),
        tbaMatch: const TbaScheduleMatch(
          key: '2026miket_qm14',
          compLevel: 'qm',
          matchNumber: 14,
          redTeams: <int>[3847, 111, 222],
          blueTeams: <int>[254, 333, 444],
        ),
      )!;

      expect(request.prompt, isNot(contains('Official result')));
    });
  });

  group('the card', () {
    testWidgets('renders nothing without an assistant', (tester) async {
      await _pump(
        tester,
        assistant: null,
        report: _report(notes: 'Broke down mid-teleop.'),
      );

      expect(find.byType(FilledButton), findsNothing);
      expect(find.text('AI summary'), findsNothing);
    });

    testWidgets('renders nothing when no backend is configured', (
      tester,
    ) async {
      await _pump(
        tester,
        assistant: _service(_FakeBackend(available: false)),
        report: _report(notes: 'Broke down mid-teleop.'),
      );

      expect(find.text('AI summary'), findsNothing);
    });

    testWidgets('renders nothing for an empty report', (tester) async {
      await _pump(
        tester,
        assistant: _service(_FakeBackend()),
        report: _report(),
      );

      expect(find.text('AI summary'), findsNothing);
    });

    testWidgets('offers the summary but does not generate it on render', (
      tester,
    ) async {
      final backend = _FakeBackend();
      await _pump(
        tester,
        assistant: _service(backend),
        report: _report(notes: 'Broke down mid-teleop.'),
      );

      expect(find.text('Summarise this report'), findsOneWidget);
      expect(backend.calls, 0);
    });

    testWidgets('generates on the button, then shows its provenance', (
      tester,
    ) async {
      final backend = _FakeBackend();
      await _pump(
        tester,
        assistant: _service(backend),
        report: _report(notes: 'Broke down mid-teleop.'),
      );

      await tester.tap(find.text('Summarise this report'));
      await tester.pumpAndSettle();

      expect(backend.calls, 1);
      expect(find.textContaining('matched the account'), findsOneWidget);
      expect(find.textContaining('fake-model'), findsOneWidget);
    });

    testWidgets('a cached summary shows without touching the backend', (
      tester,
    ) async {
      final backend = _FakeBackend();
      final service = _service(backend);
      await service.generate(
        PostMatchAnalysis.request(
          eventKey: '2026miket',
          matchId: 'qm14',
          report: _report(notes: 'Broke down mid-teleop.'),
        )!,
      );

      await _pump(
        tester,
        assistant: service,
        report: _report(notes: 'Broke down mid-teleop.'),
      );

      expect(find.textContaining('matched the account'), findsOneWidget);
      expect(find.text('Summarise this report'), findsNothing);
      expect(backend.calls, 1);
    });

    testWidgets('a failure is a message, not a broken screen', (tester) async {
      final service = _service(_FakeBackend(failWith: 'the router is down'));
      await _pump(
        tester,
        assistant: service,
        report: _report(notes: 'Broke down mid-teleop.'),
      );

      await tester.tap(find.text('Summarise this report'));
      await tester.pumpAndSettle();

      expect(find.textContaining('the router is down'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}

Future<void> _pump(
  WidgetTester tester, {
  required AssistantService? assistant,
  required PostMatchReport report,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: PostMatchAnalysisCard(
          assistant: assistant,
          eventKey: '2026miket',
          matchId: 'qm14',
          report: report,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

AssistantService _service(_FakeBackend backend) => AssistantService(
  backends: [backend],
  cache: AssistantCache(),
  minimumGap: Duration.zero,
);

PostMatchReport _report({
  String auto = '',
  String teleop = '',
  String endgame = '',
  String notes = '',
}) => PostMatchReport(
  id: PostMatchReport.idFor('2026miket', 'qm14'),
  eventKey: '2026miket',
  matchId: 'qm14',
  auto: auto,
  teleop: teleop,
  endgame: endgame,
  notes: notes,
  updatedAt: DateTime.utc(2026, 8, 18),
);

class _FakeBackend implements AssistantBackend {
  _FakeBackend({this.available = true, this.failWith});

  final bool available;
  final String? failWith;
  int calls = 0;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<AssistantSummary> complete(AssistantRequest request) async {
    calls++;
    final reason = failWith;
    if (reason != null) {
      throw AssistantUnavailable(reason);
    }
    return AssistantSummary(
      text: 'The account matched the account of what happened.',
      generatedAt: DateTime.now().toUtc(),
      model: 'fake-model',
      source: AssistantSource.openRouter,
    );
  }
}
