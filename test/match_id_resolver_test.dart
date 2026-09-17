import 'package:flutter_test/flutter_test.dart';
import 'package:spectrumstrategy/src/services/match_id_resolver.dart';
import 'package:statbotics_client/statbotics_client.dart';

StatboticsMatch _match(String key, String level, int number) => StatboticsMatch(
  key: key,
  event: '2026flor',
  matchNumber: number,
  compLevel: level,
  redTeams: const <int>[3847, 1, 2],
  blueTeams: const <int>[3, 4, 5],
);

MatchIdResolver _resolver() => MatchIdResolver(<StatboticsMatch>[
  _match('2026flor_qm1', 'qm', 1),
  _match('2026flor_qm12', 'qm', 12),
  _match('2026flor_sf1m1', 'sf', 1),
  _match('2026flor_sf2m1', 'sf', 1),
  _match('2026flor_f1m2', 'f', 2),
]);

void main() {
  test('a bare number finds the only match with that number', () {
    expect(_resolver().resolve('12')?.key, '2026flor_qm12');
    expect(_resolver().resolve(' 12 ')?.key, '2026flor_qm12');
  });

  test('a bare number spans comp levels', () {
    final resolver = _resolver();
    expect(
      resolver.candidates('1').map((m) => m.key),
      containsAll(<String>['2026flor_qm1', '2026flor_sf1m1', '2026flor_sf2m1']),
    );

    expect(resolver.resolve('1'), isNull);

    expect(resolver.resolve('qm1')?.key, '2026flor_qm1');
  });

  test('the spellings a scouter actually types all land on one match', () {
    final resolver = _resolver();
    for (final typed in <String>[
      'Q12',
      'q12',
      'qm12',
      'QM12',
      'qm 12',
      'Qual 12',
      'Match 12',
      'match-12',
    ]) {
      expect(resolver.resolve(typed)?.key, '2026flor_qm12', reason: typed);
    }
  });

  test('a full TBA key resolves to itself', () {
    expect(_resolver().resolve('2026flor_qm12')?.key, '2026flor_qm12');
    expect(_resolver().resolve('2026FLOR_QM12')?.key, '2026flor_qm12');
  });

  test('text that names no match in the event resolves to nothing', () {
    final resolver = _resolver();
    expect(resolver.resolve('Team 3847'), isNull);
    expect(resolver.resolve('99'), isNull);
    expect(resolver.resolve(''), isNull);
    expect(resolver.resolve('   '), isNull);
    expect(resolver.resolve('practice'), isNull);
  });

  test('a misspelled level resolves to nothing, not to quals', () {
    expect(_resolver().resolve('zz12'), isNull);
  });

  test('a key from another event does not resolve by its number', () {
    expect(_resolver().resolve('2025flor_qm12'), isNull);
  });

  test('a playoff set is used to pick between matches sharing a number', () {
    final resolver = _resolver();
    expect(resolver.resolve('sf1m1')?.key, '2026flor_sf1m1');
    expect(resolver.resolve('sf2m1')?.key, '2026flor_sf2m1');

    expect(resolver.resolve('sf1'), isNull);
  });

  test('finals resolve by their own level', () {
    expect(_resolver().resolve('f1m2')?.key, '2026flor_f1m2');
    expect(_resolver().resolve('Finals 2')?.key, '2026flor_f1m2');
  });

  test('numberOf gives the schedule number, not the first digits', () {
    final resolver = _resolver();
    expect(resolver.numberOf('Q12'), 12);
    expect(resolver.numberOf('sf2m1'), 1);
    expect(resolver.numberOf('Team 3847'), isNull);
  });

  test('an empty schedule resolves nothing', () {
    expect(MatchIdResolver(const <StatboticsMatch>[]).resolve('12'), isNull);
  });
}
