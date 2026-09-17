import 'package:flutter_test/flutter_test.dart';
import 'package:spectrumstrategy/src/services/video_embed.dart';

void main() {
  group('youtubeVideoId', () {
    test('reads the watch form', () {
      expect(
        youtubeVideoId('https://www.youtube.com/watch?v=dQw4w9WgXcQ'),
        'dQw4w9WgXcQ',
      );
    });

    test('reads the short-link, embed, shorts and live forms', () {
      const expected = 'dQw4w9WgXcQ';
      expect(youtubeVideoId('https://youtu.be/$expected'), expected);
      expect(
        youtubeVideoId('https://www.youtube.com/embed/$expected'),
        expected,
      );
      expect(youtubeVideoId('https://youtube.com/shorts/$expected'), expected);
      expect(youtubeVideoId('https://m.youtube.com/live/$expected'), expected);
    });

    test('ignores extra query parameters on the watch form', () {
      expect(
        youtubeVideoId('https://www.youtube.com/watch?v=dQw4w9WgXcQ&list=PL1'),
        'dQw4w9WgXcQ',
      );
    });

    test('rejects a non-YouTube host', () {
      expect(youtubeVideoId('https://vimeo.com/12345678901'), isNull);
      expect(
        youtubeVideoId('https://www.thebluealliance.com/match/2025casj_qm1'),
        isNull,
      );
    });

    test('rejects blank, relative and malformed input', () {
      expect(youtubeVideoId(''), isNull);
      expect(youtubeVideoId('   '), isNull);
      expect(youtubeVideoId('youtube.com/watch?v=dQw4w9WgXcQ'), isNull);
      expect(youtubeVideoId('ftp://youtube.com/watch?v=dQw4w9WgXcQ'), isNull);
    });

    test('rejects an id that is not 11 URL-safe characters', () {
      expect(youtubeVideoId('https://youtu.be/short'), isNull);
      expect(youtubeVideoId('https://youtu.be/way-too-long-for-an-id'), isNull);
      expect(
        youtubeVideoId('https://www.youtube.com/watch?v=abc!defghij'),
        isNull,
      );
    });
  });

  group('youtubeEmbedUrl', () {
    test('builds the privacy-mode embed URL', () {
      expect(
        youtubeEmbedUrl('https://www.youtube.com/watch?v=dQw4w9WgXcQ'),
        'https://www.youtube-nocookie.com/embed/dQw4w9WgXcQ',
      );
    });

    test('carries a bare-seconds start offset across', () {
      expect(
        youtubeEmbedUrl('https://youtu.be/dQw4w9WgXcQ?t=90'),
        'https://www.youtube-nocookie.com/embed/dQw4w9WgXcQ?start=90',
      );
    });

    test('carries the 1m30s start offset across', () {
      expect(
        youtubeEmbedUrl('https://youtu.be/dQw4w9WgXcQ?t=1h2m3s'),
        'https://www.youtube-nocookie.com/embed/dQw4w9WgXcQ?start=3723',
      );
    });

    test('drops a zero or unparseable start offset', () {
      expect(
        youtubeEmbedUrl('https://youtu.be/dQw4w9WgXcQ?t=0'),
        'https://www.youtube-nocookie.com/embed/dQw4w9WgXcQ',
      );
      expect(
        youtubeEmbedUrl('https://youtu.be/dQw4w9WgXcQ?t=later'),
        'https://www.youtube-nocookie.com/embed/dQw4w9WgXcQ',
      );
    });

    test('is null for a link it cannot embed', () {
      expect(youtubeEmbedUrl('https://vimeo.com/12345678901'), isNull);
    });
  });
}
