import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firestore_client/firestore_client.dart' as fc;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:spectrumstrategy/src/services/desktop_auth_service.dart';
import 'package:spectrumstrategy/src/services/http_timeout_client.dart';
import 'package:spectrumstrategy/src/services/spectrum_auth_service.dart';

MockClient _firebaseBackend({
  int refreshStatus = 200,
  int callableStatus = 200,
  Map<String, Object?> callableBody = const {
    'result': {
      'customToken': 'custom-token-1',
      'profile': {
        'displayName': 'Dana Scout',
        'email': 'dana@example.com',
        'role': 'mentor',
      },
    },
  },
  int exchangeStatus = 200,
}) {
  return MockClient((request) async {
    if (request.url.host == 'securetoken.googleapis.com') {
      if (refreshStatus != 200) {
        return http.Response('{"error":"revoked"}', refreshStatus);
      }
      return http.Response(
        jsonEncode({
          'id_token': 'fb-token-refreshed',
          'refresh_token': 'refresh-2',
          'expires_in': '3600',
        }),
        200,
      );
    }
    if (request.url.host ==
            'us-central1-spectrumtasks-81c63.cloudfunctions.net' &&
        request.url.path.endsWith('/getCustomToken')) {
      return http.Response(jsonEncode(callableBody), callableStatus);
    }
    if (request.url.path.contains('accounts:signInWithCustomToken')) {
      if (exchangeStatus != 200) {
        return http.Response(
          jsonEncode({
            'error': {'message': 'INVALID_CUSTOM_TOKEN'},
          }),
          exchangeStatus,
        );
      }
      return http.Response(
        jsonEncode({
          'idToken': _idTokenFor('central-uid-1'),
          'refreshToken': 'refresh-1',
          'expiresIn': '3600',
        }),
        200,
      );
    }
    if (request.url.path.endsWith('accounts:update')) {
      return http.Response(
        jsonEncode({
          'localId': 'central-uid-1',
          'displayName': 'Dana Renamed',
          'idToken': 'fb-token-2',
          'refreshToken': 'refresh-2',
          'expiresIn': '3600',
        }),
        200,
      );
    }
    expect(request.url.path, contains('accounts:signInWithIdp'));
    expect(request.url.queryParameters['key'], 'central-key');
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

String _idTokenFor(String uid) {
  final header = base64Url.encode(utf8.encode(jsonEncode({'alg': 'RS256'})));
  final claims = base64Url.encode(
    utf8.encode(jsonEncode({'user_id': uid, 'sub': uid})),
  );
  return '$header.$claims.signature';
}

MockClient _refusingLaterRefreshes() {
  final ok = _firebaseBackend();
  var refreshes = 0;
  return MockClient((request) async {
    if (request.url.host == 'securetoken.googleapis.com' && ++refreshes > 1) {
      return http.Response('{"error":"revoked"}', 403);
    }
    final streamed = await ok.send(request);
    return http.Response.fromStream(streamed);
  });
}

class _GatedRenameSession extends fc.FirebaseAuthSession {
  _GatedRenameSession({
    required super.apiKey,
    required super.httpClient,
    required this.gate,
  });

  final Completer<void> gate;

  @override
  Future<fc.FirebaseUser> updateDisplayName(String displayName) async {
    await gate.future;
    return fc.FirebaseUser(
      uid: 'central-uid-1',
      displayName: displayName,
      email: 'dana@example.com',
    );
  }
}

class _ThrowingSignOutSession extends fc.FirebaseAuthSession {
  _ThrowingSignOutSession({required super.apiKey, required super.httpClient});

  @override
  Future<void> signOut() async {
    throw const SocketException('sign-out unreachable');
  }
}

class _ListenerCountingSession extends fc.FirebaseAuthSession {
  _ListenerCountingSession({
    required super.apiKey,
    required super.httpClient,
    required super.clock,
  });

  int liveListeners = 0;

  @override
  Stream<fc.FirebaseUser?> get authStateChanges {
    final inner = super.authStateChanges;
    StreamSubscription<fc.FirebaseUser?>? sub;
    late final StreamController<fc.FirebaseUser?> controller;
    controller = StreamController<fc.FirebaseUser?>(
      onListen: () {
        liveListeners++;
        sub = inner.listen(
          controller.add,
          onError: controller.addError,
          onDone: controller.close,
        );
      },
      onCancel: () {
        liveListeners--;
        return sub?.cancel();
      },
    );
    return controller.stream;
  }
}

DesktopAuthService _service({
  int refreshStatus = 200,
  int callableStatus = 200,
  Map<String, Object?> callableBody = const {
    'result': {
      'customToken': 'custom-token-1',
      'profile': {
        'displayName': 'Dana Scout',
        'email': 'dana@example.com',
        'role': 'mentor',
      },
    },
  },
  int exchangeStatus = 200,
  http.Client? client,
  Future<fc.GoogleTokens> Function()? signInFlow,
}) {
  return DesktopAuthService(
    clientId: 'client-123',
    firebaseApiKey: 'app-key',
    centralApiKey: 'central-key',
    session: fc.FirebaseAuthSession(
      apiKey: 'app-key',
      httpClient: client ?? _firebaseBackend(refreshStatus: refreshStatus),
    ),
    signInFlow:
        signInFlow ??
        () async => const fc.GoogleTokens(idToken: 'google-id-token'),
    centralHttpClient:
        client ??
        _firebaseBackend(
          callableStatus: callableStatus,
          callableBody: callableBody,
          exchangeStatus: exchangeStatus,
        ),
  );
}

const _deniedCallable = <String, Object?>{
  'error': {'status': 'PERMISSION_DENIED', 'message': 'not approved'},
};

const _appSession = <String, Object>{
  'uid': 'central-uid-1',
  'displayName': 'Dana Scout',
  'email': 'dana@example.com',
  'refreshToken': 'refresh-1',
};

const _centralSession = <String, Object>{
  'uid': 'central-uid-1',
  'refreshToken': 'central-refresh-1',
};

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('signIn exchanges the Google token on the central project and mints an app session', () async {
    final service = _service();
    addTearDown(service.dispose);
    await service.signIn();

    expect(service.snapshot.state, SpectrumAuthState.signedIn);

    expect(service.currentUser?.uid, 'central-uid-1');
    expect(service.currentUser?.displayName, 'Dana Scout');

    expect(await service.idToken(), 'fb-token-refreshed');
  });

  test('signIn persists the app session for the next launch', () async {
    final service = _service();
    addTearDown(service.dispose);
    await service.signIn();

    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString('desktop_auth_session_v2');
    expect(stored, isNotNull);
    final decoded = jsonDecode(stored!) as Map<String, dynamic>;
    expect(decoded['uid'], 'central-uid-1');

    expect(decoded['refreshToken'], 'refresh-2');
  });

  test('updateDisplayName publishes and persists the new name', () async {
    final service = _service();
    addTearDown(service.dispose);
    await service.signIn();

    await service.updateDisplayName('Dana Renamed');

    expect(service.currentUser?.displayName, 'Dana Renamed');
    final prefs = await SharedPreferences.getInstance();
    final stored = jsonDecode(
      prefs.getString('desktop_auth_session_v2')!,
    ) as Map<String, dynamic>;
    expect(stored['displayName'], 'Dana Renamed');
  });

  test(
    'a rename landing after a sign-out does not restore the session',
    () async {
      final gate = Completer<void>();
      final session = _GatedRenameSession(
        apiKey: 'app-key',
        httpClient: _firebaseBackend(),
        gate: gate,
      );
      final service = DesktopAuthService(
        clientId: 'client-123',
        firebaseApiKey: 'app-key',
        centralApiKey: 'central-key',
        session: session,
        signInFlow: () async =>
            const fc.GoogleTokens(idToken: 'google-id-token'),
        centralHttpClient: _firebaseBackend(),
      );
      addTearDown(service.dispose);
      await service.signIn();

      final rename = service.updateDisplayName('Dana Renamed');
      await service.signOut();
      gate.complete();
      await rename;

      expect(service.snapshot.state, SpectrumAuthState.signedOut);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('desktop_auth_session_v2'), isNull);
    },
  );

  test('initialize restores a persisted session', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'desktop_auth_session_v2': jsonEncode({
        'uid': 'central-uid-1',
        'displayName': 'Dana Scout',
        'email': 'dana@example.com',
        'refreshToken': 'refresh-1',
      }),
    });
    final service = _service();
    addTearDown(service.dispose);
    await service.initialize();

    expect(service.snapshot.state, SpectrumAuthState.signedIn);
    expect(service.currentUser?.uid, 'central-uid-1');
    expect(await service.idToken(), 'fb-token-refreshed');
  });

  test('initialize drops a revoked session and stays signed out', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'desktop_auth_session_v2': jsonEncode({
        'uid': 'central-uid-1',
        'refreshToken': 'dead',
      }),
    });
    final backend = _firebaseBackend(refreshStatus: 400);
    final service = _service(client: backend);
    addTearDown(service.dispose);
    await service.initialize();

    expect(service.snapshot.state, SpectrumAuthState.signedOut);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('desktop_auth_session_v2'), isNull);
  });

  test('initialize drops a payload with a wrong-typed refresh token', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'desktop_auth_session_v2': jsonEncode({
        'uid': 'central-uid-1',
        'refreshToken': 12345,
      }),
    });
    final service = _service();
    addTearDown(service.dispose);
    final ended = <String>[];
    service.onSessionEnded = (uid) async => ended.add(uid);
    await service.initialize();

    expect(service.snapshot.state, SpectrumAuthState.signedOut);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('desktop_auth_session_v2'), isNull);

    expect(ended, <String>['central-uid-1']);
  });

  test('initialize stays signed in when the network fails', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'desktop_auth_session_v2': jsonEncode({
        'uid': 'central-uid-1',
        'refreshToken': 'refresh-1',
      }),
    });
    final service = DesktopAuthService(
      clientId: 'client-123',
      firebaseApiKey: 'app-key',
      centralApiKey: 'central-key',
      session: fc.FirebaseAuthSession(
        apiKey: 'app-key',
        httpClient: MockClient(
          (_) async => throw const SocketException('No route to host'),
        ),
      ),
      signInFlow: () async => const fc.GoogleTokens(idToken: 'google-id-token'),
    );
    addTearDown(service.dispose);
    await service.initialize();

    expect(service.snapshot.state, SpectrumAuthState.signedIn);
    expect(service.currentUser?.uid, 'central-uid-1');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('desktop_auth_session_v2'), isNotNull);
  });

  test('initialize drops a corrupt stored payload', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'desktop_auth_session_v2': 'not json at all',
    });
    final service = _service();
    addTearDown(service.dispose);
    await service.initialize();

    expect(service.snapshot.state, SpectrumAuthState.signedOut);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('desktop_auth_session_v2'), isNull);
  });

  test('signOut clears the session and the persisted copy', () async {
    final service = _service();
    addTearDown(service.dispose);
    await service.signIn();
    await service.signOut();

    expect(service.snapshot.state, SpectrumAuthState.signedOut);
    expect(await service.idToken(), isNull);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('desktop_auth_session_v2'), isNull);
  });

  test('signOut drops the data scoped to the user who left', () async {
    final service = _service();
    addTearDown(service.dispose);
    final ended = <String>[];
    service.onSessionEnded = (uid) async => ended.add(uid);
    await service.signIn();
    await service.signOut();

    expect(ended, <String>['central-uid-1']);
  });

  test('signOut completes when clearing the cached data fails', () async {
    final service = _service();
    addTearDown(service.dispose);
    service.onSessionEnded = (_) async =>
        throw const FileSystemException('locked');
    await service.signIn();
    await service.signOut();

    expect(service.snapshot.state, SpectrumAuthState.signedOut);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('desktop_auth_session_v2'), isNull);
  });

  test('a revoked session drops the data cached for it', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'desktop_auth_session_v2': jsonEncode({
        'uid': 'uid-gone',
        'refreshToken': 'refresh-1',
      }),
    });
    final backend = _firebaseBackend(refreshStatus: 400);
    final service = _service(client: backend);
    addTearDown(service.dispose);
    final ended = <String>[];
    service.onSessionEnded = (uid) async => ended.add(uid);
    await service.initialize();

    expect(service.snapshot.state, SpectrumAuthState.signedOut);
    expect(ended, <String>['uid-gone']);
  });

  test('signOut tears the session down exactly once', () async {
    final endedFor = <String>[];
    final service = _service();
    addTearDown(service.dispose);
    service.onSessionEnded = (uid) async => endedFor.add(uid);

    await service.initialize();
    await service.signIn();
    await service.signOut();
    await pumpEventQueue();

    expect(service.snapshot.state, SpectrumAuthState.signedOut);
    expect(endedFor, <String>['central-uid-1']);
  });

  test('a sign-out that throws still ends the session', () async {
    final endedFor = <String>[];
    final service = DesktopAuthService(
      clientId: 'client-123',
      firebaseApiKey: 'app-key',
      centralApiKey: 'central-key',
      session: _ThrowingSignOutSession(
        apiKey: 'app-key',
        httpClient: _firebaseBackend(),
      ),
      signInFlow: () async => const fc.GoogleTokens(idToken: 'google-id-token'),
      centralHttpClient: _firebaseBackend(),
    );
    addTearDown(service.dispose);
    service.onSessionEnded = (uid) async => endedFor.add(uid);

    await service.initialize();
    await service.signIn();
    await service.signOut();
    await pumpEventQueue();

    expect(service.snapshot.state, SpectrumAuthState.signedOut);
    expect(endedFor, <String>['central-uid-1']);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('desktop_auth_session_v2'), isNull);
  });

  test('the service still works after a sign-out that threw', () async {
    final endedFor = <String>[];
    final service = DesktopAuthService(
      clientId: 'client-123',
      firebaseApiKey: 'app-key',
      centralApiKey: 'central-key',
      session: _ThrowingSignOutSession(
        apiKey: 'app-key',
        httpClient: _firebaseBackend(),
      ),
      signInFlow: () async => const fc.GoogleTokens(idToken: 'google-id-token'),
      centralHttpClient: _firebaseBackend(),
    );
    addTearDown(service.dispose);
    service.onSessionEnded = (uid) async => endedFor.add(uid);

    await service.initialize();
    await service.signIn();
    await service.signOut();
    await pumpEventQueue();

    await service.signIn();
    expect(service.snapshot.state, SpectrumAuthState.signedIn);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('desktop_auth_session_v2'), isNotNull);
  });

  test('overlapping initialize calls leave one live subscription', () async {
    final endedFor = <String>[];
    var now = DateTime.utc(2026, 1, 1, 12);

    final session = _ListenerCountingSession(
      apiKey: 'app-key',
      httpClient: _refusingLaterRefreshes(),
      clock: () => now,
    );
    final service = DesktopAuthService(
      clientId: 'client-123',
      firebaseApiKey: 'app-key',
      centralApiKey: 'central-key',
      session: session,
      signInFlow: () async => const fc.GoogleTokens(idToken: 'google-id-token'),
      centralHttpClient: _firebaseBackend(),
    );
    addTearDown(service.dispose);
    service.onSessionEnded = (uid) async => endedFor.add(uid);

    await Future.wait(<Future<void>>[
      service.initialize(),
      service.initialize(),
      service.initialize(),
    ]);

    expect(session.liveListeners, 1);

    await service.signIn();
    now = now.add(const Duration(hours: 2));
    expect(await service.idToken(), isNull);
    await pumpEventQueue();

    expect(endedFor, <String>['central-uid-1']);
  });

  test('signing in during a teardown keeps the new session', () async {
    final releaseCleanup = Completer<void>();
    final service = _service();
    addTearDown(service.dispose);
    service.onSessionEnded = (_) => releaseCleanup.future;

    await service.initialize();
    await service.signIn();

    final signOut = service.signOut();
    await pumpEventQueue();

    final signIn = service.signIn();
    await pumpEventQueue();
    releaseCleanup.complete();
    await Future.wait(<Future<void>>[signOut, signIn]);

    expect(service.snapshot.state, SpectrumAuthState.signedIn);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('desktop_auth_session_v2'), isNotNull);
  });

  test('a failed sign-in flow emits a friendly error', () async {
    final service = DesktopAuthService(
      clientId: 'client-123',
      firebaseApiKey: 'app-key',
      centralApiKey: 'central-key',
      session: fc.FirebaseAuthSession(
        apiKey: 'app-key',
        httpClient: _firebaseBackend(),
      ),
      signInFlow: () async =>
          throw StateError('Sign-in was cancelled or denied.'),
      centralHttpClient: _firebaseBackend(),
    );
    addTearDown(service.dispose);
    await service.signIn();

    expect(service.snapshot.state, SpectrumAuthState.error);
    expect(service.snapshot.error, 'Sign-in was cancelled or denied.');
  });

  test('an unanticipated failure is named on the screen', () async {
    final service = _service(
      signInFlow: () async => throw const _UnexpectedFailure(),
    );
    addTearDown(service.dispose);
    await service.signIn();

    expect(service.snapshot.state, SpectrumAuthState.error);
    expect(
      service.snapshot.error,
      'Sign-in failed (_UnexpectedFailure). Please try again.',
    );
  });

  test('an unapproved account surfaces the approval error', () async {
    final service = _service(
      callableStatus: 403,
      callableBody: {
        'error': {
          'code': 403,
          'message': 'Account not approved.',
          'status': 'PERMISSION_DENIED',
        },
      },
    );
    addTearDown(service.dispose);
    await service.signIn();

    expect(service.snapshot.state, SpectrumAuthState.error);
    expect(service.snapshot.error, contains('not approved'));
    expect(service.currentUser, isNull);
  });

  test('an unregistered app surfaces the registration error', () async {
    final service = _service(
      callableStatus: 404,
      callableBody: {
        'error': {
          'code': 404,
          'message': 'No app registered for "spectrumstrategy".',
          'status': 'NOT_FOUND',
        },
      },
    );
    addTearDown(service.dispose);
    await service.signIn();

    expect(service.snapshot.state, SpectrumAuthState.error);
    expect(service.snapshot.error, contains('not registered'));
  });

  test(
    'a refused custom-token exchange surfaces an error, not a session',
    () async {
      final service = _service(exchangeStatus: 400);
      addTearDown(service.dispose);
      await service.signIn();

      expect(service.snapshot.state, SpectrumAuthState.error);
      expect(service.currentUser, isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('desktop_auth_session_v2'), isNull);
    },
  );

  test(
    'signIn still works through a TimeoutHttpClient-wrapped session',
    () async {
      final service = DesktopAuthService(
        clientId: 'client-123',
        firebaseApiKey: 'app-key',
        centralApiKey: 'central-key',
        session: fc.FirebaseAuthSession(
          apiKey: 'app-key',
          httpClient: TimeoutHttpClient(inner: _firebaseBackend()),
        ),
        signInFlow: () async =>
            const fc.GoogleTokens(idToken: 'google-id-token'),
        centralHttpClient: _firebaseBackend(),
      );
      addTearDown(service.dispose);

      await service.signIn();

      expect(service.snapshot.state, SpectrumAuthState.signedIn);
      expect(service.currentUser?.uid, 'central-uid-1');
    },
  );

  test(
    'initialize lands on signedOut when something unexpected throws',
    () async {
      final service = DesktopAuthService(
        clientId: 'client-123',
        firebaseApiKey: 'app-key',
        centralApiKey: 'central-key',
        session: fc.FirebaseAuthSession(
          apiKey: 'app-key',
          httpClient: _firebaseBackend(),
        ),
        signInFlow: () async =>
            const fc.GoogleTokens(idToken: 'google-id-token'),
        prefsLoader: () async => throw StateError('disk full'),
      );
      addTearDown(service.dispose);

      await service.initialize();

      expect(service.snapshot.state, isNot(SpectrumAuthState.unknown));
      expect(service.snapshot.state, SpectrumAuthState.signedOut);
    },
  );

  test(
    'a hung central sign-in gives up on its own deadline, not the transport',
    () async {
      final service = DesktopAuthService(
        clientId: 'client-123',
        firebaseApiKey: 'app-key',
        centralApiKey: 'central-key',
        session: fc.FirebaseAuthSession(
          apiKey: 'app-key',
          httpClient: _firebaseBackend(),
        ),
        signInFlow: () async =>
            const fc.GoogleTokens(idToken: 'google-id-token'),
        centralHttpClient: MockClient((_) => Completer<http.Response>().future),
        exchangeTimeout: const Duration(milliseconds: 50),
        customTokenTimeout: const Duration(seconds: 30),
      );
      addTearDown(service.dispose);

      await service.signIn().timeout(const Duration(seconds: 5));

      expect(service.snapshot.state, SpectrumAuthState.error);
      expect(service.currentUser, isNull);
    },
  );

  test(
    'a restore that times out leaves the user signed in, not signed out',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'desktop_auth_session_v2': jsonEncode({
          'uid': 'central-uid-1',
          'refreshToken': 'refresh-1',
        }),
      });
      final hangingBackend = MockClient(
        (_) => Completer<http.Response>().future,
      );
      final service = DesktopAuthService(
        clientId: 'client-123',
        firebaseApiKey: 'app-key',
        centralApiKey: 'central-key',
        session: fc.FirebaseAuthSession(
          apiKey: 'app-key',
          httpClient: TimeoutHttpClient(
            inner: hangingBackend,
            timeout: const Duration(milliseconds: 50),
          ),
        ),
        signInFlow: () async =>
            const fc.GoogleTokens(idToken: 'google-id-token'),
      );
      addTearDown(service.dispose);

      await service.initialize().timeout(const Duration(seconds: 2));

      expect(service.snapshot.state, SpectrumAuthState.signedIn);
      expect(service.currentUser?.uid, 'central-uid-1');
    },
  );

  test(
    'a hanging getCustomToken call ends in error instead of hanging sign-in',
    () async {
      final hangingCallable = MockClient((request) async {
        if (request.url.path.endsWith('/getCustomToken')) {
          return Completer<http.Response>().future;
        }
        if (request.url.path.contains('accounts:signInWithCustomToken')) {
          return http.Response(
            jsonEncode({
              'idToken': _idTokenFor('central-uid-1'),
              'refreshToken': 'refresh-1',
              'expiresIn': '3600',
            }),
            200,
          );
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
      final service = DesktopAuthService(
        clientId: 'client-123',
        firebaseApiKey: 'app-key',
        centralApiKey: 'central-key',
        session: fc.FirebaseAuthSession(
          apiKey: 'app-key',
          httpClient: _firebaseBackend(),
        ),
        signInFlow: () async =>
            const fc.GoogleTokens(idToken: 'google-id-token'),
        centralHttpClient: hangingCallable,
        customTokenTimeout: const Duration(milliseconds: 50),
      );
      addTearDown(service.dispose);

      await service.signIn().timeout(const Duration(seconds: 2));

      expect(service.snapshot.state, SpectrumAuthState.error);
    },
  );

  test(
    'a hanging custom-token exchange ends in error instead of hanging sign-in',
    () async {
      final hangingExchange = MockClient((request) async {
        if (request.url.path.contains('accounts:signInWithCustomToken')) {
          return Completer<http.Response>().future;
        }
        if (request.url.path.endsWith('/getCustomToken')) {
          return http.Response(
            jsonEncode({
              'result': {'customToken': 'custom-token-1'},
            }),
            200,
          );
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
      final service = DesktopAuthService(
        clientId: 'client-123',
        firebaseApiKey: 'app-key',
        centralApiKey: 'central-key',
        session: fc.FirebaseAuthSession(
          apiKey: 'app-key',
          httpClient: _firebaseBackend(),
        ),
        signInFlow: () async =>
            const fc.GoogleTokens(idToken: 'google-id-token'),
        centralHttpClient: hangingExchange,
        exchangeTimeout: const Duration(milliseconds: 50),
      );
      addTearDown(service.dispose);

      await service.signIn().timeout(const Duration(seconds: 2));

      expect(service.snapshot.state, SpectrumAuthState.error);
    },
  );

  group('desktop central approval re-check', () {
    test(
      'a session stored before the central key existed keeps working',
      () async {
        SharedPreferences.setMockInitialValues(<String, Object>{
          'desktop_auth_session_v2': jsonEncode(_appSession),
        });
        final service = _service(
          callableStatus: 403,
          callableBody: _deniedCallable,
        );
        addTearDown(service.dispose);
        await service.initialize();
        await pumpEventQueue();

        expect(service.snapshot.state, SpectrumAuthState.signedIn);
      },
    );

    test('a single denial keeps the member signed in', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'desktop_auth_session_v2': jsonEncode(_appSession),
        'desktop_central_session_v1': jsonEncode(_centralSession),
      });
      final service = _service(
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
        'desktop_auth_session_v2': jsonEncode(_appSession),
        'desktop_central_session_v1': jsonEncode(_centralSession),
        'central_approval_denials_v1': 1,
      });
      final service = _service(
        callableStatus: 403,
        callableBody: _deniedCallable,
      );
      addTearDown(service.dispose);
      await service.initialize();
      await pumpEventQueue();

      expect(service.snapshot.state, SpectrumAuthState.error);
      expect(service.snapshot.error, contains('not approved'));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('desktop_central_session_v1'), isNull);
    });

    test(
      'an unreachable central platform keeps the member signed in',
      () async {
        SharedPreferences.setMockInitialValues(<String, Object>{
          'desktop_auth_session_v2': jsonEncode(_appSession),
          'desktop_central_session_v1': jsonEncode(_centralSession),
        });
        final service = _service(
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

  test(
    'the default central http client is bounded, and covers a cold start',
    () {
      final source = File('lib/src/services/desktop_auth_service.dart')
          .readAsStringSync();
      expect(
        source.contains(
          'timeout: customTokenTimeout ?? _defaultCustomTokenTimeout',
        ),
        isTrue,
        reason:
            'the central http client default must carry the callable timeout',
      );
      expect(source.contains('centralHttpClient ?? http.Client()'), isFalse);
      expect(
        source.contains('centralHttpClient ?? TimeoutHttpClient()'),
        isFalse,
      );
    },
  );
}

class _UnexpectedFailure implements Exception {
  const _UnexpectedFailure();
}
