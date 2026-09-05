import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'assistant_backend.dart';

abstract class RemoteAssistantCache {
  Future<AssistantSummary?> read(String cacheKey);

  Future<void> write(String cacheKey, AssistantSummary summary);
}

String assistantCacheDocId(String cacheKey) =>
    sha256.convert(utf8.encode(cacheKey)).toString();
