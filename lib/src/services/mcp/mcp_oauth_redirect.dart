library;

import 'dart:async';
import 'dart:io';

import 'package:apple_web_auth/apple_web_auth.dart';

abstract class McpRedirect {
  Future<String> authorize({
    required Future<Uri> Function(String redirectUri) buildAuthorizeUrl,
    required String state,
  });
}

class LoopbackMcpRedirect implements McpRedirect {
  LoopbackMcpRedirect({required this.launch, this.timeout = _defaultTimeout});

  static const Duration _defaultTimeout = Duration(minutes: 5);

  final Future<void> Function(Uri url) launch;
  final Duration timeout;

  @override
  Future<String> authorize({
    required Future<Uri> Function(String redirectUri) buildAuthorizeUrl,
    required String state,
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    try {
      final authorizeUrl = await buildAuthorizeUrl(
        'http://127.0.0.1:${server.port}/callback',
      );

      final code = _await(server, state);
      try {
        await launch(authorizeUrl);
      } catch (_) {
        unawaited(code.catchError((_) => ''));
        rethrow;
      }
      return await code;
    } finally {
      await server.close(force: true);
    }
  }

  Future<String> _await(HttpServer server, String state) =>
      _read(server, state).timeout(
        timeout,
        onTimeout: () => throw TimeoutException(
          'The sign-in window was not completed in time.',
          timeout,
        ),
      );

  Future<String> _read(HttpServer server, String state) async {
    await for (final request in server) {
      final params = request.uri.queryParameters;
      request.response
        ..statusCode = 200
        ..headers.contentType = ContentType.html
        ..write(
          '<html><body style="font-family:sans-serif">'
          '<p>Sign-in complete. You can close this tab.</p>'
          '</body></html>',
        );
      await request.response.close();
      return codeFrom(params, state: state);
    }
    throw StateError('No authorization code was received.');
  }
}

class WebAuthMcpRedirect implements McpRedirect {
  const WebAuthMcpRedirect({
    this.scheme = 'org.spectrum3847.spectrumstrategy',
    this.path = 'mcp-callback',
    this.authenticate = appleWebAuthenticate,
  });

  final String scheme;
  final String path;

  final Future<Uri> Function({required Uri url, required String callbackScheme})
  authenticate;

  @override
  Future<String> authorize({
    required Future<Uri> Function(String redirectUri) buildAuthorizeUrl,
    required String state,
  }) async {
    final authorizeUrl = await buildAuthorizeUrl('$scheme://$path');
    final Uri callback;
    try {
      callback = await authenticate(url: authorizeUrl, callbackScheme: scheme);
    } on AppleWebAuthCancelled {
      throw StateError('Sign-in was cancelled.');
    } on AppleWebAuthException catch (error) {
      throw StateError(error.message);
    }
    return codeFrom(callback.queryParameters, state: state);
  }
}

String codeFrom(Map<String, String> params, {required String state}) {
  if (params['error'] != null) {
    throw StateError('Sign-in was cancelled or denied.');
  }
  if (params['state'] != state) {
    throw StateError('Sign-in state mismatch; aborting.');
  }
  final code = params['code'];
  if (code == null || code.isEmpty) {
    throw StateError('No authorization code was received.');
  }
  return code;
}
