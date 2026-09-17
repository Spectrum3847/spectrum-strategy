import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:tba_client/tba_client.dart';
import 'package:spectrumstrategy/src/services/team_avatar_service.dart';

void main() {
  const sampleAvatarBase64 =
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==';

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  TbaClient avatarClient(MockClient mock) =>
      TbaClient(config: InMemoryTbaConfig('k'), httpClient: mock);

  test('fetches an avatar once, then serves it from cache', () async {
    var requests = 0;
    final mock = MockClient((_) async {
      requests++;
      return http.Response(
        jsonEncode(<Map<String, dynamic>>[
          <String, dynamic>{
            'type': 'avatar',
            'details': <String, dynamic>{'base64Image': sampleAvatarBase64},
          },
        ]),
        200,
      );
    });
    final service = TeamAvatarService(
      client: avatarClient(mock),
      year: 2026,
      prefsLoader: SharedPreferences.getInstance,
    );

    final first = await service.avatarFor(3847);
    final second = await service.avatarFor(3847);
    expect(first, isNotNull);
    expect(first, equals(base64Decode(sampleAvatarBase64)));
    expect(second, equals(first));
    expect(requests, 1);

    final service2 = TeamAvatarService(
      client: avatarClient(mock),
      year: 2026,
      prefsLoader: SharedPreferences.getInstance,
    );
    expect(await service2.avatarFor(3847), equals(first));
    expect(requests, 1);
  });

  test('negatively caches a team that has no avatar', () async {
    var requests = 0;
    final mock = MockClient((_) async {
      requests++;
      return http.Response(jsonEncode(<dynamic>[]), 200);
    });
    final service = TeamAvatarService(
      client: avatarClient(mock),
      year: 2026,
      prefsLoader: SharedPreferences.getInstance,
    );

    expect(await service.avatarFor(1), isNull);
    expect(await service.avatarFor(1), isNull);
    expect(requests, 1);
  });

  test('returns null and does not cache when no key is configured', () async {
    final mock = MockClient((_) async => http.Response('', 200));
    final service = TeamAvatarService(
      client: TbaClient(config: InMemoryTbaConfig(), httpClient: mock),
      year: 2026,
      prefsLoader: SharedPreferences.getInstance,
    );

    expect(await service.avatarFor(3847), isNull);
    expect(await service.avatarFor(3847), isNull);
  });
}
