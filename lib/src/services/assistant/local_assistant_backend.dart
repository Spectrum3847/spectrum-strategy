import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../llama_runtime_service.dart';
import 'assistant_backend.dart';

class LocalAssistantBackend implements AssistantBackend {
  LocalAssistantBackend({
    LlamaRuntimeService? runtime,
    AssistantModel? model,
    http.Client? client,
    this.timeout = const Duration(minutes: 5),
    this._startServer,
  }) : _runtime = runtime ?? LlamaRuntimeService.shared,
       _fixedModel = model,
       _client = client ?? http.Client();

  final LlamaRuntimeService _runtime;
  final AssistantModel? _fixedModel;
  final http.Client _client;
  final Future<String> Function(AssistantModel model)? _startServer;

  final Duration timeout;

  Future<AssistantModel?> _resolveModel() async {
    if (_fixedModel != null) return _fixedModel;
    final installed = await _runtime.installedModels();
    if (installed.isEmpty) return null;
    final recommended = LlamaRuntimeService.recommendedModel(
      await _runtime.totalRamGb(),
    );
    if (installed.contains(recommended)) return recommended;
    return installed.reduce((a, b) => b.sizeBytes > a.sizeBytes ? b : a);
  }

  @override
  Future<bool> isAvailable() async {
    if (await _runtime.serverBinaryPath() == null) return false;
    return (await _resolveModel()) != null;
  }

  @override
  Future<AssistantSummary> complete(AssistantRequest request) async {
    final model = await _resolveModel();
    if (model == null) {
      throw const AssistantUnavailable(
        'No local model installed. Download one in Settings.',
      );
    }

    final String endpoint;
    try {
      endpoint = _startServer != null
          ? await _startServer(model)
          : await _runtime.startServer(model);
    } catch (error) {
      throw AssistantUnavailable('Could not start the local model: $error');
    }

    final text = await _ask(endpoint: endpoint, model: model, request: request);
    return AssistantSummary(
      text: text,
      generatedAt: DateTime.now().toUtc(),
      model: model.name,
      source: AssistantSource.local,
    );
  }

  Future<String> _ask({
    required String endpoint,
    required AssistantModel model,
    required AssistantRequest request,
  }) async {
    final base = endpoint.trim().replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.parse('$base/v1/chat/completions');

    final http.Response response;
    try {
      response = await _client
          .post(
            uri,
            headers: const <String, String>{'Content-Type': 'application/json'},
            body: jsonEncode(<String, dynamic>{
              'model': model.name,
              'temperature': 0.2,
              'stream': false,

              'max_tokens': 1024,

              'chat_template_kwargs': <String, dynamic>{
                'enable_thinking': false,
              },
              'messages': <Map<String, String>>[
                if (request.system != null)
                  <String, String>{
                    'role': 'system',
                    'content': request.system!,
                  },
                for (final turn in request.history ?? const <AssistantTurn>[])
                  <String, String>{
                    'role': turn.role.name,
                    'content': turn.content,
                  },
                <String, String>{'role': 'user', 'content': request.prompt},
              ],
            }),
          )
          .timeout(timeout);
    } on TimeoutException {
      throw const AssistantUnavailable('The local model timed out.');
    } catch (error) {
      throw AssistantUnavailable('Could not reach the local model: $error');
    }

    if (response.statusCode != 200) {
      throw AssistantUnavailable(
        'Local model server answered HTTP ${response.statusCode}.',
      );
    }

    final Map<String, dynamic> decoded;
    try {
      decoded =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    } on FormatException {
      throw const AssistantUnavailable(
        'Local model server answered with something that is not JSON.',
      );
    }

    final choices = decoded['choices'];
    final choice = choices is List && choices.isNotEmpty ? choices.first : null;
    final message = choice is Map ? choice['message'] : null;
    final content = message is Map ? message['content'] as String? : null;

    final reasoning = message is Map
        ? message['reasoning_content'] as String?
        : null;
    final answer = (content != null && content.trim().isNotEmpty)
        ? content.trim()
        : (reasoning?.trim() ?? '');
    if (answer.isEmpty) {
      throw const AssistantUnavailable('Local model server sent no answer.');
    }
    return answer;
  }
}
