import 'dart:convert';

import 'package:http/http.dart' as http;

import 'llama_runtime_service.dart' show AssistantModel;

const List<String> blockedModelNameMarkers = <String>[
  'uncensored',
  'abliterated',
  'heretic',
  'obliterated',
  'unleashed',
  'nsfw',
  'roleplay',
  'toxic',
  'jailbreak',
  'horny',
  'waifu',
  'smut',
];

bool isBlockedModelName(String repoId) {
  final lower = repoId.toLowerCase();
  return blockedModelNameMarkers.any(lower.contains);
}

class HuggingFaceRateLimited implements Exception {
  const HuggingFaceRateLimited();

  @override
  String toString() => 'Hugging Face rate limited this network';
}

bool isGatedOrPrivate(Map<String, dynamic> entry) {
  final gated = entry['gated'];
  if (gated != null && gated != false) return true;
  return entry['private'] == true;
}

final RegExp shardedGgufPattern = RegExp(r'-\d{5}-of-\d{5}');

class HuggingFaceCatalogService {
  HuggingFaceCatalogService({
    http.Client? client,
    this._maxScanned = 120,
    this._wanted = 30,
    this._concurrency = 6,
    this._tokenLoader,
  }) : _client = client ?? http.Client();

  final Future<String?> Function()? _tokenLoader;

  Map<String, String> _headers = const <String, String>{};

  Future<void> _loadHeaders() async {
    final token = (await _tokenLoader?.call())?.trim();
    _headers = (token == null || token.isEmpty)
        ? const <String, String>{}
        : <String, String>{'Authorization': 'Bearer $token'};
  }

  final http.Client _client;

  final int _maxScanned;

  final int _wanted;

  final int _concurrency;

  static const int _pageSize = 100;
  static const String _listUrl = 'https://huggingface.co/api/models';

  static const Duration overallTimeout = Duration(seconds: 90);

  Future<List<AssistantModel>> discover() =>
      _discover().timeout(overallTimeout);

  Future<List<AssistantModel>> _discover() async {
    await _loadHeaders();
    final candidates = await _listCandidates();
    final repoIds = <String>[];
    for (final entry in candidates) {
      final repoId = entry['id'] as String?;
      if (repoId == null || repoId.isEmpty) continue;

      if (isGatedOrPrivate(entry)) continue;
      if (isBlockedModelName(repoId)) continue;
      repoIds.add(repoId);
    }

    final models = <AssistantModel>[];
    for (
      var i = 0;
      i < repoIds.length && models.length < _wanted;
      i += _concurrency
    ) {
      final batch = repoIds.skip(i).take(_concurrency);
      final resolved = await Future.wait(batch.map(_resolveQ4File));
      for (final model in resolved) {
        if (model != null) models.add(model);
      }
    }
    return models.take(_wanted).toList();
  }

  Future<List<Map<String, dynamic>>> _listCandidates() async {
    final results = <Map<String, dynamic>>[];
    var skip = 0;
    while (results.length < _maxScanned) {
      final uri = Uri.parse(
        '$_listUrl?filter=gguf&pipeline_tag=text-generation'
        '&sort=downloads&direction=-1&limit=$_pageSize&skip=$skip',
      );
      final response = await _client
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 20));
      if (response.statusCode == 429) throw const HuggingFaceRateLimited();
      if (response.statusCode != 200) {
        throw http.ClientException(
          'Hugging Face answered HTTP ${response.statusCode} listing models',
        );
      }
      final page = (jsonDecode(utf8.decode(response.bodyBytes)) as List)
          .cast<Map<String, dynamic>>();
      if (page.isEmpty) break;
      results.addAll(page);
      if (page.length < _pageSize) break;
      skip += _pageSize;
    }
    return results;
  }

  Future<AssistantModel?> _resolveQ4File(String repoId) async {
    final uri = Uri.parse(
      'https://huggingface.co/api/models/$repoId/tree/main?recursive=1',
    );
    final http.Response response;
    try {
      response = await _client
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 15));
    } on HuggingFaceRateLimited {
      rethrow;
    } catch (_) {
      return null;
    }

    if (response.statusCode == 429) throw const HuggingFaceRateLimited();
    if (response.statusCode != 200) return null;
    final List<Map<String, dynamic>> entries;
    try {
      entries = (jsonDecode(utf8.decode(response.bodyBytes)) as List)
          .cast<Map<String, dynamic>>();
    } catch (_) {
      return null;
    }
    for (final entry in entries) {
      if (entry['type'] != 'file') continue;
      final path = entry['path'] as String?;
      if (path == null) continue;
      final lower = path.toLowerCase();
      if (!lower.endsWith('.gguf')) continue;
      if (!lower.contains('q4_k_m')) continue;
      if (shardedGgufPattern.hasMatch(path)) continue;
      final size =
          (entry['size'] as num?)?.toInt() ??
          ((entry['lfs'] as Map<String, dynamic>?)?['size'] as num?)?.toInt();
      if (size == null) continue;
      return AssistantModel(repoId: repoId, path: path, sizeBytes: size);
    }
    return null;
  }
}
