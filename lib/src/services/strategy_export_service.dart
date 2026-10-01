import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../models/strategy_session.dart';
import 'png_delivery_web.dart'
    if (dart.library.io) 'png_delivery_io.dart'
    as png_delivery;

typedef PngExportDirResolver =
    Future<({String directoryPath, String description})> Function();

class BoardExport {
  const BoardExport(this.savedMessage);

  final String savedMessage;
}

class StrategyExportService {
  StrategyExportService({this.exportDirResolver});

  final PngExportDirResolver? exportDirResolver;

  Future<BoardExport> exportBoardPng({
    required GlobalKey boundaryKey,
    required StrategySession session,
  }) async {
    final bytes = await _renderBoardPng(boundaryKey);
    return writeBoardPng(bytes, session);
  }

  Future<BoardExport> writeBoardPng(
    Uint8List bytes,
    StrategySession session,
  ) async {
    final message = await png_delivery.savePng(
      bytes: bytes,
      fileName: '${_fileName(session)}.png',
      exportDirResolver: exportDirResolver,
    );
    return BoardExport(message);
  }

  Future<String> shareBoardImage({
    required GlobalKey boundaryKey,
    required StrategySession session,
  }) async {
    final bytes = await _renderBoardPng(boundaryKey);

    return png_delivery.sharePng(
      bytes: bytes,
      fileName: '${_fileName(session)}.png',
      subject: session.title,
      exportDirResolver: exportDirResolver,
    );
  }

  Future<Uint8List> _renderBoardPng(GlobalKey boundaryKey) async {
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
    return byteData.buffer.asUint8List();
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
