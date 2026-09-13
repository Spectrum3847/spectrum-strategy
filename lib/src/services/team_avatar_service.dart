import 'dart:convert';
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:tba_client/tba_client.dart';

class TeamAvatarService {
  TeamAvatarService({
    required this._client,
    int? year,
    Future<SharedPreferences> Function()? prefsLoader,
  }) : _year = year ?? DateTime.now().year,
       _prefsLoader = prefsLoader ?? SharedPreferences.getInstance;

  final TbaClient _client;
  final int _year;
  final Future<SharedPreferences> Function() _prefsLoader;

  final Map<int, Uint8List?> _memory = <int, Uint8List?>{};

  static const String _noAvatarSentinel = 'none';

  String _key(int team) => 'tba_avatar_${_year}_$team';

  Future<Uint8List?> avatarFor(int teamNumber) async {
    if (_memory.containsKey(teamNumber)) {
      return _memory[teamNumber];
    }

    final prefs = await _prefsLoader();
    final cached = prefs.getString(_key(teamNumber));
    if (cached != null) {
      if (cached == _noAvatarSentinel) {
        _memory[teamNumber] = null;
        return null;
      }
      try {
        final bytes = base64Decode(cached);
        _memory[teamNumber] = bytes;
        return bytes;
      } on FormatException {}
    }

    try {
      final bytes = await _client.fetchTeamAvatar(teamNumber, _year);
      _memory[teamNumber] = bytes;
      await prefs.setString(
        _key(teamNumber),
        bytes == null ? _noAvatarSentinel : base64Encode(bytes),
      );
      return bytes;
    } on TbaApiKeyMissingException {
      return null;
    } catch (_) {
      return null;
    }
  }
}
