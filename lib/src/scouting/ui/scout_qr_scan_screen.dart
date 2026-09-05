import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

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
  const ScoutQrScanScreen({required this.controller, this.config, super.key});

  final ScoutingController controller;

  final ScoutConfig? config;

  @override
  State<ScoutQrScanScreen> createState() => _ScoutQrScanScreenState();
}

class _ScoutQrScanScreenState extends State<ScoutQrScanScreen> {
  MobileScannerController? _scannerController;
  final TextEditingController _pasteController = TextEditingController();
  final FocusNode _scanFocus = FocusNode();
  bool _handled = false;
  String? _errorMessage;

  int _importedCount = 0;
  int _duplicateCount = 0;
  final List<String> _log = <String>[];

  @override
  void initState() {
    super.initState();
    if (!_isDesktop) {
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
        return ScoutEntry(
          matchId: '',
          teamNumber: teamNum,
          fieldValues: values,
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

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_handled) return;
    final raw = capture.barcodes.isNotEmpty
        ? capture.barcodes.first.rawValue
        : null;
    if (raw == null || raw.isEmpty) return;
    _handled = true;
    await _scannerController?.stop();

    _errorMessage = null;
    final decoded = _decode(raw);
    if (decoded == null) {
      if (!mounted) return;
      setState(() {
        _errorMessage ??= 'Could not read scout data from QR.';
        _handled = false;
      });
      await _scannerController?.start();
      return;
    }

    final result = await widget.controller.importScannedEntry(decoded);
    if (!mounted) return;
    if (result == ScanImportResult.duplicate) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Already imported (duplicate).')),
      );
      setState(() => _handled = false);
      await _scannerController?.start();
      return;
    }
    Navigator.of(context).pop(decoded);
  }

  Future<void> _onDesktopSubmit(String raw) async {
    final trimmed = raw.trim();
    _pasteController.clear();
    _scanFocus.requestFocus();
    if (trimmed.isEmpty) return;

    _errorMessage = null;
    final decoded = _decode(trimmed);
    if (decoded == null) {
      setState(
        () => _errorMessage ??= 'Could not read scout data from that payload.',
      );
      return;
    }
    final result = await widget.controller.importScannedEntry(decoded);
    if (!mounted) return;
    setState(() {
      final label = 'Team ${decoded.teamNumber}';
      if (result == ScanImportResult.duplicate) {
        _duplicateCount++;
        _log.insert(0, 'Duplicate skipped: $label');
      } else {
        _importedCount++;
        _log.insert(0, 'Imported: $label');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isDesktop ? 'Scan / import scout QR' : 'Scan scout QR'),
      ),
      body: _isDesktop ? _buildDesktopScanner(context) : _buildScanner(),
    );
  }

  Widget _buildScanner() {
    return Stack(
      children: [
        MobileScanner(
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
        if (_errorMessage != null)
          Positioned(
            left: 16,
            right: 16,
            bottom: 32,
            child: Container(
              padding: const EdgeInsets.all(12),
              color: StrategyPalette.surfaceOf(context),
              child: Text('Could not read that QR: $_errorMessage'),
            ),
          ),
      ],
    );
  }

  Widget _buildDesktopScanner(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Connect a USB QR scanner and scan the QR codes off other '
                'devices, or paste a payload and press Enter. Each scan imports '
                'one entry; duplicates are detected and skipped automatically.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _pasteController,
                focusNode: _scanFocus,
                autofocus: true,

                onSubmitted: _onDesktopSubmit,
                decoration: InputDecoration(
                  labelText: 'Scan or paste QR payload, then Enter',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.download_done_rounded),
                    tooltip: 'Import',
                    onPressed: () => _onDesktopSubmit(_pasteController.text),
                  ),
                ),
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 8),
                Text(
                  _errorMessage!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 12),
              Text(
                'Imported $_importedCount, $_duplicateCount duplicate'
                '${_duplicateCount == 1 ? '' : 's'} skipped',
                style: Theme.of(context).textTheme.labelMedium,
              ),
              const SizedBox(height: 8),
              Expanded(
                child: _log.isEmpty
                    ? const SizedBox.shrink()
                    : ListView.builder(
                        itemCount: _log.length,
                        itemBuilder: (context, i) => ListTile(
                          dense: true,
                          leading: Icon(
                            _log[i].startsWith('Duplicate')
                                ? Icons.info_outline
                                : Icons.check_circle_outline,
                            size: 18,
                          ),
                          title: Text(_log[i]),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
