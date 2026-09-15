import 'package:flutter/material.dart';

import '../models/user_profile.dart';
import '../models/user_role.dart';
import '../state/user_role_controller.dart';

class UserManagementBody extends StatefulWidget {
  const UserManagementBody({required this.roleController, super.key});

  final UserRoleController roleController;

  @override
  State<UserManagementBody> createState() => _UserManagementBodyState();
}

class _UserManagementBodyState extends State<UserManagementBody> {
  late Stream<List<UserProfile>> _profiles = widget.roleController
      .streamAllProfiles();

  void _retry() {
    setState(() {
      _profiles = widget.roleController.streamAllProfiles();
    });
  }

  Future<void> _linkAccount(
    BuildContext context,
    UserRoleController roleController,
    UserProfile secondary,
    List<UserProfile> roster,
  ) async {
    final candidates =
        roster
            .where((p) => p.uid != secondary.uid && !p.isLinkedSecondary)
            .toList()
          ..sort(UserProfile.byDisplayName);
    final messenger = ScaffoldMessenger.of(context);
    final primary = await showDialog<UserProfile>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text(
          'Link ${secondary.email ?? secondary.displayName} to an account',
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
            child: Text(
              'The account keeps its own sign-in, but submits under the '
              'name and roles of the one you pick.',
              style: Theme.of(dialogContext).textTheme.bodySmall,
            ),
          ),
          for (final candidate in candidates)
            SimpleDialogOption(
              onPressed: () => Navigator.of(dialogContext).pop(candidate),
              child: Text(
                candidate.displayName.isEmpty
                    ? (candidate.email ?? candidate.uid)
                    : '${candidate.displayName} (${candidate.email ?? candidate.uid})',
              ),
            ),
          if (candidates.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 0, 24, 16),
              child: Text('No other accounts to link to.'),
            ),
        ],
      ),
    );
    if (primary == null) return;
    try {
      await roleController.linkAccounts(secondary: secondary, primary: primary);
      messenger.showSnackBar(
        SnackBar(content: Text('Linked to ${primary.displayName}.')),
      );
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not link the account: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final roleController = widget.roleController;
    return StreamBuilder<List<UserProfile>>(
      stream: _profiles,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Could not load users: ${snapshot.error}',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _retry,
                    child: const Text('Try again'),
                  ),
                ],
              ),
            ),
          );
        }
        final profiles = snapshot.data ?? [];
        if (profiles.isEmpty) {
          return const Center(child: Text('No users found.'));
        }
        return ListView.builder(
          itemCount: profiles.length,
          itemBuilder: (context, i) {
            final profile = profiles[i];
            final isOwnProfile = profile.uid == roleController.currentUid;
            final primaries = profiles.where(
              (p) => p.uid == profile.canonicalUid,
            );
            final primary = primaries.isEmpty ? null : primaries.first;
            return _UserProfileTile(
              key: ValueKey(profile.uid),
              profile: profile,
              isOwnProfile: isOwnProfile,
              primary: primary,
              onRolesChanged: isOwnProfile
                  ? null
                  : (newRoles) => roleController.updateUserRolesWithLinked(
                      profile,
                      newRoles,
                      profiles,
                    ),
              onRenamed: isOwnProfile
                  ? null
                  : (newName) =>
                        roleController.updateDisplayName(profile.uid, newName),
              onLink: isOwnProfile
                  ? null
                  : () => _linkAccount(
                      context,
                      roleController,
                      profile,
                      profiles,
                    ),
              onUnlink: isOwnProfile || !profile.isLinkedSecondary
                  ? null
                  : () => roleController.unlinkAccount(profile),
            );
          },
        );
      },
    );
  }
}

class _UserProfileTile extends StatefulWidget {
  const _UserProfileTile({
    required this.profile,
    required this.isOwnProfile,
    required this.primary,
    required this.onRolesChanged,
    required this.onRenamed,
    required this.onLink,
    required this.onUnlink,
    super.key,
  });

  final UserProfile profile;
  final bool isOwnProfile;

  final UserProfile? primary;
  final Future<void> Function(Set<UserRole>)? onRolesChanged;
  final Future<void> Function(String)? onRenamed;
  final Future<void> Function()? onLink;
  final Future<void> Function()? onUnlink;

  @override
  State<_UserProfileTile> createState() => _UserProfileTileState();
}

class _UserProfileTileState extends State<_UserProfileTile> {
  bool _expanded = false;
  bool _saving = false;
  late Set<UserRole> _pendingRoles;

  @override
  void initState() {
    super.initState();
    _pendingRoles = Set.of(widget.profile.roles);
  }

  @override
  void didUpdateWidget(_UserProfileTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profile.uid != widget.profile.uid) {
      _expanded = false;
      _pendingRoles = Set.of(widget.profile.roles);
    } else if (!_expanded) {
      _pendingRoles = Set.of(widget.profile.roles);
    }
  }

  Future<void> _save() async {
    if (_pendingRoles.isEmpty) {
      _pendingRoles = {UserRole.viewer};
    }
    setState(() => _saving = true);
    try {
      await widget.onRolesChanged!(_pendingRoles);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed to save roles: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
          _expanded = false;
        });
      }
    }
  }

  Future<void> _rename() async {
    final profile = widget.profile;
    final controller = TextEditingController(text: profile.displayName);
    final newName = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Change display name'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'The name on everything ${profile.email ?? profile.uid} '
              'submits. It reaches their device on their next sign-in.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              maxLength: 64,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Display name'),
              onSubmitted: (value) =>
                  Navigator.of(dialogContext).pop(value.trim()),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (newName == null || newName.isEmpty || !mounted) return;
    setState(() => _saving = true);
    try {
      await widget.onRenamed!(newName);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed to rename: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _link() async {
    setState(() => _saving = true);
    try {
      await widget.onLink!();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _unlink() async {
    setState(() => _saving = true);
    try {
      await widget.onUnlink!();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed to unlink: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = widget.profile;
    final subtitleParts = <String>[
      if (profile.email != null) profile.email!,
      'uid: ${profile.uid}',
    ];
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            title: Text(
              profile.displayName.isEmpty ? '(no name)' : profile.displayName,
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final part in subtitleParts)
                  Text(part, style: Theme.of(context).textTheme.bodySmall),
                Text(
                  'Roles: ${profile.roles.displayText}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (profile.isLinkedSecondary)
                  Text(
                    'Linked to ${widget.primary?.displayName ?? profile.canonicalUid}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                if (profile.linkedEmails.isNotEmpty)
                  Text(
                    'Also signs in as: ${profile.linkedEmails.join(", ")}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                if (widget.isOwnProfile)
                  Text(
                    'You cannot edit your own roles.',
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(fontStyle: FontStyle.italic),
                  ),
              ],
            ),
            trailing: widget.isOwnProfile
                ? null
                : IconButton(
                    icon: Icon(
                      _expanded
                          ? Icons.expand_less_rounded
                          : Icons.edit_rounded,
                    ),
                    tooltip: _expanded ? 'Collapse' : 'Edit roles',
                    onPressed: () => setState(() => _expanded = !_expanded),
                  ),
            isThreeLine: true,
          ),
          if (_expanded && !widget.isOwnProfile) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text(
                'Assign roles',
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ),
            if (widget.onRenamed != null ||
                widget.onLink != null ||
                widget.onUnlink != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
                child: Wrap(
                  children: [
                    if (widget.onRenamed != null)
                      TextButton.icon(
                        onPressed: _saving ? null : _rename,
                        icon: const Icon(Icons.badge_rounded),
                        label: const Text('Change name'),
                      ),
                    if (widget.onUnlink == null)
                      TextButton.icon(
                        onPressed: _saving ? null : _link,
                        icon: const Icon(Icons.link_rounded),
                        label: const Text('Link to account'),
                      )
                    else
                      TextButton.icon(
                        onPressed: _saving ? null : _unlink,
                        icon: const Icon(Icons.link_off_rounded),
                        label: const Text('Unlink'),
                      ),
                  ],
                ),
              ),
            for (final role in UserRole.values)
              CheckboxListTile(
                title: Text(role.displayName),
                value: _pendingRoles.contains(role),
                onChanged: _saving
                    ? null
                    : (checked) {
                        setState(() {
                          if (checked == true) {
                            _pendingRoles.add(role);
                          } else {
                            _pendingRoles.remove(role);
                          }
                        });
                      },
                dense: true,
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _saving
                        ? null
                        : () => setState(() {
                            _expanded = false;
                            _pendingRoles = Set.of(profile.roles);
                          }),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Save'),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
