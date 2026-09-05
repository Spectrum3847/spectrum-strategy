import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show AssetManifest, rootBundle;
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../models/user_role.dart';

const Set<UserRole> _members = {
  UserRole.scouter,
  UserRole.strategy,
  UserRole.admin,
  UserRole.developer,
};
const Set<UserRole> _leads = {
  UserRole.strategy,
  UserRole.admin,
  UserRole.developer,
};
const Set<UserRole> _adminOnly = {UserRole.admin, UserRole.developer};
const Set<UserRole> _devOnly = {UserRole.developer};

class _DocEntry {
  const _DocEntry({
    required this.title,
    required this.asset,
    required this.group,
    this.subtitle = '',
    this.roles = _members,
  });

  final String title;
  final String subtitle;

  final String asset;
  final String group;

  final Set<UserRole> roles;

  bool visibleTo(Set<UserRole> userRoles) => roles.any(userRoles.contains);
}

const List<_DocEntry> _docs = <_DocEntry>[
  _DocEntry(
    title: 'Using Spectrum Strategy',
    subtitle: 'How the app works, plus answers to common questions',
    asset: 'docs/using-the-app.md',
    group: 'Using the app',
  ),
  _DocEntry(
    title: 'Scouter Manual',
    subtitle: 'How to capture scouting data and handle accuracy alerts',
    asset: 'docs/scouter-manual.md',
    group: 'Role manuals',
    roles: _members,
  ),
  _DocEntry(
    title: 'Strategy Manual',
    subtitle: 'Using the strategy board, prematch analysis, and pick lists',
    asset: 'docs/strategy-manual.md',
    group: 'Role manuals',
    roles: _leads,
  ),
  _DocEntry(
    title: 'Admin Manual',
    subtitle: 'User management, configuration, and integrations',
    asset: 'docs/admin-manual.md',
    group: 'Role manuals',
    roles: _adminOnly,
  ),
  _DocEntry(
    title: 'Overview',
    subtitle: 'Index of all documentation',
    asset: 'docs/README.md',
    group: 'Start here',
  ),
  _DocEntry(
    title: 'Scouting Accuracy: Mapping Guide',
    subtitle: 'Configure which fields are checked and how lenient alerts are',
    asset: 'docs/scouting-accuracy-mapping-guide.md',
    group: 'Setup & configuration',
    roles: _leads,
  ),
  _DocEntry(
    title: 'Scouting Accuracy: Slack Setup',
    subtitle: 'Turn on Slack notifications for accuracy alerts',
    asset: 'docs/scouting-accuracy-slack-setup.md',
    group: 'Setup & configuration',
    roles: _adminOnly,
  ),
  _DocEntry(
    title: 'Firebase: Regenerate Config',
    subtitle: 'Regenerate FlutterFire config with the CLI',
    asset: 'docs/regen-flutterfire-config.md',
    group: 'Setup & configuration',
    roles: _devOnly,
  ),
  _DocEntry(
    title: 'Database Plan',
    subtitle: 'What is local vs. Firestore, and why',
    asset: 'docs/database-plan.md',
    group: 'Reference',
    roles: _devOnly,
  ),
  _DocEntry(
    title: 'Design Review',
    subtitle: 'Roadmap and gap analysis',
    asset: 'docs/design-review.md',
    group: 'Reference',
    roles: _devOnly,
  ),
  _DocEntry(
    title: 'Scouting Accuracy: Roadmap',
    subtitle: 'Design roadmap for the accuracy feature',
    asset: 'docs/scouting-accuracy-notifications-roadmap.md',
    group: 'Reference',
    roles: _devOnly,
  ),
  _DocEntry(
    title: 'iOS Install: AltStore',
    subtitle: 'Install the app through AltStore',
    asset: 'docs/altstore.md',
    group: 'Installing',
  ),
  _DocEntry(
    title: 'iOS Install: SideStore',
    subtitle: 'Install the app through SideStore',
    asset: 'docs/sidestore-install.md',
    group: 'Installing',
  ),
  _DocEntry(
    title: 'Android Install: Obtainium',
    subtitle: 'Install and auto-update the app on Android',
    asset: 'docs/obtainium-install.md',
    group: 'Installing',
  ),
  _DocEntry(
    title: 'Desktop Install',
    subtitle: 'Run the unsigned Windows, macOS, or Linux build',
    asset: 'docs/desktop-install.md',
    group: 'Installing',
  ),
  _DocEntry(
    title: 'Release Process',
    subtitle: 'Branch model, versioning, and cutting releases',
    asset: 'docs/release-process.md',
    group: 'Developer reference',
    roles: _devOnly,
  ),
  _DocEntry(
    title: 'Developer Manual',
    subtitle: 'Building, testing, and contributing to Spectrum Strategy',
    asset: 'docs/developer-manual.md',
    group: 'Developer reference',
    roles: _devOnly,
  ),
  _DocEntry(
    title: 'CI Workflows',
    subtitle: 'What each GitHub Actions workflow does',
    asset: 'docs/ci-workflows.md',
    group: 'Developer reference',
    roles: _devOnly,
  ),
];

Future<Set<String>>? _bundledDocs;

Future<Set<String>> bundledDocAssets() {
  return _bundledDocs ??= AssetManifest.loadFromAssetBundle(rootBundle)
      .then(
        (manifest) =>
            manifest.listAssets().where((a) => a.startsWith('docs/')).toSet(),
      )
      .onError<Object>((error, stack) {
        _bundledDocs = null;
        throw error;
      });
}

class DocsTab extends StatelessWidget {
  const DocsTab({required this.roles, super.key});

  final Set<UserRole> roles;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Set<String>>(
      future: bundledDocAssets(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Could not load the doc list: ${snapshot.error}'),
            ),
          );
        }
        final available = snapshot.data ?? const <String>{};
        final groups = <String, List<_DocEntry>>{};
        for (final d in _docs) {
          if (!d.visibleTo(roles) || !available.contains(d.asset)) continue;
          groups.putIfAbsent(d.group, () => <_DocEntry>[]).add(d);
        }
        if (groups.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('This build bundles no documentation.'),
            ),
          );
        }
        return _buildList(context, groups);
      },
    );
  }

  Widget _buildList(BuildContext context, Map<String, List<_DocEntry>> groups) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        for (final entry in groups.entries) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              entry.key,
              style: Theme.of(context).textTheme.labelLarge
                  ?.copyWith(color: Theme.of(context).colorScheme.primary),
            ),
          ),
          for (final doc in entry.value)
            ListTile(
              leading: const Icon(Icons.description_outlined),
              title: Text(doc.title),
              subtitle: doc.subtitle.isEmpty ? null : Text(doc.subtitle),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => DocPage(title: doc.title, asset: doc.asset),
                ),
              ),
            ),
        ],
      ],
    );
  }
}

void openBundledDoc(BuildContext context, String asset) {
  final matches = _docs.where((d) => d.asset == asset).toList(growable: false);
  final title = matches.isNotEmpty
      ? matches.first.title
      : asset.split('/').last;
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => DocPage(title: title, asset: asset),
    ),
  );
}

class DocHelpButton extends StatelessWidget {
  const DocHelpButton({required this.docAsset, this.tooltip, super.key});

  final String docAsset;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Set<String>>(
      future: bundledDocAssets(),
      builder: (context, snapshot) {
        if (snapshot.data?.contains(docAsset) != true) {
          return const SizedBox.shrink();
        }
        return IconButton(
          icon: const Icon(Icons.help_outline_rounded),
          tooltip: tooltip ?? 'Open the manual',
          visualDensity: VisualDensity.compact,
          onPressed: () => openBundledDoc(context, docAsset),
        );
      },
    );
  }
}

class DocPage extends StatefulWidget {
  const DocPage({required this.title, required this.asset, super.key});

  final String title;
  final String asset;

  @override
  State<DocPage> createState() => _DocPageState();
}

class _DocPageState extends State<DocPage> {
  late Future<String> _content;

  @override
  void initState() {
    super.initState();
    _content = rootBundle.loadString(widget.asset);
  }

  void _reload() {
    setState(() => _content = rootBundle.loadString(widget.asset));
  }

  void _onTapLink(String text, String? href, String title) {
    if (href == null) return;
    final normalized = href.split('/').last.split('#').first;
    final match = _docs
        .where((d) => d.asset.split('/').last == normalized)
        .toList(growable: false);
    if (match.isNotEmpty) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              DocPage(title: match.first.title, asset: match.first.asset),
        ),
      );
      return;
    }
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Link: $href')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: FutureBuilder<String>(
        future: _content,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || snapshot.data == null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Could not load this doc: ${snapshot.error}'),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _reload,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Try again'),
                    ),
                  ],
                ),
              ),
            );
          }
          return Markdown(
            data: snapshot.data!,
            padding: const EdgeInsets.all(16),
            onTapLink: _onTapLink,
            styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)),
          );
        },
      ),
    );
  }
}
