import 'package:flutter/material.dart';

class SegmentLabel extends StatelessWidget {
  const SegmentLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,

      child: Text(text, maxLines: 1, softWrap: false),
    );
  }
}
