import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:spectrumstrategy/src/services/mcp/mcp_client.dart';

http.Response _jsonRpcResponse(int id, Map<String, dynamic> result) {
  return http.Response(
    jsonEncode({'jsonrpc': '2.0', 'id': id, 'result': result}),
    200,
  );
}

http.Response _sseResponse(int id, Map<String, dynamic> result) {
  final message = jsonEncode({'jsonrpc': '2.0', 'id': id, 'result': result});
  return http.Response(
    'event: message\ndata: $message\n\n',
    200,
    headers: {'content-type': 'text/event-stream'},
  );
}

void main() {
  group('McpClient', () {
    test('tools/list maps into McpTool', () async {
      var requestId = 0;
      final client = McpClient(
        endpoint: 'https://example.test/mcp',
        protocolVersion: '2026-07-28',
        accessTokenProvider: ({bool forceRefresh = false}) async => 'tok',
        httpClient: MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          requestId = body['id'] as int;
          if (body['method'] == 'initialize') {
            return _jsonRpcResponse(requestId, {});
          }
          expect(body['method'], 'tools/list');
          return _jsonRpcResponse(requestId, {
            'tools': [
              {
                'name': 'whoami',
                'description': 'Who am I',
                'inputSchema': {'type': 'object', 'properties': {}},
              },
            ],
          });
        }),
      );

      final tools = await client.listTools();
      expect(tools, hasLength(1));
      expect(tools.single.name, 'whoami');
      expect(tools.single.description, 'Who am I');
      expect(tools.single.inputSchema['type'], 'object');
    });

    test('tools/call flattens text content blocks', () async {
      final client = McpClient(
        endpoint: 'https://example.test/mcp',
        protocolVersion: '2026-07-28',
        accessTokenProvider: ({bool forceRefresh = false}) async => 'tok',
        httpClient: MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          final id = body['id'] as int;
          if (body['method'] == 'initialize') return _jsonRpcResponse(id, {});
          return _jsonRpcResponse(id, {
            'content': [
              {'type': 'text', 'text': 'line one'},
              {'type': 'text', 'text': 'line two'},
            ],
            'isError': false,
          });
        }),
      );

      final result = await client.callTool('whoami', {});
      expect(result.text, 'line one\nline two');
      expect(result.isError, isFalse);
    });

    test(
      'an isError result comes back as text, not a thrown exception',
      () async {
        final client = McpClient(
          endpoint: 'https://example.test/mcp',
          protocolVersion: '2026-07-28',
          accessTokenProvider: ({bool forceRefresh = false}) async => 'tok',
          httpClient: MockClient((request) async {
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            final id = body['id'] as int;
            if (body['method'] == 'initialize') return _jsonRpcResponse(id, {});
            return _jsonRpcResponse(id, {
              'content': [
                {'type': 'text', 'text': 'permission denied'},
              ],
              'isError': true,
            });
          }),
        );

        final result = await client.callTool('create_document', {});
        expect(result.isError, isTrue);
        expect(result.text, 'permission denied');
      },
    );

    test('an SSE-framed response parses the same as plain JSON', () async {
      final client = McpClient(
        endpoint: 'https://example.test/mcp',
        protocolVersion: '2026-07-28',
        accessTokenProvider: ({bool forceRefresh = false}) async => 'tok',
        httpClient: MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          final id = body['id'] as int;
          if (body['method'] == 'initialize') return _sseResponse(id, {});
          return _sseResponse(id, {
            'content': [
              {'type': 'text', 'text': 'sse ok'},
            ],
            'isError': false,
          });
        }),
      );

      final result = await client.callTool('whoami', {});
      expect(result.text, 'sse ok');
    });

    test('a 401 refreshes the token and retries once', () async {
      var callCount = 0;
      var refreshed = false;
      final client = McpClient(
        endpoint: 'https://example.test/mcp',
        protocolVersion: '2026-07-28',
        accessTokenProvider: ({bool forceRefresh = false}) async {
          if (forceRefresh) refreshed = true;
          return forceRefresh ? 'fresh-tok' : 'stale-tok';
        },
        httpClient: MockClient((request) async {
          callCount++;
          final auth = request.headers['Authorization'];
          if (auth == 'Bearer stale-tok') {
            return http.Response('unauthorized', 401);
          }
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          final id = body['id'] as int;
          return _jsonRpcResponse(id, {'tools': []});
        }),
      );

      final tools = await client.listTools();
      expect(tools, isEmpty);
      expect(refreshed, isTrue);

      expect(callCount, 4);
    });

    test('a 401 with no refreshed token available throws', () async {
      final client = McpClient(
        endpoint: 'https://example.test/mcp',
        protocolVersion: '2026-07-28',
        accessTokenProvider: ({bool forceRefresh = false}) async =>
            forceRefresh ? null : 'stale-tok',
        httpClient: MockClient(
          (request) async => http.Response('unauthorized', 401),
        ),
      );

      expect(client.initialize(), throwsA(isA<McpUnauthorizedException>()));
    });
  });
}
