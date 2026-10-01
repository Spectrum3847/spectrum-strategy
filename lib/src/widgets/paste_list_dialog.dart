import 'package:flutter/material.dart';

import '../services/name_list_parse.dart';

Future<List<String>?> showPasteListDialog(
  BuildContext context, {
  required String title,
  required String hint,
}) {
  return showDialog<List<String>>(
    context: context,
    builder: (_) => _PasteListDialog(title: title, hint: hint),
  );
}

class _PasteListDialog extends StatefulWidget {
  const _PasteListDialog({required this.title, required this.hint});

  final String title;
  final String hint;

  @override
  State<_PasteListDialog> createState() => _PasteListDialogState();
}

class _PasteListDialogState extends State<_PasteListDialog> {
  final TextEditingController _text = TextEditingController();
  List<String> _parsed = const <String>[];

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'One per line, or separated by commas or tabs.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            TextField(
              key: const ValueKey('paste-list-field'),
              controller: _text,
              maxLines: 8,
              minLines: 4,
              autofocus: true,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                hintText: widget.hint,
              ),
              onChanged: (value) =>
                  setState(() => _parsed = parsePastedNames(value)),
            ),
            const SizedBox(height: 8),

            Text(
              _parsed.length == 1 ? '1 entry' : '${_parsed.length} entries',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('paste-list-add'),
          onPressed: _parsed.isEmpty
              ? null
              : () => Navigator.of(context).pop(_parsed),
          child: const Text('Add'),
        ),
      ],
    );
  }
}
