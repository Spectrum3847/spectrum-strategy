import 'package:flutter/material.dart';

import '../../theme/strategy_palette.dart';
import '../models/entry_delivery.dart';

enum _StepState { done, current, todo, failed }

typedef _Step = ({String title, String detail, _StepState state});

List<_Step> _stepsFor(EntryDelivery delivery, String? rejectionReason) {
  const saved = (
    title: 'Saved on this device',
    detail: 'Kept on this device even if the app closes.',
    state: _StepState.done,
  );
  const unconfirmed = 'Confirmed once the team database shows it back.';
  return switch (delivery) {
    EntryDelivery.savedOnly => [
      saved,
      (
        title: 'Sent',
        detail: 'Sign in with a team account to send entries.',
        state: _StepState.todo,
      ),
      (title: 'In the database', detail: unconfirmed, state: _StepState.todo),
    ],
    EntryDelivery.pending => [
      saved,
      (
        title: 'Sent',
        detail: 'Goes out by itself once this device is online.',
        state: _StepState.current,
      ),
      (title: 'In the database', detail: unconfirmed, state: _StepState.todo),
    ],
    EntryDelivery.sentByQr => [
      saved,
      (
        title: 'Sent by QR',
        detail:
            'Another device has to import the code. Nothing confirms that '
            'back here.',
        state: _StepState.done,
      ),
      (
        title: 'In the database',
        detail: 'Confirmed once this device syncs its own copy.',
        state: _StepState.todo,
      ),
    ],
    EntryDelivery.sent => [
      saved,
      (
        title: 'Sent',
        detail: 'The team database accepted it.',
        state: _StepState.done,
      ),
      (
        title: 'In the database',
        detail: 'Waiting for the database to show it back.',
        state: _StepState.current,
      ),
    ],
    EntryDelivery.confirmed => [
      saved,
      (
        title: 'Sent',
        detail: 'The team database accepted it.',
        state: _StepState.done,
      ),
      (
        title: 'In the database',
        detail: 'The database holds this version.',
        state: _StepState.done,
      ),
    ],
    EntryDelivery.rejected => [
      saved,
      (
        title: 'Not accepted',
        detail: rejectionReason == null || rejectionReason.isEmpty
            ? 'The team database refused it. It stays on this device.'
            : 'The team database refused it: $rejectionReason',
        state: _StepState.failed,
      ),
      (title: 'In the database', detail: unconfirmed, state: _StepState.todo),
    ],
  };
}

class DeliveryTracker extends StatelessWidget {
  const DeliveryTracker({
    required this.delivery,
    this.rejectionReason,
    super.key,
  });

  final EntryDelivery delivery;

  final String? rejectionReason;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final step in _stepsFor(delivery, rejectionReason))
          _StepRow(step: step),
      ],
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({required this.step});

  final _Step step;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final failed = step.state == _StepState.failed;
    final (IconData icon, String label) = switch (step.state) {
      _StepState.done => (Icons.check_circle_rounded, 'Done'),
      _StepState.current => (Icons.schedule_rounded, 'In progress'),
      _StepState.todo => (Icons.radio_button_unchecked_rounded, 'Not yet'),
      _StepState.failed => (Icons.error_outline_rounded, 'Failed'),
    };
    final iconColor = switch (step.state) {
      _StepState.failed => colorScheme.error,
      _StepState.todo => colorScheme.onSurfaceVariant,
      _ => colorScheme.onSurface,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: iconColor, semanticLabel: label),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  step.title,
                  style: textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: failed ? colorScheme.error : null,
                  ),
                ),
                Text(
                  step.detail,
                  style: textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class SavedEntryConfirmation extends StatelessWidget {
  const SavedEntryConfirmation({
    required this.title,
    required this.delivery,
    required this.onNextMatch,
    this.rejectionReason,
    super.key,
  });

  final String title;
  final EntryDelivery delivery;
  final String? rejectionReason;
  final VoidCallback onNextMatch;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            DeliveryTracker(
              delivery: delivery,
              rejectionReason: rejectionReason,
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton(
                onPressed: onNextMatch,
                child: const Text('Next match'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class DeliveryBanner extends StatelessWidget {
  const DeliveryBanner({
    required this.unconfirmed,
    required this.rejected,
    super.key,
  });

  final int unconfirmed;
  final int rejected;

  @override
  Widget build(BuildContext context) {
    if (unconfirmed == 0) return const SizedBox.shrink();
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        color: StrategyPalette.surfaceStrongOf(context),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                rejected > 0
                    ? Icons.error_outline_rounded
                    : Icons.cloud_upload_outlined,
                size: 16,
                color: rejected > 0
                    ? colorScheme.error
                    : colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      unconfirmed == 1
                          ? '1 entry is not in the database yet'
                          : '$unconfirmed entries are not in the database yet',
                      style: textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (rejected > 0)
                      Text(
                        '$rejected not accepted by the database',
                        style: textTheme.bodySmall?.copyWith(
                          color: colorScheme.error,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
