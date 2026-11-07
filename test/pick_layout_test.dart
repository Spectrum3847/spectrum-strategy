import 'package:flutter_test/flutter_test.dart';

import 'package:spectrumstrategy/src/models/pick_layout.dart';
import 'package:spectrumstrategy/src/models/pick_list.dart';

PickList _list({
  List<int> teams = const <int>[],
  List<PickTier> tiers = const <PickTier>[],
  List<DoNotPick> dnp = const <DoNotPick>[],
}) => PickList(
  id: 'a',
  name: 'Quals',
  teamNumbers: teams,
  updatedAt: DateTime.utc(2026, 3, 1),
  tiers: tiers,
  dnp: dnp,
);

List<List<int>> _teams(PickLayout l) => [for (final t in l.tiers) t.teams];

void main() {
  group('PickList layout', () {
    test('a list with no tiers gets the default tiers, teams in the first', () {
      final layout = _list(teams: [254, 118]).layout;
      expect(layout.tiers.map((t) => t.name), kDefaultPickTierNames);
      expect(layout.tiers.first.teams, [254, 118]);
      expect(layout.dnp, isEmpty);
    });

    test(
      'a team another writer added to teamNumbers lands in the first tier',
      () {
        final list = _list(
          teams: [254, 118, 1678],
          tiers: [
            const PickTier(name: 'A', teams: [254]),
            const PickTier(name: 'B', teams: [118]),
          ],
        );
        final tiers = list.layout.tiers;
        expect(tiers[0].teams, [254, 1678]);
        expect(tiers[1].teams, [118]);
      },
    );

    test('a team removed from teamNumbers leaves its tier', () {
      final list = _list(
        teams: [254],
        tiers: [
          const PickTier(name: 'A', teams: [254, 118]),
        ],
      );
      expect(list.layout.tiers.single.teams, [254]);
    });

    test('tiers and dnp round trip through json and stay out of old lists', () {
      final list = _list(
        teams: [254],
        tiers: [
          const PickTier(name: 'A', teams: [254]),
        ],
        dnp: [const DoNotPick(team: 1, reason: 'Tips over')],
      );
      final back = PickList.fromJson(list.toJson());
      expect(back.tiers, list.tiers);
      expect(back.dnp, list.dnp);
      final plain = _list(teams: [254]).toJson();
      expect(plain.containsKey('tiers'), isFalse);
      expect(plain.containsKey('dnp'), isFalse);
    });

    test('junk tiers and dnp entries are dropped, not thrown on', () {
      final list = PickList.fromJson(<String, dynamic>{
        'id': 'a',
        'teamNumbers': <dynamic>[254],
        'updatedAt': '2026-03-01T00:00:00.000Z',
        'tiers': <dynamic>[
          'junk',
          <String, dynamic>{
            'name': 'A',
            'teams': <dynamic>[254, 'x'],
          },
        ],
        'dnp': <dynamic>[
          null,
          <String, dynamic>{'team': -3, 'reason': 'x'},
          <String, dynamic>{'team': 971, 'reason': 'Slow'},
        ],
      });
      expect(list.tiers.single.teams, [254]);
      expect(list.dnp.single.team, 971);
    });

    test('a dnp team that teamNumbers also holds is shown as listed', () {
      final list = _list(
        teams: [254],
        dnp: [const DoNotPick(team: 254, reason: 'x')],
      );
      expect(list.layout.dnp, isEmpty);
    });
  });

  group('PickLayout edits', () {
    PickLayout base() => PickLayout(
      tiers: const [
        PickTier(name: 'A', teams: [1, 2]),
        PickTier(name: 'B', teams: [3]),
        PickTier(name: 'C'),
      ],
      dnp: const [],
    );

    test('add moves a team instead of duplicating it', () {
      final next = base().add(1, tier: 1);
      expect(_teams(next), [
        [2],
        [3, 1],
        <int>[],
      ]);
    });

    test('marking do-not-pick takes the team off the tiers', () {
      final next = base().markDnp(2, 'Broke twice');
      expect(_teams(next), [
        [1],
        [3],
        <int>[],
      ]);
      expect(next.dnp.single.reason, 'Broke twice');
      expect(next.add(2).dnp, isEmpty);
    });

    test('move swaps inside a tier and crosses tiers at the edge', () {
      expect(_teams(base().move(2, -1)).first, [2, 1]);
      expect(_teams(base().move(2, 1)), [
        [1],
        [2, 3],
        <int>[],
      ]);
      expect(_teams(base().move(3, -1)), [
        [1, 2, 3],
        <int>[],
        <int>[],
      ]);
      expect(_teams(base().move(3, 1)), [
        [1, 2],
        <int>[],
        [3],
      ]);
    });

    test('move at the very top or bottom does nothing', () {
      expect(_teams(base().move(1, -1)).first, [1, 2]);
      final last = PickLayout(
        tiers: const [
          PickTier(name: 'A', teams: [1]),
        ],
        dnp: const [],
      );
      expect(_teams(last.move(1, 1)), [
        [1],
      ]);
    });

    test('reorder drops a team into the tier under its new position', () {
      final top = base().reorder(1, 3);
      expect(_teams(top), [
        [2],
        [1, 3],
        <int>[],
      ]);
      final after = base().reorder(1, 4);
      expect(_teams(after), [
        [2],
        [3, 1],
        <int>[],
      ]);
      final emptyTier = base().reorder(1, 5);
      expect(_teams(emptyTier), [
        [2],
        [3],
        [1],
      ]);
    });

    test('a heading is not draggable', () {
      expect(_teams(base().reorder(0, 2)), _teams(base()));
    });

    test('tiers can be renamed, added, and removed when empty', () {
      final renamed = base().renameTier(0, ' Top ');
      expect(renamed.tiers.first.name, 'Top');
      expect(base().renameTier(0, '  ').tiers.first.name, 'A');
      expect(base().addTier('D').tiers.last.name, 'D');
      expect(base().removeTier(2).tiers.length, 2);
      expect(base().removeTier(0).tiers.length, 3);
    });

    test('rank counts across tiers', () {
      final ranks = [
        for (final r in base().rows)
          if (r is TeamRow) r.rank,
      ];
      expect(ranks, [1, 2, 3]);
    });
  });
}
