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
              Flexible(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
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
