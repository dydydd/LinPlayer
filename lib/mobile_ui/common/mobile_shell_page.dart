import 'package:flutter/material.dart';
import 'package:lin_player_ui/lin_player_ui.dart';

class MobileShellPageFrame extends StatelessWidget {
  const MobileShellPageFrame({
    super.key,
    required this.header,
    required this.child,
    this.decoration,
    this.bodyBottomInset = 92,
  });

  final Widget header;
  final Widget child;
  final Decoration? decoration;
  final double bodyBottomInset;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: decoration ??
          BoxDecoration(color: Theme.of(context).colorScheme.surface),
      child: Column(
        children: [
          SafeArea(bottom: false, child: header),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: bodyBottomInset),
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}

class MobileShellPageHeader extends StatelessWidget {
  const MobileShellPageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.bottom,
    this.trailing,
    this.enableBlur = true,
  });

  final String title;
  final String? subtitle;
  final Widget? bottom;
  final Widget? trailing;
  final bool enableBlur;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = scheme.brightness == Brightness.dark;
    final surfaceColor =
        scheme.surfaceContainerHigh.withValues(alpha: isDark ? 0.74 : 0.90);
    final borderColor =
        scheme.outlineVariant.withValues(alpha: isDark ? 0.26 : 0.42);
    final titleStyle = theme.textTheme.titleLarge?.copyWith(
      fontWeight: FontWeight.w800,
      letterSpacing: -0.3,
    );
    final subtitleStyle = theme.textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
      fontWeight: FontWeight.w600,
      height: 1.2,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: GlassCard(
        enableBlur: enableBlur,
        margin: EdgeInsets.zero,
        elevation: 0,
        color: surfaceColor,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(26),
          side: BorderSide(color: borderColor),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(title, style: titleStyle),
                        if ((subtitle ?? '').trim().isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(subtitle!, style: subtitleStyle),
                        ],
                      ],
                    ),
                  ),
                  if (trailing != null) ...[
                    const SizedBox(width: 12),
                    trailing!,
                  ],
                ],
              ),
              if (bottom != null) ...[
                const SizedBox(height: 14),
                bottom!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}
