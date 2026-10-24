import 'dart:async' show unawaited;

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../services/match_id_resolver.dart';
import '../../state/event_controller.dart';
import '../../theme/strategy_palette.dart';
import '../models/scout_config.dart';
import '../models/scout_entry.dart';
import '../services/scout_qr_codec.dart';
import '../state/scouting_controller.dart';

bool get _isDesktop =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.linux);

class ScoutQrScanScreen extends StatefulWidget {
  const ScoutQrScanScreen({
    required this.controller,
    required this.eventController,
    this.config,
    this.cameraBuilder,
    this.repeatWindow = const Duration(seconds: 3),
    super.key,
  });

  final ScoutingController controller;

  final ScoutConfig? config;

  final EventController eventController;

  final Widget Function(BuildContext, void Function(BarcodeCapture))?
  cameraBuilder;

  final Duration repeatWindow;

  @override
  State<ScoutQrScanScreen> createState() => _ScoutQrScanScreenState();
}

class _ScoutQrScanScreenState extends State<ScoutQrScanScreen> {
  MobileScannerController? _scannerController;
  final TextEditingController _pasteController = TextEditingController();
  final FocusNode _scanFocus = FocusNode();
  String? _errorMessage;

  int _importedCount = 0;
  int _duplicateCount = 0;
  int _errorCount = 0;
  final List<_LogLine> _log = <_LogLine>[];
  final Map<String, DateTime> _lastSeen = <String, DateTime>{};

  bool get _hasCamera => !_isDesktop;

  @override
  void initState() {
    super.initState();
    if (_hasCamera && widget.cameraBuilder == null) {
      _scannerController = MobileScannerController(
        formats: const <BarcodeFormat>[BarcodeFormat.qrCode],
        detectionSpeed: DetectionSpeed.normal,
      );
    }
  }

  @override
  void dispose() {
    _scannerController?.dispose();
    _pasteController.dispose();
    _scanFocus.dispose();
    super.dispose();
  }

  ScoutEntry? _decode(String raw) {
    final cfg = widget.config;
    if (cfg != null) {
      final values = ScoutQrCodec.tryDecodeQrScout(raw, cfg);
      if (values != null) {
        final teamNum =
            (values['pTnumber'] as num?)?.toInt() ??
            (values['team'] as num?)?.toInt() ??
            (values['teamNumber'] as num?)?.toInt() ??
            0;

        final tbaMatchKey = _resolveTbaMatchKey(values, teamNum);
        final typedMatchNumber = values['matchNumber']?.toString().trim() ?? '';
        if (tbaMatchKey == null && typedMatchNumber.isEmpty) {
          _errorMessage =
              'Scanned data has no match number, so it cannot be identified. '
              'Ask the scouter to fill in the match number and rescan.';
          return null;
        }
        return ScoutEntry(
          matchId: '',
          teamNumber: teamNum,
          fieldValues: values,
          tbaMatchKey: tbaMatchKey,
        );
      }
    }
    try {
      return ScoutQrCodec.decode(raw);
    } on FormatException catch (error) {
      _errorMessage = error.message;
      return null;
    }
  }

  String? _resolveTbaMatchKey(Map<String, dynamic> values, int teamNum) {
    if (!widget.eventController.hasMatches) return null;
    final typed = values['matchNumber']?.toString().trim() ?? '';
    final station = values['robot']?.toString().trim() ?? '';
    final match = MatchIdResolver(widget.eventController.matches)
        .resolveWithTiebreak(typed, station: station, teamNumber: teamNum);
    final key = match?.key ?? '';
    return key.isNotEmpty ? key : null;
  }

  void _onDetect(BarcodeCapture capture) {
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null || raw.isEmpty) continue;

      final now = DateTime.now();
      final last = _lastSeen[raw];
      _lastSeen[raw] = now;
      if (last != null && now.difference(last) < widget.repeatWindow) continue;
      unawaited(_importPayload(raw));
    }
  }

  Future<void> _onSubmitted(String raw) async {
    final payload = raw.replaceAll(RegExp(r'[\r\n]+$'), '');
    _pasteController.clear();
    _scanFocus.requestFocus();
    if (payload.trim().isEmpty) return;
    await _importPayload(payload);
  }

  Future<void> _importPayload(String payload) async {
    _errorMessage = null;
    final decoded = _decode(payload);
    if (decoded == null) {
      if (!mounted) return;
      setState(() {
        _errorCount++;
        _errorMessage ??= 'Could not read scout data from that payload.';
        _log.insert(0, _LogLine(_LogKind.error, _errorMessage!));
      });
      return;
    }
    final result = await widget.controller.importScannedEntry(decoded);
    if (!mounted) return;
    final label = 'Team ${decoded.teamNumber}';
    if (result == ScanImportResult.imported) {
      unawaited(HapticFeedback.lightImpact());
    }
    setState(() {
      if (result == ScanImportResult.duplicate) {
        _duplicateCount++;
        _log.insert(
          0,
          _LogLine(_LogKind.duplicate, 'Duplicate skipped: $label'),
        );
      } else {
        _importedCount++;
        _log.insert(0, _LogLine(_LogKind.imported, 'Imported: $label'));
      }
    });
  }

  void _done() => Navigator.of(context).pop(_importedCount);

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _done();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Scan / import scout QR'),
          actions: [TextButton(onPressed: _done, child: const Text('Done'))],
        ),
        body: LayoutBuilder(
          builder: (context, constraints) {
            final panel = _buildPanel(context);
            if (!_hasCamera) {
              return Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: panel,
                ),
              );
            }
            final camera = _buildCamera(context);
            if (constraints.maxWidth >= 840) {
              return Row(
                children: [
                  Expanded(flex: 3, child: camera),
                  Expanded(flex: 2, child: panel),
                ],
              );
            }
            return Column(
              children: [
                Expanded(flex: 3, child: camera),
                Expanded(flex: 2, child: panel),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildCamera(BuildContext context) {
    final builder = widget.cameraBuilder;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(StrategyPalette.radiusSm),
        child: builder != null
            ? builder(context, _onDetect)
            : MobileScanner(
                controller: _scannerController,
                onDetect: _onDetect,
                errorBuilder: (context, error) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Camera error: ${error.errorCode.name}. '
                      'Check that the app has camera permission and try again.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildPanel(BuildContext context) {
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (!_hasCamera) ...[
          Text(
            'Connect a USB QR scanner and scan the QR codes off other '
            'devices, or paste a payload and press Enter. Each scan imports '
            'one entry; duplicates are detected and skipped automatically.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
        ],
        TextField(
          controller: _pasteController,
          focusNode: _scanFocus,

          autofocus: !_hasCamera,

          onSubmitted: _onSubmitted,
          decoration: InputDecoration(
            labelText: 'Scan or paste QR payload, then Enter',
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              icon: const Icon(Icons.download_done_rounded),
              tooltip: 'Import',
              onPressed: () => _onSubmitted(_pasteController.text),
            ),
          ),
        ),
        if (_errorMessage != null) ...[
          const SizedBox(height: 8),
          Text(
            _errorMessage!,
            style: TextStyle(color: theme.colorScheme.error),
          ),
        ],
        const SizedBox(height: 12),
        Text(
          'Imported $_importedCount, '
          '$_duplicateCount duplicate${_duplicateCount == 1 ? '' : 's'} '
          'skipped, $_errorCount error${_errorCount == 1 ? '' : 's'}',
          style: theme.textTheme.labelMedium,
        ),
        const SizedBox(height: 8),
        for (final line in _log)
          ListTile(
            dense: true,
            leading: Icon(line.kind.icon, size: 18),
            title: Text(line.text),
          ),
      ],
    );
  }
}

enum _LogKind {
  imported(Icons.check_circle_outline),
  duplicate(Icons.info_outline),
  error(Icons.error_outline);

  const _LogKind(this.icon);

  final IconData icon;
}

class _LogLine {
  const _LogLine(this.kind, this.text);

  final _LogKind kind;
  final String text;
}
