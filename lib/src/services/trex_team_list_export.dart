import '../models/trex_team_list.dart';

class TRexTeamListExport {
  const TRexTeamListExport._();

  static String asText(TRexTeamList teamList) {
    final title = teamList.title.trim().isEmpty
        ? 'Team assignments'
        : teamList.title;
    if (teamList.isEmpty) {
      return '$title\n(no columns added yet)';
    }
    final buffer = StringBuffer('$title\n');
    for (final column in teamList.columns) {
      buffer.writeln();
      buffer.writeln(column.name);
      buffer.writeln('-' * column.name.length);
      if (column.teams.isEmpty) {
        buffer.writeln('(no teams yet)');
      } else {
        for (final team in column.teams) {
          buffer.writeln(team);
        }
      }
    }
    buffer.writeln();
    buffer.writeln('Total teams: ${teamList.totalTeams}');
    return buffer.toString().trimRight();
  }
}
