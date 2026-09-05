import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart' show GoogleAuthProvider;
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:spectrumstrategy/src/services/central_approval_check.dart';
import 'package:spectrumstrategy/src/services/central_auth_client.dart';
import 'package:spectrumstrategy/src/services/central_platform_config.dart';
import 'package:spectrumstrategy/src/services/spectrum_auth_service.dart';

class FakeCentralAuthClient implements CentralAuthClient {
  FakeCentralAuthClient({this.token = 'custom-token-1', this.throwOnHandshake});

  final String token;
  final Object? throwOnHandshake;
  final List<String> handshakeApps = [];

  @override
  Future<CentralHandshake> handshake(String targetApp) async {
    handshakeApps.add(targetApp);
    final error = throwOnHandshake;
    if (error != null) throw error;
    return CentralHandshake(
      customToken: token,
      profile: const CentralProfile(
        displayName: 'Central User',
        email: 'central@example.com',
        role: 'mentor',
      ),
    );
  }
}

final _centralUser = MockUser(
  uid: 'central-uid-1',
  displayName: 'Central User',
  email: 'central@example.com',
);

FirebaseSpectrumAuthService _service({
  required MockFirebaseAuth appAuth,
  required MockFirebaseAuth centralAuth,
  required CentralAuthClient client,
  CentralApprovalCheck? approvalCheck,
}) {
  return FirebaseSpectrumAuthService(
    appAuth: appAuth,
    centralAuth: centralAuth,
    centralClient: client,
    appKey: 'spectrumstrategy',
    approvalCheck: approvalCheck,
  );
}

CentralApprovalCheck _approvalCheck({
  DateTime? lastChecked,
  required DateTime now,
}) {
  SharedPreferences.setMockInitialValues(
    lastChecked == null
        ? <String, Object>{}
        : <String, Object>{
            'central_approval_checked_at_v1': lastChecked
                .toUtc()
                .millisecondsSinceEpoch,
          },
  );
  return CentralApprovalCheck(
    prefsLoader: SharedPreferences.getInstance,
    now: () => now,
  );
}

Future<void> _waitFor(
  FirebaseSpectrumAuthService service,
  SpectrumAuthState state,
) {
  if (service.snapshot.state == state) return Future.value();
  return service.snapshotStream
      .firstWhere((snapshot) => snapshot.state == state)
      .timeout(const Duration(seconds: 5));
}

void main() {
  group('classifyCentralAuthError over FirebaseFunctionsException codes', () {
    test('permission-denied means the account is not approved', () {
      expect(
        classifyCentralAuthError(
          FirebaseFunctionsException(
            code: 'permission-denied',
            message: 'Account not approved.',
          ).code,
        ),
        CentralAuthErrorKind.notApproved,
      );
    });

    test('not-found means the app is not registered', () {
      expect(
        classifyCentralAuthError(
          FirebaseFunctionsException(
            code: 'not-found',
            message: 'No app registered for "spectrumstrategy".',
          ).code,
        ),
        CentralAuthErrorKind.appNotRegistered,
      );
    });

    test('anything else is unknown, including a missing code', () {
      expect(
        classifyCentralAuthError(
          FirebaseFunctionsException(code: 'internal', message: 'boom').code,
        ),
        CentralAuthErrorKind.unknown,
      );
      expect(classifyCentralAuthError(null), CentralAuthErrorKind.unknown);
    });
  });

  group('errorKindName', () {
    test('gives every kind a stable label for logs and the sign-in screen', () {
      expect(CentralAuthErrorKind.values.map(errorKindName), [
        'not-approved',
        'app-not-registered',
        'unknown',
      ]);
    });
  });

  test(
    'initialize with no sessions stays signed out and does not handshake',
    () async {
      final client = FakeCentralAuthClient();
      final service = _service(
        appAuth: MockFirebaseAuth(),
        centralAuth: MockFirebaseAuth(),
        client: client,
      );
      await service.initialize();

      expect(service.snapshot.state, SpectrumAuthState.signedOut);

      expect(client.handshakeApps, isEmpty);
      await service.dispose();
    },
  );

  test(
    'initialize with a persisted app session is signed in immediately',
    () async {
      final client = FakeCentralAuthClient();
      final service = _service(
        appAuth: MockFirebaseAuth(mockUser: _centralUser, signedIn: true),
        centralAuth: MockFirebaseAuth(),
        client: client,
      );
      await service.initialize();

      expect(service.snapshot.state, SpectrumAuthState.signedIn);
      expect(service.currentUser?.uid, 'central-uid-1');

      expect(client.handshakeApps, isEmpty);
      await service.dispose();
    },
  );

  test(
    'initialize resumes the handshake from a persisted central session',
    () async {
      final client = FakeCentralAuthClient();

      final appAuth = MockFirebaseAuth(mockUser: _centralUser);
      final service = _service(
        appAuth: appAuth,

        centralAuth: MockFirebaseAuth(mockUser: _centralUser, signedIn: true),
        client: client,
      );
      await service.initialize();

      await _waitFor(service, SpectrumAuthState.signedIn);

      expect(service.currentUser?.uid, 'central-uid-1');
      expect(client.handshakeApps, <String>['spectrumstrategy']);
      expect(appAuth.currentUser?.uid, 'central-uid-1');
      await service.dispose();
    },
  );

  test(
    'an unapproved account surfaces the approval error, not a profile',
    () async {
      final service = _service(
        appAuth: MockFirebaseAuth(mockUser: _centralUser),
        centralAuth: MockFirebaseAuth(mockUser: _centralUser, signedIn: true),
        client: FakeCentralAuthClient(
          throwOnHandshake: FirebaseFunctionsException(
            code: 'permission-denied',
            message: 'Account not approved.',
          ),
        ),
      );
      await service.initialize();

      await _waitFor(service, SpectrumAuthState.error);
      expect(service.snapshot.error, contains('not approved'));

      expect(service.currentUser, isNull);
      await service.dispose();
    },
  );

  test('an unregistered app surfaces the registration error', () async {
    final service = _service(
      appAuth: MockFirebaseAuth(mockUser: _centralUser),
      centralAuth: MockFirebaseAuth(mockUser: _centralUser, signedIn: true),
      client: FakeCentralAuthClient(
        throwOnHandshake: FirebaseFunctionsException(
          code: 'not-found',
          message: 'No app registered for "spectrumstrategy".',
        ),
      ),
    );
    await service.initialize();

    await _waitFor(service, SpectrumAuthState.error);
    expect(service.snapshot.error, contains('not registered'));
    await service.dispose();
  });

  test(
    'signIn reports a friendly error when the central app is missing',
    () async {
      final service = FirebaseSpectrumAuthService(
        appAuth: MockFirebaseAuth(mockUser: _centralUser),
        centralAuth: null,
        centralClient: null,
        appKey: 'spectrumstrategy',
      );
      await service.signIn();

      expect(service.snapshot.state, SpectrumAuthState.error);
      expect(
        service.snapshot.error,
        contains('Central sign-in is not configured'),
      );
      expect(service.currentUser, isNull);
      await service.dispose();
    },
  );

  test('signOut signs out both the app and the central session', () async {
    final appAuth = MockFirebaseAuth(mockUser: _centralUser, signedIn: true);
    final centralAuth = MockFirebaseAuth(
      mockUser: _centralUser,
      signedIn: true,
    );
    final service = _service(
      appAuth: appAuth,
      centralAuth: centralAuth,
      client: FakeCentralAuthClient(),
    );
    await service.initialize();
    await service.signOut();

    expect(service.snapshot.state, SpectrumAuthState.signedOut);
    expect(appAuth.currentUser, isNull);
    expect(centralAuth.currentUser, isNull);
    await service.dispose();
  });

  test(
    'a resumed handshake is not run twice across bootstrap retries',
    () async {
      final client = FakeCentralAuthClient();
      final service = _service(
        appAuth: MockFirebaseAuth(),
        centralAuth: MockFirebaseAuth(mockUser: _centralUser, signedIn: true),
        client: client,
      );

      await Future.wait([service.initialize(), service.initialize()]);
      await _waitFor(service, SpectrumAuthState.signedIn);

      expect(client.handshakeApps.length, 1);
      await service.dispose();
    },
  );

  test(
    'idToken returns null when signed out and a token when signed in',
    () async {
      final service = _service(
        appAuth: MockFirebaseAuth(),
        centralAuth: MockFirebaseAuth(),
        client: FakeCentralAuthClient(),
      );
      await service.initialize();
      expect(await service.idToken(), isNull);

      final signedIn = _service(
        appAuth: MockFirebaseAuth(mockUser: _centralUser, signedIn: true),
        centralAuth: MockFirebaseAuth(),
        client: FakeCentralAuthClient(),
      );
      await signedIn.initialize();
      expect(await signedIn.idToken(), isNotNull);
      await service.dispose();
      await signedIn.dispose();
    },
  );

  test('a pre-platform direct Google session is dropped at launch', () async {
    final legacy = MockUser(uid: 'old-direct-uid', email: 'old@example.com');
    await legacy.linkWithProvider(GoogleAuthProvider());
    expect(FirebaseSpectrumAuthService.isPrePlatformSession(legacy), isTrue);
    expect(
      FirebaseSpectrumAuthService.isPrePlatformSession(_centralUser),
      isFalse,
    );

    final appAuth = MockFirebaseAuth(mockUser: legacy, signedIn: true);
    final client = FakeCentralAuthClient();
    final service = _service(
      appAuth: appAuth,
      centralAuth: MockFirebaseAuth(),
      client: client,
    );
    await service.initialize();
    await _waitFor(service, SpectrumAuthState.signedOut);

    expect(appAuth.currentUser, isNull);
    expect(service.currentUser, isNull);
    expect(client.handshakeApps, isEmpty);
    await service.dispose();
  });

  test('SPECTRUM_APP_KEY comes from the build environment, not the source', () {
    expect(spectrumAppKey, isEmpty);
  });

  group('daily central approval re-check', () {
    final now = DateTime.utc(2026, 9, 4, 12);

    test('a restored session re-checks when a day has passed', () async {
      final client = FakeCentralAuthClient();
      final service = _service(
        appAuth: MockFirebaseAuth(signedIn: true, mockUser: _centralUser),
        centralAuth: MockFirebaseAuth(signedIn: true, mockUser: _centralUser),
        client: client,
        approvalCheck: _approvalCheck(
          lastChecked: now.subtract(const Duration(hours: 25)),
          now: now,
        ),
      );
      await service.initialize();
      await pumpEventQueue();
      expect(client.handshakeApps, ['spectrumstrategy']);
      expect(service.snapshot.state, SpectrumAuthState.signedIn);
      await service.dispose();
    });

    test('a session checked today does not call the callable', () async {
      final client = FakeCentralAuthClient();
      final service = _service(
        appAuth: MockFirebaseAuth(signedIn: true, mockUser: _centralUser),
        centralAuth: MockFirebaseAuth(signedIn: true, mockUser: _centralUser),
        client: client,
        approvalCheck: _approvalCheck(
          lastChecked: now.subtract(const Duration(hours: 2)),
          now: now,
        ),
      );
      await service.initialize();
      await pumpEventQueue();
      expect(client.handshakeApps, isEmpty);
      expect(service.snapshot.state, SpectrumAuthState.signedIn);
      await service.dispose();
    });

    test('a single denial does not end the session', () async {
      final service = _service(
        appAuth: MockFirebaseAuth(signedIn: true, mockUser: _centralUser),
        centralAuth: MockFirebaseAuth(signedIn: true, mockUser: _centralUser),
        client: FakeCentralAuthClient(
          throwOnHandshake: FirebaseFunctionsException(
            code: 'permission-denied',
            message: 'not approved',
          ),
        ),
        approvalCheck: _approvalCheck(lastChecked: null, now: now),
      );
      await service.initialize();
      await pumpEventQueue();
      expect(service.snapshot.state, SpectrumAuthState.signedIn);
      await service.dispose();
    });

    test('a second denial signs the member out', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'central_approval_denials_v1': 1,
      });
      final service = _service(
        appAuth: MockFirebaseAuth(signedIn: true, mockUser: _centralUser),
        centralAuth: MockFirebaseAuth(signedIn: true, mockUser: _centralUser),
        client: FakeCentralAuthClient(
          throwOnHandshake: FirebaseFunctionsException(
            code: 'permission-denied',
            message: 'not approved',
          ),
        ),
        approvalCheck: CentralApprovalCheck(
          prefsLoader: SharedPreferences.getInstance,
          now: () => now,
        ),
      );
      await service.initialize();
      await _waitFor(service, SpectrumAuthState.error);
      expect(service.snapshot.error, contains('not approved'));
      await service.dispose();
    });

    test(
      'an unreachable central platform keeps the member signed in',
      () async {
        final client = FakeCentralAuthClient(
          throwOnHandshake: FirebaseFunctionsException(
            code: 'unavailable',
            message: 'network',
          ),
        );
        final service = _service(
          appAuth: MockFirebaseAuth(signedIn: true, mockUser: _centralUser),
          centralAuth: MockFirebaseAuth(signedIn: true, mockUser: _centralUser),
          client: client,
          approvalCheck: _approvalCheck(lastChecked: null, now: now),
        );
        await service.initialize();
        await pumpEventQueue();
        expect(client.handshakeApps, ['spectrumstrategy']);
        expect(service.snapshot.state, SpectrumAuthState.signedIn);
        await service.dispose();
      },
    );

    test(
      'this app not being registered does not sign the member out',
      () async {
        final service = _service(
          appAuth: MockFirebaseAuth(signedIn: true, mockUser: _centralUser),
          centralAuth: MockFirebaseAuth(signedIn: true, mockUser: _centralUser),
          client: FakeCentralAuthClient(
            throwOnHandshake: FirebaseFunctionsException(
              code: 'not-found',
              message: 'app not registered',
            ),
          ),
          approvalCheck: _approvalCheck(lastChecked: null, now: now),
        );
        await service.initialize();
        await pumpEventQueue();
        expect(service.snapshot.state, SpectrumAuthState.signedIn);
        await service.dispose();
      },
    );
  });

  test(
    'a blank custom-token session takes its identity from the roster',
    () async {
      final service = _service(
        appAuth: MockFirebaseAuth(mockUser: MockUser(uid: 'central-uid-1')),
        centralAuth: MockFirebaseAuth(signedIn: true, mockUser: _centralUser),
        client: FakeCentralAuthClient(),
        approvalCheck: _approvalCheck(
          lastChecked: null,
          now: DateTime.utc(2026),
        ),
      );
      await service.initialize();
      await service.signIn();
      await _waitFor(service, SpectrumAuthState.signedIn);
      expect(service.currentUser!.displayName, 'Central User');
      expect(service.currentUser!.email, 'central@example.com');
      await service.dispose();
    },
  );

  group('CentralApprovalCheck', () {
    test(
      'a denial marks the check as done, so the next one is a day away',
      () async {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        final now = DateTime.utc(2026, 9, 4, 12);
        final check = CentralApprovalCheck(
          prefsLoader: SharedPreferences.getInstance,
          now: () => now,
        );
        expect(await check.isDue(), isTrue);
        expect(await check.recordDenial(), 1);
        expect(await check.isDue(), isFalse);
        expect(await check.recordDenial(), 2);
      },
    );

    test('a positive answer clears the denial count', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'central_approval_denials_v1': 1,
      });
      final check = CentralApprovalCheck(
        prefsLoader: SharedPreferences.getInstance,
        now: () => DateTime.utc(2026, 9, 4, 12),
      );
      await check.markChecked();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('central_approval_denials_v1'), isNull);
    });
  });
}
