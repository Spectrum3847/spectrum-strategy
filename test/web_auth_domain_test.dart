import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spectrumstrategy/src/services/web_auth_domain.dart';

void main() {
  const defaults = FirebaseOptions(
    apiKey: 'key',
    appId: 'app',
    messagingSenderId: 'sender',
    projectId: 'frcspectrumstrategy',
    authDomain: 'frcspectrumstrategy.firebaseapp.com',
  );

  test('overrides authDomain for the staging web.app host', () {
    final result = webFirebaseOptionsForHost(
      'frcspectrumstrategy-staging.web.app',
      defaults,
    );
    expect(result.authDomain, 'frcspectrumstrategy-staging.web.app');
  });

  test('overrides authDomain for the prod web.app host', () {
    final result = webFirebaseOptionsForHost(
      'frcspectrumstrategy.web.app',
      defaults,
    );
    expect(result.authDomain, 'frcspectrumstrategy.web.app');
  });

  test('overrides authDomain for the default firebaseapp.com host', () {
    final result = webFirebaseOptionsForHost(
      'frcspectrumstrategy.firebaseapp.com',
      defaults,
    );
    expect(result.authDomain, 'frcspectrumstrategy.firebaseapp.com');
  });

  test('overrides authDomain for the staging firebaseapp.com host', () {
    final result = webFirebaseOptionsForHost(
      'frcspectrumstrategy-staging.firebaseapp.com',
      defaults,
    );
    expect(result.authDomain, 'frcspectrumstrategy-staging.firebaseapp.com');
  });

  test('overrides authDomain for the preview web.app host', () {
    final result = webFirebaseOptionsForHost(
      'frcspectrumstrategy-preview.web.app',
      defaults,
    );
    expect(result.authDomain, 'frcspectrumstrategy-preview.web.app');
  });

  test('leaves authDomain alone for an unrelated host', () {
    final result = webFirebaseOptionsForHost(
      'spectrum3847.github.io',
      defaults,
    );
    expect(result.authDomain, defaults.authDomain);
  });

  test('leaves authDomain alone for localhost', () {
    final result = webFirebaseOptionsForHost('localhost', defaults);
    expect(result.authDomain, defaults.authDomain);
  });

  test('other fields are unchanged when the host overrides authDomain', () {
    final result = webFirebaseOptionsForHost(
      'frcspectrumstrategy.web.app',
      defaults,
    );
    expect(result.apiKey, defaults.apiKey);
    expect(result.appId, defaults.appId);
    expect(result.messagingSenderId, defaults.messagingSenderId);
    expect(result.projectId, defaults.projectId);
  });
}
