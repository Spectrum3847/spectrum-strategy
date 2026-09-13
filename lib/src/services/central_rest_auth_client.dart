import 'package:firestore_client/firestore_client.dart' as fc;
import 'package:shared_preferences/shared_preferences.dart';

import 'central_approval_check.dart';
import 'central_auth_client.dart';

export 'package:firestore_client/firestore_client.dart'
    show CentralRecheckOutcome;

class CentralRestAuthClient extends fc.CentralRestAuthClient
    implements CentralAuthClient {
  CentralRestAuthClient({
    required super.centralApiKey,
    super.centralFunctionsBaseUrl,
    super.httpClient,
    super.customTokenTimeout,
  });
}

Future<fc.CentralRecheckOutcome> runCentralApprovalRecheck({
  required CentralRestAuthClient client,
  required CentralApprovalCheck approvalCheck,
  required SharedPreferences prefs,
  required String centralPrefsKey,
  required String appKey,
}) {
  return fc.runCentralApprovalRecheck(
    client: client,
    storage: _PrefsCentralSessionStorage(prefs, centralPrefsKey),
    appKey: appKey,
    denialsBeforeSignOut: CentralApprovalCheck.denialsBeforeSignOut,
    onApproved: approvalCheck.markChecked,
    onDenied: approvalCheck.recordDenial,
  );
}

class _PrefsCentralSessionStorage implements fc.CentralSessionStorage {
  _PrefsCentralSessionStorage(this._prefs, this._key);

  final SharedPreferences _prefs;
  final String _key;

  @override
  Future<String?> read() async => _prefs.getString(_key);

  @override
  Future<void> write(String value) => _prefs.setString(_key, value);

  @override
  Future<void> delete() => _prefs.remove(_key);
}
