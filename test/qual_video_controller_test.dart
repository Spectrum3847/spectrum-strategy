import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tba_client/tba_client.dart';

import 'package:spectrumstrategy/src/state/qual_video_controller.dart';

void main() {
  test('fetches a video per match key and caches the result', () async {
    var requestCount = 0;
    final client = TbaClient(
      config: InMemoryTbaConfig('k'),
      httpClient: MockClient((request) async {
        requestCount++;
        final key = request.url.pathSegments.last;
        if (key == '2026miket_qm1') {
          return http.Response(
            jsonEncode(<String, dynamic>{
              'key': key,
              'videos': [
                {'type': 'youtube', 'key': 'abc123'},
              ],
            }),
            200,
          );
        }
        return http.Response(
          jsonEncode(<String, dynamic>{'key': key, 'videos': []}),
          200,
        );
      }),
    );
    final controller = QualVideoController(tbaClient: client);

    await controller.load('2026miket', ['2026miket_qm1', '2026miket_qm2']);

    expect(requestCount, 2);
    expect(
      controller.videoFor('2026miket_qm1')?.youtubeUrl,
      contains('abc123'),
    );
    expect(controller.videoFor('2026miket_qm2'), isNull);
  });

  test('does not refetch an already-answered match key', () async {
    var requestCount = 0;
    final client = TbaClient(
      config: InMemoryTbaConfig('k'),
      httpClient: MockClient((request) async {
        requestCount++;
        return http.Response(
          jsonEncode(<String, dynamic>{
            'key': request.url.pathSegments.last,
            'videos': [],
          }),
          200,
        );
      }),
    );
    final controller = QualVideoController(tbaClient: client);

    await controller.load('2026miket', ['2026miket_qm1']);
    await controller.load('2026miket', ['2026miket_qm1']);

    expect(requestCount, 1);
  });

  test('drops the previous event cache on an event switch', () async {
    final client = TbaClient(
      config: InMemoryTbaConfig('k'),
      httpClient: MockClient(
        (request) async => http.Response(
          jsonEncode(<String, dynamic>{
            'key': request.url.pathSegments.last,
            'videos': [
              {'type': 'youtube', 'key': 'xyz'},
            ],
          }),
          200,
        ),
      ),
    );
    final controller = QualVideoController(tbaClient: client);

    await controller.load('2026miket', ['2026miket_qm1']);
    expect(controller.videoFor('2026miket_qm1'), isNotNull);

    await controller.load('2026txhou', ['2026txhou_qm1']);

    expect(controller.videoFor('2026miket_qm1'), isNull);
    expect(controller.videoFor('2026txhou_qm1'), isNotNull);
  });

  test('no-ops with no TBA client configured', () async {
    final controller = QualVideoController(tbaClient: null);

    await controller.load('2026miket', ['2026miket_qm1']);

    expect(controller.videoFor('2026miket_qm1'), isNull);
    expect(controller.isLoading, isFalse);
  });

  test('a failed match key is retried, not cached as N/A', () async {
    var qm2Attempts = 0;
    final client = TbaClient(
      config: InMemoryTbaConfig('k'),
      httpClient: MockClient((request) async {
        final key = request.url.pathSegments.last;
        if (key == '2026miket_qm2') {
          qm2Attempts++;
          if (qm2Attempts == 1) return http.Response('rate limited', 429);
        }
        return http.Response(
          jsonEncode(<String, dynamic>{
            'key': key,
            'videos': [
              {'type': 'youtube', 'key': 'abc123'},
            ],
          }),
          200,
        );
      }),
    );
    final controller = QualVideoController(tbaClient: client);

    await controller.load('2026miket', ['2026miket_qm1', '2026miket_qm2']);

    expect(controller.isLoading, isFalse);
    expect(controller.videoFor('2026miket_qm1'), isNotNull);
    expect(controller.videoFor('2026miket_qm2'), isNull);
    expect(qm2Attempts, 1);

    await controller.load('2026miket', ['2026miket_qm1', '2026miket_qm2']);

    expect(controller.videoFor('2026miket_qm2'), isNotNull);
    expect(qm2Attempts, 2);
  });

  test('fetches missing keys in batches rather than all at once', () async {
    const keyCount = 14;
    var inFlight = 0;
    var maxInFlight = 0;
    final client = TbaClient(
      config: InMemoryTbaConfig('k'),
      httpClient: MockClient((request) async {
        inFlight++;
        maxInFlight = maxInFlight < inFlight ? inFlight : maxInFlight;
        await Future<void>.delayed(const Duration(milliseconds: 5));
        inFlight--;
        return http.Response(
          jsonEncode(<String, dynamic>{
            'key': request.url.pathSegments.last,
            'videos': [],
          }),
          200,
        );
      }),
    );
    final controller = QualVideoController(tbaClient: client);
    final keys = [for (var i = 1; i <= keyCount; i++) '2026miket_qm$i'];

    await controller.load('2026miket', keys);

    for (final key in keys) {
      expect(controller.videoFor(key), isNull);
    }
    expect(maxInFlight, lessThan(keyCount));
  });

  test('disposing mid-fetch does not throw on notifyListeners', () async {
    final client = TbaClient(
      config: InMemoryTbaConfig('k'),
      httpClient: MockClient((request) async {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        return http.Response(
          jsonEncode(<String, dynamic>{
            'key': request.url.pathSegments.last,
            'videos': [],
          }),
          200,
        );
      }),
    );
    final controller = QualVideoController(tbaClient: client);

    final future = controller.load('2026miket', ['2026miket_qm1']);
    controller.dispose();

    await expectLater(future, completes);
  });
}
