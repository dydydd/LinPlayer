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
                  padding: const EdgeInsets.fromLTRB(14, 6, 14, 10),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final navWidth = constraints.maxWidth > 360
                          ? 360.0
                          : constraints.maxWidth;

                      return Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: navWidth,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: shellColor,
                                borderRadius: BorderRadius.circular(28),
                                border: Border.all(color: shellBorder),
                                boxShadow: [
                                  BoxShadow(
                                    color:
                                        scheme.shadow.withValues(alpha: 0.12),
                                    blurRadius: 26,
                                    offset: const Offset(0, 12),
                                    spreadRadius: -14,
                                  ),
                                ],
                              ),
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  6,
                                  5,
                                  6,
                                  5,
                                ),
                                child: SizedBox(
                                  height: 52,
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
                                                  vertical: 1,
                                                ),
                                                child: DecoratedBox(
                                                  decoration: BoxDecoration(
                                                    color: indicatorColor,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                      22,
                                                    ),
                                                    boxShadow: [
                                                      BoxShadow(
                                                        color: indicatorShadow,
                                                        blurRadius: 18,
                                                        offset: const Offset(
                                                          0,
                                                          8,
                                                        ),
                                                        spreadRadius: -10,
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
                                                      fontSize: 10.5,
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
  static const _iosIncomingCurve = Cubic(0.32, 0.72, 0.0, 1.0);
  static const _iosOutgoingCurve = Cubic(0.22, 0.61, 0.36, 1.0);

  late int _currentIndex;
  late int _previousIndex;
  late final AnimationController _controller;

  bool get _isAnimating =>
      _controller.isAnimating && _currentIndex != _previousIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.index;
    _previousIndex = widget.index;
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
    if (widget.index == _currentIndex) return;
    _previousIndex = _currentIndex;
    _currentIndex = widget.index;
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
    final currentPage = KeyedSubtree(
      key: ValueKey<int>(_currentIndex),
      child: widget.pages[_currentIndex],
    );

    if (!_isAnimating) {
      return ColoredBox(color: backgroundColor, child: currentPage);
    }

    final previousPage = KeyedSubtree(
      key: ValueKey<int>(_previousIndex),
      child: widget.pages[_previousIndex],
    );
    final isForward = _currentIndex > _previousIndex;

    return ColoredBox(
      color: backgroundColor,
      child: ClipRect(
        child: IgnorePointer(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final incomingProgress = _iosIncomingCurve.transform(
                _controller.value.clamp(0.0, 1.0),
              );
              final outgoingProgress = _iosOutgoingCurve.transform(
                _controller.value.clamp(0.0, 1.0),
              );

              if (isForward) {
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    FractionalTranslation(
                      translation: Offset(-0.30 * outgoingProgress, 0),
                      child: _MobilePageLayer(
                        overlayOpacity: 0.05 * outgoingProgress,
                        child: previousPage,
                      ),
                    ),
                    FractionalTranslation(
                      translation: Offset(1 - incomingProgress, 0),
                      child: _MobilePageLayer(
                        edgeShadowOpacity: 0.18 * (1 - incomingProgress),
                        shadowOnLeadingEdge: true,
                        child: currentPage,
                      ),
                    ),
                  ],
                );
              }

              return Stack(
                fit: StackFit.expand,
                children: [
                  FractionalTranslation(
                    translation: Offset(-0.08 * (1 - incomingProgress), 0),
                    child: _MobilePageLayer(
                      overlayOpacity: 0.02 * (1 - incomingProgress),
                      child: currentPage,
                    ),
                  ),
                  FractionalTranslation(
                    translation: Offset(outgoingProgress, 0),
                    child: _MobilePageLayer(
                      edgeShadowOpacity: 0.18 * (1 - outgoingProgress),
                      shadowOnLeadingEdge: true,
                      child: previousPage,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _MobilePageLayer extends StatelessWidget {
  const _MobilePageLayer({
    required this.child,
    this.overlayOpacity = 0,
    this.edgeShadowOpacity = 0,
    this.shadowOnLeadingEdge = true,
  });

  final Widget child;
  final double overlayOpacity;
  final double edgeShadowOpacity;
  final bool shadowOnLeadingEdge;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        if (overlayOpacity > 0.0001)
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: overlayOpacity),
                ),
              ),
            ),
          ),
        if (edgeShadowOpacity > 0.0001)
          Positioned(
            top: 0,
            bottom: 0,
            left: shadowOnLeadingEdge ? 0 : null,
            right: shadowOnLeadingEdge ? null : 0,
            width: 28,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: shadowOnLeadingEdge
                        ? Alignment.centerLeft
                        : Alignment.centerRight,
                    end: shadowOnLeadingEdge
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    colors: [
                      Colors.black.withValues(alpha: edgeShadowOpacity),
                      Colors.black.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
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
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
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
                      scale: selected ? 1.0 : 0.92,
                      child: Icon(
                        destination.icon,
                        size: 18,
                        color: foregroundColor,
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  AnimatedDefaultTextStyle(
                    duration: animationDuration,
                    curve: Curves.easeOutCubic,
                    style: (labelStyle ?? const TextStyle()).copyWith(
                      color: foregroundColor,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                      letterSpacing: selected ? -0.1 : 0.1,
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
