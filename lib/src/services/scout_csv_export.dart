class ScoutCsvExport {
  const ScoutCsvExport(this.filePath, this.locationDescription);

  final String filePath;

  final String locationDescription;

  String get savedMessage {
    final name = filePath.split(RegExp(r'[\\/]')).last;
    return 'Saved $name to $locationDescription.';
  }
}

typedef ExportDirResolver =
    Future<({String directory, String description})> Function();
