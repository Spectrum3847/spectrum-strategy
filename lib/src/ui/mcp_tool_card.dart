import 'package:flutter/material.dart';

import '../services/mcp/mcp_oauth_service.dart';

class McpToolCard extends StatefulWidget {
  const McpToolCard({this.oauth, super.key});

  final McpOAuthService? oauth;

  @override
  State<McpToolCard> createState() => _McpToolCardState();
}

class _McpToolCardState extends State<McpToolCard> {
  late final McpOAuthService _oauth = widget.oauth ?? McpOAuthService.shared;

  @override
  void initState() {
    super.initState();
    _oauth.addListener(_onChanged);
    _oauth.loadStoredState();
  }

  @override
  void dispose() {
    _oauth.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final connected = _oauth.isConnected;
    final connecting = _oauth.isConnecting;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Spectrum MCP tools', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Lets the local assistant read the same scouting data an '
              'external agent (Claude Code) reaches through the Spectrum '
              'MCP server. Read-only.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(
                  connected
                      ? Icons.check_circle_rounded
                      : Icons.cloud_off_rounded,
                  color: connected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    connecting
                        ? 'Connecting...'
                        : connected
                        ? 'Connected'
                        : 'Not connected',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
            if (_oauth.lastError != null) ...[
              const SizedBox(height: 8),
              Text(
                _oauth.lastError!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
            const SizedBox(height: 12),
            if (connected)
              OutlinedButton.icon(
                onPressed: connecting ? null : _oauth.disconnect,
                icon: const Icon(Icons.link_off_rounded),
                label: const Text('Disconnect'),
              )
            else
              FilledButton.icon(
                onPressed: connecting ? null : _oauth.connect,
                icon: const Icon(Icons.link_rounded),
                label: const Text('Connect'),
              ),
          ],
        ),
      ),
    );
  }
}
