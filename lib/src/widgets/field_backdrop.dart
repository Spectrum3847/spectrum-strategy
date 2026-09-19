import 'package:flutter/material.dart';

import '../services/field_map_catalog.dart';

typedef FieldBackdropBuilder = Widget Function(
  BuildContext context,
  String? imageAsset,
  double aspectRatio,
);

class FieldBackdrop extends StatelessWidget {
  const FieldBackdrop({required this.builder, this.fieldId = '', super.key});

  final String fieldId;
  final FieldBackdropBuilder builder;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<FieldMapCatalogData>(
      future: FieldMapCatalog.shared(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          debugPrint('FieldMapCatalog load error: ${snapshot.error}');
        }
        final field = snapshot.data?.fallbackFor(fieldId);
        return builder(context, field?.imageAsset, field?.aspectRatio ?? 2.0);
      },
    );
  }
}
