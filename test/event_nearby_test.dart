import 'package:flutter_test/flutter_test.dart';

import 'package:spectrumstrategy/src/ui/event_picker_dialog.dart';

void main() {
  final today = DateTime(2026, 10, 17, 15, 30);

  group('isEventNearby', () {
    test('in progress', () {
      expect(isEventNearby('2026-10-16', '2026-10-18', today), isTrue);
    });

    test('starts in 3 days', () {
      expect(isEventNearby('2026-10-20', '2026-10-22', today), isTrue);
    });

    test('starts in 4 days', () {
      expect(isEventNearby('2026-10-21', '2026-10-23', today), isFalse);
    });

    test('ended 3 days ago', () {
      expect(isEventNearby('2026-10-12', '2026-10-14', today), isTrue);
    });

    test('ended 4 days ago', () {
      expect(isEventNearby('2026-10-11', '2026-10-13', today), isFalse);
    });

    test('missing dates are not nearby', () {
      expect(isEventNearby(null, null, today), isFalse);
      expect(isEventNearby(null, '2026-10-17', today), isFalse);
    });

    test('missing end date falls back to the start date', () {
      expect(isEventNearby('2026-10-17', null, today), isTrue);
      expect(isEventNearby('2026-10-01', null, today), isFalse);
    });

    test('crosses a month boundary', () {
      expect(
        isEventNearby('2026-11-02', '2026-11-03', DateTime(2026, 10, 30)),
        isTrue,
      );
    });
  });
}
