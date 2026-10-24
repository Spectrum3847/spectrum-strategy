import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

class PitPhotoUploadService {
  PitPhotoUploadService({
    required Future<String?> Function() baseUrlLoader,
    required Future<String?> Function() idTokenProvider,
    http.Client? httpClient,
  }) : _baseUrl = baseUrlLoader,
       _idToken = idTokenProvider,
       _http = httpClient ?? http.Client();

  final Future<String?> Function() _baseUrl;

  final Future<String?> Function() _idToken;
  final http.Client _http;

  Future<bool> get isConfigured async =>
      (await _resolvedBase()) != null && (await _idToken()) != null;

  Future<String?> upload(
    Uint8List bytes, {
    String contentType = 'image/jpeg',
  }) async {
    final base = await _resolvedBase();
    final token = await _idToken();
    if (base == null || token == null) return null;
    try {
      final response = await _send(
        'POST',
        Uri.parse('$base/photos'),
        token,
        headers: <String, String>{'Content-Type': contentType},
        bytes: bytes,
      );
      if (response.statusCode != 201) return null;
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) return null;
      final key = decoded['key'];
      return key is String && key.isNotEmpty ? key : null;
    } catch (_) {
      return null;
    }
  }

  Future<Uint8List?> download(String key) async {
    final base = await _resolvedBase();
    final token = await _idToken();
    if (base == null || token == null) return null;
    try {
      final response = await _send(
        'GET',
        Uri.parse('$base/photos/${Uri.encodeComponent(key)}'),
        token,
      );
      if (response.statusCode != 200) return null;
      return response.bodyBytes;
    } catch (_) {
      return null;
    }
  }

  Future<bool> delete(String key) async {
    final base = await _resolvedBase();
    final token = await _idToken();
    if (base == null || token == null) return false;
    try {
      final response = await _send(
        'DELETE',
        Uri.parse('$base/photos/${Uri.encodeComponent(key)}'),
        token,
      );
      return response.statusCode == 204 || response.statusCode == 404;
    } catch (_) {
      return false;
    }
  }

  Future<http.Response> _send(
    String method,
    Uri url,
    String token, {
    Map<String, String> headers = const <String, String>{},
    Uint8List? bytes,
  }) async {
    final request = http.Request(method, url)
      ..followRedirects = false
      ..headers['Authorization'] = 'Bearer $token';
    request.headers.addAll(headers);
    if (bytes != null) request.bodyBytes = bytes;
    return http.Response.fromStream(await _http.send(request));
  }

  Future<String?> _resolvedBase() async {
    final raw = (await _baseUrl())?.trim() ?? '';
    if (raw.isEmpty) return null;
    final trimmed = raw.endsWith('/') ? raw.substring(0, raw.length - 1) : raw;

    return trimmed.startsWith('https://') ? trimmed : null;
  }
}
