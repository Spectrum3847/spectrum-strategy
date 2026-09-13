import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart'
    show FirebaseFunctionsException;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart'
    show debugPrint, defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'central_approval_check.dart';
import 'central_auth_client.dart';
import 'central_platform_config.dart';
import 'central_rest_auth_client.dart';

const Set<String> _popupBlockedAuthCodes = {
  'popup-blocked',
  'popup-blocked-by-user',
  'cancelled-popup-request',
  'operation-not-supported-in-this-environment',
};

bool isPopupBlockedAuthError(Object error) {
  return error is FirebaseAuthException &&
      _popupBlockedAuthCodes.contains(error.code);
}

bool isPopupPersistenceAuthError(Object error) {
  return error.toString().contains('Database is closing/hidden');
}

bool isGoogleSignInTransportError(Object error) {
  return error is GoogleSignInException &&
      error.code != GoogleSignInExceptionCode.canceled &&
      error.code != GoogleSignInExceptionCode.interrupted;
}

class SpectrumUser {
  const SpectrumUser({
    required this.uid,
    required this.displayName,
    this.email,
    this.photoUrl,
  });

  final String uid;
  final String displayName;
  final String? email;
  final String? photoUrl;
}

enum SpectrumAuthState { unknown, signedOut, signingIn, signedIn, error }

class SpectrumAuthSnapshot {
  const SpectrumAuthSnapshot({required this.state, this.user, this.error});

  final SpectrumAuthState state;
  final SpectrumUser? user;
  final String? error;
}

abstract class SpectrumAuthService {
  Stream<SpectrumAuthSnapshot> get snapshotStream;
  SpectrumAuthSnapshot get snapshot;
  SpectrumUser? get currentUser;
  Future<void> initialize();

  Future<String?> idToken();

  Future<void> signIn();

  Future<void> updateDisplayName(String displayName);

  Future<void> signOut();
  Future<void> dispose();
}

class FirebaseSpectrumAuthService implements SpectrumAuthService {
  FirebaseSpectrumAuthService({
    FirebaseAuth? appAuth,
    this._centralAuth,
    GoogleSignIn? googleSignIn,
    this._centralClient,
    this._centralRest,
    String? appKey,
    CentralApprovalCheck? approvalCheck,
    Duration? approvalRetryInterval,
    Future<SharedPreferences> Function()? prefsLoader,
  }) : _appAuth = appAuth ?? FirebaseAuth.instance,
       _googleSignIn = googleSignIn ?? GoogleSignIn.instance,
       _appKey = appKey ?? spectrumAppKey,
       _approvalCheck = approvalCheck ?? CentralApprovalCheck(),
       _approvalRetryInterval =
           approvalRetryInterval ?? centralApprovalRetryInterval,
       _prefsLoader = prefsLoader ?? SharedPreferences.getInstance;

  final FirebaseAuth _appAuth;

  final FirebaseAuth? _centralAuth;
  final GoogleSignIn _googleSignIn;

  final CentralAuthClient? _centralClient;

  final CentralRestAuthClient? _centralRest;
  final String _appKey;
  final CentralApprovalCheck _approvalCheck;
  final Duration _approvalRetryInterval;
  final Future<SharedPreferences> Function() _prefsLoader;
  Timer? _approvalRetryTimer;
  bool _approvalRecheckInFlight = false;

  static const Duration _centralSignInTimeout = Duration(seconds: 20);

  static const String _centralPrefsKey = 'mobile_central_session_v1';

  bool _disposed = false;

  CentralProfile? _centralProfile;

  final StreamController<SpectrumAuthSnapshot> _controller =
      StreamController<SpectrumAuthSnapshot>.broadcast();

  SpectrumAuthSnapshot _snapshot = const SpectrumAuthSnapshot(
    state: SpectrumAuthState.unknown,
  );
  StreamSubscription<User?>? _authStateSubscription;
  bool _googleInitialized = false;
  Future<void>? _resumeFuture;

  @override
  Stream<SpectrumAuthSnapshot> get snapshotStream => _controller.stream;

  @override
  SpectrumAuthSnapshot get snapshot => _snapshot;

  @override
  SpectrumUser? get currentUser => _snapshot.user;

  @override
  Future<String?> idToken() async {
    final user = _appAuth.currentUser;
    if (user == null) return null;
    try {
      return await user.getIdToken();
    } on FirebaseAuthException catch (e) {
      if (e.code == 'network-request-failed') return null;
      rethrow;
    } on SocketException {
      return null;
    } on TimeoutException {
      return null;
    }
  }

  @override
  Future<void> initialize() async {
    try {
      if (!kIsWeb && !_googleInitialized) {
        try {
          await _googleSignIn.initialize();
          _googleInitialized = true;
        } catch (error) {
          debugPrint('google_sign_in.initialize() failed: $error');
        }
      }

      await _authStateSubscription?.cancel();

      if (kIsWeb) {
        try {
          await _centralAuth?.getRedirectResult();
        } catch (_) {}
        try {
          await _appAuth.getRedirectResult();
        } catch (_) {}
      }
      _authStateSubscription = _appAuth.authStateChanges().listen((user) {
        if (user == null) {
          if (_snapshot.state != SpectrumAuthState.signingIn) {
            _emit(
              const SpectrumAuthSnapshot(state: SpectrumAuthState.signedOut),
            );
          }
        } else {
          _emit(
            SpectrumAuthSnapshot(
              state: SpectrumAuthState.signedIn,
              user: _userFrom(user),
            ),
          );
        }
      });
      var existing = _appAuth.currentUser;
      if (existing != null && isPrePlatformSession(existing)) {
        debugPrint('Dropping pre-platform session for ${existing.uid}');
        await _appAuth.signOut();
        existing = null;
      }
      if (existing != null) {
        _emit(
          SpectrumAuthSnapshot(
            state: SpectrumAuthState.signedIn,
            user: _userFrom(existing),
          ),
        );

        unawaited(_recheckCentralApproval());
      } else {
        _emit(const SpectrumAuthSnapshot(state: SpectrumAuthState.signedOut));

        unawaited(_resumeFromCentralSession());
      }
    } catch (error) {
      debugPrint('Auth initialize failed: $error');
      _emit(
        SpectrumAuthSnapshot(
          state: SpectrumAuthState.error,
          error: _friendlyAuthError(error),
        ),
      );
    }
  }

  static bool isPrePlatformSession(User user) =>
      user.providerData.any((info) => info.providerId == 'google.com');

  Future<void> _recheckCentralApproval() async {
    if (_disposed) return;
    if (_approvalRecheckInFlight) return;
    if (!await _approvalCheck.isDue()) return;
    _approvalRecheckInFlight = true;
    try {
      if (_centralRest != null) {
        await _recheckCentralApprovalMobile();
      } else {
        await _recheckCentralApprovalWeb();
      }
    } finally {
      _approvalRecheckInFlight = false;
    }
  }

  Future<void> _recheckCentralApprovalWeb() async {
    final client = _centralClient;
    final central = _centralAuth;

    if (client == null || central == null || central.currentUser == null) {
      return;
    }
    try {
      final handshake = await client.handshake(_appKey);

      if (_disposed) return;
      _centralProfile = handshake.profile;
      _cancelApprovalRetry();
      await _approvalCheck.markChecked();
    } on FirebaseFunctionsException catch (error) {
      if (classifyCentralAuthError(error.code) ==
          CentralAuthErrorKind.notApproved) {
        final denials = await _approvalCheck.recordDenial();
        if (_disposed) return;
        if (denials < CentralApprovalCheck.denialsBeforeSignOut) {
          _cancelApprovalRetry();
          debugPrint('Central approval denied ($denials); deferring.');
          return;
        }
        _cancelApprovalRetry();
        debugPrint('Central approval revoked; signing out.');
        await signOut();
        _emit(
          SpectrumAuthSnapshot(
            state: SpectrumAuthState.error,
            error: _friendlyCentralError(CentralAuthErrorKind.notApproved),
          ),
        );
        return;
      }

      debugPrint('Central approval re-check deferred: ${error.code}');
      _scheduleApprovalRetry();
    } catch (error) {
      debugPrint('Central approval re-check deferred: $error');
      _scheduleApprovalRetry();
    }
  }

  Future<void> _recheckCentralApprovalMobile() async {
    final rest = _centralRest;
    if (rest == null) return;
    if (_appAuth.currentUser == null) return;
    final prefs = await _prefsLoader();
    final outcome = await runCentralApprovalRecheck(
      client: rest,
      approvalCheck: _approvalCheck,
      prefs: prefs,
      centralPrefsKey: _centralPrefsKey,
      appKey: _appKey,
    );

    if (_disposed) return;
    switch (outcome) {
      case CentralRecheckOutcome.noStoredSession:
      case CentralRecheckOutcome.approved:
        _cancelApprovalRetry();
        break;
      case CentralRecheckOutcome.deniedPending:
        _cancelApprovalRetry();
        debugPrint('Central approval denied; deferring.');
        break;
      case CentralRecheckOutcome.tokenUnavailable:
      case CentralRecheckOutcome.deferred:
        _scheduleApprovalRetry();
        break;
      case CentralRecheckOutcome.sessionRevoked:
      case CentralRecheckOutcome.deniedFinal:
        _cancelApprovalRetry();
        debugPrint('Central approval revoked; signing out.');
        await signOut();
        _emit(
          SpectrumAuthSnapshot(
            state: SpectrumAuthState.error,
            error: _friendlyCentralError(CentralAuthErrorKind.notApproved),
          ),
        );
        break;
    }
  }

  void _scheduleApprovalRetry() {
    if (_disposed) return;
    if (_approvalRetryTimer != null) return;
    _approvalRetryTimer = Timer.periodic(_approvalRetryInterval, (_) {
      if (_appAuth.currentUser == null) {
        _cancelApprovalRetry();
        return;
      }
      unawaited(_recheckCentralApproval());
    });
  }

  void _cancelApprovalRetry() {
    _approvalRetryTimer?.cancel();
    _approvalRetryTimer = null;
  }

  Future<void> _resumeFromCentralSession() async {
    final inFlight = _resumeFuture;
    if (inFlight != null) return inFlight;
    final future = _doResume();
    _resumeFuture = future;
    try {
      await future;
    } finally {
      _resumeFuture = null;
    }
  }

  Future<void> _doResume() async {
    final central = _centralAuth;
    final client = _centralClient;
    if (central == null || client == null) return;
    if (central.currentUser == null) return;
    if (_appAuth.currentUser != null) return;
    try {
      await _signInFromCentral(client);
    } catch (error) {
      debugPrint('Central session resume failed: $error');
      _emit(
        SpectrumAuthSnapshot(
          state: SpectrumAuthState.error,
          error: error is FirebaseFunctionsException
              ? _friendlyCentralError(classifyCentralAuthError(error.code))
              : error is CentralAuthException
              ? _friendlyCentralError(error.kind)
              : _friendlyAuthError(error),
        ),
      );
    }
  }

  @override
  Future<void> signIn() async {
    _emit(const SpectrumAuthSnapshot(state: SpectrumAuthState.signingIn));
    try {
      if (_centralRest != null) {
        await _signInMobile();
      } else {
        await _signInWeb();
      }
    } on FirebaseFunctionsException catch (error) {
      debugPrint('Central handshake failed: ${error.code} ${error.message}');
      _emit(
        SpectrumAuthSnapshot(
          state: SpectrumAuthState.error,
          error: _friendlyCentralError(classifyCentralAuthError(error.code)),
        ),
      );
    } on CentralAuthException catch (error) {
      debugPrint('Central handshake failed: $error');
      _emit(
        SpectrumAuthSnapshot(
          state: SpectrumAuthState.error,
          error: _friendlyCentralError(error.kind),
        ),
      );
    } catch (error) {
      debugPrint('Sign-in failed: $error');
      _emit(
        SpectrumAuthSnapshot(
          state: SpectrumAuthState.error,
          error: _friendlyAuthError(error),
        ),
      );
    }
  }

  Future<void> _signInWeb() async {
    final central = _centralAuth;
    final client = _centralClient;
    if (central == null || client == null) {
      throw StateError(
        'Central sign-in is not configured in this build '
        '(missing SPECTRUM_APP_KEY or central Firebase app).',
      );
    }

    if (kIsWeb) {
      try {
        await central.signInWithPopup(GoogleAuthProvider());
      } catch (popupError) {
        if (!isPopupBlockedAuthError(popupError) &&
            !isPopupPersistenceAuthError(popupError)) {
          rethrow;
        }
        debugPrint('Popup sign-in failed, trying redirect: $popupError');
        await central.signInWithRedirect(GoogleAuthProvider());

        return;
      }
    } else {
      try {
        final account = await _googleSignIn.authenticate();
        final auth = account.authentication;
        final idToken = auth.idToken;
        if (idToken == null) {
          throw StateError('Google sign-in returned no ID token.');
        }
        final credential = GoogleAuthProvider.credential(idToken: idToken);
        await central.signInWithCredential(credential);
      } catch (signInError) {
        final isAndroid = defaultTargetPlatform == TargetPlatform.android;
        if (!isAndroid || !isGoogleSignInTransportError(signInError)) {
          rethrow;
        }
        debugPrint(
          'google_sign_in failed, trying signInWithProvider: $signInError',
        );
        await central.signInWithProvider(GoogleAuthProvider());
      }
    }

    await _signInFromCentral(client);
  }

  Future<void> _signInMobile() async {
    final rest = _centralRest;
    if (rest == null) {
      throw StateError(
        'Central sign-in is not configured in this build '
        '(missing SPECTRUM_APP_KEY or central Firebase app).',
      );
    }
    String googleIdToken;
    try {
      final account = await _googleSignIn.authenticate();
      final idToken = account.authentication.idToken;
      if (idToken == null) {
        throw StateError('Google sign-in returned no ID token.');
      }
      googleIdToken = idToken;
    } catch (signInError) {
      if (defaultTargetPlatform != TargetPlatform.android ||
          !isGoogleSignInTransportError(signInError)) {
        rethrow;
      }
      debugPrint(
        'google_sign_in failed, trying signInWithProvider: $signInError',
      );
      googleIdToken = await _googleIdTokenViaProvider();
    }

    await rest
        .signInWithGoogleIdToken(googleIdToken)
        .timeout(_centralSignInTimeout);

    await _signInFromCentral(rest);

    final prefs = await _prefsLoader();
    await prefs.setString(_centralPrefsKey, jsonEncode(rest.toJson()));
  }

  Future<String> _googleIdTokenViaProvider() async {
    final scratch = await Firebase.initializeApp(
      name: 'fireos-oauth',
      options: Firebase.app().options,
    );
    try {
      final auth = FirebaseAuth.instanceFor(app: scratch);
      final credential = await auth.signInWithProvider(GoogleAuthProvider());
      final raw = credential.credential;
      final idToken = raw is OAuthCredential ? raw.idToken : null;
      await auth.signOut();
      if (idToken == null) {
        throw StateError('Google sign-in returned no ID token.');
      }
      return idToken;
    } finally {
      await scratch.delete();
    }
  }

  Future<void> _signInFromCentral(CentralAuthClient client) async {
    final handshake = await client.handshake(_appKey);
    _centralProfile = handshake.profile;
    final appCredential = await _appAuth.signInWithCustomToken(
      handshake.customToken,
    );
    final user = appCredential.user;
    if (user == null) {
      throw StateError('Custom-token sign-in returned no user.');
    }

    final centralName = handshake.profile?.displayName;
    if (centralName != null &&
        centralName.isNotEmpty &&
        (user.displayName == null || user.displayName!.isEmpty)) {
      try {
        await user.updateDisplayName(centralName);
        await user.reload();
      } catch (error) {
        debugPrint('Could not persist the central display name: $error');
      }
    }

    _cancelApprovalRetry();
    await _approvalCheck.markChecked();
    _emit(
      SpectrumAuthSnapshot(
        state: SpectrumAuthState.signedIn,
        user: _userFrom(user),
      ),
    );
  }

  static String _friendlyCentralError(CentralAuthErrorKind kind) {
    switch (kind) {
      case CentralAuthErrorKind.notApproved:
        return 'Your account is not approved yet. Ask an admin to approve '
            'you in Spectrum Tasks.';
      case CentralAuthErrorKind.appNotRegistered:
        return 'Spectrum Strategy is not registered with the team platform '
            'yet. Ask an admin to register it in SpectrumAdmin.';
      case CentralAuthErrorKind.unknown:
        return 'Could not reach the team sign-in service. Check your '
            'connection and try again.';
    }
  }

  static String _errorCode(Object error) {
    if (error is FirebaseAuthException) return error.code;
    if (error is GoogleSignInException) return error.code.name;
    if (error is CentralAuthException) return errorKindName(error.kind);
    if (error is TimeoutException) return 'timeout';
    if (error is SocketException) return 'network';

    return error.runtimeType.toString();
  }

  static String _friendlyAuthError(Object error) {
    if (error is GoogleSignInException &&
        error.code == GoogleSignInExceptionCode.canceled) {
      return 'Sign-in was cancelled.';
    }
    if (error is FirebaseAuthException) {
      switch (error.code) {
        case 'network-request-failed':
          return 'Network error. Check your connection and try again.';
        case 'popup-closed-by-user':
        case 'cancelled-popup-request':
        case 'user-cancelled':
          return 'Sign-in was cancelled.';
        case 'account-exists-with-different-credential':
          return 'An account already exists with a different sign-in method.';
        case 'operation-not-allowed':
          return 'Google sign-in is not enabled for this app.';
        case 'unauthorized-domain':
          return 'This site is not authorized for sign-in. Contact an admin.';
        case 'popup-blocked-by-user':
          return 'The sign-in popup was blocked by your browser. Please allow popups for this site and try again.';
        case 'invalid-custom-token':
        case 'custom-token-mismatch':
          return 'Sign-in session expired or invalid. Please try again.';
      }
    }
    if (error is StateError) return error.message;
    return 'Sign-in failed (${_errorCode(error)}). Please try again.';
  }

  @override
  Future<void> updateDisplayName(String displayName) async {
    final user = _appAuth.currentUser;
    if (user == null) {
      throw StateError('No user is signed in.');
    }
    await user.updateDisplayName(displayName);

    final centralUser = _centralAuth?.currentUser;
    if (centralUser != null && centralUser.displayName != displayName) {
      try {
        await centralUser.updateDisplayName(displayName);
      } catch (error) {
        debugPrint('Central display-name update failed: $error');
      }
    }

    await user.reload();
    final refreshed = _appAuth.currentUser;

    if (refreshed == null || refreshed.uid != user.uid) return;
    _emit(
      SpectrumAuthSnapshot(
        state: SpectrumAuthState.signedIn,
        user: _userFrom(refreshed),
      ),
    );
  }

  @override
  Future<void> signOut() async {
    _cancelApprovalRetry();
    _centralProfile = null;

    await _approvalCheck.clear();
    if (!kIsWeb) {
      try {
        await _googleSignIn.signOut();
      } catch (_) {}
    }

    try {
      await _centralAuth?.signOut();
    } catch (_) {}
    try {
      await _centralRest?.signOut();
    } catch (_) {}
    if (_centralRest != null) {
      try {
        final prefs = await _prefsLoader();
        await prefs.remove(_centralPrefsKey);
      } catch (_) {}
    }
    try {
      await _appAuth.signOut();
    } catch (_) {}
    _emit(const SpectrumAuthSnapshot(state: SpectrumAuthState.signedOut));
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    _cancelApprovalRetry();
    await _authStateSubscription?.cancel();
    await _controller.close();
    _centralRest?.close();
  }

  SpectrumUser _userFrom(User user) {
    final central = _centralProfile;
    final sessionName = user.displayName;
    final sessionEmail = user.email;
    return SpectrumUser(
      uid: user.uid,
      displayName: sessionName != null && sessionName.isNotEmpty
          ? sessionName
          : (central?.displayName ?? ''),
      email: sessionEmail != null && sessionEmail.isNotEmpty
          ? sessionEmail
          : central?.email,
      photoUrl: user.photoURL ?? central?.photoUrl,
    );
  }

  void _emit(SpectrumAuthSnapshot next) {
    _snapshot = next;
    if (!_controller.isClosed) {
      _controller.add(next);
    }
  }
}
