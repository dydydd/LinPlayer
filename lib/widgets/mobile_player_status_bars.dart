import 'dart:math' as math;
import 'dart:ui';

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
    this.onBack,
    this.backTooltip = '返回',
  });

  final String title;
  final List<Widget> actions;
  final VoidCallback? onBack;
  final String backTooltip;

  @override
  Widget build(BuildContext context) {
    final hasBackButton = onBack != null;
    final actionMaxWidth = math.min(
      MediaQuery.sizeOf(context).width * (hasBackButton ? 0.5 : 0.58),
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
            if (hasBackButton) ...[
              _MobilePlayerTopIconButton(
                icon: Icons.arrow_back_rounded,
                tooltip: backTooltip,
                onTap: onBack,
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(top: hasBackButton ? 4 : 6),
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

class _MobilePlayerTopIconButton extends StatelessWidget {
  const _MobilePlayerTopIconButton({
    required this.icon,
    required this.tooltip,
    this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;

    return Semantics(
      button: true,
      enabled: enabled,
      label: tooltip,
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            customBorder: const CircleBorder(),
            child: Ink(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.black.withValues(alpha: enabled ? 0.24 : 0.12),
                border: Border.all(
                  color: Colors.white.withValues(alpha: enabled ? 0.18 : 0.08),
                ),
              ),
              child: Center(
                child: Icon(
                  icon,
                  size: 20,
                  color: enabled ? Colors.white : Colors.white38,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum MobilePlayerSidePanelVariant {
  standard,
  moreOptions,
}

class MobilePlayerOverlaySheet extends StatelessWidget {
  const MobilePlayerOverlaySheet({
    super.key,
    required this.visible,
    required this.onDismiss,
    required this.child,
  });

  final bool visible;
  final VoidCallback onDismiss;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final panelWidth = size.width / 3;

    return Positioned.fill(
      child: Stack(
        children: [
          IgnorePointer(
            ignoring: !visible,
            child: AnimatedOpacity(
              opacity: visible ? 1 : 0,
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onDismiss,
                child: ClipRect(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                    child: ColoredBox(
                      color: Colors.black.withValues(alpha: 0.28),
                      child: const SizedBox.expand(),
                    ),
                  ),
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
                minimum: const EdgeInsets.fromLTRB(0, 8, 8, 8),
                child: Padding(
                  padding: const EdgeInsets.only(left: 10),
                  child: _MobilePlayerPanelSurface(child: child),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MobilePlayerPanelSurface extends StatelessWidget {
  const _MobilePlayerPanelSurface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    const radius = 24.0;

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            color: Colors.white.withValues(alpha: 0.08),
          ),
          child: child,
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
    this.variant = MobilePlayerSidePanelVariant.standard,
  });

  final String title;
  final bool visible;
  final VoidCallback onDismiss;
  final Widget child;
  final Widget? headerTrailing;
  final MobilePlayerSidePanelVariant variant;

  @override
  Widget build(BuildContext context) {
    final contentPadding = switch (variant) {
      MobilePlayerSidePanelVariant.standard =>
        const EdgeInsets.fromLTRB(16, 12, 12, 12),
      MobilePlayerSidePanelVariant.moreOptions =>
        const EdgeInsets.fromLTRB(14, 12, 12, 12),
    };
    final headerSpacing =
        variant == MobilePlayerSidePanelVariant.moreOptions ? 8.0 : 10.0;

    return MobilePlayerOverlaySheet(
      visible: visible,
      onDismiss: onDismiss,
      child: Padding(
        padding: contentPadding,
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
            SizedBox(height: headerSpacing),
            Expanded(child: child),
          ],
        ),
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
    final enabled = onTap != null;
    final surfaceColor = Colors.white.withValues(
      alpha: selected
          ? 0.16
          : enabled
              ? 0.08
              : 0.05,
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Material(
          color: surfaceColor,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(20),
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

class MobilePlayerPillButton extends StatelessWidget {
  const MobilePlayerPillButton({
    super.key,
    required this.label,
    this.icon,
    this.onTap,
    this.onLongPress,
    this.compact = true,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(999),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            color: Colors.black.withValues(alpha: enabled ? 0.22 : 0.12),
            border: Border.all(
              color: Colors.white.withValues(alpha: enabled ? 0.16 : 0.08),
            ),
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 8 : 10,
              vertical: compact ? 5 : 6,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(
                    icon,
                    size: compact ? 14 : 16,
                    color: enabled ? Colors.white : Colors.white38,
                  ),
                  const SizedBox(width: 4),
                ],
                Text(
                  label,
                  style: _overlayLabelStyle(
                    fontSize: compact ? 10.5 : 11.5,
                    fontWeight: FontWeight.w700,
                    color: enabled ? Colors.white : Colors.white38,
                    tabular: true,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class MobilePlayerEdgeSpeedBar extends StatelessWidget {
  const MobilePlayerEdgeSpeedBar({
    super.key,
    required this.visible,
    required this.currentRate,
    required this.enabled,
    required this.onIncrease,
    required this.onDecrease,
    required this.onIncreaseHoldStart,
    required this.onIncreaseHoldEnd,
    required this.onDecreaseHoldStart,
    required this.onDecreaseHoldEnd,
  });

  final bool visible;
  final double currentRate;
  final bool enabled;
  final VoidCallback onIncrease;
  final VoidCallback onDecrease;
  final VoidCallback onIncreaseHoldStart;
  final VoidCallback onIncreaseHoldEnd;
  final VoidCallback onDecreaseHoldStart;
  final VoidCallback onDecreaseHoldEnd;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final segmentWidth =
        math.min(50.0, math.max(42.0, size.width * 0.12)).toDouble();
    final bodyHeight = math
        .min(
          math.max(112.0, size.height * 0.18),
          148.0,
        )
        .toDouble();

    return Align(
      alignment: Alignment.centerRight,
      child: IgnorePointer(
        ignoring: !visible,
        child: SafeArea(
          left: false,
          minimum: const EdgeInsets.fromLTRB(0, 72, 8, 96),
          child: AnimatedSlide(
            offset: visible ? Offset.zero : const Offset(1.1, 0),
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            child: AnimatedOpacity(
              opacity: visible ? 1 : 0,
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _MobileSpeedSegmentButton(
                    width: segmentWidth,
                    label: '+0.1x',
                    enabled: enabled,
                    onTap: onIncrease,
                    onHoldStart: onIncreaseHoldStart,
                    onHoldEnd: onIncreaseHoldEnd,
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          color: Colors.white.withValues(alpha: 0.08),
                        ),
                        child: SizedBox(
                          width: segmentWidth,
                          height: bodyHeight,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 14,
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  _formatRate(currentRate),
                                  textAlign: TextAlign.center,
                                  style: _overlayLabelStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                    tabular: true,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  '倍速',
                                  textAlign: TextAlign.center,
                                  style: _overlayLabelStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white70,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  _MobileSpeedSegmentButton(
                    width: segmentWidth,
                    label: '-0.1x',
                    enabled: enabled,
                    onTap: onDecrease,
                    onHoldStart: onDecreaseHoldStart,
                    onHoldEnd: onDecreaseHoldEnd,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static String _formatRate(double rate) {
    final value = rate.clamp(0.1, 10.0).toDouble();
    final digits = value == value.roundToDouble() ? 0 : 1;
    return '${value.toStringAsFixed(digits)}x';
  }
}

class MobilePlayerSpeedOverlay extends StatelessWidget {
  const MobilePlayerSpeedOverlay({
    super.key,
    required this.visible,
    required this.currentRate,
    required this.enabled,
    required this.onDismiss,
    required this.onIncrease,
    required this.onDecrease,
    required this.onIncreaseHoldStart,
    required this.onIncreaseHoldEnd,
    required this.onDecreaseHoldStart,
    required this.onDecreaseHoldEnd,
  });

  final bool visible;
  final double currentRate;
  final bool enabled;
  final VoidCallback onDismiss;
  final VoidCallback onIncrease;
  final VoidCallback onDecrease;
  final VoidCallback onIncreaseHoldStart;
  final VoidCallback onIncreaseHoldEnd;
  final VoidCallback onDecreaseHoldStart;
  final VoidCallback onDecreaseHoldEnd;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final panelWidth =
        math.min(60.0, math.max(48.0, size.width * 0.14)).toDouble();
    final segmentWidth = panelWidth;
    final bodyHeight = math
        .min(
          math.max(136.0, size.height * 0.22),
          188.0,
        )
        .toDouble();

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
                child: ClipRect(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                    child: ColoredBox(
                      color: Colors.black.withValues(alpha: 0.32),
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: IgnorePointer(
              ignoring: !visible,
              child: SafeArea(
                left: false,
                minimum: const EdgeInsets.fromLTRB(0, 12, 10, 12),
                child: AnimatedSlide(
                  offset: visible ? Offset.zero : const Offset(1.15, 0),
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  child: AnimatedOpacity(
                    opacity: visible ? 1 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: SizedBox(
                      width: panelWidth,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _MobileSpeedSegmentButton(
                            width: segmentWidth,
                            label: '+0.1x',
                            enabled: enabled,
                            onTap: onIncrease,
                            onHoldStart: onIncreaseHoldStart,
                            onHoldEnd: onIncreaseHoldEnd,
                          ),
                          const SizedBox(height: 8),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(22),
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(22),
                                  color: Colors.white.withValues(alpha: 0.08),
                                ),
                                child: SizedBox(
                                  width: segmentWidth,
                                  height: bodyHeight,
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 18,
                                    ),
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.speed_rounded,
                                          size: 18,
                                          color: Colors.white
                                              .withValues(alpha: 0.76),
                                        ),
                                        const SizedBox(height: 14),
                                        Text(
                                          _formatRate(currentRate),
                                          textAlign: TextAlign.center,
                                          style: _overlayLabelStyle(
                                            fontSize: 24,
                                            fontWeight: FontWeight.w800,
                                            color: Colors.white,
                                            tabular: true,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          '播放速度',
                                          textAlign: TextAlign.center,
                                          style: _overlayLabelStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                            color: Colors.white70,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          '单次 0.1x',
                                          textAlign: TextAlign.center,
                                          style: _overlayLabelStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.white.withValues(
                                              alpha: 0.62,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          _MobileSpeedSegmentButton(
                            width: segmentWidth,
                            label: '-0.1x',
                            enabled: enabled,
                            onTap: onDecrease,
                            onHoldStart: onDecreaseHoldStart,
                            onHoldEnd: onDecreaseHoldEnd,
                          ),
                        ],
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

  static String _formatRate(double rate) {
    final value = rate.clamp(0.1, 10.0).toDouble();
    final digits = value == value.roundToDouble() ? 0 : 1;
    return '${value.toStringAsFixed(digits)}x';
  }
}

class _MobileSpeedSegmentButton extends StatelessWidget {
  const _MobileSpeedSegmentButton({
    required this.width,
    required this.label,
    required this.enabled,
    required this.onTap,
    required this.onHoldStart,
    required this.onHoldEnd,
  });

  final double width;
  final String label;
  final bool enabled;
  final VoidCallback onTap;
  final VoidCallback onHoldStart;
  final VoidCallback onHoldEnd;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      onLongPressStart: enabled ? (_) => onHoldStart() : null,
      onLongPressEnd: enabled ? (_) => onHoldEnd() : null,
      onLongPressCancel: enabled ? onHoldEnd : null,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: Colors.white.withValues(alpha: enabled ? 0.08 : 0.04),
            ),
            child: SizedBox(
              width: width,
              height: 36,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    label,
                    style: _overlayLabelStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: enabled ? Colors.white : Colors.white38,
                      tabular: true,
                    ),
                  ),
                ],
              ),
            ),
          ),
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
