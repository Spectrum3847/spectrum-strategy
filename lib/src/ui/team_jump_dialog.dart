import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../widgets/glass_modal.dart';
import 'glass_chrome.dart';
import 'platform_target.dart';

class MatchQuery {
  const MatchQuery({required this.suffix, required this.label});

  final String suffix;
  final String label;

  static final RegExp _qualification = RegExp(r'^(?:qm|q|m|match)(\d+)$');
  static final RegExp _playoff = RegExp(r'^(sf|f)(\d+)(?:m(\d+))?$');

  static MatchQuery? parse(String query) {
    final text = query.toLowerCase().replaceAll(RegExp(r'[\s-]'), '');
    final qual = _qualification.firstMatch(text);
    if (qual != null) {
      final number = int.parse(qual.group(1)!);
      return number == 0
          ? null
          : MatchQuery(suffix: 'qm$number', label: 'Qualification $number');
    }
    final playoff = _playoff.firstMatch(text);
    if (playoff == null) return null;
    final level = playoff.group(1)!;
    final set = int.parse(playoff.group(2)!);
    final game = playoff.group(3);
    if (set == 0 || game == '0') return null;
    final name = level == 'sf' ? 'Semifinal' : 'Final';
    return MatchQuery(
      suffix: '$level${set}m${game ?? 1}',
      label: game == null ? '$name $set' : '$name $set match $game',
    );
  }
}

Future<void> showTeamJump(
  BuildContext context, {
  required Set<int> knownTeams,
  required ValueChanged<int> onOpenTeam,
  String eventKey = '',
  Set<String> knownMatchKeys = const <String>{},
  ValueChanged<String>? onOpenMatch,
}) {
  final glass = GlassChrome.isEnabled(context);
  return showDialog<void>(
    context: context,
    builder: (_) => TeamJumpDialog(
      glass: glass,
      knownTeams: knownTeams,
      onOpenTeam: onOpenTeam,
      eventKey: eventKey,
      knownMatchKeys: knownMatchKeys,
      onOpenMatch: onOpenMatch,
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
    this.eventKey = '',
    this.knownMatchKeys = const <String>{},
    this.onOpenMatch,
    this.glass = false,
    super.key,
  });

  final Set<int> knownTeams;
  final ValueChanged<int> onOpenTeam;
  final String eventKey;
  final Set<String> knownMatchKeys;
  final ValueChanged<String>? onOpenMatch;
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

  String? _matchKey(MatchQuery? query) {
    if (query == null || widget.onOpenMatch == null) return null;
    final key = '${widget.eventKey}_${query.suffix}';
    return widget.knownMatchKeys.contains(key.toLowerCase()) ? key : null;
  }

  void _openMatch(String key) {
    Navigator.of(context).pop();
    widget.onOpenMatch!(key);
  }

  void _submit() {
    final query = MatchQuery.parse(_team.text);
    if (query != null) {
      final key = _matchKey(query);
      if (key != null) return _openMatch(key);
      setState(() => _error = '${query.label} is not in the schedule.');
      return;
    }
    final team = int.tryParse(_team.text.trim());
    if (team == null || team <= 0) {
      setState(
        () => _error = 'Enter a team number like 3847 or a match like q45.',
      );
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
    final query = MatchQuery.parse(_team.text);
    final matchKey = _matchKey(query);
    return GlassAlertDialogShell(
      glass: widget.glass,
      title: 'Go to team or match',
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _team,
              autofocus: true,
              textInputAction: TextInputAction.go,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9 ]')),
              ],
              onChanged: (_) => setState(() => _error = null),
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: 'Team number or match',
                hintText: '3847 or q45',
                prefixIcon: const Icon(Icons.search_rounded),
                errorText: _error,
              ),
            ),
            if (query != null && matchKey != null)
              ListTile(
                key: const ValueKey('match-result'),
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.schedule_rounded),
                title: Text(query.label),
                subtitle: const Text('Match'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => _openMatch(matchKey),
              ),
          ],
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
