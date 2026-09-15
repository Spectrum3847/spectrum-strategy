import 'package:flutter/material.dart';

Future<String?> promptText(
  BuildContext context, {
  required String title,
  required String hint,
  String initial = '',
}) {
  final ctrl = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        decoration: InputDecoration(labelText: hint),
        onSubmitted: (v) => Navigator.of(context).pop(v.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(ctrl.text.trim()),
          child: const Text('Save'),
        ),
      ],
    ),
  ).whenComplete(ctrl.dispose);
}
