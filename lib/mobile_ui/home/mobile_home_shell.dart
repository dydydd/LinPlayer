import 'package:flutter/material.dart';

class MobileHomeShell extends StatelessWidget {
  const MobileHomeShell({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
    required this.pages,
    required this.visibility,
    this.appBar,
    this.extendBody = false,
    this.transitionDuration = const Duration(milliseconds: 300),
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final List<Widget> pages;
  final double visibility;
  final PreferredSizeWidget? appBar;
  final bool extendBody;
  final Duration transitionDuration;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: extendBody,
      appBar: appBar,
      body: MobileHomePageTransition(
        index: selectedIndex,
        pages: pages,
        duration: transitionDuration,
      ),
      bottomNavigationBar: MobileHomeBottomNav(
        selectedIndex: selectedIndex,
        onSelected: onSelected,
        visibility: visibility,
        animationDuration: transitionDuration,
      ),
    );
  }
}

class MobileHomeTopBarPage extends StatelessWidget {
  const MobileHomeTopBarPage({
    super.key,
    required this.child,
    required this.topBar,
    required this.topBarHeight,
    required this.topBarVisibility,
  });

  final Widget child;
  final Widget topBar;
  final double topBarHeight;
  final double topBarVisibility;

  @override
  Widget build(BuildContext context) {
    final clampedVisibility = topBarVisibility.clamp(0.0, 1.0);

    return Stack(
      fit: StackFit.expand,
      children: [
        AnimatedPadding(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOutCubic,
          padding: EdgeInsets.only(top: topBarHeight * clampedVisibility),
          child: child,
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: topBar,
        ),
      ],
    );
  }
}

class MobileHomeBottomNav extends StatelessWidget {
  const MobileHomeBottomNav({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
    required this.visibility,
    required this.animationDuration,
  });

  static const _destinations = <_MobileNavDestination>[
    _MobileNavDestination(
      pageIndex: 0,
      icon: Icons.home_rounded,
      label: '首页',
    ),
    _MobileNavDestination(
      pageIndex: 1,
      icon: Icons.hub_rounded,
      label: '聚合',
    ),
    _MobileNavDestination(
      pageIndex: 3,
      icon: Icons.settings_rounded,
      label: '设置',
    ),
  ];

  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final double visibility;
  final Duration animationDuration;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final progress = visibility.clamp(0.0, 1.0);
    final isDark = scheme.brightness == Brightness.dark;
    final shellColor = isDark
        ? scheme.surfaceContainerHigh.withValues(alpha: 0.94)
        : scheme.surfaceContainerHighest.withValues(alpha: 0.98);
    final shellBorder =
        scheme.outlineVariant.withValues(alpha: isDark ? 0.22 : 0.36);
    final indicatorColor =
        scheme.primary.withValues(alpha: isDark ? 0.94 : 0.98);
    final indicatorShadow =
        scheme.primary.withValues(alpha: isDark ? 0.34 : 0.22);
    final activeSlot = _destinations.indexWhere(
      (destination) => destination.pageIndex == selectedIndex,
    );
    final hasVisibleSelection = activeSlot >= 0;

    return IgnorePointer(
      ignoring: progress <= 0.02,
      child: ClipRect(
        child: Align(
          alignment: Alignment.bottomCenter,
          heightFactor: progress,
          child: Transform.translate(
            offset: Offset(0, 24 * (1 - progress)),
            child: Opacity(
              opacity: progress,
              child: SafeArea(
                top: false,
                left: false,
                right: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final navWidth = constraints.maxWidth > 336
                          ? 336.0
                          : constraints.maxWidth;

                      return Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: navWidth,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: shellColor,
                                borderRadius: BorderRadius.circular(24),
                                border: Border.all(color: shellBorder),
                                boxShadow: [
                                  BoxShadow(
                                    color:
                                        scheme.shadow.withValues(alpha: 0.12),
                                    blurRadius: 22,
                                    offset: const Offset(0, 10),
                                    spreadRadius: -16,
                                  ),
                                ],
                              ),
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  5,
                                  4,
                                  5,
                                  4,
                                ),
                                child: SizedBox(
                                  height: 46,
                                  child: LayoutBuilder(
                                    builder: (context, innerConstraints) {
                                      final slotWidth =
                                          innerConstraints.maxWidth /
                                              _destinations.length;

                                      return Stack(
                                        children: [
                                          AnimatedPositioned(
                                            duration: animationDuration,
                                            curve: Curves.easeOutCubic,
                                            left: hasVisibleSelection
                                                ? activeSlot * slotWidth
                                                : slotWidth,
                                            top: 0,
                                            bottom: 0,
                                            width: slotWidth,
                                            child: AnimatedOpacity(
                                              duration: animationDuration,
                                              curve: Curves.easeOut,
                                              opacity:
                                                  hasVisibleSelection ? 1 : 0,
                                              child: Padding(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 2,
                                                  vertical: 0.5,
                                                ),
                                                child: DecoratedBox(
                                                  decoration: BoxDecoration(
                                                    color: indicatorColor,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                      19,
                                                    ),
                                                    boxShadow: [
                                                      BoxShadow(
                                                        color: indicatorShadow,
                                                        blurRadius: 16,
                                                        offset: const Offset(
                                                          0,
                                                          7,
                                                        ),
                                                        spreadRadius: -11,
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                          Row(
                                            children: [
                                              for (final destination
                                                  in _destinations)
                                                Expanded(
                                                  child: _SegmentedNavButton(
                                                    destination: destination,
                                                    selected:
                                                        destination.pageIndex ==
                                                            selectedIndex,
                                                    labelStyle: theme
                                                        .textTheme.labelSmall
                                                        ?.copyWith(
                                                      fontSize: 9.5,
                                                    ),
                                                    selectedColor:
                                                        scheme.onPrimary,
                                                    unselectedColor:
                                                        scheme.onSurfaceVariant,
                                                    animationDuration:
                                                        animationDuration,
                                                    onTap: () => onSelected(
                                                      destination.pageIndex,
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ],
                                      );
                                    },
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class MobileHomePageTransition extends StatefulWidget {
  const MobileHomePageTransition({
    super.key,
    required this.index,
    required this.pages,
    required this.duration,
  });

  final int index;
  final List<Widget> pages;
  final Duration duration;

  @override
  State<MobileHomePageTransition> createState() =>
      _MobileHomePageTransitionState();
}

class _MobileHomePageTransitionState extends State<MobileHomePageTransition>
    with SingleTickerProviderStateMixin {
  late int _currentIndex;
  late int _previousIndex;
  late final AnimationController _controller;

  bool get _isAnimating =>
      _controller.isAnimating && _currentIndex != _previousIndex;

  int _clampIndex(int index) {
    final maxIndex = widget.pages.length - 1;
    if (maxIndex <= 0) return 0;
    return index.clamp(0, maxIndex).toInt();
  }

  @override
  void initState() {
    super.initState();
    _currentIndex = _clampIndex(widget.index);
    _previousIndex = _currentIndex;
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    )..addStatusListener((status) {
        if (status != AnimationStatus.completed || !mounted) return;
        setState(() => _previousIndex = _currentIndex);
      });
  }

  @override
  void didUpdateWidget(covariant MobileHomePageTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.duration != oldWidget.duration) {
      _controller.duration = widget.duration;
    }
    _currentIndex = _clampIndex(_currentIndex);
    _previousIndex = _clampIndex(_previousIndex);
    final nextIndex = _clampIndex(widget.index);
    if (nextIndex == _currentIndex) return;
    _previousIndex = _currentIndex;
    _currentIndex = nextIndex;
    _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final backgroundColor = Theme.of(context).scaffoldBackgroundColor;
    return ColoredBox(
      color: backgroundColor,
      child: ClipRect(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final currentIndex = _clampIndex(_currentIndex);
            final previousIndex = _clampIndex(_previousIndex);
            final isAnimating = _isAnimating;
            final progress = _controller.value.clamp(0.0, 1.0);

            return IgnorePointer(
              ignoring: isAnimating,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  for (int index = 0; index < widget.pages.length; index++)
                    _buildPageLayer(
                      index: index,
                      currentIndex: currentIndex,
                      previousIndex: previousIndex,
                      isAnimating: isAnimating,
                      progress: progress,
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildPageLayer({
    required int index,
    required int currentIndex,
    required int previousIndex,
    required bool isAnimating,
    required double progress,
  }) {
    final page = KeyedSubtree(
      key: ValueKey<int>(index),
      child: widget.pages[index],
    );
    final isCurrent = index == currentIndex;
    final isPrevious = index == previousIndex;
    final keepMounted = isCurrent || isPrevious || !isAnimating;
    final showPage = isCurrent || (isAnimating && isPrevious);

    var opacity = 1.0;
    var scale = 1.0;
    if (isAnimating && isCurrent) {
      opacity = Tween<double>(
        begin: 0.18,
        end: 1.0,
      ).transform(Curves.easeOutCubic.transform(progress));
      scale = Tween<double>(
        begin: 0.996,
        end: 1.0,
      ).transform(Curves.easeOutCubic.transform(progress));
    } else if (isAnimating && isPrevious) {
      opacity = Tween<double>(
        begin: 1.0,
        end: 0.0,
      ).transform(Curves.easeInCubic.transform(progress));
    }

    return Offstage(
      offstage: !showPage,
      child: TickerMode(
        enabled: keepMounted && showPage,
        child: _MobilePageLayer(
          opacity: opacity,
          scale: scale,
          child: page,
        ),
      ),
    );
  }
}

class _MobilePageLayer extends StatelessWidget {
  const _MobilePageLayer({
    required this.child,
    this.opacity = 1,
    this.scale = 1,
  });

  final Widget child;
  final double opacity;
  final double scale;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: opacity.clamp(0.0, 1.0),
      child: Transform.scale(
        scale: scale,
        alignment: Alignment.center,
        child: RepaintBoundary(
          child: child,
        ),
      ),
    );
  }
}

class _MobileNavDestination {
  const _MobileNavDestination({
    required this.pageIndex,
    required this.icon,
    required this.label,
  });

  final int pageIndex;
  final IconData icon;
  final String label;
}

class _SegmentedNavButton extends StatelessWidget {
  const _SegmentedNavButton({
    required this.destination,
    required this.selected,
    required this.labelStyle,
    required this.selectedColor,
    required this.unselectedColor,
    required this.animationDuration,
    required this.onTap,
  });

  final _MobileNavDestination destination;
  final bool selected;
  final TextStyle? labelStyle;
  final Color selectedColor;
  final Color unselectedColor;
  final Duration animationDuration;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final foregroundColor =
        selected ? selectedColor : unselectedColor.withValues(alpha: 0.92);

    return Semantics(
      button: true,
      selected: selected,
      label: destination.label,
      child: Tooltip(
        message: destination.label,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(24),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AnimatedSlide(
                    duration: animationDuration,
                    curve: Curves.easeOutCubic,
                    offset: selected ? Offset.zero : const Offset(0, 0.08),
                    child: AnimatedScale(
                      duration: animationDuration,
                      curve: Curves.easeOutCubic,
                      scale: selected ? 0.98 : 0.88,
                      child: Icon(
                        destination.icon,
                        size: 16,
                        color: foregroundColor,
                      ),
                    ),
                  ),
                  const SizedBox(height: 1),
                  AnimatedDefaultTextStyle(
                    duration: animationDuration,
                    curve: Curves.easeOutCubic,
                    style: (labelStyle ?? const TextStyle()).copyWith(
                      color: foregroundColor,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                      letterSpacing: selected ? -0.05 : 0.05,
                      height: 1.0,
                    ),
                    child: AnimatedOpacity(
                      duration: animationDuration,
                      curve: Curves.easeOut,
                      opacity: selected ? 1 : 0.84,
                      child: Text(destination.label),
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
