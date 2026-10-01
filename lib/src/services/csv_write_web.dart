import 'csv_delivery_web.dart' as csv_delivery;
import 'scout_csv_export.dart';

Future<ScoutCsvExport> writeCsvFile({
  required String csv,
  required String fileName,
  ExportDirResolver? exportDirResolver,
}) async {
  final message = await csv_delivery.deliverCsv(csv: csv, fileName: fileName);
  return ScoutCsvExport(fileName, message);
}
