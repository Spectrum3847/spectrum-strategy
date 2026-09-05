import 'package:flutter/material.dart';

import '../models/usage_rollup.dart';
import '../services/usage_rollup_service.dart';
import '../theme/strategy_palette.dart';

class UsageTab extends StatefulWidget {
  const UsageTab({required this.service, super.key});

  final UsageRollupService service;

  @override
  State<UsageTab> createState() => _UsageTabState();
}

class _UsageTabState extends State<UsageTab> {
  UsageRollup? _rollup;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rollup = await widget.service.fetch();
      if (!mounted) return;
      setState(() {
        _rollup = rollup;
        _loading = false;
      });
    } on UsageRollupUnavailable catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not read usage data.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final error = _error;
    if (error != null) {
      return _Message(title: 'No usage data', detail: error, onRetry: _load);
    }
    final rollup = _rollup ?? UsageRollup.empty;
    if (rollup.isEmpty) {
      return _Message(
        title: 'Nothing recorded yet',
        detail:
            'The rollup ran but counted no events in the last '
            '${rollup.windowDays} days.',
        onRetry: _load,
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: _Report(rollup: rollup),
    );
  }
}

class _Report extends StatelessWidget {
  const _Report({required this.rollup});

  final UsageRollup rollup;

  @override
  Widget build(BuildContext context) {
    final muted = StrategyPalette.mutedTextOf(context);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        Row(
          children: [
            Expanded(
              child: _Stat(value: '${rollup.eventsCounted}', label: 'events'),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _Stat(
                value: '${rollup.deviceCount}',
                label: rollup.deviceCount == 1 ? 'device' : 'devices',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _Stat(value: '${rollup.windowDays}', label: 'days'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          _freshness(rollup.updatedAt),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: muted),
        ),
        const SizedBox(height: 24),
        _BarSection(
          title: 'Tabs opened',
          note: 'Which screens people actually go to.',
          counts: rollup.tabs,
        ),
        _BarSection(
          title: 'Platforms',
          note: 'A desktop-only feature reads as unused without this.',
          counts: rollup.platforms,
        ),
        _BarSection(
          title: 'App versions',
          note: 'Who is still on an old build.',
          counts: rollup.appVersions,
        ),
        _DailySection(days: rollup.daily),
      ],
    );
  }

  static String _freshness(DateTime? updatedAt) {
    if (updatedAt == null) return 'Last updated: unknown.';
    final date = updatedAt.toLocal();
    final stamp =
        '${date.year}-${_two(date.month)}-${_two(date.day)} '
        '${_two(date.hour)}:${_two(date.minute)}';
    return 'Rolled up $stamp. The job runs once a day.';
  }

  static String _two(int value) => value.toString().padLeft(2, '0');
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: StrategyPalette.surfaceOf(context),
        borderRadius: BorderRadius.circular(StrategyPalette.radiusSm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: StrategyPalette.mutedTextOf(context),
            ),
          ),
        ],
      ),
    );
  }
}

class _BarSection extends StatelessWidget {
  const _BarSection({
    required this.title,
    required this.note,
    required this.counts,
  });

  final String title;
  final String note;
  final List<UsageCount> counts;

  @override
  Widget build(BuildContext context) {
    if (counts.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final muted = StrategyPalette.mutedTextOf(context);

    final top = counts.first.count;

    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(note, style: theme.textTheme.bodySmall?.copyWith(color: muted)),
          const SizedBox(height: 10),
          for (var i = 0; i < counts.length; i++)
            _Bar(
              count: counts[i],
              fraction: top <= 0 ? 0 : counts[i].count / top,

              leading: i == 0,
            ),
        ],
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({
    required this.count,
    required this.fraction,
    required this.leading,
  });

  final UsageCount count;
  final double fraction;
  final bool leading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fill = leading
        ? StrategyPalette.primary
        : StrategyPalette.borderOf(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 96,
            child: Text(
              count.name,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) => Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  width: (constraints.maxWidth * fraction).clamp(
                    2.0,
                    constraints.maxWidth,
                  ),
                  height: 14,
                  decoration: BoxDecoration(
                    color: fill,
                    borderRadius: const BorderRadius.horizontal(
                      right: Radius.circular(StrategyPalette.radiusSm),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 44,
            child: Text(
              '${count.count}',
              textAlign: TextAlign.right,

              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _DailySection extends StatelessWidget {
  const _DailySection({required this.days});

  final List<UsageDay> days;

  @override
  Widget build(BuildContext context) {
    if (days.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final muted = StrategyPalette.mutedTextOf(context);
    final busiest = days.fold<int>(
      0,
      (max, day) => day.count > max ? day.count : max,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Events per day',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'Busiest day: $busiest. A competition week should stand out.',
          style: theme.textTheme.bodySmall?.copyWith(color: muted),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 72,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final day in days)
                Expanded(
                  child: Tooltip(
                    message: '${day.date}: ${day.count}',
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 1),
                      child: FractionallySizedBox(
                        heightFactor: busiest <= 0
                            ? 0.02
                            : (day.count / busiest).clamp(0.02, 1.0),
                        child: Container(
                          decoration: BoxDecoration(
                            color: StrategyPalette.borderOf(context),
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(StrategyPalette.radiusSm),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 4),

        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              days.first.date,
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
            Text(
              days.last.date,
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
          ],
        ),
      ],
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.title,
    required this.detail,
    required this.onRetry,
  });

  final String title;
  final String detail;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: StrategyPalette.mutedTextOf(context),
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}
