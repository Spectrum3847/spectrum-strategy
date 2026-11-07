import 'package:flutter_test/flutter_test.dart';

import 'package:spectrumstrategy/src/scouting/models/scout_entry.dart';
import 'package:spectrumstrategy/src/scouting/services/scout_qr_codec.dart';

Map<String, dynamic> _stored() => <String, dynamic>{
  'id': 'e1',
  'matchId': 'qm1',
  'teamNumber': 3847,
  'alliance': 'Blue',
  'newText': 'hello',
  'newNested': <String, dynamic>{
    'a': <dynamic>[1, 2],
  },
};

void main() {
  test('fromJson keeps unknown top-level keys and toJson writes them', () {
    final entry = ScoutEntry.fromJson(_stored());

    expect(entry.extraFields.keys, containsAll(['newText', 'newNested']));
    final json = entry.toJson();
    expect(json['newText'], 'hello');
    expect(json['newNested'], <String, dynamic>{
      'a': <dynamic>[1, 2],
    });
  });

  test('modeled keys never land in extraFields', () {
    final entry = ScoutEntry.fromJson(_stored());

    expect(entry.extraFields.keys.toSet(), <String>{'newText', 'newNested'});
  });

  test('extraFields is unmodifiable', () {
    final entry = ScoutEntry.fromJson(_stored());

    expect(() => entry.extraFields['x'] = 1, throwsUnsupportedError);
  });

  test('copyWith keeps extras and can replace them', () {
    final entry = ScoutEntry.fromJson(_stored());

    expect(entry.copyWith(notes: 'edit').extraFields['newText'], 'hello');
    expect(
      entry.copyWith(extraFields: <String, dynamic>{'other': 1}).extraFields,
      <String, dynamic>{'other': 1},
    );
  });

  test('survives the fromJson(toJson()) snapshot round trip', () {
    final entry = ScoutEntry.fromJson(_stored()).copyWith(notes: 'edit');

    final snapshot = ScoutEntry.fromJson(entry.toJson());

    expect(snapshot.extraFields, entry.extraFields);
  });

  test('an extra cannot override a modeled key', () {
    final entry = ScoutEntry(
      id: 'e1',
      matchId: 'qm1',
      teamNumber: 3847,
      extraFields: <String, dynamic>{
        'matchId': 'evil',
        'teamNumber': 1,
        'addedManually': true,
        'fieldValues': <String, dynamic>{'x': 1},
        'ok': 'kept',
      },
    );

    final json = entry.toJson();
    expect(json['matchId'], 'qm1');
    expect(json['teamNumber'], 3847);
    expect(json.containsKey('addedManually'), isFalse);
    expect(json.containsKey('fieldValues'), isFalse);
    expect(json['ok'], 'kept');
  });

  test('a stored updatedAtTs is not kept as an extra', () {
    final entry = ScoutEntry.fromJson(<String, dynamic>{
      ..._stored(),
      'updatedAtTs': '2026-01-01T00:00:00Z',
    });

    expect(entry.extraFields.containsKey('updatedAtTs'), isFalse);
    expect(entry.toJson().containsKey('updatedAtTs'), isFalse);
  });

  test('values that are not JSON are dropped on read', () {
    final entry = ScoutEntry.fromJson(<String, dynamic>{
      ..._stored(),
      'when': DateTime.utc(2026),
    });

    expect(entry.extraFields.containsKey('when'), isFalse);
    expect(entry.extraFields['newText'], 'hello');
  });

  test('contentSignature ignores extras', () {
    final plain = ScoutEntry(id: 'e1', matchId: 'qm1', teamNumber: 3847);
    final withExtras = plain.copyWith(
      extraFields: <String, dynamic>{'newText': 'hello'},
    );

    expect(withExtras.contentSignature, plain.contentSignature);
  });

  test('QR JSON export keeps extras', () {
    final entry = ScoutEntry.fromJson(_stored());

    final decoded = ScoutQrCodec.decode(ScoutQrCodec.encode(entry));

    expect(decoded.extraFields['newText'], 'hello');
  });
}
