import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart' show FirebaseApp;
import 'package:firestore_client/firestore_client.dart' as fc;

export 'package:firestore_client/firestore_client.dart'
    show
        CentralAuthErrorKind,
        CentralAuthException,
        CentralHandshake,
        CentralProfile,
        classifyCentralAuthError;

abstract class CentralAuthClient {
  Future<fc.CentralHandshake> handshake(String targetApp);
}

class FirebaseCentralAuthClient implements CentralAuthClient {
  FirebaseCentralAuthClient({required FirebaseApp centralApp})
    : _functions = FirebaseFunctions.instanceFor(app: centralApp);

  final FirebaseFunctions _functions;

  @override
  Future<fc.CentralHandshake> handshake(String targetApp) async {
    final callable = _functions.httpsCallable(
      fc.customTokenCallable,
      options: HttpsCallableOptions(timeout: const Duration(seconds: 90)),
    );
    final result = await callable.call<Map<String, dynamic>>({
      'targetApp': targetApp,
    });
    final data = result.data;
    return fc.CentralHandshake(
      customToken: data['customToken'] as String,
      profile: data['profile'] is Map<String, dynamic>
          ? fc.CentralProfile.fromMap(data['profile'] as Map<String, dynamic>)
          : null,
    );
  }
}

String errorKindName(fc.CentralAuthErrorKind kind) {
  switch (kind) {
    case fc.CentralAuthErrorKind.notApproved:
      return 'not-approved';
    case fc.CentralAuthErrorKind.appNotRegistered:
      return 'app-not-registered';
    case fc.CentralAuthErrorKind.unknown:
      return 'unknown';
  }
}
