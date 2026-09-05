import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firestore_client/firestore_client.dart' as fc;
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'central_approval_check.dart';
import 'central_auth_client.dart';
import 'central_platform_config.dart';
import 'central_rest_auth_client.dart';
import 'http_timeout_client.dart';
import 'spectrum_auth_service.dart';

class DesktopAuthService implements SpectrumAuthService {
  DesktopAuthService({
    required this.clientId,
    required this.firebaseApiKey,
    required this.centralApiKey,
    this.centralFunctionsBaseUrl = defaultCentralFunctionsBaseUrl,
    String? appKey,
    this.clientSecret = '',
    Future<void> Function(Uri url)? launch,
    fc.FirebaseAuthSession? session,
    Future<fc.GoogleTokens> Function()? signInFlow,
    Future<SharedPreferences> Function()? prefsLoader,
    http.Client? centralHttpClient,
    Duration? customTokenTimeout,
    Duration? exchangeTimeout,
    CentralApprovalCheck? approvalCheck,
    Duration? approvalRetryInterval,
  }) : _session = session ?? fc.FirebaseAuthSession(apiKey: firebaseApiKey),
       _prefsLoader = prefsLoader ?? SharedPreferences.getInstance,
       _customTokenTimeout = customTokenTimeout ?? _defaultCustomTokenTimeout,

       _centralHttp =
           centralHttpClient ??
           TimeoutHttpClient(
             timeout: customTokenTimeout ?? _defaultCustomTokenTimeout,
           ),
       _ownsCentralHttp = centralHttpClient == null,
       _appKey = appKey ?? spectrumAppKey,
       _exchangeTimeout = exchangeTimeout ?? _defaultExchangeTimeout,
       _approvalCheck = approvalCheck ?? CentralApprovalCheck(),
       _approvalRetryInterval =
           approvalRetryInterval ?? centralApprovalRetryInterval {
    _signInFlow =
        signInFlow ??
        () => fc.GoogleDesktopOAuth(
          clientId: clientId,
          clientSecret: clientSecret,
          launcher: launch ?? _noLauncher,
        ).signIn();

    _centralRest = CentralRestAuthClient(
      centralApiKey: centralApiKey,
      centralFunctionsBaseUrl: centralFunctionsBaseUrl,
      httpClient: _centralHttp,
      customTokenTimeout: _customTokenTimeout,
    );
  }

  static const String _prefsKey = 'desktop_auth_session_v2';

  static const String _legacyPrefsKey = 'desktop_auth_session_v1';

  static const String _centralPrefsKey = 'desktop_central_session_v1';

  static const Duration _defaultCustomTokenTimeout = Duration(seconds: 90);

  static const Duration _defaultExchangeTimeout = Duration(seconds: 20);

  Future<void> Function(String uid)? onSessionEnded;

  final String clientId;
  final String firebaseApiKey;

  final String centralApiKey;

  final String centralFunctionsBaseUrl;

  final String clientSecret;

  final String _appKey;
  final fc.FirebaseAuthSession _session;
  late final CentralRestAuthClient _centralRest;
  final http.Client _centralHttp;
  final bool _ownsCentralHttp;
  final Duration _customTokenTimeout;
  final Duration _exchangeTimeout;
  final CentralApprovalCheck _approvalCheck;
  final Duration _approvalRetryInterval;
  Timer? _approvalRetryTimer;
  bool _approvalRecheckInFlight = false;

  bool _disposed = false;
  final Future<SharedPreferences> Function() _prefsLoader;
  late final Future<fc.GoogleTokens> Function() _signInFlow;

  StreamSubscription<fc.FirebaseUser?>? _authStateSub;

  Future<void>? _listenerSetup;

  bool _endingSession = false;

  Future<void>? _teardown;

  final StreamController<SpectrumAuthSnapshot> _controller =
      StreamController<SpectrumAuthSnapshot>.broadcast();

  SpectrumAuthSnapshot _snapshot = const SpectrumAuthSnapshot(
    state: SpectrumAuthState.unknown,
  );

  @override
  Stream<SpectrumAuthSnapshot> get snapshotStream => _controller.stream;

  @override
  SpectrumAuthSnapshot get snapshot => _snapshot;

  @override
  SpectrumUser? get currentUser => _snapshot.user;

  @override
  Future<String?> idToken() async {
    try {
      return await _session.getIdToken();
    } on SocketException {
      return null;
    } on TimeoutException {
      return null;
    } on http.ClientException {
      return null;
    } on HttpException {
      return null;
    }
  }

  Future<void> _ensureAuthStateListener() {
    final previous = _listenerSetup;
    final next = () async {
      try {
        await previous;
        await _authStateSub?.cancel();
        _authStateSub = _session.authStateChanges.listen((user) {
          if (user == null) unawaited(_handleSessionRevoked());
        });
      } catch (error) {
        debugPrint('Desktop auth listener setup failed: $error');
      }
    }();
    _listenerSetup = next;
    return next;
  }

  @override
  Future<void> initialize() async {
    try {
      await _ensureAuthStateListener();
      final prefs = await _prefsLoader();
      final stored = prefs.getString(_prefsKey);
      if (stored == null) {
        _emit(const SpectrumAuthSnapshot(state: SpectrumAuthState.signedOut));
        return;
      }
      final Map<String, dynamic> payload;
      try {
        payload = (jsonDecode(stored) as Map).cast<String, dynamic>();
      } catch (_) {
        await prefs.remove(_prefsKey);
        _emit(const SpectrumAuthSnapshot(state: SpectrumAuthState.signedOut));
        return;
      }

      final uid = payload['uid'];
      final refreshToken = payload['refreshToken'];
      if (uid is! String ||
          uid.isEmpty ||
          refreshToken is! String ||
          refreshToken.isEmpty) {
        await prefs.remove(_prefsKey);
        if (uid is String && uid.isNotEmpty) await _endSession(uid);
        _emit(const SpectrumAuthSnapshot(state: SpectrumAuthState.signedOut));
        return;
      }
      final user = await _session.restore(payload);
      if (user != null) {
        _emit(
          SpectrumAuthSnapshot(
            state: SpectrumAuthState.signedIn,
            user: _toSpectrumUser(user),
          ),
        );

        unawaited(_recheckCentralApproval(prefs));
      } else {
        await prefs.remove(_prefsKey);
        final revokedUid = payload['uid'];

        if (revokedUid is String &&
            revokedUid.isNotEmpty &&
            _snapshot.state != SpectrumAuthState.signedIn) {
          await _endSession(revokedUid);
        }
        _emit(const SpectrumAuthSnapshot(state: SpectrumAuthState.signedOut));
      }
    } catch (error) {
      debugPrint('Desktop session restore failed: $error');
      _emit(const SpectrumAuthSnapshot(state: SpectrumAuthState.signedOut));
    }
  }

  @override
  Future<void> signIn() async {
    await _teardown;
    _emit(const SpectrumAuthSnapshot(state: SpectrumAuthState.signingIn));
    try {
      final tokens = await _signInFlow();

      final centralUser = await _centralRest
          .signInWithGoogleIdToken(tokens.idToken)
          .timeout(_exchangeTimeout);

      final handshake = await _centralRest.handshake(_appKey);

      final exchange = await _exchangeCustomToken(handshake.customToken);
      final uid = _uidFromIdToken(exchange.idToken);
      final user = await _session.restore({
        'uid': uid,
        'displayName':
            handshake.profile?.displayName ?? centralUser.displayName,
        'email': handshake.profile?.email ?? centralUser.email,
        'photoUrl': handshake.profile?.photoUrl ?? centralUser.photoUrl,
        'refreshToken': exchange.refreshToken,
      });
      if (user == null) {
        throw StateError('Custom-token sign-in was refused.');
      }

      final prefs = await _prefsLoader();

      await prefs.setString(_prefsKey, jsonEncode(_session.toJson()));
      await prefs.setString(
        _centralPrefsKey,
        jsonEncode(_centralRest.toJson()),
      );
      await prefs.remove(_legacyPrefsKey);

      _cancelApprovalRetry();
      await _approvalCheck.markChecked();
      _emit(
        SpectrumAuthSnapshot(
          state: SpectrumAuthState.signedIn,
          user: _toSpectrumUser(user),
        ),
      );
    } catch (error) {
      debugPrint('Desktop sign-in failed: $error');
      _emit(
        SpectrumAuthSnapshot(
          state: SpectrumAuthState.error,
          error: _friendly(error),
        ),
      );
    }
  }

  @override
  Future<void> updateDisplayName(String displayName) async {
    final before = currentUser?.uid;
    final user = await _session.updateDisplayName(displayName);

    if (currentUser?.uid != before) return;

    try {
      final prefs = await _prefsLoader();
      await prefs.setString(_prefsKey, jsonEncode(_session.toJson()));
    } catch (_) {}
    _emit(
      SpectrumAuthSnapshot(
        state: SpectrumAuthState.signedIn,
        user: _toSpectrumUser(user),
      ),
    );
  }

  @override
  Future<void> signOut() async {
    _endingSession = true;
    _cancelApprovalRetry();

    await _approvalCheck.clear();
    final departingUid = currentUser?.uid;
    try {
      await _session.signOut();
    } catch (error) {
      debugPrint('Desktop sign-out could not reach the server: $error');
    }

    try {
      await _centralRest.signOut();
    } catch (_) {}
    try {
      final prefs = await _prefsLoader();
      await prefs.remove(_centralPrefsKey);
    } catch (_) {}
    await _runTeardown(departingUid);
    _emit(const SpectrumAuthSnapshot(state: SpectrumAuthState.signedOut));
  }

  Future<void> _handleSessionRevoked() async {
    if (_endingSession) return;
    if (_snapshot.state != SpectrumAuthState.signedIn) return;
    final departingUid = currentUser?.uid;
    _emit(const SpectrumAuthSnapshot(state: SpectrumAuthState.signedOut));
    await _runTeardown(departingUid);
  }

  Future<void> _runTeardown(String? uid) {
    _endingSession = true;
    final previous = _teardown;
    late final Future<void> done;
    done = () async {
      try {
        try {
          await previous;
        } catch (_) {}
        await _forgetStoredSession();
        if (uid != null) await _endSession(uid);
      } finally {
        if (identical(_teardown, done)) _endingSession = false;
      }
    }();
    _teardown = done;
    return done;
  }

  Future<void> _forgetStoredSession() async {
    try {
      final prefs = await _prefsLoader();
      await prefs.remove(_prefsKey);
    } catch (_) {}
  }

  Future<void> _endSession(String uid) async {
    try {
      await onSessionEnded?.call(uid);
    } catch (_) {}
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    _cancelApprovalRetry();

    await _listenerSetup;
    await _authStateSub?.cancel();
    _authStateSub = null;
    await _controller.close();
    _session.close();
    _centralRest.close();
    if (_ownsCentralHttp) {
      _centralHttp.close();
    }
  }

  static SpectrumUser _toSpectrumUser(fc.FirebaseUser user) => SpectrumUser(
    uid: user.uid,
    displayName: user.displayName,
    email: user.email,
    photoUrl: user.photoUrl,
  );

  static Future<void> _noLauncher(Uri url) async {
    throw UnsupportedError('No URL launcher was provided.');
  }

  Future<void> _recheckCentralApproval(SharedPreferences prefs) async {
    if (_disposed) return;
    if (_approvalRecheckInFlight) return;
    if (!await _approvalCheck.isDue()) return;
    _approvalRecheckInFlight = true;
    try {
      final outcome = await runCentralApprovalRecheck(
        client: _centralRest,
        approvalCheck: _approvalCheck,
        prefs: prefs,
        centralPrefsKey: _centralPrefsKey,
        appKey: _appKey,
      );
      switch (outcome) {
        case CentralRecheckOutcome.noStoredSession:
        case CentralRecheckOutcome.approved:
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
          await _revokeForCentral(prefs, 'central session was revoked');
          break;
        case CentralRecheckOutcome.deniedFinal:
          await _revokeForCentral(prefs, 'central approval revoked');
          break;
      }
    } finally {
      _approvalRecheckInFlight = false;
    }
  }

  Future<void> _revokeForCentral(SharedPreferences prefs, String reason) async {
    _cancelApprovalRetry();
    debugPrint('Desktop session ended: $reason.');
    await prefs.remove(_centralPrefsKey);
    await _approvalCheck.clear();
    await signOut();
    _emit(
      const SpectrumAuthSnapshot(
        state: SpectrumAuthState.error,
        error:
            'Your account is not approved yet. Ask an admin to approve you in '
            'Spectrum Tasks.',
      ),
    );
  }

  void _scheduleApprovalRetry() {
    if (_disposed) return;
    if (_approvalRetryTimer != null) return;
    _approvalRetryTimer = Timer.periodic(_approvalRetryInterval, (_) async {
      if (_snapshot.state != SpectrumAuthState.signedIn) {
        _cancelApprovalRetry();
        return;
      }
      unawaited(_recheckCentralApproval(await _prefsLoader()));
    });
  }

  void _cancelApprovalRetry() {
    _approvalRetryTimer?.cancel();
    _approvalRetryTimer = null;
  }

  Future<({String idToken, String refreshToken})> _exchangeCustomToken(
    String customToken,
  ) async {
    final response = await _centralHttp
        .post(
          Uri.parse(
            'https://identitytoolkit.googleapis.com/v1/accounts:signInWithCustomToken'
            '?key=$firebaseApiKey',
          ),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({'token': customToken, 'returnSecureToken': true}),
        )
        .timeout(_exchangeTimeout);
    final Map<String, dynamic> body;
    try {
      body = (jsonDecode(response.body) as Map).cast<String, dynamic>();
    } catch (_) {
      throw fc.FirebaseAuthException(response.statusCode, response.body);
    }
    if (response.statusCode != 200) {
      final error = (body['error'] as Map?)?.cast<String, dynamic>();
      throw fc.FirebaseAuthException(
        response.statusCode,
        (error?['message'] as String?) ?? response.body,
      );
    }
    final idToken = body['idToken'] as String?;
    final refreshToken = body['refreshToken'] as String?;
    if (idToken == null || refreshToken == null) {
      throw fc.FirebaseAuthException(
        response.statusCode,
        'Custom-token exchange response was missing fields.',
      );
    }
    return (idToken: idToken, refreshToken: refreshToken);
  }

  static String _uidFromIdToken(String idToken) {
    final parts = idToken.split('.');
    if (parts.length != 3) {
      throw StateError('Custom-token exchange returned a malformed ID token.');
    }
    final normalized = base64Url.normalize(parts[1]);
    final claims = (jsonDecode(
      utf8.decode(base64Url.decode(normalized)),
    ) as Map).cast<String, dynamic>();
    final uid = claims['user_id'] as String? ?? claims['sub'] as String?;
    if (uid == null || uid.isEmpty) {
      throw StateError(
        'Custom-token exchange returned an ID token with no uid.',
      );
    }
    return uid;
  }

  String _friendly(Object error) {
    if (error is CentralAuthException) {
      switch (error.kind) {
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
    if (error is StateError) return error.message;
    if (error is fc.FirebaseAuthException) {
      return 'Sign-in failed (${error.message}).';
    }
    if (error is SocketException) {
      return 'Could not reach Google or Firebase. Check your connection.';
    }
    if (error is TimeoutException) {
      return 'Could not reach the team sign-in service. Check your '
          'connection and try again.';
    }

    return 'Sign-in failed (${error.runtimeType}). Please try again.';
  }

  void _emit(SpectrumAuthSnapshot next) {
    _snapshot = next;
    if (!_controller.isClosed) _controller.add(next);
  }
}
