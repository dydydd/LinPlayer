import 'dart:math' as math;

import 'package:flutter/material.dart';

class MobilePlayerActionButton extends StatelessWidget {
  const MobilePlayerActionButton({
    super.key,
    required this.icon,
    required this.label,
    this.onTap,
    this.compact = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final iconSize = compact ? 15.0 : 16.0;
    final labelStyle = _overlayLabelStyle(
      fontSize: compact ? 11 : 12,
      fontWeight: FontWeight.w600,
      color: enabled ? Colors.white : Colors.white54,
    );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 6 : 8,
            vertical: compact ? 4 : 6,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: iconSize,
                color: enabled ? Colors.white : Colors.white54,
              ),
              const SizedBox(width: 4),
              Text(label, style: labelStyle),
            ],
          ),
        ),
      ),
    );
  }
}

class MobilePlayerTransportButton extends StatelessWidget {
  const MobilePlayerTransportButton({
    super.key,
    required this.icon,
    this.onTap,
    this.emphasized = false,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final size = emphasized ? 52.0 : 44.0;
    final iconSize = emphasized ? 34.0 : 26.0;
    final enabled = onTap != null;

    return Material(
      color: Colors.transparent,
      child: InkResponse(
        onTap: onTap,
        radius: emphasized ? 28 : 24,
        child: SizedBox(
          width: size,
          height: size,
          child: Center(
            child: Icon(
              icon,
              size: iconSize,
              color: enabled ? Colors.white : Colors.white54,
            ),
          ),
        ),
      ),
    );
  }
}

class MobilePlayerTopStatusBar extends StatelessWidget {
  const MobilePlayerTopStatusBar({
    super.key,
    required this.title,
    this.actions = const <Widget>[],
  });

  final String title;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final actionMaxWidth = math.min(
      MediaQuery.sizeOf(context).width * 0.58,
      360.0,
    );

    return DefaultTextStyle.merge(
      style: _overlayLabelStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: Colors.white,
      ),
      child: IconTheme.merge(
        data: const IconThemeData(color: Colors.white),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _overlayLabelStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            if (actions.isNotEmpty) ...[
              const SizedBox(width: 12),
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: actionMaxWidth),
                child: Align(
                  alignment: Alignment.topRight,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final entry in actions) ...[
                          entry,
                          if (entry != actions.last) const SizedBox(width: 2),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class MobilePlayerSidePanel extends StatelessWidget {
  const MobilePlayerSidePanel({
    super.key,
    required this.title,
    required this.visible,
    required this.onDismiss,
    required this.child,
    this.headerTrailing,
  });

  final String title;
  final bool visible;
  final VoidCallback onDismiss;
  final Widget child;
  final Widget? headerTrailing;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final panelWidth = math.min(
      336.0,
      size.width * (size.width > size.height ? 0.38 : 0.50),
    );

    return Positioned.fill(
      child: Stack(
        children: [
          IgnorePointer(
            ignoring: !visible,
            child: AnimatedOpacity(
              opacity: visible ? 1 : 0,
              duration: const Duration(milliseconds: 180),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onDismiss,
                child: ColoredBox(
                  color: Colors.black.withValues(alpha: 0.22),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),
          AnimatedPositioned(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            top: 0,
            bottom: 0,
            right: visible ? 0 : -panelWidth - 12,
            width: panelWidth,
            child: IgnorePointer(
              ignoring: !visible,
              child: SafeArea(
                left: false,
                minimum: const EdgeInsets.fromLTRB(0, 8, 0, 8),
                child: Padding(
                  padding: const EdgeInsets.only(left: 10),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(24),
                      color: Colors.black.withValues(alpha: 0.10),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.16),
                      ),
                      gradient: LinearGradient(
                        begin: Alignment.topRight,
                        end: Alignment.bottomLeft,
                        colors: [
                          Colors.white.withValues(alpha: 0.08),
                          Colors.white.withValues(alpha: 0.02),
                        ],
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: _overlayLabelStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                                if (headerTrailing != null) ...[
                                  const SizedBox(width: 8),
                                  headerTrailing!,
                                ],
                                const SizedBox(width: 4),
                                IconButton(
                                  tooltip: 'Close',
                                  onPressed: onDismiss,
                                  icon: const Icon(Icons.close_rounded),
                                  color: Colors.white,
                                  splashRadius: 20,
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Expanded(child: child),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class MobilePlayerOptionTile extends StatelessWidget {
  const MobilePlayerOptionTile({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.selected = false,
    this.onTap,
    this.contentPadding,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final bool selected;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? contentPadding;

  @override
  Widget build(BuildContext context) {
    final borderColor = selected
        ? Colors.white.withValues(alpha: 0.32)
        : Colors.white.withValues(alpha: 0.10);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: Colors.black.withValues(alpha: selected ? 0.16 : 0.08),
            border: Border.all(color: borderColor),
          ),
          child: Padding(
            padding: contentPadding ??
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                if (leading != null) ...[
                  leading!,
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _overlayLabelStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      if ((subtitle ?? '').trim().isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          subtitle!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: _overlayLabelStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: Colors.white70,
                          ),
                        ),
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
          ),
        ),
      ),
    );
  }
}

class MobilePlayerInfoTag extends StatelessWidget {
  const MobilePlayerInfoTag({
    super.key,
    required this.label,
  });

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(
          label,
          style: _overlayLabelStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: Colors.white70,
          ),
        ),
      ),
    );
  }
}

class MobilePlayerBottomStatusBar extends StatelessWidget {
  const MobilePlayerBottomStatusBar({
    super.key,
    required this.position,
    required this.buffered,
    required this.duration,
    required this.positionLabel,
    required this.durationLabel,
    required this.leftContent,
    required this.centerContent,
    required this.rightContent,
    this.onScrubStart,
    this.onSeekPreview,
    this.onSeekCommit,
  });

  final Duration position;
  final Duration buffered;
  final Duration duration;
  final String positionLabel;
  final String durationLabel;
  final Widget leftContent;
  final Widget centerContent;
  final Widget rightContent;
  final VoidCallback? onScrubStart;
  final ValueChanged<Duration>? onSeekPreview;
  final ValueChanged<Duration>? onSeekCommit;

  bool get _sliderEnabled =>
      duration > Duration.zero && onSeekPreview != null && onSeekCommit != null;

  @override
  Widget build(BuildContext context) {
    final sliderMaxMs = math.max(duration.inMilliseconds, 1);
    final sliderValueMs = position.inMilliseconds.clamp(0, sliderMaxMs);
    final bufferedMs =
        math.max(buffered.inMilliseconds, sliderValueMs).clamp(0, sliderMaxMs);

    return DefaultTextStyle.merge(
      style: _overlayLabelStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: Colors.white,
      ),
      child: IconTheme.merge(
        data: const IconThemeData(color: Colors.white),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text(
                  positionLabel,
                  style: _overlayLabelStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.white70,
                    tabular: true,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 3,
                      activeTrackColor: Colors.white,
                      secondaryActiveTrackColor:
                          Colors.white.withValues(alpha: 0.55),
                      inactiveTrackColor: Colors.white.withValues(alpha: 0.18),
                      thumbColor: Colors.white,
                      overlayColor: Colors.white.withValues(alpha: 0.14),
                      thumbShape:
                          const RoundSliderThumbShape(enabledThumbRadius: 4.5),
                      overlayShape:
                          const RoundSliderOverlayShape(overlayRadius: 12),
                    ),
                    child: Slider(
                      min: 0,
                      max: sliderMaxMs.toDouble(),
                      value: sliderValueMs.toDouble(),
                      secondaryTrackValue: bufferedMs.toDouble(),
                      onChangeStart:
                          _sliderEnabled ? (_) => onScrubStart?.call() : null,
                      onChanged: _sliderEnabled
                          ? (value) => onSeekPreview!(
                                Duration(milliseconds: value.round()),
                              )
                          : null,
                      onChangeEnd: _sliderEnabled
                          ? (value) => onSeekCommit!(
                                Duration(milliseconds: value.round()),
                              )
                          : null,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  durationLabel,
                  style: _overlayLabelStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.white70,
                    tabular: true,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: leftContent,
                  ),
                ),
                Expanded(
                  flex: 4,
                  child: Center(child: centerContent),
                ),
                Expanded(
                  flex: 3,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: rightContent,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

TextStyle _overlayLabelStyle({
  required double fontSize,
  required FontWeight fontWeight,
  required Color color,
  bool tabular = false,
}) {
  return TextStyle(
    color: color,
    fontSize: fontSize,
    fontWeight: fontWeight,
    fontFeatures: tabular ? const [FontFeature.tabularFigures()] : null,
    shadows: const [
      Shadow(
        blurRadius: 10,
        offset: Offset(0, 1),
        color: Color(0xCC000000),
      ),
    ],
  );
}
