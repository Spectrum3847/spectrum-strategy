import 'package:spectrumstrategy/src/services/match13/match13_ratings_service.dart';
import 'package:statbotics_client/statbotics_client.dart';

class FakeMatch13RatingsService implements Match13RatingsService {
  FakeMatch13RatingsService(this.ratings);

  FakeMatch13RatingsService.forEvent(
    String eventKey,
    Map<int, StatboticsEpa>? ratings,
  ) : ratings = <String, Map<int, StatboticsEpa>?>{eventKey: ratings};

  final Map<String, Map<int, StatboticsEpa>?> ratings;

  final List<String> requested = <String>[];

  @override
  bool get isWeb => false;

  @override
  Future<Map<int, StatboticsEpa>?> ratingsFor(String eventKey) async {
    requested.add(eventKey);
    return ratings[eventKey];
  }
}
