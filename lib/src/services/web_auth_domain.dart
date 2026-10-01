import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;

const Set<String> ownHostingDomains = {
  'frcspectrumstrategy.web.app',
  'frcspectrumstrategy-staging.web.app',
  'frcspectrumstrategy-preview.web.app',
  'frcspectrumstrategy.firebaseapp.com',
  'frcspectrumstrategy-staging.firebaseapp.com',
  'frcspectrumstrategy-preview.firebaseapp.com',
};

FirebaseOptions webFirebaseOptionsForHost(
  String host,
  FirebaseOptions defaults,
) {
  if (!ownHostingDomains.contains(host)) {
    return defaults;
  }
  return defaults.copyWith(authDomain: host);
}
