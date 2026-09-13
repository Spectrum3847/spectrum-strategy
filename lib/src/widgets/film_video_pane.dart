import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../services/video_embed.dart';
import '../theme/strategy_palette.dart';
import 'youtube_web_embed.dart';

bool get filmEmbedSupported =>
    kIsWeb ||
    defaultTargetPlatform == TargetPlatform.android ||
    defaultTargetPlatform == TargetPlatform.iOS ||
    defaultTargetPlatform == TargetPlatform.macOS;

class FilmVideoPane extends StatefulWidget {
  const FilmVideoPane({required this.url, this.embedSupported, super.key});

  final String url;

  final bool? embedSupported;

  @override
  State<FilmVideoPane> createState() => _FilmVideoPaneState();
}

class _FilmVideoPaneState extends State<FilmVideoPane> {
  WebViewController? _controller;
  String? _loadedEmbedUrl;

  bool get _canEmbed => widget.embedSupported ?? filmEmbedSupported;

  @override
  void initState() {
    super.initState();
    _syncController();
  }

  @override
  void didUpdateWidget(FilmVideoPane old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) _syncController();
  }

  void _syncController() {
    final embed = youtubeEmbedUrl(widget.url);
    if (!_canEmbed || embed == null) {
      setState(() {
        _controller = null;
        _loadedEmbedUrl = null;
      });
      return;
    }
    if (embed == _loadedEmbedUrl) return;
    if (kIsWeb) {
      setState(() => _loadedEmbedUrl = embed);
      return;
    }
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..loadRequest(Uri.parse(embed));
    setState(() {
      _controller = controller;
      _loadedEmbedUrl = embed;
    });
  }

  @override
  Widget build(BuildContext context) {
    final embedUrl = _loadedEmbedUrl;
    if (kIsWeb && embedUrl != null) {
      return ColoredBox(
        color: Colors.black,
        child: HtmlElementView(
          key: ValueKey('film-video-iframe-$embedUrl'),
          viewType: registerYoutubeEmbedView(embedUrl),
        ),
      );
    }
    final controller = _controller;
    if (controller != null) {
      return ColoredBox(
        color: Colors.black,
        child: WebViewWidget(
          key: const ValueKey('film-video-webview'),
          controller: controller,
        ),
      );
    }
    return _FilmLinkCard(url: widget.url, playable: _canEmbed);
  }
}

class _FilmLinkCard extends StatelessWidget {
  const _FilmLinkCard({required this.url, required this.playable});

  final String url;
  final bool playable;

  String get _message {
    if (!playable) {
      return 'This platform has no in-app player. Open the film in a browser '
          'and keep it beside the app.';
    }
    return 'Only YouTube links play in the app. Open this one in a browser '
        'to watch it beside the form.';
  }

  Future<void> _open() async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      color: StrategyPalette.surfaceOf(context),
      padding: const EdgeInsets.all(16),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.smart_display_outlined,
            color: StrategyPalette.mutedTextOf(context),
          ),
          const SizedBox(height: 8),
          Text(
            _message,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: StrategyPalette.mutedTextOf(context),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            key: const ValueKey('film-open-external'),
            onPressed: url.trim().isEmpty ? null : _open,
            icon: const Icon(Icons.open_in_new_rounded, size: 16),
            label: const Text('Open video'),
          ),
        ],
      ),
    );
  }
}
