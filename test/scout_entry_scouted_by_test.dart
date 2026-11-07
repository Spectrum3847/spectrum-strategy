import 'package:flutter_test/flutter_test.dart';
import 'package:spectrumstrategy/src/scouting/models/scout_entry.dart';

void main() {
  ScoutEntry entry({String name = '', String uid = ''}) => ScoutEntry(
    matchId: 'qm1',
    teamNumber: 3847,
    authorUid: 'uid-ipad',
    authorDisplayName: 'Station iPad',
    scoutedByName: name,
    scoutedByUid: uid,
  );

  test('omits the credit fields when no scout is named', () {
    final json = entry().toJson();

    expect(json.containsKey('scoutedByName'), isFalse);
    expect(json.containsKey('scoutedByUid'), isFalse);
  });

  test('round trips a named scout with an account', () {
    final copy = ScoutEntry.fromJson(entry(name: 'Robin', uid: 'u1').toJson());

    expect(copy.scoutedByName, 'Robin');
    expect(copy.scoutedByUid, 'u1');
    expect(copy.extraFields, isEmpty);
  });

  test('a typed name writes no uid', () {
    final json = entry(name: 'Robin').toJson();

    expect(json['scoutedByName'], 'Robin');
    expect(json.containsKey('scoutedByUid'), isFalse);
  });

  test('copyWith keeps and replaces the credit', () {
    final named = entry(name: 'Robin', uid: 'u1');

    expect(named.copyWith(notes: 'x').scoutedByName, 'Robin');
    final swapped = named.copyWith(scoutedByName: 'Kit', scoutedByUid: '');
    expect(swapped.scoutedByName, 'Kit');
    expect(swapped.scoutedByUid, '');
  });

  test('scouter getters fall back to the signed-in account', () {
    expect(entry().scouterName, 'Station iPad');
    expect(entry().scouterUid, 'uid-ipad');
    expect(entry(name: 'Robin', uid: 'u1').scouterName, 'Robin');
    expect(entry(name: 'Robin', uid: 'u1').scouterUid, 'u1');
    expect(entry(name: 'Robin').scouterUid, '');
  });

  test('the credit is not part of the content signature', () {
    expect(
      entry(name: 'Robin', uid: 'u1').contentSignature,
      entry().contentSignature,
    );
  });
}
