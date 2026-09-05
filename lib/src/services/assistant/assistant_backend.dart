library;

enum AssistantSource {
  openRouter,
  local;

  static AssistantSource fromName(String? name) => AssistantSource.values
      .firstWhere((s) => s.name == name, orElse: () => AssistantSource.local);
}

class AssistantRequest {
  const AssistantRequest({
    required this.cacheKey,
    required this.prompt,
    this.system,
    this.history,
    this.coverage,
    this.minimumChars,
  });

  final String cacheKey;
  final String prompt;
  final String? system;

  final List<AssistantTurn>? history;

  final int? minimumChars;

  final int? coverage;
}

enum AssistantTurnRole { user, assistant }

class AssistantTurn {
  const AssistantTurn({required this.role, required this.content});

  final AssistantTurnRole role;
  final String content;
}

class AssistantSummary {
  const AssistantSummary({
    required this.text,
    required this.generatedAt,
    required this.model,
    required this.source,
    this.coverage,
  });

  factory AssistantSummary.fromJson(Map<String, dynamic> json) {
    final stamp = json['generatedAt'];
    return AssistantSummary(
      text: json['text'] as String? ?? '',
      generatedAt:
          DateTime.tryParse(stamp is String ? stamp : '')?.toUtc() ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      model: json['model'] as String? ?? 'unknown',
      source: AssistantSource.fromName(json['source'] as String?),
      coverage: json['coverage'] as int?,
    );
  }

  final String text;
  final DateTime generatedAt;
  final String model;
  final AssistantSource source;

  final int? coverage;

  AssistantSummary withCoverage(int? coverage) => AssistantSummary(
    text: text,
    generatedAt: generatedAt,
    model: model,
    source: source,
    coverage: coverage,
  );

  Map<String, dynamic> toJson() => {
    'text': text,
    'generatedAt': generatedAt.toUtc().toIso8601String(),
    'model': model,
    'source': source.name,
    if (coverage != null) 'coverage': coverage,
  };
}

bool looksLikeAnAnswer(String text, {int? minimumChars}) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) {
    return false;
  }
  if (minimumChars != null && trimmed.length < minimumChars) {
    return false;
  }
  final opening = trimmed.toLowerCase();
  for (final pattern in _nonAnswerOpenings) {
    if (opening.startsWith(pattern)) {
      return false;
    }
  }
  return true;
}

const List<String> _nonAnswerOpenings = <String>[
  'user safety:',
  'safety:',
  'i cannot',
  "i can't",
  'i am unable',
  "i'm unable",
  'i am sorry',
  "i'm sorry",
  'as an ai',
  'as a language model',
];

class AssistantUnavailable implements Exception {
  const AssistantUnavailable(this.reason);

  final String reason;

  @override
  String toString() => 'AssistantUnavailable: $reason';
}

abstract class AssistantBackend {
  Future<bool> isAvailable();

  Future<AssistantSummary> complete(AssistantRequest request);
}
