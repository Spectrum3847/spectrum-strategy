import '../models/trex_assignments.dart';

class TRexAssignmentsExport {
  const TRexAssignmentsExport._();

  static String asText(TRexAssignments assignments) {
    if (assignments.isEmpty) {
      return 'T-Rex assignments\n(no traits added yet)';
    }
    final buffer = StringBuffer('T-Rex assignments\n');
    for (final column in assignments.columns) {
      buffer.writeln();
      buffer.writeln(column.name);
      buffer.writeln('-' * column.name.length);
      if (column.names.isEmpty) {
        buffer.writeln('(unassigned)');
      } else {
        for (final name in column.names) {
          buffer.writeln(name);
        }
      }
    }
    return buffer.toString().trimRight();
  }
}
