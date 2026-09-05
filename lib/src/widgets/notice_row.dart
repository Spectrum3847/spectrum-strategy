import 'package:flutter/material.dart';

class NoticeRow extends StatelessWidget {
  const NoticeRow({
    required this.icon,
    required this.message,
    this.action,
    this.messageStyle,
    this.iconColor,
    super.key,
  });

  final IconData icon;
  final String message;

  final Widget? action;

  final TextStyle? messageStyle;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final color = iconColor ?? Theme.of(context).colorScheme.onSurfaceVariant;
    final style = messageStyle ?? Theme.of(context).textTheme.bodySmall;

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final Widget label = ConstrainedBox(
          constraints: BoxConstraints(maxWidth: constraints.maxWidth),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 8),
              Flexible(child: Text(message, style: style)),
            ],
          ),
        );
        if (action == null) return label;
        return Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[label, action!],
        );
      },
    );
  }
}
