import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../device/device_type.dart';
import '../services/cover_cache_manager.dart';
import 'package:lin_player_server_api/network/lin_http_client.dart';
import 'app_style.dart';
import 'frosted_card.dart';
import 'rating_badge.dart';

AppStyle _styleOf(BuildContext context) =>
    Theme.of(context).extension<AppStyle>() ?? const AppStyle();

class AppPanel extends StatelessWidget {
  const AppPanel({
    super.key,
    required this.child,
    this.padding,
    this.enableBlur = true,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final bool enableBlur;

  @override
  Widget build(BuildContext context) {
    return FrostedCard(
      enableBlur: enableBlur,
      padding: padding,
      child: child,
    );
  }
}

class MediaLabelBadge extends StatelessWidget {
  const MediaLabelBadge({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = Colors.black.withValues(alpha: 0.55);
    const fg = Colors.white;
    const border = BorderSide.none;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border:
            border == BorderSide.none ? null : Border.fromBorderSide(border),
      ),
      child: Text(
        text,
        style: theme.textTheme.labelSmall?.copyWith(
              color: fg,
              fontWeight: FontWeight.w700,
            ) ??
            TextStyle(
              color: fg,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}

class MediaPosterTile extends StatefulWidget {
  const MediaPosterTile({
    super.key,
    required this.title,
    required this.imageUrl,
    required this.onTap,
    this.year,
    this.rating,
    this.badgeText,
    this.topRightBadge,
    this.titleMaxLines = 1,
    this.showOverlayRating = true,
    this.combineMetaLine = false,
    this.posterAspectRatio,
  });

  final String title;
  final String? imageUrl;
  final VoidCallback onTap;
  final String? year;
  final double? rating;
  final String? badgeText;
  final Widget? topRightBadge;
  final int titleMaxLines;
  final bool showOverlayRating;
  final bool combineMetaLine;
  final double? posterAspectRatio;

  @override
  State<MediaPosterTile> createState() => _MediaPosterTileState();
}

class _MediaPosterTileState extends State<MediaPosterTile> {
  bool _focused = false;

  void _onFocusChange(bool focused) {
    if (!DeviceType.isTv) return;

    if (focused) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Scrollable.ensureVisible(
          context,
          alignment: 0.5,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
        );
      });
    }

    if (_focused == focused) return;
    setState(() => _focused = focused);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final style = _styleOf(context);
    final isDark = scheme.brightness == Brightness.dark;

    const posterRadius = 12.0;
    final borderWidth = style.borderWidth;
    final borderColor =
        scheme.outlineVariant.withValues(alpha: isDark ? 0.38 : 0.55);
    final shadowColor = scheme.shadow.withValues(alpha: isDark ? 0.22 : 0.12);

    final image = widget.imageUrl != null
        ? CachedNetworkImage(
            imageUrl: widget.imageUrl!,
            cacheManager: CoverCacheManager.instance,
            httpHeaders: {'User-Agent': LinHttpClientFactory.userAgent},
            fit: BoxFit.cover,
            placeholder: (_, __) => const ColoredBox(color: Colors.black12),
            errorWidget: (_, __, ___) =>
                const ColoredBox(color: Colors.black26),
            useOldImageOnUrlChange: true,
            fadeInDuration: Duration.zero,
            fadeOutDuration: Duration.zero,
            placeholderFadeInDuration: Duration.zero,
          )
        : const ColoredBox(color: Colors.black26, child: Icon(Icons.image));

    final badge = (widget.badgeText ?? '').trim();
    final yearText = (widget.year ?? '').trim();
    final hasYear = yearText.isNotEmpty;
    final hasRating = widget.rating != null && widget.rating! > 0;
    final metaStyle = theme.textTheme.labelSmall?.copyWith(
          color: scheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ) ??
        TextStyle(
          color: scheme.onSurfaceVariant,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        );
    final showOverlayRating = widget.showOverlayRating && hasRating;

    Widget? metaLine;
    if (widget.combineMetaLine) {
      if (hasYear || hasRating) {
        metaLine = Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (hasYear) Text(yearText, style: metaStyle),
            if (hasRating) ...[
              if (hasYear) const SizedBox(width: 6),
              const Icon(
                Icons.star_rounded,
                size: 14,
                color: Colors.amber,
              ),
              const SizedBox(width: 2),
              Text(widget.rating!.toStringAsFixed(1), style: metaStyle),
            ],
          ],
        );
      }
    } else if (hasYear) {
      metaLine = Text(
        yearText,
        style: metaStyle,
        textAlign: TextAlign.center,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }

    final poster = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(posterRadius),
        border: Border.all(color: borderColor, width: borderWidth),
        boxShadow: shadowColor == Colors.transparent
            ? null
            : [
                BoxShadow(
                  color: shadowColor,
                  blurRadius: 18,
                  offset: const Offset(0, 10),
                ),
              ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(posterRadius),
        child: Stack(
          fit: StackFit.expand,
          children: [
            image,
            if (showOverlayRating || badge.isNotEmpty)
              Positioned(
                left: 6,
                top: 6,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (showOverlayRating) RatingBadge(rating: widget.rating!),
                    if (showOverlayRating && badge.isNotEmpty)
                      const SizedBox(width: 6),
                    if (badge.isNotEmpty) MediaLabelBadge(text: badge),
                  ],
                ),
              ),
            if (widget.topRightBadge != null)
              Positioned(
                right: 6,
                top: 6,
                child: widget.topRightBadge!,
              ),
          ],
        ),
      ),
    );

    final posterContent = widget.posterAspectRatio == null
        ? Expanded(child: poster)
        : AspectRatio(
            aspectRatio: widget.posterAspectRatio!,
            child: poster,
          );

    final tile = Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(posterRadius),
        onTap: widget.onTap,
        onFocusChange: _onFocusChange,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            posterContent,
            const SizedBox(height: 6),
            Text(
              widget.title,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
              maxLines: math.max(1, widget.titleMaxLines),
              overflow: TextOverflow.ellipsis,
            ),
            if (metaLine != null) ...[
              const SizedBox(height: 2),
              metaLine,
            ],
          ],
        ),
      ),
    );

    if (!DeviceType.isTv) return tile;

    final bg = _focused
        ? scheme.primary.withValues(alpha: isDark ? 0.16 : 0.12)
        : Colors.transparent;
    final border = _focused ? scheme.primary : Colors.transparent;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(math.max(10.0, posterRadius)),
        border: Border.all(color: border, width: 2),
      ),
      child: tile,
    );
  }
}

class MediaBackdropTile extends StatefulWidget {
  const MediaBackdropTile({
    super.key,
    required this.title,
    required this.imageUrl,
    required this.onTap,
    this.onLongPress,
    this.subtitle,
    this.badgeText,
  });

  final String title;
  final String? subtitle;
  final String? imageUrl;
  final String? badgeText;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  State<MediaBackdropTile> createState() => _MediaBackdropTileState();
}

class _MediaBackdropTileState extends State<MediaBackdropTile> {
  bool _focused = false;

  void _onFocusChange(bool focused) {
    if (!DeviceType.isTv) return;

    if (focused) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Scrollable.ensureVisible(
          context,
          alignment: 0.5,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
        );
      });
    }

    if (_focused == focused) return;
    setState(() => _focused = focused);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final style = _styleOf(context);
    final isDark = scheme.brightness == Brightness.dark;

    const radius = 14.0;
    final borderWidth = style.borderWidth;
    final borderColor =
        scheme.outlineVariant.withValues(alpha: isDark ? 0.38 : 0.55);

    final imageUrl = (widget.imageUrl ?? '').trim();
    final hasImage = imageUrl.isNotEmpty;

    final image = hasImage
        ? CachedNetworkImage(
            imageUrl: imageUrl,
            cacheManager: CoverCacheManager.instance,
            httpHeaders: {'User-Agent': LinHttpClientFactory.userAgent},
            fit: BoxFit.cover,
            placeholder: (_, __) => const ColoredBox(
              color: Colors.black12,
              child: Center(child: Icon(Icons.image_outlined)),
            ),
            errorWidget: (_, __, ___) => const ColoredBox(
              color: Colors.black26,
              child: Center(child: Icon(Icons.broken_image_outlined)),
            ),
            useOldImageOnUrlChange: true,
            fadeInDuration: Duration.zero,
            fadeOutDuration: Duration.zero,
            placeholderFadeInDuration: Duration.zero,
          )
        : const ColoredBox(
            color: Colors.black26,
            child: Center(child: Icon(Icons.image_outlined)),
          );

    final badge = (widget.badgeText ?? '').trim();

    final cover = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: borderColor, width: borderWidth),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Stack(
          fit: StackFit.expand,
          children: [
            image,
            if (badge.isNotEmpty)
              Positioned(left: 8, top: 8, child: MediaLabelBadge(text: badge)),
          ],
        ),
      ),
    );

    final tile = Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(radius),
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        onFocusChange: _onFocusChange,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(aspectRatio: 16 / 9, child: cover),
            const SizedBox(height: 6),
            Text(
              widget.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            if ((widget.subtitle ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                widget.subtitle!.trim(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );

    if (!DeviceType.isTv) return tile;

    final bg = _focused
        ? scheme.primary.withValues(alpha: isDark ? 0.16 : 0.12)
        : Colors.transparent;
    final border = _focused ? scheme.primary : Colors.transparent;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(math.max(10.0, radius)),
        border: Border.all(color: border, width: 2),
      ),
      child: tile,
    );
  }
}
