import 'package:flutter_test/flutter_test.dart';
import 'package:spectrumstrategy/src/models/usage_rollup.dart';
import 'package:spectrumstrategy/src/models/user_role.dart';

void main() {
  Map<String, dynamic> doc({
    Object? tabs,
    Object? daily,
    Object? eventsCounted,
  }) => {
    'updatedAt': '2026-08-16T06:25:00.000Z',
    'windowDays': 30,
    'eventsCounted': eventsCounted ?? 12,
    'deviceCount': 3,
    'tabs':
        tabs ??
        [
          {'name': 'Scout', 'count': 7},
          {'name': 'Strategy', 'count': 5},
        ],
    'platforms': [
      {'name': 'android', 'count': 12},
    ],
    'appVersions': [
      {'name': '1.0.0', 'count': 12},
    ],
    'daily':
        daily ??
        [
          {'date': '2026-08-15', 'count': 4},
          {'date': '2026-08-16', 'count': 8},
        ],
  };

  test('reads the shape the cron writes', () {
    final rollup = UsageRollup.fromJson(doc());

    expect(rollup.windowDays, 30);
    expect(rollup.eventsCounted, 12);
    expect(rollup.deviceCount, 3);
    expect(rollup.updatedAt, DateTime.utc(2026, 8, 16, 6, 25));
    expect(rollup.tabs.first.name, 'Scout');
    expect(rollup.tabs.first.count, 7);
    expect(rollup.daily.last.date, '2026-08-16');
  });

  test('keeps the order the cron ranked in', () {
    final rollup = UsageRollup.fromJson(doc());
    expect(rollup.tabs.map((t) => t.name), ['Scout', 'Strategy']);
  });

  test('an empty rollup is empty, not an error', () {
    final rollup = UsageRollup.fromJson(
      doc(tabs: const [], daily: const [], eventsCounted: 0),
    );

    expect(rollup.isEmpty, isTrue);
    expect(rollup.tabs, isEmpty);
    expect(rollup.busiestDay, 0);
  });

  test('a malformed row is dropped, not fatal', () {
    final rollup = UsageRollup.fromJson(
      doc(
        tabs: [
          {'name': 'Scout', 'count': 7},
          {'count': 3},
          'not a map',
          {'name': '', 'count': 9},
          {'name': 'Docs', 'count': 1},
        ],
      ),
    );

    expect(rollup.tabs.map((t) => t.name), ['Scout', 'Docs']);
  });

  test('a missing field reads as zero rather than throwing', () {
    final rollup = UsageRollup.fromJson(const <String, dynamic>{});

    expect(rollup.eventsCounted, 0);
    expect(rollup.deviceCount, 0);
    expect(rollup.windowDays, 0);
    expect(rollup.updatedAt, isNull);
    expect(rollup.tabs, isEmpty);
    expect(rollup.isEmpty, isTrue);
  });

  test('a numeric count arriving as a double still reads as a count', () {
    final rollup = UsageRollup.fromJson(
      doc(
        tabs: [
          {'name': 'Scout', 'count': 7.0},
        ],
      ),
    );

    expect(rollup.tabs.single.count, 7);
  });

  test('busiestDay is the largest day in the window', () {
    final rollup = UsageRollup.fromJson(
      doc(
        daily: [
          {'date': '2026-08-14', 'count': 2},
          {'date': '2026-08-15', 'count': 9},
          {'date': '2026-08-16', 'count': 4},
        ],
      ),
    );

    expect(rollup.busiestDay, 9);
  });

  group('who sees the Usage tab', () {
    test('a developer gets it', () {
      expect(const {UserRole.developer}.visibleTabIndices, contains(8));
    });

    test('nobody else does, admin included', () {
      for (final role in [
        UserRole.admin,
        UserRole.strategy,
        UserRole.scouter,
        UserRole.viewer,
      ]) {
        expect(
          {role}.visibleTabIndices,
          isNot(contains(8)),
          reason: '$role should not see the Usage tab',
        );
      }
    });

    test('developer keeps everything strategy had', () {
      final strategy = const {UserRole.strategy}.visibleTabIndices.toSet();
      final developer = const {UserRole.developer}.visibleTabIndices.toSet();

      expect(developer.containsAll(strategy), isTrue);
    });

    test('Usage is never a bottom-bar tab', () {
      expect(const {UserRole.developer}.primaryTabIndices, isNot(contains(8)));
      expect(const {UserRole.developer}.secondaryTabIndices, contains(8));
    });
  });
}
