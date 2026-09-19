import 'package:firestore_client/firestore_client.dart' as fc;

import '../../firebase_options_central.dart';

export 'package:firestore_client/firestore_client.dart'
    show customTokenCallable;

const String spectrumAppKey = String.fromEnvironment('SPECTRUM_APP_KEY');

const String _centralFunctionsBaseUrlDefine = String.fromEnvironment(
  'CENTRAL_FUNCTIONS_BASE_URL',
);

final String centralProjectId = fc.centralProjectId.isNotEmpty
    ? fc.centralProjectId
    : centralFirebaseOptions().projectId;

final String defaultCentralFunctionsBaseUrl =
    _centralFunctionsBaseUrlDefine.isNotEmpty
    ? _centralFunctionsBaseUrlDefine
    : 'https://us-central1-$centralProjectId.cloudfunctions.net';
