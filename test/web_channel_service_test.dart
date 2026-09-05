import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:spectrumstrategy/src/services/web_channel_service.dart';

void main() {
  group('channelForHost', () {
    test('maps each hosting site and its firebaseapp.com twin', () {
      expect(
        WebChannelService.channelForHost('frcspectrumstrategy.web.app'),
        WebChannel.stable,
      );
      expect(
        WebChannelService.channelForHost('frcspectrumstrategy.firebaseapp.com'),
        WebChannel.stable,
      );
      expect(
        WebChannelService.channelForHost('frcspectrumstrategy-staging.web.app'),
        WebChannel.staging,
      );
      expect(
        WebChannelService.channelForHost(
          'frcspectrumstrategy-staging.firebaseapp.com',
        ),
        WebChannel.staging,
      );
    });

    test('is null for preview hosts, localhost, and anything else', () {
      expect(
        WebChannelService.channelForHost('frcspectrumstrategy-preview.web.app'),
        isNull,
      );
      expect(WebChannelService.channelForHost('localhost'), isNull);
      expect(WebChannelService.channelForHost('project516.github.io'), isNull);
    });
  });

  group('hasPublishedBuild', () {
    WebChannelService serviceReturning(
      Future<http.Response> Function(http.Request) handler,
    ) {
      return WebChannelService(clientFactory: () => MockClient(handler));
    }

    test('is true when the site serves a version.json', () async {
      late Uri requested;
      final service = serviceReturning((request) async {
        requested = request.url;
        return http.Response('{"version":"1.0.0","build_number":"1"}', 200);
      });
      expect(await service.hasPublishedBuild(WebChannel.staging), isTrue);
      expect(
        requested,
        Uri.parse('https://frcspectrumstrategy-staging.web.app/version.json'),
      );
    });

    test('is false on a 404 from an empty site', () async {
      final service = serviceReturning(
        (_) async => http.Response('Not Found', 404),
      );
      expect(await service.hasPublishedBuild(WebChannel.stable), isFalse);
    });

    test('is false when the hosting 200s with a non-app page', () async {
      final service = serviceReturning(
        (_) async => http.Response('<html>Site Not Found</html>', 200),
      );
      expect(await service.hasPublishedBuild(WebChannel.stable), isFalse);
    });

    test('is false when the request fails outright', () async {
      final service = serviceReturning(
        (_) async => throw http.ClientException('refused'),
      );
      expect(await service.hasPublishedBuild(WebChannel.stable), isFalse);
    });
  });
}
