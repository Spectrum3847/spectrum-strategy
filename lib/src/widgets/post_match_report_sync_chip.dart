import 'package:flutter/material.dart';

import '../services/post_match_report_sync_service.dart';
import 'sync_status_pill.dart';

class PostMatchReportSyncChip extends StatelessWidget {
  const PostMatchReportSyncChip({required this.status, super.key});

  final PostMatchReportSyncStatus status;

  @override
  Widget build(BuildContext context) {
    final (String label, IconData icon) = switch (status.state) {
      PostMatchReportSyncState.signedOut => (
        'Not signed in to sync',
        Icons.cloud_off_rounded,
      ),
      PostMatchReportSyncState.noAccess => (
        'No team access yet',
        Icons.lock_outline_rounded,
      ),
      PostMatchReportSyncState.syncing => ('Syncing...', Icons.sync_rounded),
      PostMatchReportSyncState.synced => ('Synced', Icons.cloud_done_rounded),
      PostMatchReportSyncState.offline => ('Offline', Icons.cloud_off_rounded),
    };
    return Align(
      alignment: Alignment.centerLeft,
      child: SyncStatusPill(label: label, icon: icon),
    );
  }
}
