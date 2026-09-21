import 'package:flutter/foundation.dart';

enum MatchForecastSource {
  tba('TBA'),

  match13('match13');

  const MatchForecastSource(this.label);

  final String label;
}

@immutable
class MatchForecast {
  const MatchForecast({
    required this.matchKey,
    required this.source,
    required this.redScore,
    required this.blueScore,
    required this.redWinProbability,
  });

  final String matchKey;

  final MatchForecastSource source;
  final double redScore;
  final double blueScore;

  final double redWinProbability;

  bool get redFavored => redWinProbability >= 0.5;

  double get favoredWinProbability =>
      redFavored ? redWinProbability : 1 - redWinProbability;

  static double normalizeProbability(num raw) {
    final value = raw.toDouble();
    if (value.isNaN) return 0.5;
    final fraction = value > 1 ? value / 100 : value;
    return fraction.clamp(0.0, 1.0);
  }
}
