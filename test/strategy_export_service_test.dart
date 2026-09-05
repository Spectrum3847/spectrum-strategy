import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:spectrumstrategy/src/models/strategy_session.dart';
import 'package:spectrumstrategy/src/services/strategy_export_service.dart';

void main() {
  group('writeBoardPng', () {
    test('writes to the injected desktop directory', () async {
      final tmp = await Directory.systemTemp.createTemp('export');
      final service = StrategyExportService(
        exportDirResolver: () async =>
            (directory: tmp, description: 'Pictures/SpectrumStrategy'),
      );

      final result = await service.writeBoardPng(
        Uint8List.fromList(<int>[1, 2, 3]),
        StrategySession.create(),
      );

      expect(result.file.path, contains('match_1.png'));
      expect(result.file.parent.path, tmp.path);
      expect(await result.file.exists(), isTrue);
      expect(result.locationDescription, 'Pictures/SpectrumStrategy');
      await tmp.delete(recursive: true);
    });

    test('uses the mobile description when the resolver says so', () async {
      final tmp = await Directory.systemTemp.createTemp('export');
      final mobileDescription =
          "the app's Exports folder (visible in the Files app on iOS)";
      final service = StrategyExportService(
        exportDirResolver: () async =>
            (directory: tmp, description: mobileDescription),
      );

      final result = await service.writeBoardPng(
        Uint8List.fromList(<int>[1, 2, 3]),
        StrategySession.create(),
      );

      expect(result.locationDescription, mobileDescription);
      await tmp.delete(recursive: true);
    });

    test(
      'saveBoard message mentions Pictures/SpectrumStrategy on desktop',
      () async {
        final tmp = await Directory.systemTemp.createTemp('export');
        final service = StrategyExportService(
          exportDirResolver: () async =>
              (directory: tmp, description: 'Pictures/SpectrumStrategy'),
        );

        final result = await service.writeBoardPng(
          Uint8List.fromList(<int>[1, 2, 3]),
          StrategySession.create(),
        );

        expect(result.savedMessage, contains('Pictures/SpectrumStrategy'));
        expect(result.savedMessage, isNot(contains('Files app')));
        await tmp.delete(recursive: true);
      },
    );
  });
}
