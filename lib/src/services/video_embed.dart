library;

String? youtubeVideoId(String url) {
  final trimmed = url.trim();
  if (trimmed.isEmpty) return null;

  final uri = Uri.tryParse(trimmed);
  if (uri == null || !uri.hasScheme) return null;
  if (uri.scheme != 'http' && uri.scheme != 'https') return null;

  final host = uri.host.toLowerCase().replaceFirst('www.', '');
  final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();

  if (host == 'youtu.be') {
    return segments.isEmpty ? null : _validId(segments.first);
  }
  if (host != 'youtube.com' &&
      host != 'm.youtube.com' &&
      host != 'youtube-nocookie.com') {
    return null;
  }
  if (segments.isNotEmpty &&
      const {'embed', 'shorts', 'live', 'v'}.contains(segments.first)) {
    return segments.length < 2 ? null : _validId(segments[1]);
  }
  return _validId(uri.queryParameters['v'] ?? '');
}

String? youtubeEmbedUrl(String url) {
  final id = youtubeVideoId(url);
  if (id == null) return null;
  final start = _startSeconds(Uri.tryParse(url.trim()));
  final query = start == null ? '' : '?start=$start';
  return 'https://www.youtube-nocookie.com/embed/$id$query';
}

int? _startSeconds(Uri? uri) {
  if (uri == null) return null;
  final raw = uri.queryParameters['t'] ?? uri.queryParameters['start'] ?? '';
  if (raw.isEmpty) return null;

  final plain = int.tryParse(raw.replaceAll('s', ''));
  if (plain != null) return plain <= 0 ? null : plain;

  final match = RegExp(r'^(?:(\d+)h)?(?:(\d+)m)?(?:(\d+)s)?$')
      .firstMatch(raw.toLowerCase());
  if (match == null) return null;
  final total =
      (int.tryParse(match.group(1) ?? '') ?? 0) * 3600 +
      (int.tryParse(match.group(2) ?? '') ?? 0) * 60 +
      (int.tryParse(match.group(3) ?? '') ?? 0);
  return total <= 0 ? null : total;
}

String? _validId(String candidate) {
  return RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(candidate) ? candidate : null;
}
