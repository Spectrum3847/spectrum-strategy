import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:spectrumstrategy/src/services/mcp/mcp_oauth_metadata.dart';

void main() {
  group('McpOAuthMetadataClient', () {
    const baseUrl = 'https://spectrum-mcp-strategy.spectrum-3847.workers.dev';

    test('discovers protected-resource metadata', () async {
      final client = McpOAuthMetadataClient(
        baseUrl: baseUrl,
        httpClient: MockClient((request) async {
          expect(
            request.url.toString(),
            '$baseUrl/.well-known/oauth-protected-resource',
          );
          return http.Response(
            '{"resource":"$baseUrl","scopes_supported":["spectrum:read"]}',
            200,
          );
        }),
      );

      final metadata = await client.fetchProtectedResourceMetadata();
      expect(metadata.resource, baseUrl);
      expect(metadata.scopesSupported, ['spectrum:read']);
    });

    test('refuses endpoints that are not on the server origin', () async {
      for (final field in [
        'authorization_endpoint',
        'token_endpoint',
        'registration_endpoint',
      ]) {
        final client = McpOAuthMetadataClient(
          baseUrl: baseUrl,
          httpClient: MockClient((request) async {
            final body = <String, String>{
              'issuer': baseUrl,
              'authorization_endpoint': '$baseUrl/authorize',
              'token_endpoint': '$baseUrl/token',
              'registration_endpoint': '$baseUrl/register',
            };
            body[field] = 'https://attacker.example/steal';
            return http.Response(jsonEncode(body), 200);
          }),
        );

        await expectLater(
          client.fetchAuthorizationServerMetadata(),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              contains('attacker.example'),
            ),
          ),
          reason: '$field must not be able to point off-origin',
        );
      }
    });

    test('discovers authorization-server metadata', () async {
      final client = McpOAuthMetadataClient(
        baseUrl: baseUrl,
        httpClient: MockClient((request) async {
          expect(
            request.url.toString(),
            '$baseUrl/.well-known/oauth-authorization-server',
          );
          return http.Response(
            '{"issuer":"$baseUrl",'
            '"authorization_endpoint":"$baseUrl/authorize",'
            '"token_endpoint":"$baseUrl/token",'
            '"registration_endpoint":"$baseUrl/register",'
            '"scopes_supported":["spectrum:read","spectrum:write"]}',
            200,
          );
        }),
      );

      final metadata = await client.fetchAuthorizationServerMetadata();
      expect(metadata.issuer, baseUrl);
      expect(metadata.authorizationEndpoint, '$baseUrl/authorize');
      expect(metadata.tokenEndpoint, '$baseUrl/token');
      expect(metadata.registrationEndpoint, '$baseUrl/register');
    });

    test('reads the mcp endpoint and protocol version off GET /', () async {
      final client = McpOAuthMetadataClient(
        baseUrl: baseUrl,
        httpClient: MockClient((request) async {
          expect(request.url.toString(), baseUrl);
          return http.Response(
            '{"name":"spectrum-mcp-strategy",'
            '"mcp_endpoint":"$baseUrl/mcp",'
            '"protocol_version":"2026-07-28"}',
            200,
          );
        }),
      );

      final info = await client.fetchServerInfo();
      expect(info.mcpEndpoint, '$baseUrl/mcp');
      expect(info.protocolVersion, '2026-07-28');
    });

    test('a non-200 response throws', () async {
      final client = McpOAuthMetadataClient(
        baseUrl: baseUrl,
        httpClient: MockClient((request) async {
          return http.Response('not found', 404);
        }),
      );

      expect(client.fetchServerInfo(), throwsA(isA<StateError>()));
    });
  });
}
