import 'package:flutter_test/flutter_test.dart';

import 'package:spectrumstrategy/src/services/assistant/tool_arguments.dart';

void main() {
  group('requireTeamNumber', () {
    test('accepts a positive integer', () {
      expect(requireTeamNumber({'team_number': 3847}, 'team_number'), 3847);
    });

    test('rejects zero', () {
      expect(
        () => requireTeamNumber({'team_number': 0}, 'team_number'),
        throwsA(isA<ToolArgumentError>()),
      );
    });

    test('rejects a negative number', () {
      expect(
        () => requireTeamNumber({'team_number': -1}, 'team_number'),
        throwsA(isA<ToolArgumentError>()),
      );
    });

    test('rejects a number over the team-number ceiling', () {
      expect(
        () => requireTeamNumber({
          'team_number': maxTeamNumber + 1,
        }, 'team_number'),
        throwsA(isA<ToolArgumentError>()),
      );
    });

    test('rejects a non-numeric value', () {
      expect(
        () => requireTeamNumber({'team_number': 'frc3847'}, 'team_number'),
        throwsA(isA<ToolArgumentError>()),
      );
    });

    test('rejects a missing value', () {
      expect(
        () => requireTeamNumber({}, 'team_number'),
        throwsA(isA<ToolArgumentError>()),
      );
    });
  });

  group('optionalTeamNumber', () {
    test('is null when absent', () {
      expect(optionalTeamNumber({}, 'team_number'), isNull);
    });

    test('validates when present', () {
      expect(
        () => optionalTeamNumber({'team_number': -5}, 'team_number'),
        throwsA(isA<ToolArgumentError>()),
      );
    });
  });

  group('requireEventKey', () {
    test('accepts a year-plus-code event key', () {
      expect(
        requireEventKey({'event_key': '2026txhou'}, 'event_key'),
        '2026txhou',
      );
    });

    test('lowercases and trims', () {
      expect(
        requireEventKey({'event_key': ' 2026TXHOU '}, 'event_key'),
        '2026txhou',
      );
    });

    test('rejects a bare host', () {
      expect(
        () =>
            requireEventKey({'event_key': 'thebluealliance.com'}, 'event_key'),
        throwsA(isA<ToolArgumentError>()),
      );
    });

    test('rejects a value with a path separator', () {
      expect(
        () => requireEventKey({'event_key': '2026txhou/matches'}, 'event_key'),
        throwsA(isA<ToolArgumentError>()),
      );
    });

    test('rejects too short a code', () {
      expect(
        () => requireEventKey({'event_key': '2026t'}, 'event_key'),
        throwsA(isA<ToolArgumentError>()),
      );
    });

    test('rejects a missing value', () {
      expect(
        () => requireEventKey({}, 'event_key'),
        throwsA(isA<ToolArgumentError>()),
      );
    });
  });

  group('optionalBoundedInt', () {
    test('is null when absent', () {
      expect(
        optionalBoundedInt({}, 'match_number_min', min: 1, max: 200),
        isNull,
      );
    });

    test('accepts a value inside the bound', () {
      expect(
        optionalBoundedInt(
          {'match_number_min': 12},
          'match_number_min',
          min: 1,
          max: 200,
        ),
        12,
      );
    });

    test('rejects a value below the bound', () {
      expect(
        () => optionalBoundedInt(
          {'match_number_min': 0},
          'match_number_min',
          min: 1,
          max: 200,
        ),
        throwsA(isA<ToolArgumentError>()),
      );
    });

    test('rejects a value above the bound', () {
      expect(
        () => optionalBoundedInt(
          {'match_number_max': 201},
          'match_number_max',
          min: 1,
          max: 200,
        ),
        throwsA(isA<ToolArgumentError>()),
      );
    });
  });

  group('optionalPlainString', () {
    test('is null when absent or empty', () {
      expect(optionalPlainString({}, 'name'), isNull);
      expect(optionalPlainString({'name': '   '}, 'name'), isNull);
    });

    test('trims a present value', () {
      expect(
        optionalPlainString({'name': '  Alliance A  '}, 'name'),
        'Alliance A',
      );
    });

    test('rejects a value over the length ceiling', () {
      expect(
        () => optionalPlainString({'name': 'x' * 300}, 'name', maxLength: 200),
        throwsA(isA<ToolArgumentError>()),
      );
    });
  });
}
