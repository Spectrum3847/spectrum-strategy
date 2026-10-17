import 'dart:async';
import 'dart:io';

import 'package:apple_web_auth/apple_web_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:spectrumstrategy/src/services/mcp/mcp_oauth_redirect.dart';

void main() {
  group('codeFrom', () {
    test('reads the code', () {
      expect(
        codeFrom(<String, String>{'code': 'abc', 'state': 'xyz'}, state: 'xyz'),
        'abc',
      );
    });

    test('a state that does not match is refused', () {
      expect(
        () => codeFrom(<String, String>{
          'code': 'abc',
          'state': 'someone-elses',
        }, state: 'xyz'),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('state mismatch'),
          ),
        ),
      );
    });

    test('an error from the provider is refused before the code is read', () {
      expect(
        () => codeFrom(<String, String>{
          'error': 'access_denied',
          'code': 'abc',
          'state': 'xyz',
        }, state: 'xyz'),
        throwsA(isA<StateError>()),
      );
    });

    test('no code at all is refused', () {
      expect(
        () => codeFrom(<String, String>{'state': 'xyz'}, state: 'xyz'),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('LoopbackMcpRedirect', () {
    test('binds a port, and the authorize url points back at it', () async {
      Uri? launched;
      String? redirect;
      final door = LoopbackMcpRedirect(
        launch: (url) async {
          launched = url;

          await http.get(Uri.parse('$redirect?code=abc&state=xyz'));
        },
      );

      final code = await door.authorize(
        state: 'xyz',
        buildAuthorizeUrl: (uri) async {
          redirect = uri;
          return Uri.parse('https://example.test/authorize?redirect_uri=$uri');
        },
      );

      expect(code, 'abc');
      expect(redirect, startsWith('http://127.0.0.1:'));
      expect(launched.toString(), contains('127.0.0.1'));
    });

    test('a browser that never comes back gives up rather than hanging', () {
      final door = LoopbackMcpRedirect(
        launch: (_) async {},
        timeout: const Duration(milliseconds: 50),
      );

      expect(
        () => door.authorize(
          state: 'xyz',
          buildAuthorizeUrl: (_) async =>
              Uri.parse('https://example.test/authorize'),
        ),
        throwsA(isA<TimeoutException>()),
      );
    });

    test('the socket is closed even when the launch fails', () async {
      var redirect = '';
      final door = LoopbackMcpRedirect(
        launch: (_) async => throw const SocketException('no browser'),
      );

      await expectLater(
        () => door.authorize(
          state: 'xyz',
          buildAuthorizeUrl: (uri) async {
            redirect = uri;
            return Uri.parse('https://example.test/authorize');
          },
        ),
        throwsA(isA<SocketException>()),
      );

      final port = int.parse(Uri.parse(redirect).port.toString());
      await expectLater(
        http
            .get(Uri.parse('http://127.0.0.1:$port/callback'))
            .timeout(const Duration(seconds: 2)),
        throwsA(anything),
      );
    });
  });

  group('WebAuthMcpRedirect', () {
    test('redirects to the registered scheme and reads the code', () async {
      Uri? opened;
      String? scheme;
      final door = WebAuthMcpRedirect(
        authenticate: ({required url, required callbackScheme}) async {
          opened = url;
          scheme = callbackScheme;
          return Uri.parse(
            'org.spectrum3847.spectrumstrategy://mcp-callback'
            '?code=abc&state=xyz',
          );
        },
      );

      final code = await door.authorize(
        state: 'xyz',
        buildAuthorizeUrl: (uri) async =>
            Uri.parse('https://example.test/authorize?redirect_uri=$uri'),
      );

      expect(code, 'abc');
      expect(scheme, 'org.spectrum3847.spectrumstrategy');
      expect(
        opened.toString(),
        contains('org.spectrum3847.spectrumstrategy://mcp-callback'),
      );
    });

    test('a closed sheet reads as cancelled, in words a person can act on', () {
      final door = WebAuthMcpRedirect(
        authenticate: ({required url, required callbackScheme}) async =>
            throw const AppleWebAuthCancelled(),
      );

      expect(
        () => door.authorize(
          state: 'xyz',
          buildAuthorizeUrl: (_) async =>
              Uri.parse('https://example.test/authorize'),
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            'Sign-in was cancelled.',
          ),
        ),
      );
    });

    test('a callback carrying the wrong state is refused', () {
      final door = WebAuthMcpRedirect(
        authenticate: ({required url, required callbackScheme}) async =>
            Uri.parse(
              'org.spectrum3847.spectrumstrategy://mcp-callback'
              '?code=abc&state=someone-elses',
            ),
      );

      expect(
        () => door.authorize(
          state: 'xyz',
          buildAuthorizeUrl: (_) async =>
              Uri.parse('https://example.test/authorize'),
        ),
        throwsA(isA<StateError>()),
      );
    });
  });
}
