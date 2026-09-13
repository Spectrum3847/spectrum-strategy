import 'dart:async';

import 'package:flutter/material.dart';

import '../models/user_role.dart';
import '../scouting/services/scouting_sync_service.dart';
import '../scouting/state/scouting_controller.dart';
import '../services/spectrum_auth_service.dart';
import '../state/user_role_controller.dart';

class SignInScreen extends StatefulWidget {
  const SignInScreen({
    required this.authService,
    required this.scoutingController,
    required this.userRoleController,
    super.key,
  });

  final SpectrumAuthService authService;
  final ScoutingController scoutingController;
  final UserRoleController userRoleController;

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  String? _statusMessage;
  StreamSubscription<SpectrumAuthSnapshot>? _authSubscription;

  SpectrumAuthService get _auth => widget.authService;
  ScoutingController get _scouting => widget.scoutingController;
  UserRoleController get _roles => widget.userRoleController;

  @override
  void initState() {
    super.initState();
    _authSubscription = _auth.snapshotStream.listen((_) {
      if (mounted) setState(() {});
    });
    _scouting.addListener(_onScoutingChanged);
    _roles.addListener(_onRoleChanged);
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _scouting.removeListener(_onScoutingChanged);
    _roles.removeListener(_onRoleChanged);
    super.dispose();
  }

  void _onRoleChanged() {
    if (mounted) setState(() {});
  }

  void _onScoutingChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _signIn() async {
    setState(() => _statusMessage = null);
    await _auth.signIn();
  }

  Future<void> _signOut() async {
    setState(() => _statusMessage = null);
    await _auth.signOut();
  }

  Future<void> _syncNow() async {
    setState(() => _statusMessage = 'Sync requested.');
    await _scouting.syncNow();
  }

  String _syncLabel(ScoutingSyncStatus status) {
    switch (status.state) {
      case ScoutingSyncState.signedOut:
        return 'Sync is off (not signed in).';
      case ScoutingSyncState.noAccess:
        return 'Sync is off. Your account has no team access yet; ask an '
            'admin to approve it.';
      case ScoutingSyncState.syncing:
        return 'Syncing...';
      case ScoutingSyncState.synced:
        final at = status.lastSyncedAt;
        if (at == null) return 'Synced.';
        return 'Synced at ${_formatTime(at)}.';
      case ScoutingSyncState.offline:
        return 'Offline. Entries stay on this device and sync when the '
            'connection returns.';
    }
  }

  String _formatTime(DateTime value) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(value.hour)}:${two(value.minute)}:${two(value.second)}';
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _auth.snapshot;
    final syncStatus = _scouting.syncStatus;
    return Scaffold(
      appBar: AppBar(title: const Text('Account')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildAccountCard(context, snapshot),
          const SizedBox(height: 16),
          _buildSyncCard(context, syncStatus),
          const SizedBox(height: 16),
          _buildAboutCard(context),
        ],
      ),
    );
  }

  Widget _buildAccountCard(
    BuildContext context,
    SpectrumAuthSnapshot snapshot,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Account', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            ..._accountBody(context, snapshot),
          ],
        ),
      ),
    );
  }

  List<Widget> _accountBody(
    BuildContext context,
    SpectrumAuthSnapshot snapshot,
  ) {
    switch (snapshot.state) {
      case SpectrumAuthState.unknown:
        return const [
          Row(
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 12),
              Text('Checking your session...'),
            ],
          ),
        ];
      case SpectrumAuthState.signingIn:
        return const [
          Row(
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 12),
              Text('Signing in...'),
            ],
          ),
        ];
      case SpectrumAuthState.error:
        return [
          Text(
            'Sign-in failed: ${snapshot.error ?? "unknown error"}',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _signIn,
            icon: const Icon(Icons.login_rounded),
            label: const Text('Try again'),
          ),
        ];
      case SpectrumAuthState.signedIn:
        final user = snapshot.user;
        if (user == null) {
          return _accountBody(
            context,
            const SpectrumAuthSnapshot(state: SpectrumAuthState.signedOut),
          );
        }
        final linkedEmails = _roles.linkedEmails;
        return [
          Text(
            user.displayName.isEmpty
                ? (user.email ?? 'Signed in')
                : user.displayName,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          if (user.email != null)
            Text(user.email!, style: Theme.of(context).textTheme.bodySmall),
          if (_roles.isLinkedSecondary)
            Text(
              'Linked to your main account. Your name and access come from '
              'there.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          if (!_roles.isLinkedSecondary)
            Text(
              'Ask an admin to change the name on your submissions.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          if (linkedEmails.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Also signs in as: ${linkedEmails.join(", ")}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 4),
          Text(
            'uid: ${user.uid}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 4),
          Text(
            'Roles: ${_roles.roles.displayText}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _signOut,
            icon: const Icon(Icons.logout_rounded),
            label: const Text('Sign out'),
          ),
        ];
      case SpectrumAuthState.signedOut:
        return [
          const Text(
            'Sign in with your team Google account to get access. Access is '
            'granted through Spectrum Tasks: if you are not on the team '
            'roster there yet, ask an admin to approve you before signing '
            'in. Once you have signed in, the app keeps working offline and '
            'syncs your entries when you are back online.',
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _signIn,
            icon: const Icon(Icons.login_rounded),
            label: const Text('Sign in with Google'),
          ),
        ];
    }
  }

  Widget _buildSyncCard(BuildContext context, ScoutingSyncStatus status) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Sync', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              _syncLabel(status),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (_statusMessage != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _statusMessage!,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed:
                  status.state == ScoutingSyncState.signedOut ||
                      status.state == ScoutingSyncState.noAccess
                  ? null
                  : _syncNow,
              icon: const Icon(Icons.sync_rounded),
              label: const Text('Sync now'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAboutCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'About sign-in',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            const Text(
              'Sign in with your team Google account (the one approved in '
              'Spectrum Tasks) to sync scout entries. Anyone signed in can '
              'see all team scout entries, but only the original author can '
              'change or delete their own.',
            ),
          ],
        ),
      ),
    );
  }
}
