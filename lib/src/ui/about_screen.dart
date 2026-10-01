import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/debug_info.dart';

class AboutScreen extends StatefulWidget {
  const AboutScreen({this.debugInfo, super.key});

  final Future<DebugInfo>? debugInfo;

  static final Uri mirrorRepoUrl = Uri.parse(
    'https://github.com/Spectrum3847/spectrum-strategy',
  );
  static final Uri project516Url = Uri.parse('https://project516.dev');
  static final Uri project516GitHubUrl = Uri.parse(
    'https://github.com/Project516',
  );
  static final Uri spectrum3847Url = Uri.parse('https://www.spectrum3847.org/');

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  late final Future<DebugInfo> _info = widget.debugInfo ?? DebugInfo.gather();

  Future<void> _open(Uri url) async {
    bool launched;
    try {
      launched = await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (_) {
      launched = false;
    }
    if (!mounted || launched) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Could not open ${url.host}')));
  }

  void _openLicenses(String versionLabel) {
    showLicensePage(
      context: context,
      applicationName: 'Spectrum Strategy',
      applicationVersion: versionLabel,
      applicationLegalese:
          'Built by project516 for Spectrum 3847 (FRC Team 3847).',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: FutureBuilder<DebugInfo>(
        future: _info,
        builder: (context, snapshot) {
          final info = snapshot.data;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'Spectrum Strategy',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              Text(
                info == null
                    ? 'Loading version...'
                    : 'Version ${info.versionLabel}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 24),
              Text('Credits', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              Card(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _LinkTile(
                      icon: Icons.person_outline_rounded,
                      title: 'Made by project516',
                      subtitle: 'project516.dev',
                      onTap: () => _open(AboutScreen.project516Url),
                    ),
                    const Divider(height: 1),
                    _LinkTile(
                      icon: Icons.code_rounded,
                      title: 'project516 on GitHub',
                      subtitle: 'github.com/Project516',
                      onTap: () => _open(AboutScreen.project516GitHubUrl),
                    ),
                    const Divider(height: 1),
                    _LinkTile(
                      icon: Icons.groups_outlined,
                      title: 'Spectrum 3847',
                      subtitle: 'FRC Team 3847 -- spectrum3847.org',
                      onTap: () => _open(AboutScreen.spectrum3847Url),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Open source',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              Text(
                'Spectrum Strategy is open source (AGPL-3.0). Read the code, '
                'file an issue, or send a pull request.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              Card(
                child: _LinkTile(
                  icon: Icons.open_in_new_rounded,
                  title: 'View source on GitHub',
                  subtitle: 'github.com/Spectrum3847/spectrum-strategy',
                  onTap: () => _open(AboutScreen.mirrorRepoUrl),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.description_outlined),
                  title: const Text('Open source licenses'),
                  subtitle: const Text(
                    'Every bundled package, font, and asset',
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => _openLicenses(info?.versionLabel ?? 'unknown'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _LinkTile extends StatelessWidget {
  const _LinkTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.open_in_new_rounded, size: 18),
      onTap: onTap,
    );
  }
}
