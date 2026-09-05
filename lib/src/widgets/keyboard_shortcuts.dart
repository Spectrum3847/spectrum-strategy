library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class SaveShortcut extends StatelessWidget {
  const SaveShortcut({required this.onSave, required this.child, super.key});

  final VoidCallback? onSave;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final VoidCallback? onSave = this.onSave;
    if (onSave == null) return child;
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): onSave,
        const SingleActivator(LogicalKeyboardKey.keyS, meta: true): onSave,
      },
      child: child,
    );
  }
}

class HorizontalStepShortcuts extends StatelessWidget {
  const HorizontalStepShortcuts({
    required this.onPrevious,
    required this.onNext,
    required this.child,
    super.key,
  });

  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return FocusTraversalGroup(
      child: CallbackShortcuts(
        bindings: <ShortcutActivator, VoidCallback>{
          const SingleActivator(LogicalKeyboardKey.arrowLeft): onPrevious,
          const SingleActivator(LogicalKeyboardKey.arrowRight): onNext,
        },
        child: child,
      ),
    );
  }
}
