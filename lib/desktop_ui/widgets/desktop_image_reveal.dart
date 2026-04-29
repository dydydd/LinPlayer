import 'dart:ui';

import 'package:flutter/material.dart';

class DesktopImageReveal extends StatelessWidget {
  const DesktopImageReveal({
    super.key,
    required this.image,
    this.fit = BoxFit.cover,
    this.duration = const Duration(milliseconds: 360),
    this.curve = Curves.easeOutCubic,
  });

  final ImageProvider image;
  final BoxFit fit;
  final Duration duration;
  final Curve curve;

  @override
  Widget build(BuildContext context) {
    final disableAnimations =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return LayoutBuilder(
      builder: (context, constraints) {
        final imageChild = SizedBox(
          width: constraints.maxWidth,
          height: constraints.maxHeight,
          child: Image(
            image: image,
            fit: fit,
            gaplessPlayback: true,
            filterQuality: FilterQuality.medium,
          ),
        );

        if (disableAnimations) {
          return imageChild;
        }

        return TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0, end: 1),
          duration: duration,
          curve: curve,
          child: imageChild,
          builder: (context, value, child) {
            final reveal = value.clamp(0.001, 1.0);
            final opacity = Interval(
              0.08,
              1.0,
              curve: Curves.easeOutCubic,
            ).transform(value);
            final translateY = lerpDouble(-10, 0, value) ?? 0;
            final sheenOpacity =
                (1 - Curves.easeOut.transform(value)).clamp(0.0, 1.0) * 0.18;

            return Stack(
              fit: StackFit.expand,
              children: [
                Opacity(
                  opacity: opacity,
                  child: Transform.translate(
                    offset: Offset(0, translateY),
                    child: ClipRect(
                      child: Align(
                        alignment: Alignment.topCenter,
                        heightFactor: reveal,
                        child: child,
                      ),
                    ),
                  ),
                ),
                if (sheenOpacity > 0)
                  IgnorePointer(
                    child: Opacity(
                      opacity: sheenOpacity,
                      child: const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.white24,
                              Colors.white10,
                              Colors.transparent,
                            ],
                            stops: [0, 0.48, 1],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }
}
