import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tba_client/tba_client.dart';

Map<String, dynamic> tbaEvent(
  String key,
  String name, {
  required String start,
  required String end,
  int type = 0,
}) => <String, dynamic>{
  'key': key,
  'name': name,
  'year': int.parse(key.substring(0, 4)),
  'event_type': type,
  'start_date': start,
  'end_date': end,
};

Map<String, dynamic> tbaMatch(
  String key, {
  required int time,
  String? video,
  bool played = true,
}) {
  final level = RegExp(r'_(qm|ef|qf|sf|f)').firstMatch(key)!.group(1)!;
  final numbers = RegExp(r'(\d+)(?:m(\d+))?$').firstMatch(key)!;
  final hasSet = numbers.group(2) != null;
  return <String, dynamic>{
    'key': key,
    'comp_level': level,
    'set_number': hasSet ? int.parse(numbers.group(1)!) : 1,
    'match_number': int.parse(numbers.group(hasSet ? 2 : 1)!),
    'actual_time': time,
    'alliances': <String, dynamic>{
      'red': <String, dynamic>{
        'score': played ? 100 : -1,
        'team_keys': <String>[],
      },
      'blue': <String, dynamic>{
        'score': played ? 90 : -1,
        'team_keys': <String>[],
      },
    },
    'winning_alliance': played ? 'red' : '',
    'videos': <Map<String, String>>[
      if (video != null) <String, String>{'type': 'youtube', 'key': video},
    ],
  };
}

TbaClient fakePrescoutTba({
  required List<Map<String, dynamic>> events,
  Map<String, List<Map<String, dynamic>>> matchesByEvent = const {},
  List<String>? log,
}) {
  return TbaClient(
    config: InMemoryTbaConfig('test-key'),
    httpClient: MockClient((request) async {
      final path = request.url.path;
      log?.add(path);
      if (path.contains('/events/')) {
        return http.Response(jsonEncode(events), 200);
      }
      final event = RegExp(r'/event/([^/]+)/matches').firstMatch(path);
      final matches = event == null ? null : matchesByEvent[event.group(1)];
      if (matches == null) return http.Response('', 404);
      return http.Response(jsonEncode(matches), 200);
    }),
  );
}
