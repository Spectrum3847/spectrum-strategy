import 'package:flutter_test/flutter_test.dart';
import 'package:spectrumstrategy/src/services/name_list_parse.dart';

void main() {
  group('parsePastedNames', () {
    test('splits on newlines, commas, tabs and semicolons', () {
      expect(parsePastedNames('Ada\nGrace'), <String>['Ada', 'Grace']);
      expect(parsePastedNames('Ada, Grace'), <String>['Ada', 'Grace']);
      expect(parsePastedNames('Ada\tGrace'), <String>['Ada', 'Grace']);
      expect(parsePastedNames('Ada; Grace'), <String>['Ada', 'Grace']);
    });

    test('handles a spreadsheet paste with CRLF line endings', () {
      expect(parsePastedNames('Ada\r\nGrace\r\n'), <String>['Ada', 'Grace']);
    });

    test('keeps a space inside a name', () {
      expect(parsePastedNames('Ada Lovelace\nGrace Hopper'), <String>[
        'Ada Lovelace',
        'Grace Hopper',
      ]);
    });

    test('drops blank entries and surrounding whitespace', () {
      expect(parsePastedNames('  Ada  \n\n\n , ,Grace '), <String>[
        'Ada',
        'Grace',
      ]);
    });

    test('collapses case-insensitive repeats to the first spelling', () {
      expect(parsePastedNames('Ada\nADA\nada\nGrace'), <String>[
        'Ada',
        'Grace',
      ]);
    });

    test('is empty for blank input', () {
      expect(parsePastedNames(''), isEmpty);
      expect(parsePastedNames('  \n , \t '), isEmpty);
    });
  });

  group('appendNewEntries', () {
    test('appends only what is missing, in paste order', () {
      expect(
        appendNewEntries(<String>['Ada'], <String>['Grace', 'Ada', 'Alan']),
        <String>['Ada', 'Grace', 'Alan'],
      );
    });

    test('matches existing entries case-insensitively', () {
      expect(appendNewEntries(<String>['Ada'], <String>['ADA']), <String>[
        'Ada',
      ]);
    });

    test('leaves the existing list alone when nothing is new', () {
      expect(appendNewEntries(<String>['Ada'], <String>[]), <String>['Ada']);
    });
  });
}
