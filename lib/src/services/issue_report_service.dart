import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';

import 'debug_info.dart';
import 'report_screenshot_picker.dart';

typedef ScreenshotUploader = Future<String?> Function(
  Uint8List bytes, {
  String contentType,
});

class IssueReportService {
  IssueReportService({this._firestore, this._write, this._uploadScreenshot});

  final FirebaseFirestore? _firestore;

  final Future<void> Function(String docPath, Map<String, dynamic> data)?
  _write;

  final ScreenshotUploader? _uploadScreenshot;

  bool get supportsScreenshots => _uploadScreenshot != null;

  FirebaseFirestore get _db => _firestore ?? FirebaseFirestore.instance;

  Future<void> _writeDoc(String id, Map<String, dynamic> data) {
    final write = _write;
    if (write != null) return write('bugReports/$id', data);
    return _db.collection('bugReports').doc(id).set(data);
  }

  static String _clamp(String value, int max) =>
      value.length <= max ? value : value.substring(0, max);

  Future<int> submit({
    required String title,
    required String body,
    required String reporterUid,
    required String reporterName,
    String roles = '',

    String kind = 'bug',
    String area = '',
    String impact = '',
    List<PickedScreenshot> screenshots = const <PickedScreenshot>[],
  }) async {
    final info = await DebugInfo.gather();
    final keys = await _uploadScreenshots(screenshots);

    final id = const Uuid().v4();
    await _writeDoc(id, <String, dynamic>{
      'id': id,
      'title': _clamp(title.trim(), 200),
      'body': _clamp(body.trim(), 4096),
      'reporterUid': _clamp(reporterUid, 128),
      'reporterName': _clamp(reporterName, 128),

      if (roles.isNotEmpty) 'roles': _clamp(roles, 128),
      'kind': kind == 'feedback' ? 'feedback' : 'bug',
      if (area.isNotEmpty) 'area': _clamp(area, 64),
      if (impact.isNotEmpty) 'impact': _clamp(impact, 64),
      if (keys.isNotEmpty) 'screenshotKeys': keys,
      'appVersion': _clamp(info.reportVersion, 64),
      'platform': _clamp(info.platform, 64),
      'osVersion': _clamp(info.osVersion, 128),
      'deviceInfo': _clamp(info.device, 256),
      'status': 'new',
      'createdAt': DateTime.now().toUtc().toIso8601String(),
    });
    return screenshots.length.clamp(0, maxReportScreenshots) - keys.length;
  }

  Future<List<String>> _uploadScreenshots(
    List<PickedScreenshot> screenshots,
  ) async {
    final upload = _uploadScreenshot;
    if (upload == null || screenshots.isEmpty) return const <String>[];
    final keys = <String>[];
    for (final shot in screenshots.take(maxReportScreenshots)) {
      final key = await upload(shot.bytes, contentType: shot.contentType);
      if (key != null && key.isNotEmpty) keys.add(key);
    }
    return keys;
  }
}
