import 'package:flutter/foundation.dart';
import 'package:match13_client/match13_client.dart';
import 'package:statbotics_client/statbotics_client.dart';

import '../firestore_api_key_config.dart';
import 'match13_worker_config.dart';

class Match13RatingsService {
  Match13RatingsService({
    FirestoreApiKeyConfig? config,
    Match13WorkerConfig? workerConfig,
    Match13Client Function(String apiKey)? clientFactory,
    Match13Client Function(String baseUrl)? proxyClientFactory,
    @visibleForTesting this.isWeb = kIsWeb,
  }) : _config = config ?? FirestoreApiKeyConfig.match13(),
       _workerConfig = workerConfig ?? Match13WorkerConfig(),
       _clientFactory =
           clientFactory ?? ((apiKey) => Match13Client(apiKey: apiKey)),
       _proxyClientFactory =
           proxyClientFactory ??
           ((baseUrl) => Match13Client(apiKey: null, baseUrl: baseUrl));

  final FirestoreApiKeyConfig _config;
  final Match13WorkerConfig _workerConfig;
  final Match13Client Function(String apiKey) _clientFactory;
  final Match13Client Function(String baseUrl) _proxyClientFactory;

  @visibleForTesting
  final bool isWeb;

  Future<Map<int, StatboticsEpa>?> ratingsFor(String eventKey) async {
    if (eventKey.isEmpty) return null;

    if (isWeb) {
      final origin = await _resolveWorkerOrigin();
      if (origin == null) return null;
      return _fetch(_proxyClientFactory(origin), eventKey);
    }

    final apiKey = await _resolveKey();
    if (apiKey == null) return null;
    return _fetch(_clientFactory(apiKey), eventKey);
  }

  Future<Map<int, StatboticsEpa>?> _fetch(
    Match13Client client,
    String eventKey,
  ) async {
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

  Future<String?> _resolveWorkerOrigin() async {
    try {
      final origin = await _workerConfig.resolve();
      return (origin == null || origin.isEmpty) ? null : origin;
    } catch (e) {
      debugPrint('Match13RatingsService: resolving the Worker failed — $e');
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
