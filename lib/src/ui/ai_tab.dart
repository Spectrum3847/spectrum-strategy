library;

import 'package:flutter/material.dart';

import '../services/llama_runtime_service.dart';
import '../state/assistant_chat_controller.dart';
import '../theme/strategy_palette.dart';
import 'assistant_chat_screen.dart';
import 'assistant_setup_card.dart';
import 'mcp_tool_card.dart';
import 'glass_chrome.dart';

enum AiSection {
  chat('Chat', Icons.forum_outlined),
  models('Models', Icons.memory_outlined),
  tools('Tools', Icons.handyman_outlined);

  const AiSection(this.label, this.icon);

  final String label;
  final IconData icon;
}

class AiTab extends StatefulWidget {
  const AiTab({
    super.key,
    this.chatController,
    this.applies = true,
    this.hasLlamaRuntime = true,
    this.hasMcp = true,
    this.runtime,
  });

  final AssistantChatController? chatController;

  final bool applies;

  final bool hasLlamaRuntime;

  final bool hasMcp;

  final LlamaRuntimeService? runtime;

  @override
  State<AiTab> createState() => _AiTabState();
}

class _AiTabState extends State<AiTab> {
  AiSection _section = AiSection.chat;

  final Set<AiSection> _built = <AiSection>{};

  late final LlamaRuntimeService? _runtime = widget.hasLlamaRuntime
      ? (widget.runtime ?? LlamaRuntimeService.shared)
      : widget.runtime;

  bool _ready = false;

  int _readyCheck = 0;

  @override
  void initState() {
    super.initState();

    _runtime?.addListener(_checkReady);
    _checkReady();
  }

  @override
  void dispose() {
    _runtime?.removeListener(_checkReady);
    super.dispose();
  }

  Future<void> _checkReady() async {
    final generation = ++_readyCheck;
    final controller = widget.chatController;
    final ready = controller != null && await controller.isAvailable();
    if (!mounted || generation != _readyCheck || ready == _ready) return;
    setState(() => _ready = ready);
  }

  List<AiSection> get _availableSections => <AiSection>[
    if (widget.applies)
      for (final section in AiSection.values)
        if (_sectionApplies(section)) section,
  ];

  bool _sectionApplies(AiSection section) => switch (section) {
    AiSection.chat => widget.chatController != null,
    AiSection.models => widget.hasLlamaRuntime,
    AiSection.tools => widget.hasMcp,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final available = _availableSections;
    if (available.isEmpty) return _empty(theme);
    final section = available.contains(_section) ? _section : available.first;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (available.length > 1)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: SegmentedButton<AiSection>(
              segments: [
                for (final s in available)
                  ButtonSegment<AiSection>(
                    value: s,
                    icon: Icon(s.icon),
                    label: Text(s.label),
                  ),
              ],
              selected: {section},
              onSelectionChanged: (selected) => _show(selected.first),
            ),
          ),

        Expanded(
          child: IndexedStack(
            index: available.indexOf(section),
            children: [
              for (final s in available)
                if (s == section || _built.contains(s))
                  KeyedSubtree(key: ValueKey(s), child: _body(s))
                else
                  KeyedSubtree(
                    key: ValueKey(s),
                    child: const SizedBox.shrink(),
                  ),
            ],
          ),
        ),
      ],
    );
  }

  void _show(AiSection next) {
    setState(() {
      _built.add(_section);
      _section = next;
    });

    if (next == AiSection.chat) _checkReady();
  }

  Widget _body(AiSection section) {
    switch (section) {
      case AiSection.chat:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!_ready) _notReady(Theme.of(context)),

            Expanded(
              child: AssistantChatScreen(
                controller: widget.chatController!,
                embedded: true,
              ),
            ),
          ],
        );
      case AiSection.models:
        return SingleChildScrollView(
          padding:
              const EdgeInsets.all(16) +
              EdgeInsets.only(bottom: GlassChrome.bottomInsetOf(context)),
          child: AssistantSetupCard(runtime: widget.runtime),
        );
      case AiSection.tools:
        return SingleChildScrollView(
          padding:
              const EdgeInsets.all(16) +
              EdgeInsets.only(bottom: GlassChrome.bottomInsetOf(context)),
          child: const McpToolCard(),
        );
    }
  }

  Widget _notReady(ThemeData theme) => Container(
    margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: theme.colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(StrategyPalette.radiusSm),
    ),
    child: Row(
      children: [
        Icon(
          widget.hasLlamaRuntime ? Icons.download_outlined : Icons.info_outline,
          size: 18,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            widget.hasLlamaRuntime
                ? 'This chat answers from a model on this computer, and none '
                      'is ready yet. Download the llama.cpp runtime and a '
                      'model to start asking questions.'
                : 'This chat answers from Apple Intelligence on this device. '
                      'It needs iOS 26 on an iPhone that supports Apple '
                      'Intelligence, turned on in Settings, with its model '
                      'finished downloading.',
            style: theme.textTheme.bodySmall,
          ),
        ),
        if (widget.hasLlamaRuntime) ...[
          const SizedBox(width: 8),
          FilledButton.tonal(
            onPressed: () => _show(AiSection.models),
            child: const Text('Open Models'),
          ),
        ],
      ],
    ),
  );

  Widget _empty(ThemeData theme) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(
        'The AI assistant answers from a model on your own device, and this '
        'one has none. The generated summaries elsewhere in the app still '
        'work here.',
        textAlign: TextAlign.center,
        style: theme.textTheme.bodyMedium,
      ),
    ),
  );
}
