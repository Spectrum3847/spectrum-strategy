import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../models/assistant_chat_session.dart';
import '../services/assistant/assistant_backend.dart';
import '../services/llama_runtime_service.dart';
import '../state/assistant_chat_controller.dart';
import '../theme/strategy_palette.dart';
import '../widgets/empty_state.dart';
import 'glass_chrome.dart';
import 'platform_target.dart';
import '../widgets/glass_modal.dart';
import '../widgets/glass_popup_menu.dart';

class AssistantChatScreen extends StatefulWidget {
  const AssistantChatScreen({
    required this.controller,
    this.embedded = false,
    this.runtime,
    super.key,
  });

  final AssistantChatController controller;
  final bool embedded;

  final LlamaRuntimeService? runtime;

  static const double sidebarBreakpoint = 900;

  @override
  State<AssistantChatScreen> createState() => _AssistantChatScreenState();
}

class _AssistantChatScreenState extends State<AssistantChatScreen> {
  final TextEditingController _composer = TextEditingController();
  final ScrollController _scroll = ScrollController();

  List<AssistantModel> _installed = const <AssistantModel>[];

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
    widget.controller.bootstrap();
    _loadInstalled();
  }

  Future<void> _loadInstalled() async {
    if (!isDesktopPlatform && widget.runtime == null) return;
    final runtime = widget.runtime ?? LlamaRuntimeService.shared;
    try {
      final installed = await runtime.installedModels();
      if (mounted) setState(() => _installed = installed);
    } catch (_) {}
  }

  @override
  void didUpdateWidget(AssistantChatScreen old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_onChanged);
      widget.controller.addListener(_onChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    _composer.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onChanged() {
    setState(() {});

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
      );
    });
  }

  Future<void> _send() async {
    final text = _composer.text;
    _composer.clear();
    await widget.controller.send(text);
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = widget.embedded
        ? GlassChrome.bottomInsetOf(context)
        : 0.0;
    final body = _Body(
      controller: widget.controller,
      composer: _composer,
      scroll: _scroll,
      onSend: _send,
      installed: _installed,
      composerBottomInset: bottomInset,
    );
    if (widget.embedded) {
      return body;
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Assistant')),
      body: body,
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.controller,
    required this.composer,
    required this.scroll,
    required this.onSend,
    required this.installed,
    required this.composerBottomInset,
  });

  final AssistantChatController controller;
  final TextEditingController composer;
  final ScrollController scroll;
  final Future<void> Function() onSend;
  final List<AssistantModel> installed;

  final double composerBottomInset;

  @override
  Widget build(BuildContext context) {
    final wide =
        MediaQuery.sizeOf(context).width >=
        AssistantChatScreen.sidebarBreakpoint;
    final conversation = _conversation(context, wide: wide);
    if (!wide) return conversation;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(width: 260, child: _ChatSidebar(controller: controller)),
        VerticalDivider(width: 1, color: StrategyPalette.borderOf(context)),
        Expanded(child: conversation),
      ],
    );
  }

  Widget _conversation(BuildContext context, {required bool wide}) {
    final messages = controller.messages;

    return Column(
      children: [
        _ChatToolbar(
          controller: controller,
          installed: installed,
          showChatList: !wide,
        ),
        Divider(height: 1, color: StrategyPalette.borderOf(context)),
        Expanded(
          child: messages.isEmpty
              ? const EmptyState(
                  icon: Icons.forum_outlined,
                  message:
                      'Ask about a team, a match, or a pick list. Chats are '
                      'saved on this computer and are private to you.',
                )
              : Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: ListView.builder(
                      controller: scroll,
                      padding: const EdgeInsets.all(16),
                      itemCount:
                          messages.length + (controller.isSending ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index >= messages.length) {
                          return const _ThinkingRow();
                        }

                        return _MessageBubble(
                          message: messages[index],
                          onRetry:
                              index == messages.length - 1 &&
                                  !controller.isSending
                              ? controller.retryLast
                              : null,
                        );
                      },
                    ),
                  ),
                ),
        ),
        Divider(height: 1, color: StrategyPalette.borderOf(context)),
        _Composer(
          controller: composer,
          enabled: !controller.isSending,
          onSend: onSend,
          bottomInset: composerBottomInset,
        ),
      ],
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message, this.onRetry});

  final AssistantChatMessage message;

  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    switch (message.kind) {
      case AssistantChatMessageKind.user:
        return Align(
          alignment: Alignment.centerRight,
          child: Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            constraints: BoxConstraints(
              maxWidth: MediaQuery.sizeOf(context).width * 0.8,
            ),
            decoration: BoxDecoration(
              color: StrategyPalette.chipSelectedOf(context),
              borderRadius: BorderRadius.circular(StrategyPalette.radiusSm),
            ),
            child: Text(
              message.text,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: StrategyPalette.onChipSelectedOf(context)),
            ),
          ),
        );
      case AssistantChatMessageKind.assistant:
        final scheme = Theme.of(context).colorScheme;
        return Align(
          alignment: Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            constraints: BoxConstraints(
              maxWidth: MediaQuery.sizeOf(context).width * 0.8,
            ),
            decoration: BoxDecoration(
              color: StrategyPalette.surfaceOf(context),
              borderRadius: BorderRadius.circular(StrategyPalette.radiusSm),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                MarkdownBody(
                  data: message.text,
                  styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)),
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        _sourceLabel(message),
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ),
                    if (onRetry != null) ...[
                      const SizedBox(width: 8),
                      _RetryButton(onPressed: onRetry!),
                    ],
                  ],
                ),
              ],
            ),
          ),
        );
      case AssistantChatMessageKind.error:
        final scheme = Theme.of(context).colorScheme;
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(12),
          width: double.infinity,
          decoration: BoxDecoration(
            color: StrategyPalette.surfaceOf(context),
            border: Border.all(color: scheme.error),
            borderRadius: BorderRadius.circular(StrategyPalette.radiusSm),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.error_outline_rounded, size: 18, color: scheme.error),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  message.text,
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: scheme.error),
                ),
              ),
              if (onRetry != null) ...[
                const SizedBox(width: 8),
                _RetryButton(onPressed: onRetry!),
              ],
            ],
          ),
        );
    }
  }

  static String _sourceLabel(AssistantChatMessage message) {
    final backend = switch (message.source) {
      AssistantSource.openRouter => 'OpenRouter',
      AssistantSource.apple => 'On-device (Apple)',
      AssistantSource.local => 'Local model',
      null => 'Unknown backend',
    };
    final model = message.model;
    return model == null || model.isEmpty ? backend : '$backend · $model';
  }
}

class _RetryButton extends StatelessWidget {
  const _RetryButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => TextButton.icon(
    onPressed: onPressed,
    icon: const Icon(Icons.refresh, size: 16),
    label: const Text('Retry'),
    style: TextButton.styleFrom(
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      textStyle: Theme.of(context).textTheme.bodySmall,
      minimumSize: const Size(0, 32),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    ),
  );
}

class _ThinkingRow extends StatelessWidget {
  const _ThinkingRow();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: StrategyPalette.surfaceOf(context),
          borderRadius: BorderRadius.circular(StrategyPalette.radiusSm),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              height: 14,
              width: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 10),

            Flexible(
              child: Text(
                'Thinking. On-device inference can take real seconds.',
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.enabled,
    required this.onSend,
    required this.bottomInset,
  });

  final TextEditingController controller;
  final bool enabled;
  final Future<void> Function() onSend;

  final double bottomInset;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(12, 12, 12, 12 + bottomInset),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  enabled: enabled,
                  minLines: 1,
                  maxLines: 4,
                  textInputAction: TextInputAction.send,
                  onSubmitted: enabled ? (_) => onSend() : null,
                  decoration: const InputDecoration(
                    hintText: 'Ask a follow-up',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.all(
                        Radius.circular(StrategyPalette.radiusSm),
                      ),
                    ),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: enabled ? onSend : null,
                icon: const Icon(Icons.send_rounded),
                tooltip: 'Send',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChatSidebar extends StatelessWidget {
  const _ChatSidebar({required this.controller});

  final AssistantChatController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sessions = controller.sessions;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: controller.newChat,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('New chat'),
                ),
              ),
              const SizedBox(width: 8),

              IconButton(
                onPressed: controller.refresh,
                icon: const Icon(Icons.sync, size: 18),
                tooltip: 'Sync chats from your other devices',
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: sessions.length,
            itemBuilder: (context, index) {
              final session = sessions[index];
              final selected = session.id == controller.activeId;
              return ListTile(
                dense: true,
                selected: selected,
                title: Text(
                  session.displayTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium,
                ),
                onTap: () => controller.selectChat(session.id),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18),
                  tooltip: 'Delete chat',
                  onPressed: () => _confirmDelete(context, session),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    AssistantChatSession session,
  ) async {
    final confirmed = await showGlassConfirmDialog<bool>(
      context: context,
      title: 'Delete this chat?',
      content: Text(
        '"${session.displayTitle}" is deleted for good. There is no undo.',
      ),
      actionsBuilder: (dialogContext) => [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Delete'),
        ),
      ],
    );
    if (confirmed ?? false) await controller.deleteChat(session.id);
  }
}

class _ChatToolbar extends StatelessWidget {
  const _ChatToolbar({
    required this.controller,
    required this.installed,
    required this.showChatList,
  });

  final AssistantChatController controller;
  final List<AssistantModel> installed;
  final bool showChatList;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final session = controller.activeSession;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Row(
        children: [
          if (showChatList) ...[
            IconButton(
              icon: const Icon(Icons.forum_outlined),
              tooltip: 'Saved chats',
              onPressed: () => _openChatSheet(context),
            ),
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: 'New chat',
              onPressed: controller.newChat,
            ),
          ],
          Expanded(
            child: Text(
              session?.displayTitle ?? 'New chat',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall,
            ),
          ),
          if (installed.isNotEmpty)
            _ModelSwitcher(controller: controller, installed: installed),
        ],
      ),
    );
  }

  Future<void> _openChatSheet(BuildContext context) =>
      showGlassModalBottomSheet<void>(
        context: context,
        builder: (context) =>
            SizedBox(height: 400, child: _ChatSidebar(controller: controller)),
      );
}

class _ModelSwitcher extends StatelessWidget {
  const _ModelSwitcher({required this.controller, required this.installed});

  final AssistantChatController controller;
  final List<AssistantModel> installed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selectedId = controller.activeSession?.modelId;
    return GlassPopupMenuButton<String?>(
      tooltip: 'Model for this chat',
      onSelected: controller.selectModel,
      itemBuilder: (context) => <PopupMenuEntry<String?>>[
        const PopupMenuItem<String?>(value: null, child: Text('Automatic')),
        const PopupMenuDivider(),
        for (final model in installed)
          PopupMenuItem<String?>(value: model.id, child: Text(model.name)),
      ],
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_labelFor(selectedId), style: theme.textTheme.labelMedium),
          const Icon(Icons.arrow_drop_down, size: 18),
        ],
      ),
    );
  }

  String _labelFor(String? id) {
    if (id == null) return 'Automatic';
    for (final model in installed) {
      if (model.id == id) return model.name;
    }

    return 'Automatic';
  }
}
