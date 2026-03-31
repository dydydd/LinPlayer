import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:lin_player_server_api/network/lin_http_client.dart';

import '../services/cover_cache_manager.dart';

class LinNetworkImage extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final resolvedUrl = imageUrl.trim();
    final fallback = errorWidget ?? const SizedBox.shrink();
    final loading = placeholder ?? fallback;

    if (resolvedUrl.isEmpty) {
      return fallback;
    }

    return CachedNetworkImage(
      imageUrl: resolvedUrl,
      cacheManager: CoverCacheManager.instance,
      httpHeaders: {'User-Agent': LinHttpClientFactory.userAgent},
      fit: fit,
      alignment: alignment,
      placeholder: (_, __) => loading,
      errorWidget: (_, __, ___) => fallback,
      useOldImageOnUrlChange: true,
      fadeInDuration: Duration.zero,
      fadeOutDuration: Duration.zero,
      placeholderFadeInDuration: Duration.zero,
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
