library;

import 'dart:convert';

import 'package:http/http.dart' as http;

class OAuthProtectedResourceMetadata {
  const OAuthProtectedResourceMetadata({
    required this.resource,
    required this.scopesSupported,
  });

  factory OAuthProtectedResourceMetadata.fromJson(Map<String, dynamic> json) {
    return OAuthProtectedResourceMetadata(
      resource: json['resource'] as String? ?? '',
      scopesSupported:
          (json['scopes_supported'] as List?)?.cast<String>() ??
          const <String>[],
    );
  }

  final String resource;
  final List<String> scopesSupported;
}

class OAuthAuthorizationServerMetadata {
  const OAuthAuthorizationServerMetadata({
    required this.issuer,
    required this.authorizationEndpoint,
    required this.tokenEndpoint,
    this.registrationEndpoint,
  });

  factory OAuthAuthorizationServerMetadata.fromJson(Map<String, dynamic> json) {
    final authorizationEndpoint = json['authorization_endpoint'] as String?;
    final tokenEndpoint = json['token_endpoint'] as String?;
    if (authorizationEndpoint == null || tokenEndpoint == null) {
      throw const FormatException(
        'Authorization server metadata is missing authorization_endpoint '
        'or token_endpoint.',
      );
    }
    return OAuthAuthorizationServerMetadata(
      issuer: json['issuer'] as String? ?? '',
      authorizationEndpoint: authorizationEndpoint,
      tokenEndpoint: tokenEndpoint,
      registrationEndpoint: json['registration_endpoint'] as String?,
    );
  }

  final String issuer;
  final String authorizationEndpoint;
  final String tokenEndpoint;
  final String? registrationEndpoint;
}

class McpServerInfo {
  const McpServerInfo({
    required this.mcpEndpoint,
    required this.protocolVersion,
  });

  final String mcpEndpoint;
  final String protocolVersion;
}

class McpOAuthMetadataClient {
  McpOAuthMetadataClient({required this.baseUrl, http.Client? httpClient})
    : _http = httpClient ?? http.Client();

  final String baseUrl;
  final http.Client _http;

  Future<OAuthProtectedResourceMetadata>
  fetchProtectedResourceMetadata() async {
    final json = await _fetchJson(
      '$baseUrl/.well-known/oauth-protected-resource',
    );
    return OAuthProtectedResourceMetadata.fromJson(json);
  }

  Future<OAuthAuthorizationServerMetadata>
  fetchAuthorizationServerMetadata() async {
    final json = await _fetchJson(
      '$baseUrl/.well-known/oauth-authorization-server',
    );
    final metadata = OAuthAuthorizationServerMetadata.fromJson(json);

    final expected = Uri.parse(baseUrl);
    for (final url in <String?>[
      metadata.issuer.isEmpty ? null : metadata.issuer,
      metadata.authorizationEndpoint,
      metadata.tokenEndpoint,
      metadata.registrationEndpoint,
    ]) {
      if (url == null) continue;
      final parsed = Uri.tryParse(url);
      if (parsed == null || !_sameOrigin(parsed, expected)) {
        throw StateError(
          'Authorization server metadata points at $url, which is not on '
          '${expected.origin}. Refusing to send credentials there.',
        );
      }
    }
    return metadata;
  }

  static bool _sameOrigin(Uri a, Uri b) =>
      a.scheme == b.scheme && a.host == b.host && a.port == b.port;

  Future<McpServerInfo> fetchServerInfo() async {
    final json = await _fetchJson(baseUrl);
    final endpoint = json['mcp_endpoint'] as String?;
    final protocolVersion = json['protocol_version'] as String?;
    if (endpoint == null || endpoint.isEmpty) {
      throw const FormatException('Server root response had no mcp_endpoint.');
    }
    if (protocolVersion == null || protocolVersion.isEmpty) {
      throw const FormatException(
        'Server root response had no protocol_version.',
      );
    }
    return McpServerInfo(
      mcpEndpoint: endpoint,
      protocolVersion: protocolVersion,
    );
  }

  Future<Map<String, dynamic>> _fetchJson(String url) async {
    final response = await _http
        .get(Uri.parse(url))
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw StateError(
        'GET $url failed (${response.statusCode}): ${response.body}',
      );
    }
    return (jsonDecode(response.body) as Map).cast<String, dynamic>();
  }
}
