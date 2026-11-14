import 'package:flutter_test/flutter_test.dart';
import 'package:spectrumstrategy/src/services/debug_info.dart';

DebugInfo _info({
  String appVersion = '1.2.3',
  String buildNumber = '9',
  String platform = 'android',
  String osVersion = 'Android 14',
  String device = 'Pixel 8',
  String gitCommit = 'a1b2c3d',
  String gitBranch = 'master',
  String buildDate = '',
}) => DebugInfo(
  appVersion: appVersion,
  buildNumber: buildNumber,
  platform: platform,
  osVersion: osVersion,
  device: device,
  gitCommit: gitCommit,
  gitBranch: gitBranch,
  buildDate: buildDate,
);

void main() {
  test('versionLabel joins version and build, dropping an empty build', () {
    expect(_info().versionLabel, '1.2.3+9');
    expect(_info(buildNumber: '').versionLabel, '1.2.3');
  });

  test(
    'commitLabel falls back to a local build when no commit is injected',
    () {
      expect(_info(gitCommit: 'a1b2c3d').commitLabel, 'a1b2c3d');
      expect(_info(gitCommit: '').commitLabel, 'local build');
    },
  );

  test('reportVersion always carries the commit, plus branch and date', () {
    expect(_info().reportVersion, '1.2.3+9 (a1b2c3d master)');

    expect(
      _info(buildDate: '2026-07-06').reportVersion,
      '1.2.3+9 (a1b2c3d master 2026-07-06)',
    );

    expect(
      _info(gitCommit: '', gitBranch: '').reportVersion,
      '1.2.3+9 (local build)',
    );
  });

  test('toDisplayText lists provenance and omits empty lines', () {
    expect(
      _info(buildDate: '2026-07-06').toDisplayText(),
      [
        'App version: 1.2.3+9',
        'Commit: a1b2c3d',
        'Branch: master',
        'Built: 2026-07-06',
        'Platform: android',
        'OS: Android 14',
        'Device: Pixel 8',
      ].join('\n'),
    );

    expect(
      _info(
        platform: 'web',
        osVersion: '',
        device: '',
        gitCommit: '',
        gitBranch: '',
      ).toDisplayText(),
      [
        'App version: 1.2.3+9',
        'Commit: local build',
        'Platform: web',
      ].join('\n'),
    );
  });
}
