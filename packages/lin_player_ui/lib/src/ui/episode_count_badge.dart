import 'package:flutter/material.dart';

class EpisodeCountBadge extends StatelessWidget {
  const EpisodeCountBadge({super.key, required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = Colors.black.withValues(alpha: 0.55);
    const fg = Colors.white;
    const border = BorderSide.none;
    const iconColor = Colors.white;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border:
            border == BorderSide.none ? null : Border.fromBorderSide(border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.format_list_numbered, size: 14, color: iconColor),
          const SizedBox(width: 3),
          Text(
            '$count集',
            style: theme.textTheme.labelMedium?.copyWith(
                  color: fg,
                  fontWeight: FontWeight.w700,
                ) ??
                TextStyle(
                  color: fg,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }
}
