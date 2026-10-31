library;

import 'dart:convert';

import 'package:http/http.dart' as http;

class McpTool {
  const McpTool({
    required this.name,
    required this.description,
    required this.inputSchema,
    required this.readOnly,
    required this.scope,
  });

  factory McpTool.fromJson(Map<String, dynamic> json) {
    final annotations = (json['annotations'] as Map?)?.cast<String, dynamic>();
    final meta = (json['_meta'] as Map?)?.cast<String, dynamic>();
    return McpTool(
      name: json['name'] as String,
      description: json['description'] as String? ?? '',
      inputSchema:
          (json['inputSchema'] as Map?)?.cast<String, dynamic>() ??
          <String, dynamic>{
            'type': 'object',
            'properties': <String, dynamic>{},
          },

      readOnly: annotations?['readOnlyHint'] == true,
      scope: meta?['spectrum/scope'] as String?,
    );
  }

  final String name;
  final String description;
  final Map<String, dynamic> inputSchema;

  final bool readOnly;

  final String? scope;
}

class McpToolCallResult {
  const McpToolCallResult({required this.text, required this.isError});

  final String text;
  final bool isError;
}

class McpUnauthorizedException implements Exception {
  const McpUnauthorizedException();
}

class McpClient {
  McpClient({
    required this.endpoint,
    required this.protocolVersion,
    required this._accessTokenProvider,
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client();

  static const Duration requestTimeout = Duration(seconds: 20);

  final String endpoint;
  final String protocolVersion;
  final Future<String?> Function({bool forceRefresh}) _accessTokenProvider;
  final http.Client _http;

  int _nextId = 1;
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    await _request('initialize', <String, dynamic>{
      'protocolVersion': protocolVersion,
      'capabilities': <String, dynamic>{},
      'clientInfo': <String, dynamic>{
        'name': 'spectrum-strategy-desktop',
        'version': '1.0.0',
      },
    });
    _initialized = true;
  }

  Future<List<McpTool>> listTools() async {
    await initialize();
    final result = await _request('tools/list', const <String, dynamic>{});
    final tools = (result['tools'] as List?) ?? const <dynamic>[];
    return tools
        .map((tool) => McpTool.fromJson((tool as Map).cast<String, dynamic>()))
        .toList();
  }

  Future<McpToolCallResult> callTool(
    String name,
    Map<String, dynamic> arguments,
  ) async {
    await initialize();
    final result = await _request('tools/call', <String, dynamic>{
      'name': name,
      'arguments': arguments,
    });
    final blocks = (result['content'] as List?) ?? const <dynamic>[];
    final text = blocks
        .cast<Map>()
        .map((block) => block.cast<String, dynamic>())
        .where((block) => block['type'] == 'text')
        .map((block) => block['text'] as String? ?? '')
        .join('\n');
    return McpToolCallResult(text: text, isError: result['isError'] == true);
  }

  Future<Map<String, dynamic>> _request(
    String method,
    Map<String, dynamic> params,
  ) async {
    final id = _nextId++;
    final body = jsonEncode(<String, dynamic>{
      'jsonrpc': '2.0',
      'id': id,
      'method': method,
      'params': params,
    });

    Future<http.Response> send(String? token) => _http
        .post(
          Uri.parse(endpoint),
          headers: <String, String>{
            'Content-Type': 'application/json',
            'Accept': 'application/json, text/event-stream',
            'MCP-Protocol-Version': protocolVersion,
            if (token != null) 'Authorization': 'Bearer $token',
          },
          body: body,
        )
        .timeout(requestTimeout);

    var token = await _accessTokenProvider();
    var response = await send(token);
    if (response.statusCode == 401) {
      token = await _accessTokenProvider(forceRefresh: true);
      if (token == null) throw const McpUnauthorizedException();
      response = await send(token);
      if (response.statusCode == 401) throw const McpUnauthorizedException();
    }
    if (response.statusCode != 200) {
      throw StateError(
        '$method failed (${response.statusCode}): ${response.body}',
      );
    }

    final message = _parseMessage(response, id);
    final error = message['error'];
    if (error is Map) {
      final errorMap = error.cast<String, dynamic>();
      throw StateError(
        '$method returned an error: ${errorMap['message'] ?? errorMap}',
      );
    }
    return (message['result'] as Map?)?.cast<String, dynamic>() ??
        <String, dynamic>{};
  }

  Map<String, dynamic> _parseMessage(http.Response response, int id) {
    final contentType = response.headers['content-type'] ?? '';
    if (!contentType.contains('text/event-stream')) {
      return (jsonDecode(response.body) as Map).cast<String, dynamic>();
    }
    for (final event in response.body.split('\n\n')) {
      for (final line in event.split('\n')) {
        if (!line.startsWith('data:')) continue;
        final data = line.substring(5).trim();
        if (data.isEmpty) continue;
        final decoded = (jsonDecode(data) as Map).cast<String, dynamic>();
        if (decoded['id'] == id) return decoded;
      }
    }
    throw StateError('SSE response had no message for request id $id.');
  }
}
