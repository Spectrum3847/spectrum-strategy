library;

import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart' show visibleForTesting;

class AssistantToolSpec {
  const AssistantToolSpec({
    required this.name,
    required this.description,
    required this.parameters,
    this.guidance,
  });

  final String name;

  final String description;

  final String? guidance;

  final Map<String, dynamic> parameters;

  String get fullDescription =>
      guidance == null ? description : '$description $guidance';

  Map<String, dynamic> toJson() => <String, dynamic>{
    'type': 'function',
    'function': <String, dynamic>{
      'name': name,
      'description': fullDescription,
      'parameters': parameters,
    },
  };
}

abstract class AssistantToolProvider {
  Future<List<AssistantToolSpec>> tools();

  Future<String> call(String name, Map<String, dynamic> arguments);
}

class AssistantToolRegistry {
  AssistantToolRegistry(
    List<AssistantToolProvider> providers, {
    this.callTimeout = const Duration(seconds: 30),
  }) : _providers = List.unmodifiable(providers);

  static const int maxResultChars = 4000;

  final Duration callTimeout;

  final List<AssistantToolProvider> _providers;

  Future<Map<String, AssistantToolProvider>>? _owners;

  Future<List<AssistantToolSpec>> tools() async {
    final owners = await _resolveOwners();
    final specs = <AssistantToolSpec>[];
    for (final provider in _providers) {
      for (final spec in await _specsOf(provider)) {
        if (identical(owners[spec.name], provider)) {
          specs.add(spec);
        }
      }
    }
    return specs;
  }

  Future<String> call(
    String name,
    Map<String, dynamic> arguments, {
    int resultCharLimit = maxResultChars,
  }) async {
    final owner = (await _resolveOwners())[name];
    if (owner == null) {
      return 'Error: no such tool "$name". Pick one of the tools you were '
          'given and try again.';
    }
    try {
      return truncate(
        await owner.call(name, arguments).timeout(callTimeout),
        limit: resultCharLimit,
      );
    } on TimeoutException {
      return 'Error: tool "$name" took too long and was given up on. Answer '
          'with what you already have, or try a narrower query.';
    } catch (error) {
      return 'Error: tool "$name" failed: $error';
    }
  }

  Future<Map<String, AssistantToolProvider>> _resolveOwners() =>
      _owners ??= _buildOwners();

  Future<Map<String, AssistantToolProvider>> _buildOwners() async {
    final owners = <String, AssistantToolProvider>{};
    for (final provider in _providers) {
      for (final spec in await _specsOf(provider)) {
        if (owners.containsKey(spec.name)) {
          developer.log(
            'Duplicate assistant tool name "${spec.name}" from '
            '${provider.runtimeType}; keeping the earlier provider\'s tool.',
            name: 'AssistantToolRegistry',
          );
          continue;
        }
        owners[spec.name] = provider;
      }
    }
    return owners;
  }

  Future<List<AssistantToolSpec>> _specsOf(
    AssistantToolProvider provider,
  ) async {
    try {
      return await provider.tools().timeout(callTimeout);
    } catch (error) {
      developer.log(
        'Assistant tool provider ${provider.runtimeType} could not list its '
        'tools: $error',
        name: 'AssistantToolRegistry',
      );
      return const <AssistantToolSpec>[];
    }
  }

  static bool _isHighSurrogate(int unit) => unit >= 0xD800 && unit <= 0xDBFF;

  @visibleForTesting
  static String truncate(String text, {int limit = maxResultChars}) {
    if (text.length <= limit) {
      return text;
    }

    var end = limit;
    if (_isHighSurrogate(text.codeUnitAt(end - 1))) end -= 1;
    return '${text.substring(0, end)}\n\n'
        '[Truncated: this result was ${text.length} characters, over the '
        '$limit-character limit. Narrow the query (a single team, '
        'a smaller match range) instead of assuming you saw everything.]';
  }
}
