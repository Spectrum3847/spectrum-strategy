import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:spectrumstrategy/src/services/assistant/assistant_tool.dart';

class _FakeToolProvider implements AssistantToolProvider {
  _FakeToolProvider(this._specs);

  final List<AssistantToolSpec> _specs;
  final Map<String, String> _throwsOn = {};

  void alwaysThrowOn(String name) => _throwsOn[name] = 'boom';

  final Map<String, String Function(Map<String, dynamic>)> _handlers = {};

  void handle(String name, String Function(Map<String, dynamic>) handler) {
    _handlers[name] = handler;
  }

  @override
  Future<List<AssistantToolSpec>> tools() async => _specs;

  @override
  Future<String> call(String name, Map<String, dynamic> arguments) async {
    if (_throwsOn.containsKey(name)) {
      throw StateError(_throwsOn[name]!);
    }
    final handler = _handlers[name];
    if (handler != null) {
      return handler(arguments);
    }
    return 'result for $name';
  }
}

AssistantToolSpec _spec(String name) => AssistantToolSpec(
  name: name,
  description: 'test tool $name',
  parameters: const <String, dynamic>{'type': 'object', 'properties': {}},
);

class _HangingProvider implements AssistantToolProvider {
  @override
  Future<List<AssistantToolSpec>> tools() async => [
    const AssistantToolSpec(
      name: 'hangs',
      description: 'never answers',
      parameters: {'type': 'object', 'properties': {}},
    ),
  ];

  @override
  Future<String> call(String name, Map<String, dynamic> arguments) =>
      Completer<String>().future;
}

void main() {
  group('AssistantToolRegistry.tools', () {
    test('merges providers in order', () async {
      final a = _FakeToolProvider([_spec('a'), _spec('b')]);
      final b = _FakeToolProvider([_spec('c')]);
      final registry = AssistantToolRegistry([a, b]);

      final names = (await registry.tools()).map((s) => s.name).toList();
      expect(names, ['a', 'b', 'c']);
    });

    test('keeps the earlier provider on a duplicate name', () async {
      final earlier = _FakeToolProvider([_spec('shared')]);
      final later = _FakeToolProvider([_spec('shared'), _spec('later-only')]);
      final registry = AssistantToolRegistry([earlier, later]);

      final names = (await registry.tools()).map((s) => s.name).toList();
      expect(names, ['shared', 'later-only']);

      earlier.handle('shared', (_) => 'from earlier');
      later.handle('shared', (_) => 'from later');
      expect(await registry.call('shared', {}), 'from earlier');
    });
  });

  group('AssistantToolRegistry.call', () {
    test('routes a call to the provider that declared it', () async {
      final provider = _FakeToolProvider([_spec('lookup')]);
      provider.handle('lookup', (args) => 'team ${args['team']}');
      final registry = AssistantToolRegistry([provider]);

      expect(await registry.call('lookup', {'team': 3847}), 'team 3847');
    });

    test('an unknown tool name comes back as recoverable text', () async {
      final registry = AssistantToolRegistry([
        _FakeToolProvider([_spec('a')]),
      ]);

      final result = await registry.call('no_such_tool', {});
      expect(result, contains('no such tool'));
    });

    test('a provider that throws comes back as recoverable text', () async {
      final provider = _FakeToolProvider([_spec('flaky')]);
      provider.alwaysThrowOn('flaky');
      final registry = AssistantToolRegistry([provider]);

      final result = await registry.call('flaky', {});
      expect(result, contains('flaky'));
      expect(result, contains('boom'));
    });

    test('truncates a result over the character budget', () async {
      final provider = _FakeToolProvider([_spec('big')]);
      final huge = 'x' * (AssistantToolRegistry.maxResultChars + 500);
      provider.handle('big', (_) => huge);
      final registry = AssistantToolRegistry([provider]);

      final result = await registry.call('big', {});
      expect(result.length, lessThan(huge.length));
      expect(result, contains('Truncated'));
      expect(
        result.startsWith('x' * AssistantToolRegistry.maxResultChars),
        isTrue,
      );
    });

    test('a result under the budget is returned unchanged', () async {
      final provider = _FakeToolProvider([_spec('small')]);
      provider.handle('small', (_) => 'short answer');
      final registry = AssistantToolRegistry([provider]);

      expect(await registry.call('small', {}), 'short answer');
    });
  });
  test('a hanging tool is given up on instead of stalling the chat', () async {
    final registry = AssistantToolRegistry([
      _HangingProvider(),
    ], callTimeout: const Duration(milliseconds: 20));

    expect(await registry.call('hangs', {}), contains('took too long'));
  });

  test('truncation does not split a surrogate pair', () {
    const emoji = '\u{1F600}';
    final padded = 'a' * (AssistantToolRegistry.maxResultChars - 1);
    final text = '$padded$emoji$padded';

    final cut = AssistantToolRegistry.truncate(text);
    final body = cut.split('\n\n[Truncated').first;

    expect(body.length, AssistantToolRegistry.maxResultChars - 1);
    expect(
      body.codeUnits.any((u) => u >= 0xD800 && u <= 0xDFFF),
      isFalse,
      reason: 'no unpaired surrogate survives the cut',
    );
  });

  group('tool guidance', () {
    const spec = AssistantToolSpec(
      name: 'frc_team_history',
      description: 'A team\'s official season history.',
      guidance: 'Prefer scouting_team_summary for what our scouts observed.',
      parameters: <String, dynamic>{'type': 'object'},
    );

    test('the OpenAI shape carries both halves', () {
      final function = spec.toJson()['function']! as Map<String, dynamic>;
      expect(
        function['description'],
        'A team\'s official season history. Prefer scouting_team_summary '
        'for what our scouts observed.',
      );
    });

    test('a tool with no guidance reads the same as before', () {
      const plain = AssistantToolSpec(
        name: 'scouting_list_teams',
        description: 'Every team our scouts have an entry for.',
        parameters: <String, dynamic>{'type': 'object'},
      );
      expect(plain.fullDescription, plain.description);
    });
  });

  group('result truncation', () {
    test('honours a caller\'s tighter limit', () {
      final cut = AssistantToolRegistry.truncate('y' * 500, limit: 100);
      expect(cut, startsWith('y' * 100));
      expect(cut, contains('over the 100-character limit'));
    });
  });
}
