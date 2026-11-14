import 'dart:typed_data';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spectrumstrategy/src/services/issue_report_service.dart';
import 'package:spectrumstrategy/src/services/report_screenshot_picker.dart';

PickedScreenshot _shot(int byte, [String type = 'image/png']) =>
    PickedScreenshot(bytes: Uint8List.fromList([byte]), contentType: type);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('submit writes a bugReports doc matching the rules whitelist', () async {
    final firestore = FakeFirebaseFirestore();
    final service = IssueReportService(firestore: firestore);

    await service.submit(
      title: '  Board did not save  ',
      body: '  Steps to reproduce  ',
      reporterUid: 'uid-123',
      reporterName: 'Jane Scout',
    );

    final snap = await firestore.collection('bugReports').get();
    expect(snap.docs, hasLength(1));
    final data = snap.docs.single.data();

    expect(data.keys.toSet(), {
      'id',
      'title',
      'body',
      'reporterUid',
      'reporterName',
      'appVersion',
      'platform',
      'osVersion',
      'deviceInfo',
      'status',
      'createdAt',
      'kind',
    });

    expect(data['title'], 'Board did not save');
    expect(data['body'], 'Steps to reproduce');
    expect(data['reporterUid'], 'uid-123');
    expect(data['reporterName'], 'Jane Scout');
    expect(data['status'], 'new');
    expect(data['kind'], 'bug');
    expect(data['id'], snap.docs.single.id);

    final createdAt = data['createdAt'] as String;
    expect(createdAt.startsWith('20'), isTrue);
    expect(DateTime.tryParse(createdAt), isNotNull);
  });

  test('submit records the reporter roles when provided', () async {
    final firestore = FakeFirebaseFirestore();
    final service = IssueReportService(firestore: firestore);

    await service.submit(
      title: 't',
      body: 'b',
      reporterUid: 'u',
      reporterName: 'n',
      roles: 'Strategist, Admin',
    );

    final data = (await firestore.collection('bugReports').get()).docs.single
        .data();
    expect(data['roles'], 'Strategist, Admin');

    expect(data.keys.contains('roles'), isTrue);
  });

  test('submit omits roles when none are granted', () async {
    final firestore = FakeFirebaseFirestore();
    final service = IssueReportService(firestore: firestore);

    await service.submit(
      title: 't',
      body: 'b',
      reporterUid: 'u',
      reporterName: 'n',
    );

    final data = (await firestore.collection('bugReports').get()).docs.single
        .data();
    expect(data.containsKey('roles'), isFalse);
  });

  test(
    'submit clamps an over-long title and body to the rule bounds',
    () async {
      final firestore = FakeFirebaseFirestore();
      final service = IssueReportService(firestore: firestore);

      await service.submit(
        title: 'x' * 500,
        body: 'y' * 8000,
        reporterUid: 'u',
        reporterName: 'n',
      );

      final data = (await firestore.collection('bugReports').get()).docs.single
          .data();
      expect((data['title'] as String).length, 200);
      expect((data['body'] as String).length, 4096);
    },
  );

  test('an injected writer gets the same doc, without FlutterFire', () async {
    String? path;
    Map<String, dynamic>? written;
    final service = IssueReportService(
      write: (docPath, data) async {
        path = docPath;
        written = data;
      },
    );

    await service.submit(
      title: 'Linux report',
      body: 'sent over REST',
      reporterUid: 'uid-9',
      reporterName: 'Desk Top',
    );

    expect(path, 'bugReports/${written!['id']}');
    expect(written!['title'], 'Linux report');
    expect(written!['reporterUid'], 'uid-9');
    expect(written!['status'], 'new');
  });

  test('submit records feedback kind, area and impact when provided', () async {
    final firestore = FakeFirebaseFirestore();
    final service = IssueReportService(firestore: firestore);

    await service.submit(
      title: 'Add dark mode',
      body: 'Would love a dark theme.',
      reporterUid: 'u',
      reporterName: 'n',
      kind: 'feedback',
      area: 'Strategy board',
      impact: 'Cosmetic issue',
    );

    final data = (await firestore.collection('bugReports').get()).docs.single
        .data();
    expect(data['kind'], 'feedback');
    expect(data['area'], 'Strategy board');
    expect(data['impact'], 'Cosmetic issue');
  });

  test(
    'submit defaults to bug kind and omits area/impact when blank',
    () async {
      final firestore = FakeFirebaseFirestore();
      final service = IssueReportService(firestore: firestore);

      await service.submit(
        title: 't',
        body: 'b',
        reporterUid: 'u',
        reporterName: 'n',
      );

      final data = (await firestore.collection('bugReports').get()).docs.single
          .data();
      expect(data['kind'], 'bug');
      expect(data.containsKey('area'), isFalse);
      expect(data.containsKey('impact'), isFalse);
    },
  );

  test('submit uploads screenshots and stores their keys', () async {
    final firestore = FakeFirebaseFirestore();
    final uploaded = <String>[];
    final service = IssueReportService(
      firestore: firestore,
      uploadScreenshot: (bytes, {contentType = 'image/jpeg'}) async {
        uploaded.add(contentType);
        return 'key-${bytes.first}';
      },
    );

    final dropped = await service.submit(
      title: 't',
      body: 'b',
      reporterUid: 'u',
      reporterName: 'n',
      screenshots: [_shot(1), _shot(2, 'image/jpeg')],
    );

    expect(dropped, 0);
    expect(uploaded, ['image/png', 'image/jpeg']);
    final data = (await firestore.collection('bugReports').get()).docs.single
        .data();
    expect(data['screenshotKeys'], ['key-1', 'key-2']);
  });

  test('a screenshot that fails to upload is reported, not fatal', () async {
    final firestore = FakeFirebaseFirestore();
    final service = IssueReportService(
      firestore: firestore,
      uploadScreenshot: (bytes, {contentType = 'image/jpeg'}) async =>
          bytes.first == 1 ? 'key-1' : null,
    );

    final dropped = await service.submit(
      title: 't',
      body: 'b',
      reporterUid: 'u',
      reporterName: 'n',
      screenshots: [_shot(1), _shot(2)],
    );

    expect(dropped, 1);
    final data = (await firestore.collection('bugReports').get()).docs.single
        .data();

    expect(data['screenshotKeys'], ['key-1']);
    expect(data['title'], 't');
  });

  test('submit never sends more screenshots than the rules allow', () async {
    final firestore = FakeFirebaseFirestore();
    var calls = 0;
    final service = IssueReportService(
      firestore: firestore,
      uploadScreenshot: (bytes, {contentType = 'image/jpeg'}) async {
        calls++;
        return 'key-$calls';
      },
    );

    final dropped = await service.submit(
      title: 't',
      body: 'b',
      reporterUid: 'u',
      reporterName: 'n',
      screenshots: [_shot(1), _shot(2), _shot(3), _shot(4), _shot(5)],
    );

    expect(calls, maxReportScreenshots);
    expect(dropped, 0);
    final data = (await firestore.collection('bugReports').get()).docs.single
        .data();
    expect((data['screenshotKeys'] as List).length, maxReportScreenshots);
  });

  test('with no uploader the field is omitted entirely', () async {
    final firestore = FakeFirebaseFirestore();
    final service = IssueReportService(firestore: firestore);

    expect(service.supportsScreenshots, isFalse);
    await service.submit(
      title: 't',
      body: 'b',
      reporterUid: 'u',
      reporterName: 'n',
      screenshots: [_shot(1)],
    );

    final data = (await firestore.collection('bugReports').get()).docs.single
        .data();
    expect(data.containsKey('screenshotKeys'), isFalse);
  });
}
