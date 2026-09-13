import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/strategy_session.dart';
import 'windows_pictures_dir.dart';

class BoardExport {
  const BoardExport(this.file, this.locationDescription);

  final File file;
  final String locationDescription;

  String get savedMessage {
    final name = file.path.split(RegExp(r'[\\/]')).last;
    return 'Saved $name to $locationDescription.';
  }
}

typedef ExportDirResolver =
    Future<({Directory directory, String description})> Function();

class StrategyExportService {
  StrategyExportService({ExportDirResolver? exportDirResolver})
    : _exportDirResolver = exportDirResolver ?? _defaultExportDirResolver;

  final ExportDirResolver _exportDirResolver;

  Future<BoardExport> exportBoardPng({
    required GlobalKey boundaryKey,
    required StrategySession session,
  }) async {
    final context = boundaryKey.currentContext;
    if (context == null) {
      throw StateError('Strategy board is not ready to export yet.');
    }

    final renderObject = context.findRenderObject();
    if (renderObject is! RenderRepaintBoundary) {
      throw StateError(
        'Strategy board export target is not a repaint boundary.',
      );
    }

    final image = await renderObject.toImage(pixelRatio: 3);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) {
      throw StateError('Unable to encode the strategy board image.');
    }

    return writeBoardPng(byteData.buffer.asUint8List(), session);
  }

  Future<BoardExport> writeBoardPng(
    Uint8List bytes,
    StrategySession session,
  ) async {
    final resolved = await _exportDirResolver();
    await resolved.directory.create(recursive: true);

    final file = File(
      '${resolved.directory.path}${Platform.pathSeparator}${_fileName(session)}.png',
    );
    await file.writeAsBytes(bytes, flush: true);
    return BoardExport(file, resolved.description);
  }

  Future<void> shareBoardImage({
    required GlobalKey boundaryKey,
    required StrategySession session,
  }) async {
    final result = await exportBoardPng(
      boundaryKey: boundaryKey,
      session: session,
    );

    await SharePlus.instance.share(
      ShareParams(
        files: <XFile>[XFile(result.file.path)],
        subject: session.title,
      ),
    );
  }

  String _fileName(StrategySession session) {
    final raw = session.title
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    return raw.isEmpty ? 'strategy_match' : raw;
  }
}

String _homeDirectory() {
  if (!Platform.isWindows) return Platform.environment['HOME'] ?? '';
  return Platform.environment['USERPROFILE'] ??
      ((Platform.environment['HOMEDRIVE'] ?? '') +
          (Platform.environment['HOMEPATH'] ?? ''));
}

Future<({Directory directory, String description})>
_defaultExportDirResolver() async {
  if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
    final resolved = windowsPicturesPath();
    final pictures = resolved != null
        ? Directory('$resolved${Platform.pathSeparator}SpectrumStrategy')
        : Directory(
            '${_homeDirectory()}${Platform.pathSeparator}Pictures'
            '${Platform.pathSeparator}SpectrumStrategy',
          );
    return (directory: pictures, description: 'Pictures/SpectrumStrategy');
  }
  final directory = await getApplicationDocumentsDirectory();
  final exportDirectory = Directory(
    '${directory.path}${Platform.pathSeparator}exports',
  );
  return (
    directory: exportDirectory,
    description: "the app's exports folder (visible in the Files app on iOS)",
  );
}
