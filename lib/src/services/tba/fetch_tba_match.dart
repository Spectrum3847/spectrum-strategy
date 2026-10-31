import 'package:tba_client/tba_client.dart';

Future<TbaScheduleMatch?> fetchTbaMatch(
  TbaClient client,
  String eventKey,
  String matchKey,
) async {
  try {
    final matches = await client.getEventMatches(eventKey);
    for (final match in matches) {
      if (match.key == matchKey) return match;
    }
  } catch (_) {
    // Intentionally empty.
  }
  return null;
}
