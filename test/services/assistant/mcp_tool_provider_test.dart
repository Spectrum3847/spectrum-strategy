import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:spectrumstrategy/src/services/assistant/mcp_tool_provider.dart';
import 'package:spectrumstrategy/src/services/mcp/mcp_oauth_service.dart';

const _baseUrl = 'https://spectrum-mcp-strategy.spectrum-3847.workers.dev';

http.Response _rpc(String body, int id, Map<String, dynamic> result) =>
    http.Response(
      jsonEncode({'jsonrpc': '2.0', 'id': id, 'result': result}),
      200,
    );

void _seedConnectedSession() {
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
}

void main() {
  group('McpAssistantToolProvider', () {
    test(
      'not connected: tools() returns an empty list without throwing',
      () async {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        final oauth = McpOAuthService(
          baseUrl: _baseUrl,
          httpClient: MockClient((request) async {
            fail('No network call expected with no stored session.');
          }),
        );
        final provider = McpAssistantToolProvider(
          baseUrl: _baseUrl,
          oauth: oauth,
        );

        expect(await provider.tools(), isEmpty);
      },
    );

    test('connected: tools/list maps into AssistantToolSpec, mcp_-prefixed, '
        'write and unannotated tools filtered out', () async {
      _seedConnectedSession();
      final oauth = McpOAuthService(
        baseUrl: _baseUrl,
        httpClient: MockClient(
          (request) async => http.Response('should not be called', 500),
        ),
      );
      final provider = McpAssistantToolProvider(
        baseUrl: _baseUrl,
        oauth: oauth,
        httpClient: MockClient((request) async {
          if (request.method == 'GET') {
            return http.Response(
              jsonEncode({
                'name': 'spectrum-mcp-strategy',
                'mcp_endpoint': '$_baseUrl/mcp',
                'protocol_version': '2026-07-28',
              }),
              200,
            );
          }
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          final id = body['id'] as int;
          if (body['method'] == 'initialize') return _rpc(request.body, id, {});
          expect(body['method'], 'tools/list');
          return _rpc(request.body, id, {
            'tools': [
              {
                'name': 'whoami',
                'description': 'Who am I',
                'inputSchema': {'type': 'object', 'properties': {}},
                'annotations': {'readOnlyHint': true},
                '_meta': {'spectrum/scope': 'spectrum:read'},
              },
              {
                'name': 'create_document',
                'description': 'Create a document',
                'inputSchema': {'type': 'object', 'properties': {}},
                'annotations': {'readOnlyHint': false},
                '_meta': {'spectrum/scope': 'spectrum:write'},
              },
              {
                'name': 'some_future_tool',
                'description': 'No annotations at all',
                'inputSchema': {'type': 'object', 'properties': {}},
              },
            ],
          });
        }),
      );

      final tools = await provider.tools();

      expect(tools, hasLength(1));
      expect(tools.single.name, 'mcp_whoami');
      expect(tools.single.description, 'Who am I');
    });

    test('call() flattens the result and marks it untrusted', () async {
      _seedConnectedSession();
      final oauth = McpOAuthService(
        baseUrl: _baseUrl,
        httpClient: MockClient(
          (request) async => http.Response('should not be called', 500),
        ),
      );
      final provider = McpAssistantToolProvider(
        baseUrl: _baseUrl,
        oauth: oauth,
        httpClient: MockClient((request) async {
          if (request.method == 'GET') {
            return http.Response(
              jsonEncode({
                'mcp_endpoint': '$_baseUrl/mcp',
                'protocol_version': '2026-07-28',
              }),
              200,
            );
          }
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          final id = body['id'] as int;
          if (body['method'] == 'initialize') return _rpc(request.body, id, {});
          if (body['method'] == 'tools/list') {
            return _rpc(request.body, id, {
              'tools': [
                {
                  'name': 'whoami',
                  'description': 'Who am I',
                  'inputSchema': {'type': 'object', 'properties': {}},
                  'annotations': {'readOnlyHint': true},
                  '_meta': {'spectrum/scope': 'spectrum:read'},
                },
              ],
            });
          }
          expect(body['method'], 'tools/call');
          return _rpc(request.body, id, {
            'content': [
              {'type': 'text', 'text': 'uid: abc123'},
            ],
            'isError': false,
          });
        }),
      );

      final result = await provider.call('mcp_whoami', {});

      expect(result, contains('untrusted'));
      expect(result, contains('uid: abc123'));
    });

    test('an isError result comes back as readable text', () async {
      _seedConnectedSession();
      final oauth = McpOAuthService(
        baseUrl: _baseUrl,
        httpClient: MockClient(
          (request) async => http.Response('should not be called', 500),
        ),
      );
      final provider = McpAssistantToolProvider(
        baseUrl: _baseUrl,
        oauth: oauth,
        httpClient: MockClient((request) async {
          if (request.method == 'GET') {
            return http.Response(
              jsonEncode({
                'mcp_endpoint': '$_baseUrl/mcp',
                'protocol_version': '2026-07-28',
              }),
              200,
            );
          }
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          final id = body['id'] as int;
          if (body['method'] == 'initialize') return _rpc(request.body, id, {});
          if (body['method'] == 'tools/list') {
            return _rpc(request.body, id, {
              'tools': [
                {
                  'name': 'whoami',
                  'description': 'Who am I',
                  'inputSchema': {'type': 'object', 'properties': {}},
                  'annotations': {'readOnlyHint': true},
                  '_meta': {'spectrum/scope': 'spectrum:read'},
                },
              ],
            });
          }
          return _rpc(request.body, id, {
            'content': [
              {'type': 'text', 'text': 'not signed in'},
            ],
            'isError': true,
          });
        }),
      );

      final result = await provider.call('mcp_whoami', {});

      expect(result, contains('error'));
      expect(result, contains('not signed in'));
    });
  });
}
