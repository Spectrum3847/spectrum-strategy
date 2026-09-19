import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/scout_config.dart';

class ScoutConfigService {
  ScoutConfigService()
    : _storageKey = 'scout_config_v1',
      defaultConfigAsset = 'assets/scout_config_default.json';

  ScoutConfigService.pit()
    : _storageKey = 'pit_scout_config_v1',
      defaultConfigAsset = 'assets/pit_scout_config_default.json';

  ScoutConfigService.prescout()
    : _storageKey = 'prescout_config_v1',
      defaultConfigAsset = 'assets/prescout_config_default.json';

  final String _storageKey;

  final String defaultConfigAsset;

  static final Map<String, ScoutConfig> _defaultCache = <String, ScoutConfig>{};

  Future<ScoutConfig> load() async {
    return await loadStored() ?? await loadDefault();
  }

  Future<ScoutConfig?> loadStored() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null) return null;
    try {
      return ScoutConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (e, st) {
      debugPrint(
        'Failed to load persisted scout config from SharedPreferences '
        '($_storageKey); falling back to default. Error: $e\n$st',
      );
      return null;
    }
  }

  Future<void> save(ScoutConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, jsonEncode(config.toJson()));
  }

  Future<ScoutConfig> loadDefault() async {
    final cached = _defaultCache[defaultConfigAsset];
    if (cached != null) {
      return cached;
    }
    final raw = await rootBundle.loadString(defaultConfigAsset);
    final config = ScoutConfig.fromJson(
      jsonDecode(raw) as Map<String, dynamic>,
    );
    _defaultCache[defaultConfigAsset] = config;
    return config;
  }

  static ScoutConfig get seedConfig =>
      ScoutConfig.fromJson(const <String, dynamic>{
        'title': 'Scouting',
        'page_title': '',
        'delimiter': '\t',
        'sections': <dynamic>[],
      });
}
