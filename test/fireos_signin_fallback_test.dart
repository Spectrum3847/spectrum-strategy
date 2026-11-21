// ignore_for_file: invalid_use_of_protected_member

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';
import 'package:mock_exceptions/mock_exceptions.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:spectrumstrategy/src/services/central_auth_client.dart';
import 'package:spectrumstrategy/src/services/spectrum_auth_service.dart';

class _FakeCentralAuthClient implements CentralAuthClient {
  @override
  Future<CentralHandshake> handshake(String targetApp) async =>
      const CentralHandshake(customToken: 'custom-token-1');
}

final _member = MockUser(uid: 'central-uid-1', email: 'member@example.com');

FirebaseSpectrumAuthService _service({MockFirebaseAuth? centralAuth}) {
  return FirebaseSpectrumAuthService(
    appAuth: MockFirebaseAuth(mockUser: _member),
    centralAuth: centralAuth ?? MockFirebaseAuth(mockUser: _member),
    googleSignIn: GoogleSignIn.instance,
    centralClient: _FakeCentralAuthClient(),
    appKey: 'spectrumstrategy',
  );
}

class _ThrowingGoogleSignInPlatform extends GoogleSignInPlatform
    with MockPlatformInterfaceMixin {
  _ThrowingGoogleSignInPlatform(this.errorToThrow, {this.throwOnInit = false});

  final Object errorToThrow;

  final bool throwOnInit;

  @override
  Future<void> init(InitParameters params) async {
    if (throwOnInit) throw errorToThrow;
  }

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
    throw errorToThrow;
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

class _RecordingGoogleSignInPlatform extends GoogleSignInPlatform
    with MockPlatformInterfaceMixin {
  int initCalls = 0;

  @override
  Future<void> init(InitParameters params) async {
    initCalls++;
  }

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
    throw UnimplementedError();
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

void main() {
  group('isGoogleSignInTransportError', () {
    test('canceled does not fall back', () {
      expect(
        isGoogleSignInTransportError(
          const GoogleSignInException(code: GoogleSignInExceptionCode.canceled),
        ),
        isFalse,
      );
    });

    test('interrupted does not fall back', () {
      expect(
        isGoogleSignInTransportError(
          const GoogleSignInException(
            code: GoogleSignInExceptionCode.interrupted,
          ),
        ),
        isFalse,
      );
    });

    test('unknownError (the Fire OS Play-services gap) falls back', () {
      expect(
        isGoogleSignInTransportError(
          const GoogleSignInException(
            code: GoogleSignInExceptionCode.unknownError,
          ),
        ),
        isTrue,
      );
    });

    test('clientConfigurationError falls back', () {
      expect(
        isGoogleSignInTransportError(
          const GoogleSignInException(
            code: GoogleSignInExceptionCode.clientConfigurationError,
          ),
        ),
        isTrue,
      );
    });

    test('providerConfigurationError falls back', () {
      expect(
        isGoogleSignInTransportError(
          const GoogleSignInException(
            code: GoogleSignInExceptionCode.providerConfigurationError,
          ),
        ),
        isTrue,
      );
    });

    test('uiUnavailable falls back', () {
      expect(
        isGoogleSignInTransportError(
          const GoogleSignInException(
            code: GoogleSignInExceptionCode.uiUnavailable,
          ),
        ),
        isTrue,
      );
    });

    test('userMismatch falls back', () {
      expect(
        isGoogleSignInTransportError(
          const GoogleSignInException(
            code: GoogleSignInExceptionCode.userMismatch,
          ),
        ),
        isTrue,
      );
    });

    test('a non-GoogleSignInException does not fall back', () {
      expect(isGoogleSignInTransportError(StateError('boom')), isFalse);
    });
  });

  group('FirebaseSpectrumAuthService Fire OS fallback', () {
    late GoogleSignInPlatform originalPlatform;

    setUp(() {
      originalPlatform = GoogleSignInPlatform.instance;
    });

    tearDown(() {
      GoogleSignInPlatform.instance = originalPlatform;
      debugDefaultTargetPlatformOverride = null;
    });

    test(
      'Android + a transport error falls back to signInWithProvider',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        GoogleSignInPlatform.instance = _ThrowingGoogleSignInPlatform(
          const GoogleSignInException(
            code: GoogleSignInExceptionCode.unknownError,
          ),
        );
        final service = _service();

        await service.signIn();

        expect(service.snapshot.state, SpectrumAuthState.signedIn);
        expect(service.currentUser?.uid, 'central-uid-1');
      },
    );

    test('Android + canceled does not fall back', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      GoogleSignInPlatform.instance = _ThrowingGoogleSignInPlatform(
        const GoogleSignInException(code: GoogleSignInExceptionCode.canceled),
      );
      final service = _service();

      await service.signIn();

      expect(service.snapshot.state, SpectrumAuthState.error);
      expect(service.snapshot.error, 'Sign-in was cancelled.');
    });

    test('Android + interrupted does not fall back', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      GoogleSignInPlatform.instance = _ThrowingGoogleSignInPlatform(
        const GoogleSignInException(
          code: GoogleSignInExceptionCode.interrupted,
        ),
      );
      final service = _service();

      await service.signIn();

      expect(service.snapshot.state, SpectrumAuthState.error);
    });

    test('iOS does not fall back even for a transport error', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      GoogleSignInPlatform.instance = _ThrowingGoogleSignInPlatform(
        const GoogleSignInException(
          code: GoogleSignInExceptionCode.unknownError,
        ),
      );
      final service = _service();

      await service.signIn();

      expect(service.snapshot.state, SpectrumAuthState.error);
    });

    test(
      'a failure in the fallback itself still surfaces a friendly error',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        GoogleSignInPlatform.instance = _ThrowingGoogleSignInPlatform(
          const GoogleSignInException(
            code: GoogleSignInExceptionCode.unknownError,
          ),
        );

        final centralAuth = MockFirebaseAuth(mockUser: _member);
        whenCalling(Invocation.method(#signInWithProvider, null))
            .on(centralAuth)
            .thenThrow(FirebaseAuthException(code: 'network-request-failed'));
        final service = _service(centralAuth: centralAuth);

        await service.signIn();

        expect(service.snapshot.state, SpectrumAuthState.error);
        expect(
          service.snapshot.error,
          'Network error. Check your connection and try again.',
        );
      },
    );
  });

  group('FirebaseSpectrumAuthService.initialize', () {
    late GoogleSignInPlatform originalPlatform;

    setUp(() {
      originalPlatform = GoogleSignInPlatform.instance;
    });

    tearDown(() {
      GoogleSignInPlatform.instance = originalPlatform;
      debugDefaultTargetPlatformOverride = null;
    });

    test('calls GoogleSignIn.initialize() on non-web platforms', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final platform = _RecordingGoogleSignInPlatform();
      GoogleSignInPlatform.instance = platform;
      final service = _service();

      await service.initialize();

      expect(platform.initCalls, 1);
    });

    test('a second initialize() call issues no second platform init', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final platform = _RecordingGoogleSignInPlatform();
      GoogleSignInPlatform.instance = platform;
      final service = _service();

      await service.initialize();
      await service.initialize();

      expect(platform.initCalls, 1);
    });

    test('a device with no Play Services and no session comes up signed out, '
        'not stuck unknown', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      GoogleSignInPlatform.instance = _ThrowingGoogleSignInPlatform(
        const GoogleSignInException(
          code: GoogleSignInExceptionCode.unknownError,
        ),
        throwOnInit: true,
      );
      final service = _service();

      await service.initialize();

      expect(service.snapshot.state, SpectrumAuthState.signedOut);
    });

    test('a device with no Play Services still comes up signed in when it '
        'already holds a Firebase session', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      GoogleSignInPlatform.instance = _ThrowingGoogleSignInPlatform(
        const GoogleSignInException(
          code: GoogleSignInExceptionCode.unknownError,
        ),
        throwOnInit: true,
      );
      final appAuth = MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(uid: 'uid-kindle', displayName: 'Kindle Scout'),
      );
      final service = FirebaseSpectrumAuthService(
        appAuth: appAuth,
        googleSignIn: GoogleSignIn.instance,
      );

      await service.initialize();

      expect(service.snapshot.state, SpectrumAuthState.signedIn);
      expect(service.currentUser?.uid, 'uid-kindle');
    });
  });
}
