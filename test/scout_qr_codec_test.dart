import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:spectrumstrategy/src/scouting/models/scout_config.dart';
import 'package:spectrumstrategy/src/scouting/models/scout_entry.dart';
import 'package:spectrumstrategy/src/scouting/services/scout_qr_codec.dart';
import 'package:spectrumstrategy/src/theme/strategy_palette.dart';

ScoutConfig _loadQrScoutConfig() {
  final raw = jsonDecode(
    File('test/data/qrscout_2026_config.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  return ScoutConfig.fromJson(raw);
}

void main() {
  test('round-trips a fully populated ScoutEntry', () {
    final entry = ScoutEntry(
      id: 'entry-3847',
      matchId: 'match-q42',
      teamNumber: 3847,
      alliance: 'Blue',
      notes: 'consistent climber',
      authorUid: 'u-1',
      authorDisplayName: 'scouter one',
      byPhase: <StrategyPhase, ScoutPhaseData>{
        StrategyPhase.auton: const ScoutPhaseData(
          score: 6,
          counters: <String, int>{'mobility': 1},
        ),
        StrategyPhase.teleop: const ScoutPhaseData(
          score: 22,
          penalties: 1,
          notes: 'defense played by 254',
        ),
        StrategyPhase.endgame: const ScoutPhaseData(score: 10, notes: 'climb'),
      },
      updatedAt: DateTime.utc(2026, 5, 15, 12, 30, 45),
    );

    final payload = ScoutQrCodec.encode(entry);
    final decoded = ScoutQrCodec.decode(payload);

    expect(decoded.id, entry.id);
    expect(decoded.matchId, entry.matchId);
    expect(decoded.teamNumber, entry.teamNumber);
    expect(decoded.alliance, entry.alliance);
    expect(decoded.notes, entry.notes);
    expect(decoded.authorUid, entry.authorUid);
    expect(decoded.authorDisplayName, entry.authorDisplayName);
    expect(
      decoded.updatedAt.toIso8601String(),
      entry.updatedAt.toIso8601String(),
    );
    expect(decoded.phaseData(StrategyPhase.auton).score, 6);
    expect(decoded.phaseData(StrategyPhase.auton).counters['mobility'], 1);
    expect(decoded.phaseData(StrategyPhase.teleop).score, 22);
    expect(decoded.phaseData(StrategyPhase.teleop).penalties, 1);
    expect(
      decoded.phaseData(StrategyPhase.teleop).notes,
      'defense played by 254',
    );
    expect(decoded.phaseData(StrategyPhase.endgame).notes, 'climb');
  });

  test('payload size stays within a comfortable QR margin', () {
    final entry = ScoutEntry(
      matchId: 'match-q9999',
      teamNumber: 99999,
      alliance: 'Red',
      notes: 'a' * 256,
      authorUid: 'u-12345678901234567890',
      authorDisplayName: 'Scout with a fairly long display name',
      byPhase: <StrategyPhase, ScoutPhaseData>{
        for (final phase in StrategyPhase.values)
          phase: ScoutPhaseData(score: 99, penalties: 9, notes: 'b' * 128),
      },
    );
    final payload = ScoutQrCodec.encode(entry);

    expect(payload.length, lessThan(2048));
  });

  test('decode rejects non-JSON payloads with a clear FormatException', () {
    expect(
      () => ScoutQrCodec.decode('not json at all'),
      throwsA(isA<FormatException>()),
    );
  });

  test('decode rejects JSON that is not an object', () {
    expect(() => ScoutQrCodec.decode('[1,2,3]'), throwsFormatException);
    expect(() => ScoutQrCodec.decode('"a string"'), throwsFormatException);
  });

  test('decode rejects payloads missing the version field', () {
    expect(() => ScoutQrCodec.decode('{"entry": {}}'), throwsFormatException);
  });

  test('decode rejects payloads from a future codec version', () {
    expect(
      () => ScoutQrCodec.decode(
        '{"v": ${ScoutQrCodec.currentVersion + 1}, "entry": {}}',
      ),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('newer app version'),
        ),
      ),
    );
  });

  test('decode rejects payloads missing the entry field', () {
    expect(() => ScoutQrCodec.decode('{"v": 1}'), throwsFormatException);
  });

  group('QRScout-compatible round trip (the format devices exchange)', () {
    late ScoutConfig config;

    setUpAll(() {
      config = _loadQrScoutConfig();
    });

    test('round-trips scalar field values unchanged', () {
      final values = <String, dynamic>{
        'scouter': 'AdaL',
        'matchNumber': 42,
        'noShow': false,
        'scoringEff': 75.0,
        'co': 'ran defense the whole match',
      };
      final payload = ScoutQrCodec.encodeQrScout(values, config);
      final decoded = ScoutQrCodec.tryDecodeQrScout(payload, config);

      expect(decoded, isNotNull);
      expect(decoded!['scouter'], 'AdaL');
      expect(decoded['matchNumber'], 42);
      expect(decoded['noShow'], false);
      expect(decoded['scoringEff'], 75.0);
      expect(decoded['co'], 'ran defense the whole match');
    });

    test('round-trips a select field as its choice key, not its label', () {
      final values = <String, dynamic>{'startPos': 'DT', 'climbed': 'L2'};
      final payload = ScoutQrCodec.encodeQrScout(values, config);
      final decoded = ScoutQrCodec.tryDecodeQrScout(payload, config);

      expect(decoded, isNotNull);
      expect(decoded!['startPos'], 'DT');
      expect(decoded['climbed'], 'L2');
      expect(payload, isNot(contains('Depot Trench')));
      expect(payload, isNot(contains('Level 2')));
    });

    test('round-trips a checkbox-select as its comma-joined keys', () {
      final values = <String, dynamic>{'autoCollectLoc': '1,3'};
      final payload = ScoutQrCodec.encodeQrScout(values, config);
      final decoded = ScoutQrCodec.tryDecodeQrScout(payload, config);

      expect(decoded, isNotNull);
      expect(decoded!['autoCollectLoc'], '1,3');
    });

    test('tryDecodeQrScout rejects a payload from an unrelated config', () {
      final decoded = ScoutQrCodec.tryDecodeQrScout('just one column', config);
      expect(decoded, isNull);
    });
  });

  group('the real scan-screen fallback order', () {
    ScoutEntry? decodeLikeTheScanScreen(String raw, ScoutConfig config) {
      final values = ScoutQrCodec.tryDecodeQrScout(raw, config);
      if (values != null) {
        return ScoutEntry(matchId: '', teamNumber: 0, fieldValues: values);
      }
      return ScoutQrCodec.decode(raw);
    }

    test('a legacy JSON payload falls through to the JSON decoder', () {
      final config = _loadQrScoutConfig();
      final entry = ScoutEntry(
        matchId: 'match-q1',
        teamNumber: 3847,
        alliance: 'Red',
      );
      final jsonPayload = ScoutQrCodec.encode(entry);

      expect(ScoutQrCodec.tryDecodeQrScout(jsonPayload, config), isNull);

      final decoded = decodeLikeTheScanScreen(jsonPayload, config);
      expect(decoded, isNotNull);
      expect(decoded!.matchId, 'match-q1');
      expect(decoded.teamNumber, 3847);
    });

    test('a QRScout payload is not readable as legacy JSON on its own', () {
      final config = _loadQrScoutConfig();
      final payload = ScoutQrCodec.encodeQrScout(<String, dynamic>{
        'scouter': 'AdaL',
      }, config);

      expect(() => ScoutQrCodec.decode(payload), throwsFormatException);
    });
  });
}
