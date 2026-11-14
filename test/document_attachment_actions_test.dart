import 'package:flutter_test/flutter_test.dart';

import 'package:spectrumstrategy/src/scouting/services/document_attachment_actions.dart';

void main() {
  group('contentTypeForKey', () {
    test('resolves the content type from a recognized extension', () {
      expect(contentTypeForKey('abc123.pdf'), 'application/pdf');
      expect(contentTypeForKey('abc123.png'), 'image/png');
      expect(contentTypeForKey('abc123.jpg'), 'image/jpeg');
      expect(contentTypeForKey('abc123.jpeg'), 'image/jpeg');
    });

    test('is case-insensitive on the extension', () {
      expect(contentTypeForKey('abc123.PDF'), 'application/pdf');
    });

    test('falls back to a generic binary type for an unknown extension', () {
      expect(contentTypeForKey('abc123.docx'), 'application/octet-stream');
    });

    test('falls back to a generic binary type with no extension at all', () {
      expect(contentTypeForKey('abc123'), 'application/octet-stream');
    });
  });
}
