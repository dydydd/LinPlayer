import 'package:flutter/material.dart';
import 'package:lin_player_server_api/network/lin_http_client.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../services/cover_cache_manager.dart';

class LinNetworkImage extends StatefulWidget {
  const LinNetworkImage({
    super.key,
    required this.imageUrl,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
    this.placeholder,
    this.errorWidget,
  });

  final String imageUrl;
  final BoxFit fit;
  final Alignment alignment;
  final Widget? placeholder;
  final Widget? errorWidget;

  @override
  State<LinNetworkImage> createState() => _LinNetworkImageState();
}

class _LinNetworkImageState extends State<LinNetworkImage> {
  String _currentUrl = '';
  bool _hasShownFrame = false;
  bool _hasFailed = false;
  bool _frameMarkPending = false;
  bool _failureMarkPending = false;

  @override
  void initState() {
    super.initState();
    _syncUrl(resetState: true);
  }

  @override
  void didUpdateWidget(covariant LinNetworkImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl.trim() != widget.imageUrl.trim()) {
      _syncUrl(resetState: true);
    }
  }

  void _syncUrl({required bool resetState}) {
    _currentUrl = widget.imageUrl.trim();
    if (!resetState) return;
    _hasShownFrame = false;
    _hasFailed = false;
    _frameMarkPending = false;
    _failureMarkPending = false;
  }

  void _markFrameShown() {
    if (_hasShownFrame || _frameMarkPending) return;
    _frameMarkPending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _frameMarkPending = false;
      if (!mounted || _hasShownFrame) return;
      setState(() {
        _hasShownFrame = true;
        _hasFailed = false;
      });
    });
  }

  void _markFailed() {
    if (_hasFailed || _failureMarkPending) return;
    _failureMarkPending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _failureMarkPending = false;
      if (!mounted || _hasFailed) return;
      setState(() => _hasFailed = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final resolvedUrl = _currentUrl;
    final fallback = widget.errorWidget ?? const SizedBox.shrink();
    final loading = widget.placeholder ?? fallback;

    if (resolvedUrl.isEmpty) {
      return fallback;
    }

    final provider = CachedNetworkImageProvider(
      resolvedUrl,
      cacheManager: CoverCacheManager.instance,
      headers: {'User-Agent': LinHttpClientFactory.userAgent},
    );

    return Image(
      image: provider,
      fit: widget.fit,
      alignment: widget.alignment,
      gaplessPlayback: true,
      filterQuality: FilterQuality.medium,
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        final ready = wasSynchronouslyLoaded || frame != null;
        if (ready) {
          _markFrameShown();
          return child;
        }
        if (_hasShownFrame) {
          return child;
        }
        return loading;
      },
      errorBuilder: (context, error, stackTrace) {
        _markFailed();
        return fallback;
      },
    );
  }
}

ImageProvider<Object>? linNetworkImageProvider(String? imageUrl) {
  final resolvedUrl = (imageUrl ?? '').trim();
  if (resolvedUrl.isEmpty) return null;
  return CachedNetworkImageProvider(
    resolvedUrl,
    cacheManager: CoverCacheManager.instance,
    headers: {'User-Agent': LinHttpClientFactory.userAgent},
  );
}
