import 'package:flutter/foundation.dart';
import 'package:tba_client/tba_client.dart';

import '../services/tba/tba_match_videos.dart';

const int _fetchBatchSize = 6;

class QualVideoController extends ChangeNotifier {
  QualVideoController({required this._tbaClient});

  final TbaClient? _tbaClient;

  String? _loadedEventKey;
  bool _loading = false;
  bool _disposed = false;
  Map<String, TbaMatchVideo?> _videoByMatchKey =
      const <String, TbaMatchVideo?>{};

  bool get isLoading => _loading;

  TbaMatchVideo? videoFor(String matchKey) => _videoByMatchKey[matchKey];

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _notifyListeners() {
    if (!_disposed) notifyListeners();
  }

  Future<void> load(String eventKey, List<String> matchKeys) async {
    if (eventKey.isEmpty || matchKeys.isEmpty || _loading) return;
    final tba = _tbaClient;
    if (tba == null) return;

    if (eventKey != _loadedEventKey) {
      _videoByMatchKey = const <String, TbaMatchVideo?>{};
      _loadedEventKey = eventKey;
    }
    final missing = matchKeys
        .where((key) => !_videoByMatchKey.containsKey(key))
        .toList(growable: false);
    if (missing.isEmpty) return;

    _loading = true;
    _notifyListeners();
    try {
      final fetched = <MapEntry<String, TbaMatchVideo?>>[];
      for (var start = 0; start < missing.length; start += _fetchBatchSize) {
        final batch = missing.skip(start).take(_fetchBatchSize);
        final results = await Future.wait(
          batch.map((key) async {
            List<TbaMatchVideo> videos;
            try {
              videos = await fetchMatchVideos(tba, key);
            } catch (_) {
              return null;
            }
            TbaMatchVideo? youtube;
            for (final video in videos) {
              if (video.isYoutube) {
                youtube = video;
                break;
              }
            }
            return MapEntry(key, youtube);
          }),
        );
        fetched.addAll(results.whereType<MapEntry<String, TbaMatchVideo?>>());
      }

      if (eventKey != _loadedEventKey) {
        return;
      }
      _videoByMatchKey = <String, TbaMatchVideo?>{
        ..._videoByMatchKey,
        for (final entry in fetched) entry.key: entry.value,
      };
    } finally {
      _loading = false;
      _notifyListeners();
    }
  }
}
