import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../widgets/glass_modal.dart';
import 'glass_chrome.dart';
import 'platform_target.dart';

Future<void> showTeamJump(
  BuildContext context, {
  required Set<int> knownTeams,
  required ValueChanged<int> onOpenTeam,
}) {
  final glass = GlassChrome.isEnabled(context);
  return showDialog<void>(
    context: context,
    builder: (_) => TeamJumpDialog(
      glass: glass,
      knownTeams: knownTeams,
      onOpenTeam: onOpenTeam,
    ),
  );
}

class TeamJumpShortcut extends StatefulWidget {
  const TeamJumpShortcut({
    required this.onJump,
    required this.child,
    this.enabled,
    super.key,
  });

  final ValueChanged<BuildContext> onJump;
  final Widget child;
  final bool? enabled;

  @override
  State<TeamJumpShortcut> createState() => _TeamJumpShortcutState();
}

class _TeamJumpShortcutState extends State<TeamJumpShortcut> {
  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  bool get _typing {
    final focus = FocusManager.instance.primaryFocus?.context;
    if (focus == null) return false;
    if (focus.widget is EditableText) return true;
    return focus.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    if (event.logicalKey != LogicalKeyboardKey.slash) return false;
    if (!(widget.enabled ?? isDesktopOs)) return false;
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isControlPressed ||
        keyboard.isMetaPressed ||
        keyboard.isAltPressed) {
      return false;
    }
    if (!(ModalRoute.of(context)?.isCurrent ?? false) || _typing) {
      return false;
    }
    widget.onJump(context);
    return true;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class TeamJumpDialog extends StatefulWidget {
  const TeamJumpDialog({
    required this.knownTeams,
    required this.onOpenTeam,
    this.glass = false,
    super.key,
  });

  final Set<int> knownTeams;
  final ValueChanged<int> onOpenTeam;
  final bool glass;

  @override
  State<TeamJumpDialog> createState() => _TeamJumpDialogState();
}

class _TeamJumpDialogState extends State<TeamJumpDialog> {
  final TextEditingController _team = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _team.dispose();
    super.dispose();
  }

  void _submit() {
    final team = int.tryParse(_team.text.trim());
    if (team == null || team <= 0) {
      setState(() => _error = 'Enter a team number, like 3847.');
      return;
    }
    final known = widget.knownTeams;
    if (known.isNotEmpty && !known.contains(team)) {
      setState(() => _error = 'Team $team is not at this event.');
      return;
    }
    Navigator.of(context).pop();
    widget.onOpenTeam(team);
  }

  @override
  Widget build(BuildContext context) {
    return GlassAlertDialogShell(
      glass: widget.glass,
      title: 'Go to team',
      content: SizedBox(
        width: double.maxFinite,
        child: TextField(
          controller: _team,
          autofocus: true,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.go,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onChanged: (_) {
            if (_error != null) setState(() => _error = null);
          },
          onSubmitted: (_) => _submit(),
          decoration: InputDecoration(
            labelText: 'Team number',
            prefixIcon: const Icon(Icons.search_rounded),
            errorText: _error,
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Go')),
      ],
    );
  }
}
