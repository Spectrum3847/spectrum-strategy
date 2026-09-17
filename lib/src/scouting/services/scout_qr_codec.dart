import 'dart:convert';

import '../models/scout_config.dart';
import '../models/scout_entry.dart';

class ScoutQrCodec {
  const ScoutQrCodec._();

  static const int currentVersion = 1;
  static const String _versionKey = 'v';
  static const String _entryKey = 'entry';

  static String encodeQrScout(Map<String, dynamic> values, ScoutConfig config) {
    return config.encodeValues(values);
  }

  static Map<String, dynamic>? tryDecodeQrScout(
    String payload,
    ScoutConfig config,
  ) {
    final columns = config.payloadColumns;
    if (columns.isEmpty) return null;
    final parts = payload.split(config.delimiter);

    if ((parts.length - columns.length).abs() > 2) return null;
    return config.decodeValues(payload);
  }

  static String encode(ScoutEntry entry) {
    return jsonEncode(<String, dynamic>{
      _versionKey: currentVersion,
      _entryKey: entry.toJson(),
    });
  }

  static ScoutEntry decode(String payload) {
    final dynamic decoded;
    try {
      decoded = jsonDecode(payload);
    } on FormatException catch (error) {
      throw FormatException(
        'Scout QR payload is not valid JSON: ${error.message}',
      );
    }
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Scout QR payload is not a JSON object.');
    }
    final version = decoded[_versionKey];
    if (version is! int) {
      throw const FormatException(
        'Scout QR payload is missing the version field.',
      );
    }
    if (version > currentVersion) {
      throw FormatException(
        'Scout QR payload is from a newer app version ($version > $currentVersion). '
        'Update this device to import it.',
      );
    }
    final rawEntry = decoded[_entryKey];
    if (rawEntry is! Map<String, dynamic>) {
      throw const FormatException(
        'Scout QR payload is missing the entry field.',
      );
    }
    try {
      return ScoutEntry.fromJson(rawEntry);
    } catch (error) {
      throw FormatException(
        'Scout QR payload decoded but ScoutEntry could not be built: $error',
      );
    }
  }
}
