import 'dart:convert';

import 'assistant_tool.dart';

typedef AssistantCompleter = Future<Map<String, dynamic>> Function(
  List<Map<String, dynamic>> messages,
  List<Map<String, dynamic>>? tools,
);

Future<Map<String, dynamic>> runAssistantToolLoop({
  required List<Map<String, dynamic>> messages,
  required AssistantToolRegistry? registry,
  required AssistantCompleter complete,
  int maxRounds = 4,
  int maxToolCalls = 8,
}) async {
  final specs = registry == null
      ? const <AssistantToolSpec>[]
      : await registry.tools();
  if (specs.isEmpty) {
    return complete(messages, null);
  }

  final toolsJson = specs.map((spec) => spec.toJson()).toList(growable: false);
  final conversation = List<Map<String, dynamic>>.from(messages);
  var totalCalls = 0;

  for (var round = 0; round < maxRounds && totalCalls < maxToolCalls; round++) {
    final message = await complete(conversation, toolsJson);
    final calls = message['tool_calls'];
    if (calls is! List || calls.isEmpty) {
      return message;
    }

    conversation.add(message);

    for (final raw in calls) {
      final call = raw is Map ? Map<String, dynamic>.from(raw) : null;
      final id = call?['id']?.toString() ?? '';
      final String result;
      if (call == null) {
        result = 'Error: this tool call was not readable.';
      } else if (totalCalls >= maxToolCalls) {
        result =
            'Error: the tool call budget for this question is used up. '
            'Answer with what you already have.';
      } else {
        totalCalls++;
        final function = call['function'];
        final name = function is Map ? '${function['name']}' : '';
        result = await registry!.call(name, _decodeArguments(function));
      }
      conversation.add(<String, dynamic>{
        'role': 'tool',
        'tool_call_id': id,
        'content': result,
      });
    }
  }

  return complete(conversation, null);
}

Map<String, dynamic> _decodeArguments(dynamic function) {
  if (function is! Map) return const <String, dynamic>{};
  final raw = function['arguments'];
  if (raw is Map) return Map<String, dynamic>.from(raw);
  if (raw is String && raw.trim().isNotEmpty) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } on FormatException {}
  }
  return const <String, dynamic>{};
}
