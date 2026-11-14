import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:tba_client/tba_client.dart';
import 'package:spectrumstrategy/src/services/tba/tba_match_videos.dart';

void main() {
  TbaClient client(MockClient mock) =>
      TbaClient(config: InMemoryTbaConfig('k'), httpClient: mock);

  test('returns the match videos', () async {
    final mock = MockClient(
      (_) async => http.Response(
        jsonEncode(<String, dynamic>{
          'key': '2026miket_qm14',
          'videos': [
            {'type': 'youtube', 'key': 'abc123'},
          ],
        }),
        200,
      ),
    );

    final videos = await fetchMatchVideos(client(mock), '2026miket_qm14');

    expect(videos, hasLength(1));
    expect(videos.single.type, 'youtube');
    expect(videos.single.key, 'abc123');
  });

  test('returns an empty list when TBA has no match at that key', () async {
    final mock = MockClient((_) async => http.Response('', 404));

    final videos = await fetchMatchVideos(client(mock), 'nope');

    expect(videos, isEmpty);
  });
}
