import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../widgets/glass_modal.dart';
import '../glass_chrome.dart';

Future<String?> showPrompt(
  BuildContext context, {
  required String title,
  required String label,
  required String confirmLabel,
  String initial = '',
  bool digitsOnly = false,
  String? Function(String text)? validate,
}) {
  final glass = GlassChrome.isEnabled(context);
  return showDialog<String>(
    context: context,
    builder: (_) => _PromptDialog(
      glass: glass,
      title: title,
      label: label,
      confirmLabel: confirmLabel,
      initial: initial,
      digitsOnly: digitsOnly,
      validate: validate,
    ),
  );
}

class _PromptDialog extends StatefulWidget {
  const _PromptDialog({
    required this.glass,
    required this.title,
    required this.label,
    required this.confirmLabel,
    required this.initial,
    required this.digitsOnly,
    required this.validate,
  });

  final bool glass;
  final String title;
  final String label;
  final String confirmLabel;
  final String initial;
  final bool digitsOnly;
  final String? Function(String text)? validate;

  @override
  State<_PromptDialog> createState() => _PromptDialogState();
}

class _PromptDialogState extends State<_PromptDialog> {
  late final TextEditingController _text = TextEditingController(
    text: widget.initial,
  );
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _text.text.trim();
    final error = widget.validate?.call(value);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    return GlassAlertDialogShell(
      glass: widget.glass,
      title: widget.title,
      content: SizedBox(
        width: double.maxFinite,
        child: TextField(
          controller: _text,
          autofocus: true,
          keyboardType: widget.digitsOnly ? TextInputType.number : null,
          inputFormatters: widget.digitsOnly
              ? [FilteringTextInputFormatter.digitsOnly]
              : null,
          textInputAction: TextInputAction.done,
          onChanged: (_) {
            if (_error != null) setState(() => _error = null);
          },
          onSubmitted: (_) => _submit(),
          decoration: InputDecoration(
            labelText: widget.label,
            errorText: _error,
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: Text(widget.confirmLabel)),
      ],
    );
  }
}
