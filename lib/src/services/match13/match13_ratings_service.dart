import 'package:flutter/foundation.dart';
import 'package:match13_client/match13_client.dart';
import 'package:statbotics_client/statbotics_client.dart';

import '../firestore_api_key_config.dart';

class Match13RatingsService {
  Match13RatingsService({
    FirestoreApiKeyConfig? config,
    Match13Client Function(String apiKey)? clientFactory,
    @visibleForTesting this.isWeb = kIsWeb,
  }) : _config = config ?? FirestoreApiKeyConfig.match13(),
       _clientFactory =
           clientFactory ?? ((apiKey) => Match13Client(apiKey: apiKey));

  final FirestoreApiKeyConfig _config;
  final Match13Client Function(String apiKey) _clientFactory;

  @visibleForTesting
  final bool isWeb;

  Future<Map<int, StatboticsEpa>?> ratingsFor(String eventKey) async {
    if (eventKey.isEmpty) return null;

    if (isWeb) return null;

    final apiKey = await _resolveKey();
    if (apiKey == null) return null;

    final client = _clientFactory(apiKey);
    try {
      final event = await client.getEventTeams(eventKey);
      if (event == null) return const <int, StatboticsEpa>{};
      return <int, StatboticsEpa>{
        for (final team in event.teams)
          if (team.teamNumber != null) team.teamNumber!: _epaOf(team),
      };
    } catch (e) {
      debugPrint('Match13RatingsService: $eventKey failed — $e');
      return null;
    } finally {
      client.close();
    }
  }

  Future<String?> _resolveKey() async {
    try {
      final key = await _config.resolveApiKey();
      return (key == null || key.isEmpty) ? null : key;
    } catch (e) {
      debugPrint('Match13RatingsService: resolving the key failed — $e');
      return null;
    }
  }

  static StatboticsEpa _epaOf(Match13TeamEvent team) => StatboticsEpa(
    totalPoints: team.xpEnd,
    autoPoints: team.xAuto,
    teleopPoints: team.xTele,
    endgamePoints: team.xEnd,
  );
}
