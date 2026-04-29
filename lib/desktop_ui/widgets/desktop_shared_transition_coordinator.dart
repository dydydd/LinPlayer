import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

class DesktopSharedPosterSourceSnapshot {
  const DesktopSharedPosterSourceSnapshot({
    required this.itemId,
    required this.globalRect,
    required this.imageUrls,
    required this.snapshotImage,
    required this.fallbackLabel,
    required this.aspectRatio,
    required this.borderRadius,
    required this.recordedAt,
  });

  final String itemId;
  final Rect globalRect;
  final List<String> imageUrls;
  final ui.Image? snapshotImage;
  final String fallbackLabel;
  final double aspectRatio;
  final double borderRadius;
  final DateTime recordedAt;

  void dispose() {
    snapshotImage?.dispose();
  }
}

class DesktopSharedTransitionCoordinator {
  DesktopSharedTransitionCoordinator._();

  static final DesktopSharedTransitionCoordinator instance =
      DesktopSharedTransitionCoordinator._();

  DesktopSharedPosterSourceSnapshot? _pendingSource;

  Future<void> recordTapSource({
    required String itemId,
    required BuildContext context,
    required List<String> imageUrls,
    required String fallbackLabel,
    required double aspectRatio,
    double borderRadius = 12,
  }) async {
    final normalizedId = itemId.trim();
    if (normalizedId.isEmpty) return;

    clear();

    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return;

    final origin = renderObject.localToGlobal(Offset.zero);
    final snapshotImage = await _captureSourceImage(context, renderObject);
    _pendingSource = DesktopSharedPosterSourceSnapshot(
      itemId: normalizedId,
      globalRect: origin & renderObject.size,
      imageUrls: imageUrls
          .map((url) => url.trim())
          .where((url) => url.isNotEmpty)
          .toList(growable: false),
      snapshotImage: snapshotImage,
      fallbackLabel: fallbackLabel.trim(),
      aspectRatio: aspectRatio,
      borderRadius: borderRadius,
      recordedAt: DateTime.now(),
    );
  }

  DesktopSharedPosterSourceSnapshot? consumePendingSource(
    String itemId, {
    Duration maxAge = const Duration(milliseconds: 1200),
  }) {
    final snapshot = _pendingSource;
    _pendingSource = null;
    if (snapshot == null) return null;
    if (snapshot.itemId != itemId.trim()) return null;
    if (DateTime.now().difference(snapshot.recordedAt) > maxAge) return null;
    return snapshot;
  }

  void clear() {
    _pendingSource?.dispose();
    _pendingSource = null;
  }

  Future<ui.Image?> _captureSourceImage(
    BuildContext context,
    RenderBox renderObject,
  ) async {
    if (renderObject is! RenderRepaintBoundary) return null;
    try {
      final pixelRatio = MediaQuery.maybeOf(context)?.devicePixelRatio ?? 1.0;
      return await renderObject.toImage(pixelRatio: pixelRatio.clamp(1.0, 2.0));
    } catch (_) {
      return null;
    }
  }
}
