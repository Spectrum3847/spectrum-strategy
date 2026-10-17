import '../theme/strategy_palette.dart';

String fieldCanvasLabel({
  required String surface,
  required StrategyPhase phase,
  required int strokeCount,
  int markerCount = 0,
  bool readOnly = false,
}) {
  final parts = <String>[
    surface,
    '${phase.label} phase',
    if (strokeCount == 0 && markerCount == 0)
      'empty'
    else ...[
      if (strokeCount > 0) _plural(strokeCount, 'drawing', 'drawings'),
      if (markerCount > 0) _plural(markerCount, 'robot', 'robots'),
    ],
    if (readOnly) 'read only',
  ];
  return parts.join(', ');
}

String _plural(int count, String one, String many) =>
    '$count ${count == 1 ? one : many}';
