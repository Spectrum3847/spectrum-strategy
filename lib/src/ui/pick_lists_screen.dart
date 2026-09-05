import 'package:flutter/material.dart';

import '../models/pick_list.dart';
import '../services/pick_list_sync_service.dart';
import '../state/failed_write_tracker.dart';
import '../state/pick_list_controller.dart';
import '../widgets/empty_state.dart';
import '../widgets/sync_status_pill.dart';
import '../widgets/text_prompt.dart';

class PickListsScreen extends StatelessWidget {
  const PickListsScreen({
    required this.controller,
    this.embedded = false,
    super.key,
  });

  final PickListController controller;

  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final body = Column(
      children: [
        _PickListHeader(
          controller: controller,
          onCreate: () => _create(context),
        ),
        Expanded(child: _lists()),
      ],
    );
    if (embedded) return body;
    return Scaffold(
      appBar: AppBar(title: const Text('Pick lists')),
      body: body,
    );
  }

  Widget _lists() {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final uid = controller.currentUserUid;
        final all = controller.lists;

        final myLists = uid == null
            ? all
            : all
                  .where((l) => l.authorUid.isEmpty || l.authorUid == uid)
                  .toList();
        final teamLists = uid == null
            ? <PickList>[]
            : all
                  .where((l) => l.authorUid.isNotEmpty && l.authorUid != uid)
                  .toList();

        if (myLists.isEmpty && teamLists.isEmpty) {
          return EmptyState(
            icon: Icons.format_list_numbered_rounded,
            message:
                'No pick lists yet.\nTap New list to rank teams for '
                'alliance selection.',
          );
        }

        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              children: [
                if (myLists.isNotEmpty) ...[
                  _SectionHeader(
                    label: 'Your lists',
                    hint: uid == null
                        ? 'Saved on this device. Sign in to share with the '
                              'team.'
                        : 'Saved and shared with your team automatically.',
                  ),
                  const SizedBox(height: 8),
                  for (final list in myLists)
                    _MyListTile(
                      list: list,
                      onTap: () => _open(context, list.id),
                    ),
                  const SizedBox(height: 16),
                ],
                if (teamLists.isNotEmpty) ...[
                  _SectionHeader(
                    label: 'Team lists',
                    hint: 'Built by teammates. Anyone can reorder these.',
                  ),
                  const SizedBox(height: 8),
                  for (final list in teamLists)
                    _TeamListTile(
                      list: list,
                      onTap: () => _open(context, list.id),
                    ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  void _open(BuildContext context, String id) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            PickListEditorScreen(controller: controller, listId: id),
      ),
    );
  }

  Future<void> _create(BuildContext context) async {
    final name = await promptText(
      context,
      title: 'New pick list',
      hint: 'List name',
    );
    if (name == null) return;
    final list = await controller.create(name);
    if (!context.mounted) return;
    if (list == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not create the pick list.')),
      );
      return;
    }
    _open(context, list.id);
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label, this.hint});

  final String label;

  final String? hint;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: textTheme.labelMedium?.copyWith(
              color: scheme.onSurfaceVariant,
              letterSpacing: 0.5,
            ),
          ),
          if (hint != null)
            Text(
              hint!,
              style: textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }
}

const double _headerStackBelow = 400;

class _PickListHeader extends StatelessWidget {
  const _PickListHeader({required this.controller, required this.onCreate});

  final PickListController controller;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),

          child: LayoutBuilder(
            builder: (context, constraints) {
              final pill = AnimatedBuilder(
                animation: controller,
                builder: (context, _) => Align(
                  alignment: Alignment.centerLeft,
                  child: _PickListSyncPill(
                    status: controller.syncStatus,
                    failedWrites: controller.failedWrites,
                  ),
                ),
              );
              final createButton = FilledButton.icon(
                onPressed: onCreate,
                icon: const Icon(Icons.add_rounded),
                label: const Text('New list'),
              );
              if (constraints.maxWidth < _headerStackBelow) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [pill, const SizedBox(height: 8), createButton],
                );
              }
              return Row(
                children: [
                  Expanded(child: pill),
                  const SizedBox(width: 12),
                  createButton,
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _PickListSyncPill extends StatelessWidget {
  const _PickListSyncPill({required this.status, required this.failedWrites});

  final PickListSyncStatus status;

  final FailedWriteTracker failedWrites;

  @override
  Widget build(BuildContext context) {
    if (failedWrites.hasFailures) {
      final count = failedWrites.unlandedCount;
      return SyncStatusPill(
        label: '$count edit${count == 1 ? '' : 's'} not saved',
        icon: Icons.cloud_off_rounded,
        isFailure: true,
      );
    }

    final (String label, IconData icon) = switch (status.state) {
      PickListSyncState.signedOut => (
        'Not signed in to sync',
        Icons.cloud_off_rounded,
      ),
      PickListSyncState.noAccess => (
        'No team access yet',
        Icons.lock_outline_rounded,
      ),
      PickListSyncState.syncing => ('Syncing...', Icons.sync_rounded),
      PickListSyncState.synced => ('Synced', Icons.cloud_done_rounded),
      PickListSyncState.offline => ('Offline', Icons.cloud_off_rounded),
    };

    return SyncStatusPill(label: label, icon: icon);
  }
}

class _MyListTile extends StatelessWidget {
  const _MyListTile({required this.list, required this.onTap});

  final PickList list;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final count = list.teamNumbers.length;
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(list.name),
        subtitle: Text('$count ${count == 1 ? 'team' : 'teams'}'),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: onTap,
      ),
    );
  }
}

class _TeamListTile extends StatelessWidget {
  const _TeamListTile({required this.list, required this.onTap});

  final PickList list;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final count = list.teamNumbers.length;
    final authorName = list.authorDisplayName.isNotEmpty
        ? list.authorDisplayName
        : 'Teammate';
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(list.name),
        subtitle: Text('$count ${count == 1 ? 'team' : 'teams'} · $authorName'),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: onTap,
      ),
    );
  }
}

class PickListEditorScreen extends StatefulWidget {
  const PickListEditorScreen({
    required this.controller,
    required this.listId,
    super.key,
  });

  final PickListController controller;
  final String listId;

  @override
  State<PickListEditorScreen> createState() => _PickListEditorScreenState();
}

class _PickListEditorScreenState extends State<PickListEditorScreen> {
  final TextEditingController _teamCtrl = TextEditingController();
  final FocusNode _teamFocus = FocusNode();

  @override
  void dispose() {
    _teamCtrl.dispose();
    _teamFocus.dispose();
    super.dispose();
  }

  void _addTeams(String id) {
    final numbers = _teamCtrl.text
        .split(RegExp(r'[^0-9]+'))
        .map((s) => int.tryParse(s))
        .whereType<int>()
        .where((n) => n > 0);
    for (final team in numbers) {
      widget.controller.addTeam(id, team);
    }
    _teamCtrl.clear();
    _teamFocus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final list = widget.controller.byId(widget.listId);
        if (list == null) {
          return const Scaffold(
            body: Center(child: Text('This pick list was deleted.')),
          );
        }
        final teams = list.teamNumbers;
        final uid = widget.controller.currentUserUid;
        final isMine = list.authorUid.isEmpty || list.authorUid == uid;
        final authorName = list.authorDisplayName.isNotEmpty
            ? list.authorDisplayName
            : 'a teammate';
        return Scaffold(
          appBar: AppBar(
            title: Text(list.name),
            actions: [
              if (isMine) ...[
                IconButton(
                  tooltip: 'Rename',
                  icon: const Icon(Icons.edit_rounded),
                  onPressed: () => _rename(list.id, list.name),
                ),
                IconButton(
                  tooltip: 'Delete list',
                  icon: const Icon(Icons.delete_outline_rounded),
                  onPressed: () => _deleteList(list.id),
                ),
              ],
            ],
            bottom: isMine
                ? null
                : PreferredSize(
                    preferredSize: const Size.fromHeight(24),
                    child: Padding(
                      padding: const EdgeInsets.only(left: 72, bottom: 8),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'by $authorName · everyone can edit the ranking',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                        ),
                      ),
                    ),
                  ),
          ),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _teamCtrl,
                            focusNode: _teamFocus,
                            keyboardType: TextInputType.number,
                            textInputAction: TextInputAction.done,
                            decoration: const InputDecoration(
                              labelText: 'Add team numbers',
                              hintText: 'e.g. 3847, 254, 118',
                            ),
                            onSubmitted: (_) => _addTeams(list.id),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.icon(
                          onPressed: () => _addTeams(list.id),
                          icon: const Icon(Icons.add_rounded, size: 18),
                          label: const Text('Add'),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: teams.isEmpty
                        ? EmptyState(
                            icon: Icons.groups_rounded,
                            message:
                                'No teams yet.\nAdd team numbers, then drag to '
                                'rank them. The top is your first pick.',
                          )
                        : ReorderableListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            itemCount: teams.length,

                            onReorderItem: (oldIndex, newIndex) => widget
                                .controller
                                .reorder(list.id, oldIndex, newIndex),
                            itemBuilder: (context, i) {
                              final team = teams[i];
                              return Card(
                                key: ValueKey<int>(team),
                                margin: const EdgeInsets.only(bottom: 8),
                                child: ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: Theme.of(context)
                                        .colorScheme
                                        .primaryContainer,
                                    child: Text('${i + 1}'),
                                  ),
                                  title: Text(
                                    team.toString(),
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(fontWeight: FontWeight.w700),
                                  ),
                                  trailing: IconButton(
                                    tooltip: 'Remove',
                                    icon: const Icon(Icons.close_rounded),
                                    onPressed: () => widget.controller
                                        .removeTeam(list.id, team),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _rename(String id, String current) async {
    final name = await promptText(
      context,
      title: 'Rename pick list',
      hint: 'List name',
      initial: current,
    );
    if (name != null) widget.controller.rename(id, name);
  }

  Future<void> _deleteList(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this pick list?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    final deleted = await widget.controller.delete(id);
    if (!mounted) return;
    if (!deleted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not delete this pick list.')),
      );
      return;
    }
    Navigator.of(context).pop();
  }
}
