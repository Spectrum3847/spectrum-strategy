library;

import 'assistant_backend.dart';
import 'remote_assistant_cache.dart';

class PendingAssistantRequest {
  const PendingAssistantRequest({
    required this.cacheKey,
    required this.prompt,
    required this.requestedBy,
    required this.requestedAt,
    this.system,
    this.minimumChars,
    this.coverage,
    this.claimedBy,
    this.claimedAt,
  });

  factory PendingAssistantRequest.fromRequest(
    AssistantRequest request, {
    required String requestedBy,
    required DateTime requestedAt,
  }) => PendingAssistantRequest(
    cacheKey: request.cacheKey,
    prompt: request.prompt,
    system: request.system,
    minimumChars: request.minimumChars,
    coverage: request.coverage,
    requestedBy: requestedBy,
    requestedAt: requestedAt.toUtc(),
  );

  factory PendingAssistantRequest.fromJson(Map<String, dynamic> json) =>
      PendingAssistantRequest(
        cacheKey: json['cacheKey'] as String? ?? '',
        prompt: json['prompt'] as String? ?? '',
        system: json['system'] as String?,
        minimumChars: json['minimumChars'] as int?,
        coverage: json['coverage'] as int?,
        requestedBy: json['requestedBy'] as String? ?? '',
        requestedAt: _parseStamp(json['requestedAt']),
        claimedBy: json['claimedBy'] as String?,
        claimedAt: json['claimedAt'] == null
            ? null
            : _parseStamp(json['claimedAt']),
      );

  final String cacheKey;
  final String prompt;
  final String? system;
  final int? minimumChars;
  final int? coverage;
  final String requestedBy;
  final DateTime requestedAt;

  final String? claimedBy;
  final DateTime? claimedAt;

  String get id => assistantCacheDocId(cacheKey);

  AssistantRequest toRequest() => AssistantRequest(
    cacheKey: cacheKey,
    prompt: prompt,
    system: system,
    minimumChars: minimumChars,
    coverage: coverage,
  );

  Map<String, dynamic> toJson() => {
    'cacheKey': cacheKey,
    'prompt': prompt,
    if (system != null) 'system': system,
    if (minimumChars != null) 'minimumChars': minimumChars,
    if (coverage != null) 'coverage': coverage,
    'requestedBy': requestedBy,
    'requestedAt': requestedAt.toUtc().toIso8601String(),
    if (claimedBy != null) 'claimedBy': claimedBy,
    if (claimedAt != null) 'claimedAt': claimedAt!.toUtc().toIso8601String(),
  };

  static DateTime _parseStamp(Object? value) =>
      DateTime.tryParse(value is String ? value : '')?.toUtc() ??
      DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
}

abstract class RemoteAssistantRequests {
  Future<bool> post(AssistantRequest request);

  Future<List<PendingAssistantRequest>> open();

  Future<bool> claim(PendingAssistantRequest request);

  Future<void> remove(String cacheKey);
}
