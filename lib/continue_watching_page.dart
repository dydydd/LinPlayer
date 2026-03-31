import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:lin_player_server_adapters/lin_player_server_adapters.dart';
import 'package:lin_player_state/lin_player_state.dart';
import 'package:lin_player_ui/lin_player_ui.dart';

import 'server_adapters/server_access.dart';
import 'show_detail_page.dart';

class ContinueWatchingPage extends StatefulWidget {
  const ContinueWatchingPage({
    super.key,
    required this.appState,
  });

  final AppState appState;

  @override
  State<ContinueWatchingPage> createState() => _ContinueWatchingPageState();
}

class _ContinueWatchingPageState extends State<ContinueWatchingPage> {
  bool _loading = true;
  String? _error;
  List<MediaItem> _items = const <MediaItem>[];

  @override
  void initState() {
    super.initState();
    unawaited(_load(forceRefresh: true));
  }

  Future<void> _load({required bool forceRefresh}) async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final items = await widget.appState.loadContinueWatching(
        forceRefresh: forceRefresh,
        forceNewRequest: forceRefresh,
      );
      if (!mounted) return;
      setState(() => _items = items);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final enableBlur = widget.appState.enableBlurEffects;

    return Scaffold(
      appBar: GlassAppBar(
        enableBlur: enableBlur,
        child: AppBar(
          title: const Text('观看记录'),
          actions: [
            IconButton(
              tooltip: '刷新',
              onPressed: _loading ? null : () => _load(forceRefresh: true),
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () => _load(forceRefresh: true),
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading && _items.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 240),
          Center(child: CircularProgressIndicator()),
        ],
      );
    }

    if ((_error ?? '').trim().isNotEmpty && _items.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
        children: [
          Text(
            _error!,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: () => _load(forceRefresh: true),
            icon: const Icon(Icons.refresh),
            label: const Text('重试'),
          ),
        ],
      );
    }

    if (_items.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(24, 64, 24, 24),
        children: const [
          Center(child: Text('暂无观看记录')),
        ],
      );
    }

    return ContinueWatchingGrid(
      appState: widget.appState,
      items: _items,
      shrinkWrap: false,
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
    );
  }
}

class ContinueWatchingGrid extends StatelessWidget {
  const ContinueWatchingGrid({
    super.key,
    required this.appState,
    required this.items,
    this.padding = EdgeInsets.zero,
    this.physics,
    this.shrinkWrap = false,
    this.maxItems,
  });

  final AppState appState;
  final List<MediaItem> items;
  final EdgeInsetsGeometry padding;
  final ScrollPhysics? physics;
  final bool shrinkWrap;
  final int? maxItems;

  @override
  Widget build(BuildContext context) {
    final limitedItems = maxItems == null || maxItems! >= items.length
        ? items
        : items.take(maxItems!).toList(growable: false);

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final resolvedPadding = padding.resolve(Directionality.of(context));
        final contentWidth =
            (width - resolvedPadding.horizontal).clamp(0.0, width);
        final columns = width >= 820
            ? 3
            : width >= 560
                ? 2
                : 2;
        final spacing = width >= 560 ? 14.0 : 12.0;
        final tileWidth =
            (contentWidth - spacing * (columns - 1))
                    .clamp(0.0, double.infinity) /
                columns;
        final imageHeight = tileWidth * 9 / 16;
        final textHeight = width >= 560 ? 58.0 : 66.0;
        final aspectRatio = tileWidth <= 0
            ? 1.0
            : tileWidth / (imageHeight + textHeight);

        return GridView.builder(
          shrinkWrap: shrinkWrap,
          physics: physics,
          padding: padding,
          itemCount: limitedItems.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: spacing,
            crossAxisSpacing: spacing,
            childAspectRatio: aspectRatio,
          ),
          itemBuilder: (context, index) {
            return _ContinueWatchingCard(
              item: limitedItems[index],
              appState: appState,
            );
          },
        );
      },
    );
  }
}

class _ContinueWatchingCard extends StatelessWidget {
  const _ContinueWatchingCard({
    required this.item,
    required this.appState,
  });

  final MediaItem item;
  final AppState appState;

  Duration _ticksToDuration(int ticks) =>
      Duration(microseconds: (ticks / 10).round());

  String _fmt(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:'
          '${minutes.toString().padLeft(2, '0')}:'
          '${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }

  String _episodeTag(MediaItem item) {
    final season = item.seasonNumber ?? 0;
    final episode = item.episodeNumber ?? 0;
    if (season <= 0 && episode <= 0) return '';
    if (season > 0 && episode > 0) {
      return 'S${season.toString().padLeft(2, '0')}'
          'E${episode.toString().padLeft(2, '0')}';
    }
    if (episode > 0) return 'E${episode.toString().padLeft(2, '0')}';
    return 'S${season.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final access = resolveServerAccess(appState: appState);
    final theme = Theme.of(context);
    final isEpisode = item.type.toLowerCase() == 'episode';
    final title = isEpisode && item.seriesName.trim().isNotEmpty
        ? item.seriesName.trim()
        : item.name;
    final position = _ticksToDuration(item.playbackPositionTicks);
    final tag = isEpisode ? _episodeTag(item) : '';
    final subtitleParts = <String>[
      if (tag.isNotEmpty) tag,
      if (position > Duration.zero) '看到 ${_fmt(position)}',
    ];
    final subtitle = subtitleParts.join(' · ');

    final imageUrl = item.hasImage && access != null
        ? access.adapter.imageUrl(
            access.auth,
            itemId: item.id,
            imageType: 'Primary',
            maxWidth: 640,
          )
        : null;

    void openDetail() {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => isEpisode
              ? EpisodeDetailPage(
                  episode: item,
                  appState: appState,
                  isTv: false,
                )
              : ShowDetailPage(
                  itemId: item.id,
                  title: item.name,
                  appState: appState,
                  isTv: false,
                ),
        ),
      );
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: openDetail,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: imageUrl == null
                    ? const ColoredBox(
                        color: Colors.black12,
                        child: Center(child: Icon(Icons.image)),
                      )
                    : CachedNetworkImage(
                        imageUrl: imageUrl,
                        cacheManager: CoverCacheManager.instance,
                        httpHeaders: {
                          'User-Agent': LinHttpClientFactory.userAgent,
                        },
                        fit: BoxFit.cover,
                        placeholder: (_, __) => const ColoredBox(
                          color: Colors.black12,
                          child: Center(child: Icon(Icons.image)),
                        ),
                        errorWidget: (_, __, ___) => const ColoredBox(
                          color: Colors.black12,
                          child: Center(child: Icon(Icons.broken_image)),
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            if (subtitle.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
