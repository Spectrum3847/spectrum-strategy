import 'package:flutter_test/flutter_test.dart';
import 'package:spectrumstrategy/src/models/post_match_report.dart';

void main() {
  final now = DateTime.utc(2026, 8, 16, 12);

  PostMatchReport report({
    String auto = '',
    String teleop = '',
    String endgame = '',
    String notes = '',
  }) => PostMatchReport(
    id: PostMatchReport.idFor('2026miket', 'qm14'),
    eventKey: '2026miket',
    matchId: 'qm14',
    auto: auto,
    teleop: teleop,
    endgame: endgame,
    notes: notes,
    authorUid: 'uid-1',
    authorDisplayName: 'Lead',
    updatedAt: now,
  );

  group('identity', () {
    test('the id is derived from the event and match, not random', () {
      expect(PostMatchReport.idFor('2026miket', 'qm14'), '2026miket_qm14');
      expect(
        PostMatchReport.idFor('2026miket', 'qm14'),
        PostMatchReport.idFor('2026miket', 'qm14'),
      );
    });

    test('different matches at one event do not collide', () {
      expect(
        PostMatchReport.idFor('2026miket', 'qm14'),
        isNot(PostMatchReport.idFor('2026miket', 'qm15')),
      );
    });
  });

  group('isEmpty', () {
    test('a fresh report is empty', () {
      expect(report().isEmpty, isTrue);
    });

    test('a section that is only whitespace still counts as empty', () {
      expect(report(auto: '   ').isEmpty, isTrue);
    });

    test('any section written makes it non-empty', () {
      expect(report(auto: 'scored two').isEmpty, isFalse);
      expect(report(teleop: 'cycled steadily').isEmpty, isFalse);
      expect(report(endgame: 'climbed').isEmpty, isFalse);
      expect(report(notes: 'broke down in auton').isEmpty, isFalse);
    });
  });

  group('copyWith', () {
    test('changes one section and leaves the rest alone', () {
      final before = report(auto: 'started fine');
      final after = before.copyWith(teleop: 'died mid-cycle');

      expect(after.auto, 'started fine');
      expect(after.teleop, 'died mid-cycle');
      expect(after.id, before.id);
    });

    test('does not mutate the report it was called on', () {
      final before = report();
      before.copyWith(auto: 'scored two');

      expect(before.auto, '');
    });
  });

  group('round trip', () {
    test('survives toJson then fromJson unchanged', () {
      final before = report(
        auto: 'Scored two, missed the third.',
        teleop: 'Died in teleop, drive motor cut out.',
        endgame: 'Did not climb.',
        notes: 'Got defended hard.',
      );
      final after = PostMatchReport.fromJson(before.toJson());

      expect(after.id, before.id);
      expect(after.eventKey, before.eventKey);
      expect(after.matchId, before.matchId);
      expect(after.auto, before.auto);
      expect(after.teleop, before.teleop);
      expect(after.endgame, before.endgame);
      expect(after.notes, before.notes);
      expect(after.authorUid, before.authorUid);
      expect(after.authorDisplayName, before.authorDisplayName);
      expect(after.updatedAt, before.updatedAt);
    });

    test('a document with no updatedAt reads as the epoch, not as now', () {
      final after = PostMatchReport.fromJson(const {
        'id': 'x',
        'eventKey': 'e',
        'matchId': 'm',
      });

      expect(after.updatedAt.millisecondsSinceEpoch, 0);
    });

    test('an id is rebuilt from the event and match when absent', () {
      final after = PostMatchReport.fromJson(const {
        'eventKey': '2026miket',
        'matchId': 'qm14',
      });

      expect(after.id, '2026miket_qm14');
    });

    test(
      'missing sections read as empty strings, not null crashing the parse',
      () {
        final after = PostMatchReport.fromJson(const {
          'eventKey': '2026miket',
          'matchId': 'qm14',
        });

        expect(after.auto, '');
        expect(after.teleop, '');
        expect(after.endgame, '');
        expect(after.notes, '');
      },
    );

    test('a non-string section value reads as empty rather than crashing', () {
      final after = PostMatchReport.fromJson(const {
        'eventKey': '2026miket',
        'matchId': 'qm14',
        'auto': 5,
      });

      expect(after.auto, '');
    });
  });
}
