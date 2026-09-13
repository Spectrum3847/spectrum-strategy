import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firestore_client/firestore_client.dart' as fc;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../ui/platform_target.dart';
import 'mcp_oauth_metadata.dart';
import 'mcp_oauth_redirect.dart';

class McpOAuthService extends ChangeNotifier {
  factory McpOAuthService({
    required String baseUrl,
    http.Client? httpClient,
    Future<SharedPreferences> Function()? prefsLoader,
    McpRedirect? redirect,
  }) {
    final resolvedHttpClient = httpClient ?? http.Client();
    return McpOAuthService._(
      baseUrl: baseUrl,
      httpClient: resolvedHttpClient,
      redirect: redirect ?? defaultRedirect(),
      prefsLoader: prefsLoader ?? SharedPreferences.getInstance,
    );
  }

  static McpRedirect defaultRedirect() => isDesktopPlatform
      ? LoopbackMcpRedirect(launch: _defaultLaunch)
      : const WebAuthMcpRedirect();

  McpOAuthService._({
    required this.baseUrl,
    required http.Client httpClient,
    required this._redirect,
    required this._prefsLoader,
  }) : _http = httpClient,
       _metadata = McpOAuthMetadataClient(
         baseUrl: baseUrl,
         httpClient: httpClient,
       );

  static final McpOAuthService shared = McpOAuthService(
    baseUrl: baseUrlDefault,
  );

  static const String baseUrlDefault =
      'https://spectrum-mcp-strategy.spectrum-3847.workers.dev';

  static const String _prefsKey = 'mcp_strategy_oauth_v1';
  static const String _scope = 'spectrum:read';

  final String baseUrl;
  final http.Client _http;
  final McpRedirect _redirect;
  final Future<SharedPreferences> Function() _prefsLoader;
  final McpOAuthMetadataClient _metadata;

  bool _connected = false;
  String? _error;
  bool _connecting = false;

  bool get isConnected => _connected;
  bool get isConnecting => _connecting;
  String? get lastError => _error;

  Future<void> loadStoredState() async {
    final stored = await _readStored();
    _connected = stored != null;
    notifyListeners();
  }

  Future<void> connect() async {
    _connecting = true;
    _error = null;
    notifyListeners();
    try {
      final asMetadata = await _metadata.fetchAuthorizationServerMetadata();
      final verifier = fc.GoogleDesktopOAuth.randomToken(64);
      final state = fc.GoogleDesktopOAuth.randomToken(24);

      var clientId = '';
      var redirectUri = '';
      final code = await _redirect.authorize(
        state: state,
        buildAuthorizeUrl: (uri) async {
          redirectUri = uri;
          clientId = await _registerClient(asMetadata, uri);
          return Uri.parse(asMetadata.authorizationEndpoint).replace(
            queryParameters: <String, String>{
              'response_type': 'code',
              'client_id': clientId,
              'redirect_uri': uri,
              'scope': _scope,
              'state': state,
              'code_challenge': fc.GoogleDesktopOAuth.codeChallengeFor(
                verifier,
              ),
              'code_challenge_method': 'S256',
            },
          );
        },
      );

      final tokens = await _exchangeCode(
        tokenEndpoint: asMetadata.tokenEndpoint,
        clientId: clientId,
        code: code,
        codeVerifier: verifier,
        redirectUri: redirectUri,
      );

      await _store(
        _StoredSession(
          clientId: clientId,
          tokenEndpoint: asMetadata.tokenEndpoint,
          accessToken: tokens.accessToken,
          refreshToken: tokens.refreshToken,
          expiresAt: tokens.expiresAt,
        ),
      );
      _connected = true;
    } catch (error) {
      _error = _friendly(error);
      _connected = false;
    } finally {
      _connecting = false;
      notifyListeners();
    }
  }

  Future<void> disconnect() async {
    try {
      final prefs = await _prefsLoader();
      await prefs.remove(_prefsKey);
    } catch (_) {}
    _connected = false;
    _error = null;
    notifyListeners();
  }

  Future<String?> accessToken({bool forceRefresh = false}) async {
    final stored = await _readStored();
    if (stored == null) return null;
    if (!forceRefresh && !stored.isExpired) return stored.accessToken;
    final refreshToken = stored.refreshToken;
    if (refreshToken == null) return forceRefresh ? null : stored.accessToken;
    try {
      final tokens = await _exchangeRefreshToken(
        tokenEndpoint: stored.tokenEndpoint,
        clientId: stored.clientId,
        refreshToken: refreshToken,
      );
      final next = _StoredSession(
        clientId: stored.clientId,
        tokenEndpoint: stored.tokenEndpoint,
        accessToken: tokens.accessToken,
        refreshToken: tokens.refreshToken ?? refreshToken,
        expiresAt: tokens.expiresAt,
      );
      await _store(next);
      return next.accessToken;
    } catch (_) {
      await disconnect();
      return null;
    }
  }

  Future<String> _registerClient(
    OAuthAuthorizationServerMetadata metadata,
    String redirectUri,
  ) async {
    final registrationEndpoint = metadata.registrationEndpoint;
    if (registrationEndpoint == null) {
      throw StateError('Server has no dynamic client registration endpoint.');
    }
    final response = await _postWithTimeout(
      Uri.parse(registrationEndpoint),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode(<String, dynamic>{
        'client_name': 'Spectrum Strategy (desktop)',
        'redirect_uris': <String>[redirectUri],
        'grant_types': <String>['authorization_code', 'refresh_token'],
        'response_types': <String>['code'],
        'token_endpoint_auth_method': 'none',
      }),
    );
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw StateError(
        'Client registration failed (${response.statusCode}): '
        '${response.body}',
      );
    }
    final body = (jsonDecode(response.body) as Map).cast<String, dynamic>();
    final clientId = body['client_id'] as String?;
    if (clientId == null || clientId.isEmpty) {
      throw StateError('Client registration response had no client_id.');
    }
    return clientId;
  }

  static const Duration _httpTimeout = Duration(seconds: 20);

  Future<http.Response> _postWithTimeout(
    Uri url, {
    required Map<String, String> headers,
    required Object body,
  }) => _http.post(url, headers: headers, body: body).timeout(_httpTimeout);

  Future<_TokenResponse> _exchangeCode({
    required String tokenEndpoint,
    required String clientId,
    required String code,
    required String codeVerifier,
    required String redirectUri,
  }) => _tokenRequest(tokenEndpoint, <String, String>{
    'grant_type': 'authorization_code',
    'client_id': clientId,
    'code': code,
    'code_verifier': codeVerifier,
    'redirect_uri': redirectUri,
  });

  Future<_TokenResponse> _exchangeRefreshToken({
    required String tokenEndpoint,
    required String clientId,
    required String refreshToken,
  }) => _tokenRequest(tokenEndpoint, <String, String>{
    'grant_type': 'refresh_token',
    'client_id': clientId,
    'refresh_token': refreshToken,
  });

  Future<_TokenResponse> _tokenRequest(
    String tokenEndpoint,
    Map<String, String> body,
  ) async {
    final response = await _postWithTimeout(
      Uri.parse(tokenEndpoint),
      headers: const {'Content-Type': 'application/x-www-form-urlencoded'},
      body: body,
    );
    if (response.statusCode != 200) {
      throw StateError(
        'Token request failed (${response.statusCode}): ${response.body}',
      );
    }
    final data = (jsonDecode(response.body) as Map).cast<String, dynamic>();
    final accessToken = data['access_token'] as String?;
    if (accessToken == null || accessToken.isEmpty) {
      throw StateError('Token response had no access_token.');
    }
    final expiresIn = data['expires_in'];
    return _TokenResponse(
      accessToken: accessToken,
      refreshToken: data['refresh_token'] as String?,
      expiresAt: DateTime.now().add(
        Duration(seconds: expiresIn is int ? expiresIn : 3600),
      ),
    );
  }

  Future<_StoredSession?> _readStored() async {
    try {
      final prefs = await _prefsLoader();
      final raw = prefs.getString(_prefsKey);
      if (raw == null) return null;
      return _StoredSession.fromJson(
        (jsonDecode(raw) as Map).cast<String, dynamic>(),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _store(_StoredSession session) async {
    final prefs = await _prefsLoader();
    await prefs.setString(_prefsKey, jsonEncode(session.toJson()));
  }

  static Future<void> _defaultLaunch(Uri url) async {
    await launchUrl(url, mode: LaunchMode.externalApplication);
  }

  String _friendly(Object error) {
    if (error is StateError) return error.message;
    if (error is FormatException) return error.message;
    if (error is SocketException) {
      return 'Could not reach the Spectrum MCP server. Check your connection.';
    }
    return 'Connecting to the Spectrum MCP server failed (${error.runtimeType}).';
  }
}

class _TokenResponse {
  const _TokenResponse({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
  });

  final String accessToken;
  final String? refreshToken;
  final DateTime expiresAt;
}

class _StoredSession {
  const _StoredSession({
    required this.clientId,
    required this.tokenEndpoint,
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
  });

  factory _StoredSession.fromJson(Map<String, dynamic> json) => _StoredSession(
    clientId: json['clientId'] as String,
    tokenEndpoint: json['tokenEndpoint'] as String,
    accessToken: json['accessToken'] as String,
    refreshToken: json['refreshToken'] as String?,
    expiresAt: DateTime.parse(json['expiresAt'] as String),
  );

  final String clientId;
  final String tokenEndpoint;
  final String accessToken;
  final String? refreshToken;
  final DateTime expiresAt;

  bool get isExpired =>
      DateTime.now().isAfter(expiresAt.subtract(const Duration(minutes: 1)));

  Map<String, dynamic> toJson() => <String, dynamic>{
    'clientId': clientId,
    'tokenEndpoint': tokenEndpoint,
    'accessToken': accessToken,
    'refreshToken': refreshToken,
    'expiresAt': expiresAt.toIso8601String(),
  };
}
