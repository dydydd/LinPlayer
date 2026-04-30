import 'dart:ui' as ui;
import 'dart:math' as math;

import 'package:flutter/material.dart';

enum DesktopPageTransitionStyle {
  push,
  fade,
  flip,
  stack,
  anchorExpand,
}

Route<T> buildDesktopPageRoute<T>({
  required WidgetBuilder builder,
  DesktopPageTransitionStyle transition = DesktopPageTransitionStyle.push,
  Duration duration = const Duration(milliseconds: 240),
  RouteSettings? settings,
  Rect? anchorRect,
  double anchorBorderRadius = 18,
}) {
  final useAnchorExpand =
      transition == DesktopPageTransitionStyle.anchorExpand &&
          anchorRect != null;
  return PageRouteBuilder<T>(
    settings: settings,
    opaque: !useAnchorExpand,
    transitionDuration: duration,
    reverseTransitionDuration: duration,
    pageBuilder: (context, _, __) => builder(context),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      final transitionChild = RepaintBoundary(child: child);

      switch (transition) {
        case DesktopPageTransitionStyle.push:
          return FadeTransition(
            opacity: Tween<double>(begin: 0.16, end: 1.0).animate(curved),
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0.032, 0),
                end: Offset.zero,
              ).animate(curved),
              child: transitionChild,
            ),
          );
        case DesktopPageTransitionStyle.fade:
          return FadeTransition(
            opacity: curved,
            child: transitionChild,
          );
        case DesktopPageTransitionStyle.flip:
          return FadeTransition(
            opacity: Tween<double>(begin: 0.2, end: 1.0).animate(curved),
            child: AnimatedBuilder(
              animation: curved,
              child: transitionChild,
              builder: (context, child) {
                final matrix = Matrix4.identity()
                  ..setEntry(3, 2, 0.0012)
                  ..rotateY((1 - curved.value) * (math.pi / 22));
                return Transform(
                  alignment: Alignment.center,
                  transform: matrix,
                  child: child,
                );
              },
            ),
          );
        case DesktopPageTransitionStyle.stack:
          return FadeTransition(
            opacity: Tween<double>(begin: 0.0, end: 1.0).animate(curved),
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.982, end: 1.0).animate(curved),
              child: transitionChild,
            ),
          );
        case DesktopPageTransitionStyle.anchorExpand:
          if (anchorRect == null) {
            return FadeTransition(
              opacity: Tween<double>(begin: 0.16, end: 1.0).animate(curved),
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0.032, 0),
                  end: Offset.zero,
                ).animate(curved),
                child: transitionChild,
              ),
            );
          }
          return _AnchoredDesktopPageTransition(
            animation: curved,
            anchorRect: anchorRect,
            anchorBorderRadius: anchorBorderRadius,
            child: transitionChild,
          );
      }
    },
  );
}

class _AnchoredDesktopPageTransition extends StatelessWidget {
  const _AnchoredDesktopPageTransition({
    required this.animation,
    required this.anchorRect,
    required this.anchorBorderRadius,
    required this.child,
  });

  final Animation<double> animation;
  final Rect anchorRect;
  final double anchorBorderRadius;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.maybeOf(context);
    final screenSize = mediaQuery?.size;
    if (screenSize == null || screenSize.isEmpty) {
      return FadeTransition(opacity: animation, child: child);
    }

    final fullRect = Offset.zero & screenSize;
    final clampedAnchorRect = _clampRectToBounds(
      anchorRect.inflate(4),
      fullRect,
    );
    final rectT = Curves.easeOutCubic.transform(animation.value);
    final contentOpacity = ui.lerpDouble(
      0.78,
      1.0,
      Curves.easeOutCubic.transform(
        ((animation.value - 0.08) / 0.92).clamp(0.0, 1.0),
      ),
    )!;
    final currentRect = Rect.lerp(clampedAnchorRect, fullRect, rectT)!;
    final brightness = Theme.of(context).brightness;
    final shadowColor =
        brightness == Brightness.dark ? Colors.black : const Color(0xFF122033);
    final scrimOpacity = ui.lerpDouble(
      0.0,
      brightness == Brightness.dark ? 0.16 : 0.08,
      Curves.easeOutCubic.transform(
        ((animation.value - 0.02) / 0.98).clamp(0.0, 1.0),
      ),
    )!;
    final shadowOpacity = ui.lerpDouble(
      brightness == Brightness.dark ? 0.34 : 0.16,
      0.12,
      rectT,
    )!;
    final firstRadius = ui.lerpDouble(
      anchorBorderRadius,
      28,
      Curves.easeOutCubic.transform((animation.value / 0.46).clamp(0.0, 1.0)),
    )!;
    final borderRadiusValue = ui.lerpDouble(
      firstRadius,
      0,
      Curves.easeInOutCubic.transform(
        ((animation.value - 0.48) / 0.52).clamp(0.0, 1.0),
      ),
    )!;
    final borderOpacity = ui.lerpDouble(0.26, 0.0, rectT)!;

    return Stack(
      fit: StackFit.expand,
      children: [
        IgnorePointer(
          child: ColoredBox(color: shadowColor.withValues(alpha: scrimOpacity)),
        ),
        Positioned.fromRect(
          rect: currentRect,
          child: IgnorePointer(
            ignoring: animation.value < 1,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(borderRadiusValue),
                boxShadow: [
                  BoxShadow(
                    color: shadowColor.withValues(alpha: shadowOpacity),
                    blurRadius: ui.lerpDouble(18, 42, rectT)!,
                    spreadRadius: ui.lerpDouble(0, 1.5, rectT)!,
                    offset: Offset(0, ui.lerpDouble(10, 22, rectT)!),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(borderRadiusValue),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: Theme.of(context)
                          .dividerColor
                          .withValues(alpha: borderOpacity),
                    ),
                  ),
                  child: FittedBox(
                    fit: BoxFit.fill,
                    alignment: Alignment.topLeft,
                    child: SizedBox(
                      width: fullRect.width,
                      height: fullRect.height,
                      child: Opacity(opacity: contentOpacity, child: child),
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

  Rect _clampRectToBounds(Rect rect, Rect bounds) {
    final left = rect.left.clamp(bounds.left, bounds.right);
    final top = rect.top.clamp(bounds.top, bounds.bottom);
    final right = rect.right.clamp(bounds.left, bounds.right);
    final bottom = rect.bottom.clamp(bounds.top, bounds.bottom);

    if (right <= left || bottom <= top) {
      final safeRect = Rect.fromCenter(
        center: rect.center,
        width: rect.width.clamp(1.0, bounds.width),
        height: rect.height.clamp(1.0, bounds.height),
      );
      return safeRect.intersect(bounds);
    }

    return Rect.fromLTRB(left, top, right, bottom);
  }
}
