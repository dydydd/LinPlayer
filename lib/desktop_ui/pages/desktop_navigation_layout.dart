import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../theme/desktop_theme_extension.dart';

class DesktopNavigationLayout extends StatelessWidget {
  static const double _kTopBarHeight = 70.0;
  static const double _kTopBarGap = 28.0;
  static const Duration _kSidebarAnimationDuration = Duration(
    milliseconds: 260,
  );
  static const Curve _kSidebarAnimationCurve = Curves.easeOutCubic;

  const DesktopNavigationLayout({
    super.key,
    required this.sidebar,
    required this.topBar,
    required this.content,
    required this.topBarVisibilityListenable,
    this.backgroundStartColor,
    this.backgroundEndColor,
    this.sidebarVisible = false,
    this.onDismissSidebar,
    this.sidebarWidth = 264,
  });

  final Widget sidebar;
  final Widget topBar;
  final Widget content;
  final ValueListenable<double> topBarVisibilityListenable;
  final Color? backgroundStartColor;
  final Color? backgroundEndColor;
  final bool sidebarVisible;
  final VoidCallback? onDismissSidebar;
  final double sidebarWidth;

  @override
  Widget build(BuildContext context) {
    final desktopTheme = DesktopThemeExtension.of(context);
    final backgroundStart = backgroundStartColor ?? desktopTheme.background;
    final backgroundEnd =
        backgroundEndColor ?? desktopTheme.backgroundGradientEnd;
    final canAnimateSidebar = sidebarWidth > 0;
    final showSidebar = sidebarVisible && canAnimateSidebar;
    const horizontalPadding = 0.0;

    return Stack(
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                backgroundStart,
                backgroundEnd,
              ],
            ),
          ),
          child: const SizedBox.expand(),
        ),
        SafeArea(
          child: ValueListenableBuilder<double>(
            valueListenable: topBarVisibilityListenable,
            builder: (context, value, _) {
              final topBarTarget = value.clamp(0.0, 1.0).toDouble();
              final topBarArea = _kTopBarHeight + _kTopBarGap;
              final contentOffsetY = topBarArea * topBarTarget;
              final topBarOffsetY = -topBarArea * (1.0 - topBarTarget);

              return Stack(
                clipBehavior: Clip.hardEdge,
                children: [
                  Positioned.fill(
                    child: Transform.translate(
                      offset: Offset(0, contentOffsetY),
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                          horizontalPadding,
                          0,
                          horizontalPadding,
                          24,
                        ),
                        child: content,
                      ),
                    ),
                  ),
                  Positioned(
                    top: 0,
                    left: horizontalPadding,
                    right: horizontalPadding,
                    child: IgnorePointer(
                      ignoring: topBarTarget < 0.05,
                      child: Opacity(
                        opacity: topBarTarget,
                        child: Transform.translate(
                          offset: Offset(0, topBarOffsetY),
                          child: RepaintBoundary(child: topBar),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        if (canAnimateSidebar)
          Positioned.fill(
            child: IgnorePointer(
              ignoring: !showSidebar,
              child: AnimatedOpacity(
                opacity: showSidebar ? 1 : 0,
                duration: _kSidebarAnimationDuration,
                curve: _kSidebarAnimationCurve,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onDismissSidebar,
                  child: ColoredBox(
                    color: Colors.black.withValues(alpha: 0.32),
                  ),
                ),
              ),
            ),
          ),
        if (canAnimateSidebar)
          Positioned(
            top: 82,
            bottom: 24,
            left: 16,
            child: IgnorePointer(
              ignoring: !showSidebar,
              child: AnimatedSlide(
                offset: showSidebar ? Offset.zero : const Offset(-0.08, 0),
                duration: _kSidebarAnimationDuration,
                curve: _kSidebarAnimationCurve,
                child: AnimatedScale(
                  scale: showSidebar ? 1 : 0.985,
                  alignment: Alignment.topLeft,
                  duration: _kSidebarAnimationDuration,
                  curve: _kSidebarAnimationCurve,
                  child: AnimatedOpacity(
                    opacity: showSidebar ? 1 : 0,
                    duration: _kSidebarAnimationDuration,
                    curve: _kSidebarAnimationCurve,
                    child: SizedBox(
                      width: sidebarWidth,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: desktopTheme.shadowColor.withValues(
                                alpha: 0.34,
                              ),
                              blurRadius: 34,
                              spreadRadius: -10,
                              offset: const Offset(0, 18),
                            ),
                            BoxShadow(
                              color: desktopTheme.accent.withValues(
                                alpha: 0.08,
                              ),
                              blurRadius: 40,
                              spreadRadius: -18,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: RepaintBoundary(child: sidebar),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
