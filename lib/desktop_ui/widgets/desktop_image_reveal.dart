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
    return Image(
      image: image,
      fit: fit,
      gaplessPlayback: true,
      filterQuality: FilterQuality.medium,
    );
  }
}
