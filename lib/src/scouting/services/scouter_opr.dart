import 'package:tba_client/tba_client.dart';

import '../models/scout_entry.dart';
import 'entry_match.dart';

class OfficialAllianceFuel {
  const OfficialAllianceFuel({
    required this.matchKey,
    required this.compLevel,
    required this.matchNumber,
    required this.alliance,
    required this.teams,
    required this.fuel,
  });

  final String matchKey;
  final String compLevel;
  final int matchNumber;

  final String alliance;
  final List<int> teams;
  final int fuel;
}

enum ScouterBand { ok, checkIn, coach }

class ScouterScore {
  const ScouterScore({
    required this.name,
    required this.miss,
    required this.robots,
  });

  final String name;

  final double miss;

  final int robots;

  bool get hasEnoughData => robots >= ScouterOpr.minRobots;

  ScouterBand get band {
    final size = miss.abs();
    if (size <= ScouterOpr.okLimit) return ScouterBand.ok;
    if (size <= ScouterOpr.checkInLimit) return ScouterBand.checkIn;
    return ScouterBand.coach;
  }
}

class ScouterOprReport {
  const ScouterOprReport({
    required this.scouts,
    required this.equations,
    required this.skipped,
    required this.incomplete,
    required this.averageCapture,
  });

  const ScouterOprReport.empty()
    : scouts = const <ScouterScore>[],
      equations = 0,
      skipped = 0,
      incomplete = 0,
      averageCapture = null;

  final List<ScouterScore> scouts;

  final int equations;

  final int skipped;

  final int incomplete;

  final double? averageCapture;
}

class ScouterOpr {
  const ScouterOpr._();

  static const double lambda = 1;
  static const int minRobots = 6;
  static const double okLimit = 4;
  static const double checkInLimit = 12;

  static const _autoFuelCode = 'autoFuelScored';
  static const _teleopFuelCode = 'teleopFuelScored';
  static const _scouterCode = 'scouter';

  static List<OfficialAllianceFuel> officialFuel(
    Iterable<TbaScheduleMatch> matches,
  ) {
    final result = <OfficialAllianceFuel>[];
    for (final match in matches) {
      for (final side in <(String, List<int>)>[
        ('red', match.redTeams),
        ('blue', match.blueTeams),
      ]) {
        final hub = match.scoreBreakdown[side.$1]?['hubScore'];
        final total = hub is Map ? hub['totalCount'] : null;
        if (total is! num) continue;
        result.add(
          OfficialAllianceFuel(
            matchKey: match.key,
            compLevel: match.compLevel,
            matchNumber: match.matchNumber,
            alliance: side.$1,
            teams: side.$2,
            fuel: total.toInt(),
          ),
        );
      }
    }
    return result;
  }

  static String normalizeName(String raw) =>
      raw.trim().replaceAll(RegExp(r'\s+'), ' ');

  static String? scoutOf(ScoutEntry entry) {
    final typed = entry.fieldValues[_scouterCode];
    for (final candidate in <String>[
      if (typed is String || typed is num) typed.toString(),
      entry.authorDisplayName,
      entry.authorUid,
    ]) {
      final name = normalizeName(candidate);
      if (name.isNotEmpty) return name;
    }
    return null;
  }

  static ScouterOprReport build({
    required Iterable<ScoutEntry> entries,
    required Iterable<OfficialAllianceFuel> official,
    required String eventKey,
  }) {
    final byMatch = <String, List<ScoutEntry>>{};
    for (final entry in entriesForEvent(entries, eventKey)) {
      final key = entry.tbaMatchKey?.trim().toLowerCase() ?? '';
      if (key.isEmpty || entry.addedManually) continue;
      (byMatch[key] ??= <ScoutEntry>[]).add(entry);
    }

    final equations = <_Equation>[];
    var skipped = 0;
    var incomplete = 0;
    for (final alliance in official) {
      final inMatch = byMatch[alliance.matchKey.toLowerCase()] ?? const [];
      final picked = <ScoutEntry>[];
      var duplicate = false;
      var missing = alliance.teams.length != 3;
      for (final team in alliance.teams) {
        final forTeam = inMatch.where((e) => e.teamNumber == team).toList();
        if (forTeam.length > 1) duplicate = true;
        if (forTeam.isEmpty) missing = true;
        if (forTeam.length == 1) picked.add(forTeam.single);
      }
      if (missing) {
        incomplete++;
        continue;
      }
      if (duplicate) {
        skipped++;
        continue;
      }
      final equation = _Equation.tryBuild(alliance, picked);
      if (equation == null) {
        skipped++;
        continue;
      }
      equations.add(equation);
    }
    if (equations.isEmpty) {
      return ScouterOprReport(
        scouts: const <ScouterScore>[],
        equations: 0,
        skipped: skipped,
        incomplete: incomplete,
        averageCapture: null,
      );
    }
    return _report(equations, skipped: skipped, incomplete: incomplete);
  }

  static ScouterOprReport _report(
    List<_Equation> equations, {
    required int skipped,
    required int incomplete,
  }) {
    final indexByKey = <String, int>{};
    final spellings = <Map<String, int>>[];
    final rows = <List<int>>[];
    for (final equation in equations) {
      final row = <int>[];
      for (final name in equation.scouts) {
        final index = indexByKey.putIfAbsent(name.toLowerCase(), () {
          spellings.add(<String, int>{});
          return spellings.length - 1;
        });
        spellings[index][name] = (spellings[index][name] ?? 0) + 1;
        row.add(index);
      }
      rows.add(row);
    }

    final misses = solveRidge(rows, <double>[
      for (final e in equations) e.error,
    ], spellings.length);
    final robots = List<int>.filled(spellings.length, 0);
    for (final row in rows) {
      for (final index in row) {
        robots[index]++;
      }
    }

    final scores = <ScouterScore>[
      for (var i = 0; i < spellings.length; i++)
        ScouterScore(
          name: _commonest(spellings[i]),
          miss: misses[i],
          robots: robots[i],
        ),
    ];
    scores.sort((a, b) {
      if (a.hasEnoughData != b.hasEnoughData) return a.hasEnoughData ? -1 : 1;
      final bySize = b.miss.abs().compareTo(a.miss.abs());
      return bySize != 0 ? bySize : a.name.compareTo(b.name);
    });

    final captures = <double>[
      for (final e in equations)
        if (e.official > 0) e.scouted / e.official,
    ];
    return ScouterOprReport(
      scouts: scores,
      equations: equations.length,
      skipped: skipped,
      incomplete: incomplete,
      averageCapture: captures.isEmpty
          ? null
          : captures.reduce((a, b) => a + b) / captures.length,
    );
  }

  static String _commonest(Map<String, int> spellings) {
    final names = spellings.keys.toList()
      ..sort((a, b) {
        final byCount = spellings[b]!.compareTo(spellings[a]!);
        return byCount != 0 ? byCount : a.compareTo(b);
      });
    return names.first;
  }

  static List<double> solveRidge(
    List<List<int>> rows,
    List<double> errors,
    int scoutCount, {
    double lambda = ScouterOpr.lambda,
  }) {
    final n = scoutCount;
    final matrix = List<List<double>>.generate(
      n,
      (_) => List<double>.filled(n + 1, 0),
    );
    for (var r = 0; r < rows.length; r++) {
      for (final i in rows[r]) {
        matrix[i][n] += errors[r];
        for (final j in rows[r]) {
          matrix[i][j] += 1;
        }
      }
    }
    for (var i = 0; i < n; i++) {
      matrix[i][i] += lambda;
    }

    for (var col = 0; col < n; col++) {
      var pivot = col;
      for (var r = col + 1; r < n; r++) {
        if (matrix[r][col].abs() > matrix[pivot][col].abs()) pivot = r;
      }
      if (matrix[pivot][col].abs() < 1e-12) continue;
      final swap = matrix[col];
      matrix[col] = matrix[pivot];
      matrix[pivot] = swap;
      for (var r = col + 1; r < n; r++) {
        final factor = matrix[r][col] / matrix[col][col];
        if (factor == 0) continue;
        for (var c = col; c <= n; c++) {
          matrix[r][c] -= factor * matrix[col][c];
        }
      }
    }
    final solution = List<double>.filled(n, 0);
    for (var i = n - 1; i >= 0; i--) {
      if (matrix[i][i].abs() < 1e-12) continue;
      var sum = matrix[i][n];
      for (var j = i + 1; j < n; j++) {
        sum -= matrix[i][j] * solution[j];
      }
      solution[i] = sum / matrix[i][i];
    }
    return solution;
  }
}

class _Equation {
  const _Equation(this.official, this.scouted, this.scouts);

  final int official;
  final double scouted;
  final List<String> scouts;

  double get error => official - scouted;

  static _Equation? tryBuild(
    OfficialAllianceFuel alliance,
    List<ScoutEntry> entries,
  ) {
    var scouted = 0.0;
    final scouts = <String>[];
    for (final entry in entries) {
      final scout = ScouterOpr.scoutOf(entry);
      final fuel = _fuelOf(entry);
      if (scout == null || fuel == null) return null;
      scouts.add(scout);
      scouted += fuel;
    }
    return _Equation(alliance.fuel, scouted, scouts);
  }

  static double? _fuelOf(ScoutEntry entry) {
    final raw = <Object?>[
      entry.fieldValues[ScouterOpr._autoFuelCode],
      entry.fieldValues[ScouterOpr._teleopFuelCode],
    ];
    if (raw.every((v) => v == null)) return null;
    var total = 0.0;
    for (final value in raw) {
      if (value == null) continue;
      final number = value is num ? value : num.tryParse('$value');
      if (number == null) return null;
      total += number;
    }
    return total;
  }
}
