import 'package:tba_client/tba_client.dart';

Future<List<TbaMatchVideo>> fetchMatchVideos(
  TbaClient client,
  String matchKey,
) {
  return client.getMatch(matchKey).then((match) => match?.videos ?? const []);
}
