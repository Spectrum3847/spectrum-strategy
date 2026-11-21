import 'package:apple_ai/apple_ai.dart';

import 'assistant_backend.dart';
import 'assistant_chat.dart';
import 'assistant_tool.dart';

typedef AppleAiAvailabilityCheck = Future<AppleAiAvailability> Function();

typedef AppleAiResponder = Future<String> Function({
  required String prompt,
  String? instructions,
  double? temperature,
  String? sessionId,
  List<AppleAiTool>? tools,
});

class AppleAssistantBackend
    implements AssistantBackend, AssistantSessionBackend {
  AppleAssistantBackend({
    AppleAiAvailabilityCheck? availability,
    AppleAiResponder? respond,
    void Function(AppleAiToolHandler?)? setToolHandler,
    this._tools,
  }) : _availability = availability ?? appleAiAvailability,
       _respond = respond ?? appleAiRespond,
       _setToolHandler = setToolHandler ?? appleAiSetToolHandler;

  final AssistantToolRegistry? _tools;
  final AppleAiAvailabilityCheck _availability;
  final AppleAiResponder _respond;
  final void Function(AppleAiToolHandler?) _setToolHandler;

  static const int appleToolResultCharBudget = 1200;

  static const Set<String> _appleMcpToolAllowlist = <String>{
    'whoami',
    'get_document',
    'query_collection',
    'get_team_epa',
    'get_event_teams',
    'get_event_rankings',
  };

  static const String _mcpToolNamePrefix = 'mcp_';

  static const String _mcpToolsUnavailableNote =
      'Some data tools are not available in this chat on this device: '
      'creating, updating, or deleting records, editing scout config, and a '
      'few lookups covered by another tool here. If asked to do one of '
      'those, say plainly that it is not available on mobile rather than '
      'guessing or claiming it is done.';

  bool _handlerInstalled = false;

  final Set<String> _seeded = <String>{};

  @override
  Future<bool> isAvailable() async => (await _availability()).isAvailable;

  @override
  Future<AssistantSummary> complete(AssistantRequest request) async {
    final availability = await _availability();
    if (!availability.isAvailable) {
      throw AssistantUnavailable(availability.reason!.message);
    }

    final toolSelection = await _appleTools(request);
    final sessionId = request.sessionId;
    final seeded = sessionId != null && !_seeded.add(sessionId);

    final String text;
    try {
      text = await _respond(
        prompt: seeded ? request.prompt : _promptFor(request),
        instructions: _instructionsFor(request, toolSelection.droppedMcpTool),

        temperature: 0.2,
        sessionId: sessionId,
        tools: toolSelection.tools,
      );
    } on AppleAiException catch (error) {
      if (sessionId != null) {
        _seeded.remove(sessionId);
      }
      throw AssistantUnavailable(error.message);
    }

    if (!looksLikeAnAnswer(text, minimumChars: request.minimumChars)) {
      throw AssistantUnavailable(
        'The on-device model answered too short to be an answer '
        '(${text.length} characters, expected at least '
        '${request.minimumChars ?? 1}).',
      );
    }

    return AssistantSummary(
      text: text,
      generatedAt: DateTime.now().toUtc(),
      model: 'Apple Intelligence (on-device)',
      source: AssistantSource.apple,
    );
  }

  @override
  Future<void> closeSession(String sessionId) async {
    _seeded.remove(sessionId);
    await appleAiCloseSession(sessionId);
  }

  static bool _isDroppedMcpTool(String name) =>
      name.startsWith(_mcpToolNamePrefix) &&
      !_appleMcpToolAllowlist.contains(
        name.substring(_mcpToolNamePrefix.length),
      );

  Future<_AppleToolSelection> _appleTools(AssistantRequest request) async {
    final registry = _tools;
    if (!request.useTools || registry == null) {
      return const _AppleToolSelection(null, false);
    }
    final allSpecs = await registry.tools();
    if (allSpecs.isEmpty) {
      return const _AppleToolSelection(null, false);
    }
    var droppedMcpTool = false;
    final specs = <AssistantToolSpec>[];
    for (final spec in allSpecs) {
      if (_isDroppedMcpTool(spec.name)) {
        droppedMcpTool = true;
        continue;
      }
      specs.add(spec);
    }
    if (specs.isEmpty) {
      return _AppleToolSelection(null, droppedMcpTool);
    }

    if (!_handlerInstalled) {
      _handlerInstalled = true;
      _setToolHandler((name, arguments) {
        if (_isDroppedMcpTool(name)) {
          return Future.value(_mcpToolsUnavailableNote);
        }

        return registry.call(
          name,
          arguments,
          resultCharLimit: appleToolResultCharBudget,
        );
      });
    }
    return _AppleToolSelection(<AppleAiTool>[
      for (final spec in specs)
        AppleAiTool(
          name: spec.name,
          description: spec.description,
          parameters: spec.parameters,
        ),
    ], droppedMcpTool);
  }

  String? _instructionsFor(AssistantRequest request, bool droppedMcpTool) {
    final base = request.compactSystem ?? request.system;
    if (!droppedMcpTool) return base;
    return base == null
        ? _mcpToolsUnavailableNote
        : '$base $_mcpToolsUnavailableNote';
  }

  String _promptFor(AssistantRequest request) {
    final history = boundAssistantChatHistory(
      request.history ?? const <AssistantTurn>[],
      maxChars: assistantChatHistoryCharBudgetSmall,
    );
    if (history.isEmpty) {
      return request.prompt;
    }
    final buffer = StringBuffer('Earlier in this conversation:\n');
    for (final turn in history) {
      final speaker = turn.role == AssistantTurnRole.user ? 'Question' : 'You';
      buffer.writeln('$speaker: ${turn.content}');
    }
    buffer
      ..writeln()
      ..write(request.prompt);
    return buffer.toString();
  }
}

class _AppleToolSelection {
  const _AppleToolSelection(this.tools, this.droppedMcpTool);

  final List<AppleAiTool>? tools;
  final bool droppedMcpTool;
}
