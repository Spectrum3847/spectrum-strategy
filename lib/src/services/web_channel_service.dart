import 'package:http/http.dart' as http;

enum WebChannel {
  stable('Stable', 'frcspectrumstrategy.web.app'),
  staging('Staging', 'frcspectrumstrategy-staging.web.app');

  const WebChannel(this.label, this.host);

  final String label;
  final String host;

  Uri get url => Uri.https(host, '/');
}

class WebChannelService {
  WebChannelService({http.Client Function()? clientFactory})
    : _clientFactory = clientFactory ?? http.Client.new;

  final http.Client Function() _clientFactory;

  static const _checkTimeout = Duration(seconds: 8);

  static WebChannel? channelForHost(String host) {
    for (final channel in WebChannel.values) {
      if (host == channel.host ||
          host == channel.host.replaceFirst('.web.app', '.firebaseapp.com')) {
        return channel;
      }
    }
    return null;
  }

  Future<bool> hasPublishedBuild(WebChannel channel) async {
    final client = _clientFactory();
    try {
      final response = await client
          .get(channel.url.replace(path: '/version.json'))
          .timeout(_checkTimeout);
      return response.statusCode == 200 && response.body.contains('version');
    } catch (_) {
      return false;
    } finally {
      client.close();
    }
  }
}
