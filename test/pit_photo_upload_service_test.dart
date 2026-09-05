import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:spectrumstrategy/src/scouting/services/pit_photo_upload_service.dart';

final Uint8List _bytes = Uint8List.fromList(<int>[1, 2, 3]);

PitPhotoUploadService _service(
  MockClient client, {
  String? origin = 'https://photos.example.workers.dev',
  String? token = 'fb-token',
}) {
  return PitPhotoUploadService(
    baseUrlLoader: () async => origin,
    idTokenProvider: () async => token,
    httpClient: client,
  );
}

void main() {
  test(
    'upload posts the bytes and returns the key the Worker minted',
    () async {
      http.Request? seen;
      final service = _service(
        MockClient((request) async {
          seen = request;
          return http.Response(jsonEncode({'key': 'abc.jpg'}), 201);
        }),
      );

      expect(await service.upload(_bytes), 'abc.jpg');
      expect(seen!.method, 'POST');
      expect(seen!.url.toString(), 'https://photos.example.workers.dev/photos');
      expect(seen!.headers['Authorization'], 'Bearer fb-token');
      expect(seen!.headers['Content-Type'], 'image/jpeg');
      expect(seen!.bodyBytes, _bytes);
    },
  );

  test(
    'a trailing slash on the origin does not double up in the path',
    () async {
      Uri? seen;
      final service = _service(
        MockClient((request) async {
          seen = request.url;
          return http.Response(jsonEncode({'key': 'abc.jpg'}), 201);
        }),
        origin: 'https://photos.example.workers.dev/',
      );

      await service.upload(_bytes);
      expect(seen.toString(), 'https://photos.example.workers.dev/photos');
    },
  );

  test('upload returns null for anything short of a 201', () async {
    for (final status in <int>[400, 403, 413, 415, 500]) {
      final service = _service(
        MockClient((_) async => http.Response('{}', status)),
      );
      expect(await service.upload(_bytes), isNull, reason: 'HTTP $status');
    }
  });

  test('upload returns null when the network throws', () async {
    final service = _service(
      MockClient((_) async => throw http.ClientException('down')),
    );
    expect(await service.upload(_bytes), isNull);
  });

  test('upload returns null on a 201 with no usable key', () async {
    for (final body in <String>['{}', '{"key":""}', '[]', 'not json']) {
      final service = _service(
        MockClient((_) async => http.Response(body, 201)),
      );
      expect(await service.upload(_bytes), isNull, reason: body);
    }
  });

  test('nothing is sent when the Worker is not configured', () async {
    var called = false;
    final client = MockClient((_) async {
      called = true;
      return http.Response('{}', 201);
    });

    expect(await _service(client, origin: null).upload(_bytes), isNull);
    expect(await _service(client, origin: '').upload(_bytes), isNull);
    expect(await _service(client, token: null).upload(_bytes), isNull);
    expect(called, isFalse);
  });

  test('a non-https origin is refused rather than used', () async {
    var called = false;
    final service = _service(
      MockClient((_) async {
        called = true;
        return http.Response('{}', 201);
      }),
      origin: 'http://photos.example.workers.dev',
    );

    expect(await service.upload(_bytes), isNull);
    expect(called, isFalse);
  });

  test('a redirect is not followed with the token attached', () async {
    final seen = <Uri>[];
    final service = _service(
      MockClient((request) async {
        seen.add(request.url);
        expect(request.followRedirects, isFalse);
        return http.Response(
          '',
          302,
          headers: <String, String>{
            'location': 'http://elsewhere.example/photos',
          },
        );
      }),
    );

    expect(await service.upload(_bytes), isNull);
    expect(await service.download('abc.jpg'), isNull);
    expect(await service.delete('abc.jpg'), isFalse);

    expect(seen, hasLength(3));
    expect(seen.every((u) => u.scheme == 'https'), isTrue);
  });

  test('download returns the bytes for a key', () async {
    Uri? seen;
    final service = _service(
      MockClient((request) async {
        seen = request.url;
        return http.Response.bytes(_bytes, 200);
      }),
    );

    expect(await service.download('abc.jpg'), _bytes);
    expect(
      seen.toString(),
      'https://photos.example.workers.dev/photos/abc.jpg',
    );
  });

  test('download returns null when the object is gone or refused', () async {
    for (final status in <int>[403, 404, 500]) {
      final service = _service(
        MockClient((_) async => http.Response('', status)),
      );
      expect(await service.download('abc.jpg'), isNull, reason: 'HTTP $status');
    }
  });

  test('delete counts a 404 as gone, because it is', () async {
    for (final status in <int>[204, 404]) {
      final service = _service(
        MockClient((_) async => http.Response('', status)),
      );
      expect(await service.delete('abc.jpg'), isTrue, reason: 'HTTP $status');
    }
    final refused = _service(MockClient((_) async => http.Response('', 403)));
    expect(await refused.delete('abc.jpg'), isFalse);
  });

  test('isConfigured needs both an origin and a token', () async {
    final client = MockClient((_) async => http.Response('{}', 201));
    expect(await _service(client).isConfigured, isTrue);
    expect(await _service(client, origin: null).isConfigured, isFalse);
    expect(await _service(client, token: null).isConfigured, isFalse);
  });
}
