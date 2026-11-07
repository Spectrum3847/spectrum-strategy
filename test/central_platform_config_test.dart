import 'package:flutter_test/flutter_test.dart';
import 'package:spectrumstrategy/src/services/central_platform_config.dart';
import 'package:spectrumstrategy/src/services/central_rest_auth_client.dart';

void main() {
  test('central project falls back to the app\'s central Firebase options', () {
    expect(centralProjectId, 'spectrumtasks-81c63');
    expect(
      defaultCentralFunctionsBaseUrl,
      'https://us-central1-spectrumtasks-81c63.cloudfunctions.net',
    );
  });

  test('CentralRestAuthClient constructs without an explicit base url', () {
    final client = CentralRestAuthClient(centralApiKey: 'central-key');
    expect(client.centralFunctionsBaseUrl, defaultCentralFunctionsBaseUrl);
  });
}
