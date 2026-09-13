library;

import '../services/assistant/assistant_backend.dart';
import '../state/assistant_chat_controller.dart';

class AssistantChatSession {
  AssistantChatSession({
    required this.id,
    required this.createdAt,
    required this.updatedAt,
    this.title,
    this.modelId,
    this.syncedUid,
    List<AssistantChatMessage>? messages,
    List<AssistantTurn>? turns,
  }) : messages = messages ?? <AssistantChatMessage>[],
       turns = turns ?? <AssistantTurn>[];

  final String id;

  final DateTime createdAt;
  DateTime updatedAt;

  String? title;

  String? modelId;

  final List<AssistantChatMessage> messages;
  final List<AssistantTurn> turns;

  String? syncedUid;

  static const int maxEntries = 200;

  void trim() {
    while (messages.length > maxEntries) {
      messages.removeAt(0);
    }
    while (turns.length > maxEntries) {
      turns.removeAt(0);
    }
  }

  bool get isEmpty => messages.isEmpty;

  String get displayTitle {
    final trimmed = title?.trim();
    if (trimmed != null && trimmed.isNotEmpty) return trimmed;
    return 'New chat';
  }

  void titleFrom(String question) {
    if (title != null) return;
    final firstLine = question.trim().split('\n').first.trim();
    if (firstLine.isEmpty) return;
    title = firstLine.length <= 60
        ? firstLine
        : '${firstLine.substring(0, 57)}...';
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    if (title != null) 'title': title,
    if (modelId != null) 'modelId': modelId,
    'messages': [for (final message in messages) _messageToJson(message)],
    'turns': [
      for (final turn in turns)
        <String, dynamic>{'role': turn.role.name, 'content': turn.content},
    ],
  };

  Map<String, dynamic> toLocalJson() => <String, dynamic>{
    ...toJson(),
    if (syncedUid != null) 'syncedUid': syncedUid,
  };

  static AssistantChatSession fromJson(Map<String, dynamic> json) =>
      AssistantChatSession(
        id: json['id'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        updatedAt: DateTime.parse(json['updatedAt'] as String),
        title: json['title'] as String?,
        modelId: json['modelId'] as String?,
        syncedUid: json['syncedUid'] as String?,
        messages: [
          for (final raw in (json['messages'] as List? ?? const []))
            _messageFromJson(Map<String, dynamic>.from(raw as Map)),
        ],
        turns: [
          for (final raw in (json['turns'] as List? ?? const []))
            _turnFromJson(Map<String, dynamic>.from(raw as Map)),
        ],
      );
}

Map<String, dynamic> _messageToJson(AssistantChatMessage message) =>
    <String, dynamic>{
      'kind': message.kind.name,
      'text': message.text,
      if (message.source != null) 'source': message.source!.name,
      if (message.model != null) 'model': message.model,
    };

AssistantChatMessage _messageFromJson(Map<String, dynamic> json) {
  final text = json['text'] as String? ?? '';
  switch (json['kind'] as String?) {
    case 'user':
      return AssistantChatMessage.user(text);
    case 'error':
      return AssistantChatMessage.error(text);
    default:
      return AssistantChatMessage.assistant(
        text,
        source: _sourceFromName(json['source'] as String?),
        model: json['model'] as String?,
      );
  }
}

AssistantSource? _sourceFromName(String? name) {
  if (name == null) return null;
  for (final source in AssistantSource.values) {
    if (source.name == name) return source;
  }
  return null;
}

AssistantTurn _turnFromJson(Map<String, dynamic> json) => AssistantTurn(
  role: json['role'] == AssistantTurnRole.assistant.name
      ? AssistantTurnRole.assistant
      : AssistantTurnRole.user,
  content: json['content'] as String? ?? '',
);
