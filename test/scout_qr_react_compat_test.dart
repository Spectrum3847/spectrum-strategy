import 'package:flutter_test/flutter_test.dart';
import 'package:spectrumstrategy/src/scouting/models/scout_config.dart';
import 'package:spectrumstrategy/src/scouting/models/scout_entry.dart';
import 'package:spectrumstrategy/src/scouting/services/scout_qr_codec.dart';

const _payload =
    'Sam\t12\tR2\t1234\t7\t3.5\ttrue\ta,b\t2\t1.5-2.5,8\t0\t\tgood auto ok';

const _phase = '{"score":0,"penalties":0,"notes":"","counters":{}}';

const _signature =
    '{"matchId":"","tbaMatchKey":"2027test_qm12","teamNumber":1234,'
    '"alliance":"Red","notes":"","fieldValues":{"defense":true,"fuel":7,'
    '"level":3.5,"matchNumber":12,"notes":"good auto ok","pTnumber":1234,'
    '"robot":"R2","scouter":"Sam","track_a_count":2,'
    '"track_a_times":"1.5-2.5,8","track_b_count":0,"track_b_times":"",'
    '"traits":"a,b"},"byPhase":{"auton":$_phase,"teleop":$_phase,'
    '"endgame":$_phase}}';

final _config = ScoutConfig.fromJson(<String, dynamic>{
  'title': 'T',
  'revision': 1,
  'delimiter': '\t',
  'sections': [
    {
      'name': 'Pre',
      'fields': [
        {'code': 'scouter', 'type': 'text'},
        {'code': 'matchNumber', 'type': 'TBA-match-number'},
        {
          'code': 'robot',
          'type': 'select',
          'choices': {'R2': 'Red 2', 'B1': 'Blue 1'},
        },
        {'code': 'pTnumber', 'type': 'number'},
      ],
    },
    {
      'name': 'Match',
      'fields': [
        {'code': 'fuel', 'type': 'counter'},
        {'code': 'level', 'type': 'range'},
        {'code': 'defense', 'type': 'boolean'},
        {
          'code': 'traits',
          'type': 'checkbox-select',
          'choices': {'a': 'A', 'b': 'B'},
        },
        {
          'code': 'track',
          'type': 'action-tracker',
          'actions': [
            {'code': 'a', 'label': 'A'},
            {'code': 'b', 'label': 'B'},
          ],
        },
        {'code': 'notes', 'type': 'long-text'},
      ],
    },
  ],
});

String _scanId(String signature) {
  var hash = 0x811c9dc5;
  for (final unit in signature.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xFFFFFFFF;
  }
  return 'scan-${hash.toRadixString(16).padLeft(8, '0')}';
}

void main() {
  test('encodes the same QR payload as the React app', () {
    final payload = _config.encodeValues(<String, dynamic>{
      'scouter': 'Sam',
      'matchNumber': '12',
      'robot': 'R2',
      'pTnumber': '1234',
      'fuel': 7,
      'level': 3.5,
      'defense': true,
      'traits': 'a,b',
      'track_a_count': 2,
      'track_a_times': '1.5-2.5,8',
      'track_b_times': '',
      'notes': 'good\tauto\nok',
    });

    expect(payload, _payload);
  });

  test('a scanned React QR gets the same signature and scan id', () {
    final values = ScoutQrCodec.tryDecodeQrScout(_payload, _config);
    expect(values, isNotNull);
    final entry = ScoutEntry(
      matchId: '',
      teamNumber: 1234,
      fieldValues: values!,
      tbaMatchKey: '2027test_qm12',
    );

    expect(entry.contentSignature, _signature);
    expect(_scanId(entry.contentSignature), 'scan-be99d2a4');
  });
}
