import 'dart:ui_web' as ui_web;

import 'package:web/web.dart' as web;

final Set<String> _registeredViewTypes = {};

String registerYoutubeEmbedView(String embedUrl) {
  final viewType = 'spectrumstrategy-youtube-embed-$embedUrl';
  if (_registeredViewTypes.add(viewType)) {
    ui_web.platformViewRegistry.registerViewFactory(viewType, (int viewId) {
      final iframe = web.HTMLIFrameElement()
        ..src = embedUrl
        ..style.border = 'none'
        ..style.width = '100%'
        ..style.height = '100%'
        ..allow = 'autoplay; encrypted-media; picture-in-picture'
        ..allowFullscreen = true;
      return iframe;
    });
  }
  return viewType;
}
