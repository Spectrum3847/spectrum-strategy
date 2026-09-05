// ignore_for_file: invalid_use_of_protected_member

import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:spectrumstrategy/src/services/central_rest_auth_client.dart';
import 'package:spectrumstrategy/src/services/spectrum_auth_service.dart';

class _FakeGoogleSignInPlatform extends GoogleSignInPlatform
    with MockPlatformInterfaceMixin {
  _FakeGoogleSignInPlatform({this.errorToThrow});

  final Object? errorToThrow;

  @override
  Future<void> init(InitParameters params) async {}

  @override
  Future<AuthenticationResults?> attemptLightweightAuthentication(
    AttemptLightweightAuthenticationParameters params,
  ) async => null;

  @override
  bool supportsAuthenticate() => true;

  @override
  Future<AuthenticationResults> authenticate(
    AuthenticateParameters params,
  ) async {
    final error = errorToThrow;
    if (error != null) throw error;
    return const AuthenticationResults(
      user: GoogleSignInUserData(email: 'member@example.com', id: 'g-1'),
      authenticationTokens: AuthenticationTokenData(
        idToken: 'google-id-token-1',
      ),
    );
  }

  @override
  bool authorizationRequiresUserInteraction() => false;

  @override
  Future<ClientAuthorizationTokenData?> clientAuthorizationTokensForScopes(
    ClientAuthorizationTokensForScopesParameters params,
  ) async => null;

  @override
  Future<ServerAuthorizationTokenData?> serverAuthorizationTokensForScopes(
    ServerAuthorizationTokensForScopesParameters params,
  ) async => null;

  @override
  Future<void> signOut(SignOutParams params) async {}

  @override
  Future<void> disconnect(DisconnectParams params) async {}
}

final _member = MockUser(uid: 'central-uid-1', email: 'dana@example.com');

MockClient _centralBackend({
  int callableStatus = 200,
  Map<String, Object?> callableBody = const {
    'result': {
      'customToken': 'custom-token-1',
      'profile': {'displayName': 'Dana Scout', 'email': 'dana@example.com'},
    },
  },
}) {
  return MockClient((request) async {
    if (request.url.host == 'securetoken.googleapis.com') {
      return http.Response(
        jsonEncode({
          'id_token': 'central-token-refreshed',
          'refresh_token': 'central-refresh-2',
          'expires_in': '3600',
        }),
        200,
      );
    }
    if (request.url.path.endsWith('/getCustomToken')) {
      return http.Response(jsonEncode(callableBody), callableStatus);
    }
    expect(request.url.path, contains('accounts:signInWithIdp'));
    return http.Response(
      jsonEncode({
        'localId': 'central-uid-1',
        'idToken': 'central-token-1',
        'refreshToken': 'central-refresh-1',
        'expiresIn': '3600',
        'displayName': 'Dana Scout',
        'email': 'dana@example.com',
      }),
      200,
    );
  });
}

const _deniedCallable = <String, Object?>{
  'error': {'status': 'PERMISSION_DENIED', 'message': 'not approved'},
};

const _centralSession = <String, Object>{
  'uid': 'central-uid-1',
  'refreshToken': 'central-refresh-1',
};

FirebaseSpectrumAuthService _service({
  FirebaseAuth? appAuth,
  http.Client? centralHttp,
  int callableStatus = 200,
  Map<String, Object?> callableBody = const {
    'result': {
      'customToken': 'custom-token-1',
      'profile': {'displayName': 'Dana Scout', 'email': 'dana@example.com'},
    },
  },
}) {
  return FirebaseSpectrumAuthService(
    appAuth: appAuth ?? MockFirebaseAuth(mockUser: _member),
    googleSignIn: GoogleSignIn.instance,
    centralRest: CentralRestAuthClient(
      centralApiKey: 'central-key',
      httpClient:
          centralHttp ??
          _centralBackend(
            callableStatus: callableStatus,
            callableBody: callableBody,
          ),
    ),
    appKey: 'spectrumstrategy',
  );
}

void main() {
  late GoogleSignInPlatform originalPlatform;

  setUp(() {
    originalPlatform = GoogleSignInPlatform.instance;
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  tearDown(() {
    GoogleSignInPlatform.instance = originalPlatform;
    debugDefaultTargetPlatformOverride = null;
  });

  group('mobile sign-in (#1548)', () {
    test(
      'exchanges the Google token over REST and mints an app session',
      () async {
        GoogleSignInPlatform.instance = _FakeGoogleSignInPlatform();
        final service = _service();
        addTearDown(service.dispose);

        await service.signIn();

        expect(service.snapshot.state, SpectrumAuthState.signedIn);
        expect(service.currentUser?.uid, 'central-uid-1');
      },
    );

    test('persists the central session for the daily re-check', () async {
      GoogleSignInPlatform.instance = _FakeGoogleSignInPlatform();
      final service = _service();
      addTearDown(service.dispose);

      await service.signIn();

      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString('mobile_central_session_v1');
      expect(stored, isNotNull);
      final decoded = jsonDecode(stored!) as Map<String, dynamic>;
      expect(decoded['uid'], 'central-uid-1');
    });

    test('an unapproved account surfaces the approval error', () async {
      GoogleSignInPlatform.instance = _FakeGoogleSignInPlatform();
      final service = _service(
        callableStatus: 403,
        callableBody: _deniedCallable,
      );
      addTearDown(service.dispose);

      await service.signIn();

      expect(service.snapshot.state, SpectrumAuthState.error);
      expect(service.snapshot.error, contains('not approved'));
      expect(service.currentUser, isNull);
    });

    test('signOut clears the persisted central session', () async {
      GoogleSignInPlatform.instance = _FakeGoogleSignInPlatform();
      final service = _service();
      addTearDown(service.dispose);
      await service.signIn();

      await service.signOut();

      expect(service.snapshot.state, SpectrumAuthState.signedOut);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('mobile_central_session_v1'), isNull);
    });

    test(
      'a failure in the Android fallback still surfaces a friendly error',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        GoogleSignInPlatform.instance = _FakeGoogleSignInPlatform(
          errorToThrow: const GoogleSignInException(
            code: GoogleSignInExceptionCode.unknownError,
          ),
        );
        final service = _service();
        addTearDown(service.dispose);

        await service.signIn();

        expect(service.snapshot.state, SpectrumAuthState.error);

        expect(
          service.snapshot.error,
          matches(RegExp(r'^Sign-in failed \(.+\)\. Please try again\.$')),
        );
      },
    );

    test('a non-transport google_sign_in failure is not routed through the '
        'fallback', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      GoogleSignInPlatform.instance = _FakeGoogleSignInPlatform(
        errorToThrow: const GoogleSignInException(
          code: GoogleSignInExceptionCode.canceled,
        ),
      );
      final service = _service();
      addTearDown(service.dispose);

      await service.signIn();

      expect(service.snapshot.state, SpectrumAuthState.error);
      expect(service.snapshot.error, 'Sign-in was cancelled.');
    });
  });

  group('mobile central approval re-check', () {
    test('nothing persisted keeps the member signed in', () async {
      final appAuth = MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(uid: 'central-uid-1'),
      );
      final service = _service(appAuth: appAuth);
      addTearDown(service.dispose);

      await service.initialize();
      await pumpEventQueue();

      expect(service.snapshot.state, SpectrumAuthState.signedIn);
    });

    test('a single denial keeps the member signed in', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'mobile_central_session_v1': jsonEncode(_centralSession),
      });
      final appAuth = MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(uid: 'central-uid-1'),
      );
      final service = _service(
        appAuth: appAuth,
        callableStatus: 403,
        callableBody: _deniedCallable,
      );
      addTearDown(service.dispose);

      await service.initialize();
      await pumpEventQueue();

      expect(service.snapshot.state, SpectrumAuthState.signedIn);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('central_approval_denials_v1'), 1);
    });

    test('a second denial ends the session', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'mobile_central_session_v1': jsonEncode(_centralSession),
        'central_approval_denials_v1': 1,
      });
      final appAuth = MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(uid: 'central-uid-1'),
      );
      final service = _service(
        appAuth: appAuth,
        callableStatus: 403,
        callableBody: _deniedCallable,
      );
      addTearDown(service.dispose);

      await service.initialize();
      await pumpEventQueue();

      expect(service.snapshot.state, SpectrumAuthState.error);
      expect(service.snapshot.error, contains('not approved'));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('mobile_central_session_v1'), isNull);
    });

    test(
      'an unreachable central platform keeps the member signed in',
      () async {
        SharedPreferences.setMockInitialValues(<String, Object>{
          'mobile_central_session_v1': jsonEncode(_centralSession),
        });
        final appAuth = MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(uid: 'central-uid-1'),
        );
        final service = _service(
          appAuth: appAuth,
          callableStatus: 500,
          callableBody: const <String, Object?>{
            'error': {'message': 'boom'},
          },
        );
        addTearDown(service.dispose);

        await service.initialize();
        await pumpEventQueue();

        expect(service.snapshot.state, SpectrumAuthState.signedIn);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getInt('central_approval_denials_v1'), isNull);
      },
    );
  });
}
