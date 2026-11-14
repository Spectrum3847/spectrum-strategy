import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:material_ui/material_ui.dart';

class MarkdownThemeBridge extends StatelessWidget {
  const MarkdownThemeBridge({super.key, required this.builder});

  final Widget Function(MarkdownStyleSheet styleSheet) builder;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final card = theme.cardTheme.color ?? theme.cardColor;
    // ignore: deprecated_member_use
    return MaterialUiCompatibilityBridge(
      child: builder(
        MarkdownStyleSheet(
          code: TextStyle(backgroundColor: card),
          codeblockDecoration: BoxDecoration(
            color: card,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }
}
