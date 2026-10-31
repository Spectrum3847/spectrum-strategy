import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:spectrumstrategy/src/services/mcp/mcp_oauth_redirect.dart';
import 'package:spectrumstrategy/src/services/mcp/mcp_oauth_service.dart';

const _baseUrl = 'https://spectrum-mcp-strategy.spectrum-3847.workers.dev';

String _expectedS256Challenge(String verifier) {
  final digest = sha256.convert(utf8.encode(verifier));
  return base64Url.encode(digest.bytes).replaceAll('=', '');
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('McpOAuthService', () {
    test(
      'not connected: accessToken is null without any network call',
      () async {
        final service = McpOAuthService(
          baseUrl: _baseUrl,
          httpClient: MockClient((request) async {
            fail('No network call should happen with no stored session.');
          }),
        );

        expect(await service.accessToken(), isNull);
        expect(service.isConnected, isFalse);
      },
    );

    test('connect() discovers endpoints, registers a client, and completes a '
        'correct PKCE S256 authorization-code exchange', () async {
      String? capturedCodeChallenge;
      String? capturedState;
      String? capturedRedirectUri;

      final mockClient = MockClient((request) async {
        if (request.url.path.endsWith('oauth-authorization-server')) {
          return http.Response(
            jsonEncode({
              'issuer': _baseUrl,
              'authorization_endpoint': '$_baseUrl/authorize',
              'token_endpoint': '$_baseUrl/token',
              'registration_endpoint': '$_baseUrl/register',
            }),
            200,
          );
        }
        if (request.url.path.endsWith('/register')) {
          return http.Response(
            jsonEncode({'client_id': 'registered-client-id'}),
            201,
          );
        }
        if (request.url.path.endsWith('/token')) {
          final body = Uri.splitQueryString(request.body);
          expect(body['grant_type'], 'authorization_code');
          expect(body['client_id'], 'registered-client-id');
          expect(body['code'], 'the-auth-code');

          expect(
            _expectedS256Challenge(body['code_verifier']!),
            capturedCodeChallenge,
          );
          return http.Response(
            jsonEncode({
              'access_token': 'access-1',
              'refresh_token': 'refresh-1',
              'expires_in': 3600,
            }),
            200,
          );
        }
        fail('Unexpected request to ${request.url}');
      });

      final service = McpOAuthService(
        baseUrl: _baseUrl,
        httpClient: mockClient,
        redirect: LoopbackMcpRedirect(
          launch: (url) async {
            capturedCodeChallenge = url.queryParameters['code_challenge'];
            capturedState = url.queryParameters['state'];
            capturedRedirectUri = url.queryParameters['redirect_uri'];
            expect(url.queryParameters['code_challenge_method'], 'S256');
            expect(url.queryParameters['scope'], 'spectrum:read');
            expect(url.queryParameters['client_id'], 'registered-client-id');

            await http.get(
              Uri.parse(capturedRedirectUri!).replace(
                queryParameters: {
                  'code': 'the-auth-code',
                  'state': capturedState,
                },
              ),
            );
          },
        ),
      );

      await service.connect();

      expect(service.isConnected, isTrue);
      expect(service.lastError, isNull);
      expect(await service.accessToken(), 'access-1');
    });

    test('disconnect() clears a stored session', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'mcp_strategy_oauth_v1': jsonEncode({
          'clientId': 'c1',
          'tokenEndpoint': '$_baseUrl/token',
          'accessToken': 'access-1',
          'refreshToken': 'refresh-1',
          'expiresAt': DateTime.now()
              .add(const Duration(hours: 1))
              .toIso8601String(),
        }),
      });
      final service = McpOAuthService(
        baseUrl: _baseUrl,
        httpClient: MockClient((request) async => http.Response('', 500)),
      );
      await service.loadStoredState();
      expect(service.isConnected, isTrue);

      await service.disconnect();

      expect(service.isConnected, isFalse);
      expect(await service.accessToken(), isNull);
    });
  });
}
