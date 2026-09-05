import 'package:flutter/material.dart';
import 'package:tba_client/tba_client.dart';

import '../models/post_match_report.dart';
import '../services/assistant/assistant_service.dart';
import '../state/cycle_log_controller.dart';
import '../state/post_match_report_controller.dart';
import '../state/user_role_controller.dart';
import '../theme/strategy_palette.dart';
import '../widgets/empty_state.dart';
import 'post_match_report_screen.dart';

class PostMatchReportsTableScreen extends StatelessWidget {
  const PostMatchReportsTableScreen({
    required this.controller,
    required this.eventKey,
    this.userRoleController,
    this.cycleLogController,
    this.tbaClient,
    this.myTeamNumber,
    this.assistant,
    super.key,
  });

  final PostMatchReportController controller;
  final String eventKey;
  final UserRoleController? userRoleController;
  final CycleLogController? cycleLogController;
  final TbaClient? tbaClient;
  final int? myTeamNumber;
  final AssistantService? assistant;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final reports = controller.reportsForEvent(eventKey).toList()
          ..sort((a, b) => _compareMatchId(a.matchId, b.matchId));

        if (reports.isEmpty) {
          return const EmptyState(
            icon: Icons.rate_review_outlined,
            message: 'No post match reports for this event yet.',
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: _PurposeLine(),
            ),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columnSpacing: 20,

                  showCheckboxColumn: false,
                  columns: const <DataColumn>[
                    DataColumn(label: Text('Match')),
                    DataColumn(label: Text('Auto')),
                    DataColumn(label: Text('Teleop')),
                    DataColumn(label: Text('Endgame')),
                    DataColumn(label: Text('Notes')),
                  ],
                  rows: <DataRow>[
                    for (final report in reports)
                      DataRow(
                        onSelectChanged: (_) => _open(context, report),
                        cells: <DataCell>[
                          DataCell(
                            Text(
                              report.matchId,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          DataCell(_SectionPreview(report.auto)),
                          DataCell(_SectionPreview(report.teleop)),
                          DataCell(_SectionPreview(report.endgame)),
                          DataCell(_SectionPreview(report.notes)),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _open(BuildContext context, PostMatchReport report) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => PostMatchReportScreen(
          controller: controller,
          matchLabel: 'Match ${report.matchId}',
          eventKey: eventKey,
          matchId: report.matchId,
          userRoleController: userRoleController,
          cycleLogController: cycleLogController,
          tbaClient: tbaClient,
          myTeamNumber: myTeamNumber,
          assistant: assistant,
        ),
      ),
    );
  }
}

class _PurposeLine extends StatelessWidget {
  const _PurposeLine();

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall;
    return Text(
      'Every strategy lead\'s post match survey for this event. Tap a row '
      'to read or edit one match in full.',
      style: style?.copyWith(color: StrategyPalette.mutedTextOf(context)),
    );
  }
}

class _SectionPreview extends StatelessWidget {
  const _SectionPreview(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 200,
      child: Text(
        text.trim().isEmpty ? '--' : text.trim(),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: text.trim().isEmpty
            ? Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: StrategyPalette.mutedTextOf(context))
            : Theme.of(context).textTheme.bodyMedium,
      ),
    );
  }
}

int _compareMatchId(String a, String b) {
  final ra = _matchRank(a);
  final rb = _matchRank(b);
  if (ra.level != rb.level) return ra.level.compareTo(rb.level);
  return ra.number.compareTo(rb.number);
}

({int level, int number}) _matchRank(String matchId) {
  final match = RegExp(r'^([a-zA-Z]+)(\d+)').firstMatch(matchId);
  if (match == null) return (level: 99, number: 0);
  final prefix = match.group(1)!.toLowerCase();
  final number = int.tryParse(match.group(2)!) ?? 0;
  final level = switch (prefix) {
    'qm' => 0,
    'qf' => 1,
    'sf' => 2,
    'f' => 3,
    _ => 4,
  };
  return (level: level, number: number);
}
