import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'assistant_backend.dart';
import 'firestore_assistant_config.dart';

class OpenRouterAssistantBackend implements AssistantBackend {
  OpenRouterAssistantBackend({
    required this._config,
    http.Client? client,
    this.model = 'openrouter/free',
    this.timeout = const Duration(seconds: 60),
    this.retryDelay = const Duration(seconds: 5),
    this.maxAttempts = 4,
  }) : _client = client ?? http.Client();

  static final Uri _endpoint = Uri.parse(
    'https://openrouter.ai/api/v1/chat/completions',
  );

  final FirestoreAssistantConfig _config;
  final http.Client _client;
  final String model;

  final Duration timeout;
  final Duration retryDelay;

  final int maxAttempts;

  @override
  Future<bool> isAvailable() async => (await _config.resolveApiKey()) != null;

  @override
  Future<AssistantSummary> complete(AssistantRequest request) async {
    final key = await _config.resolveApiKey();
    if (key == null) {
      throw const AssistantUnavailable(
        'No OpenRouter key. An admin sets it at appConfig/apiKeys.openrouter.',
      );
    }

    final body = jsonEncode({
      'model': model,
      'messages': [
        if (request.system != null)
          {'role': 'system', 'content': request.system},
        for (final turn in request.history ?? const <AssistantTurn>[])
          {'role': turn.role.name, 'content': turn.content},
        {'role': 'user', 'content': request.prompt},
      ],
    });

    var attempt = 0;
    while (true) {
      attempt++;
      final lastAttempt = attempt >= maxAttempts;
      try {
        return _parse(await _post(key, body), request);
      } on AssistantUnavailable catch (error) {
        if (lastAttempt || !_worthRetrying(error)) {
          rethrow;
        }
      } on TimeoutException {
        if (lastAttempt) {
          throw AssistantUnavailable('OpenRouter timed out $attempt times.');
        }
      } catch (error) {
        if (lastAttempt) {
          throw AssistantUnavailable('Could not reach OpenRouter: $error');
        }
      }
      await Future<void>.delayed(retryDelay);
    }
  }

  Future<http.Response> _post(String key, String body) => _client
      .post(
        _endpoint,
        headers: {
          'Authorization': 'Bearer $key',
          'Content-Type': 'application/json',

          'HTTP-Referer': 'https://github.com/Spectrum3847/SpectrumStrategy',
          'X-Title': 'Spectrum Strategy',
        },
        body: body,
      )
      .timeout(timeout);

  AssistantSummary _parse(http.Response response, AssistantRequest request) {
    if (response.statusCode != 200) {
      throw AssistantUnavailable(
        'OpenRouter answered ${response.statusCode}: '
        '${_truncate(response.body)}',
      );
    }

    final Map<String, dynamic> decoded;
    try {
      decoded = jsonDecode(response.body) as Map<String, dynamic>;
    } on FormatException {
      throw AssistantUnavailable(
        'OpenRouter answered with something that is not JSON: '
        '${_truncate(response.body)}',
      );
    }

    final error = decoded['error'];
    if (error is Map && error['message'] is String) {
      throw AssistantUnavailable(error['message'] as String);
    }

    final choices = decoded['choices'];
    final choice = choices is List && choices.isNotEmpty ? choices.first : null;
    final message = choice is Map ? choice['message'] : null;
    final text = message is Map ? message['content'] : null;
    if (text is! String || text.trim().isEmpty) {
      throw const AssistantUnavailable('OpenRouter answered with no text.');
    }

    final answer = text.trim();
    final floor = request.minimumChars;
    if (!looksLikeAnAnswer(answer, minimumChars: floor)) {
      throw AssistantUnavailable(
        'OpenRouter answered too short to be an answer '
        '(${answer.length} characters, expected at least '
        '${floor ?? 1}): ${_truncate(answer)}',
      );
    }

    return AssistantSummary(
      text: answer,
      generatedAt: DateTime.now().toUtc(),

      model: decoded['model'] is String ? decoded['model'] as String : model,
      source: AssistantSource.openRouter,
    );
  }

  bool _worthRetrying(AssistantUnavailable error) =>
      error.reason.startsWith('OpenRouter answered 429') ||
      error.reason.startsWith('OpenRouter answered 5') ||
      error.reason.startsWith('OpenRouter answered too short');

  static String _truncate(String body) =>
      body.length <= 200 ? body : '${body.substring(0, 200)}...';
}
