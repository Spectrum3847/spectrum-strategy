import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../theme/strategy_palette.dart';
import '../models/scout_config.dart';
import '../models/scout_entry.dart';
import '../services/scout_qr_codec.dart';

class ScoutQrShareScreen extends StatelessWidget {
  const ScoutQrShareScreen({required this.entry, this.config, super.key});

  final ScoutEntry entry;

  final ScoutConfig? config;

  String _buildPayload() {
    final cfg = config;
    if (cfg != null && entry.fieldValues.isNotEmpty) {
      return ScoutQrCodec.encodeQrScout(entry.fieldValues, cfg);
    }
    return ScoutQrCodec.encode(entry);
  }

  @override
  Widget build(BuildContext context) {
    final payload = _buildPayload();
    final isQrScout = config != null && entry.fieldValues.isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        title: Text('Team ${entry.teamNumber} - ${entry.effectiveAlliance}'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Show this QR to the scanning device.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 4),
              Text(
                isQrScout
                    ? 'QRScout-compatible format - ${payload.length} bytes'
                    : 'App format - ${payload.length} bytes',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              Expanded(
                child: Center(
                  child: AspectRatio(
                    aspectRatio: 1,

                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(color: StrategyPalette.border),
                      ),
                      child: QrImageView(
                        data: payload,
                        version: QrVersions.auto,
                        backgroundColor: Colors.white,
                        eyeStyle: const QrEyeStyle(
                          eyeShape: QrEyeShape.square,
                          color: StrategyPalette.primary,
                        ),
                        dataModuleStyle: const QrDataModuleStyle(
                          dataModuleShape: QrDataModuleShape.square,
                          color: StrategyPalette.primary,
                        ),
                        errorCorrectionLevel: QrErrorCorrectLevel.M,
                      ),
                    ),
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
