import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_interfaces.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/providers/media_providers.dart';
import '../../../ui/utils/media_helpers.dart';
import '../../../ui/widgets/common/media_widgets.dart';
import '../../theme/tv_design_tokens.dart';
import '../../widgets/tv_button.dart';
import '../../widgets/tv_focusable.dart';
import '../../widgets/tv_toast.dart';

/// TV 详情页（剧/电影）—— 接入真实数据。
/// Hero 背景 + 标题信息 + 操作按钮 + 季选择 + 集列表。
class TvDetailScreen extends ConsumerStatefulWidget {
  final String? mediaId;

  const TvDetailScreen({super.key, this.mediaId});

  @override
  ConsumerState<TvDetailScreen> createState() => _TvDetailScreenState();
}

class _TvDetailScreenState extends ConsumerState<TvDetailScreen> {
  String? _selectedSeasonId;
  bool? _favoriteOverride; // 本地乐观状态

  @override
  Widget build(BuildContext context) {
    final id = widget.mediaId;
    if (id == null || id.isEmpty) {
      return _errorScaffold('无效的媒体 ID');
    }
    final itemAsync = ref.watch(mediaItemProvider(id));

    return Scaffold(
      backgroundColor: TvDesignTokens.background,
      body: itemAsync.when(
        data: (item) => _buildContent(item),
        loading: () => const Center(
          child: CircularProgressIndicator(color: TvDesignTokens.brand),
        ),
        error: (e, _) => _errorBody('加载详情失败：$e'),
      ),
    );
  }

  Widget _buildContent(MediaItem item) {
    final api = ref.read(apiClientProvider);
    final isSeries = item.type == 'Series';

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeroArea(api, item),
          Padding(
            padding: const EdgeInsets.all(TvDesignTokens.spacingXl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildActionButtons(item),
                if (item.overview != null && item.overview!.isNotEmpty) ...[
                  const SizedBox(height: TvDesignTokens.spacingLg),
                  _buildSynopsis(item.overview!),
                ],
                if (isSeries) ...[
                  const SizedBox(height: TvDesignTokens.spacingLg),
                  _buildSeasonsAndEpisodes(api, item),
                ],
                const SizedBox(height: TvDesignTokens.spacingXxl),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroArea(ApiClientFactory api, MediaItem item) {
    final banner = resolveMediaItemBannerImageUrls(api, item,
        maxWidth: 1600, allowPosterFallback: true);
    final logo = (item.logoItemId != null && item.logoImageTag != null)
        ? api.image
            .getLogoImageUrl(item.logoItemId!, tag: item.logoImageTag, maxWidth: 320)
        : null;

    return SizedBox(
      height: 420,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (banner.isNotEmpty)
            MediaImage(
              imageUrl: banner.first,
              imageUrls: banner.length > 1 ? banner.sublist(1) : null,
              width: double.infinity,
              height: double.infinity,
              fit: BoxFit.cover,
            )
          else
            const ColoredBox(color: TvDesignTokens.surfaceElevated),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  TvDesignTokens.background.withValues(alpha: 0.8),
                  TvDesignTokens.background,
                ],
                stops: const [0.4, 0.82, 1.0],
              ),
            ),
          ),
          Positioned(
            left: TvDesignTokens.spacingXl,
            right: TvDesignTokens.spacingXl,
            bottom: TvDesignTokens.spacingLg,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (logo != null && logo.isNotEmpty)
                  Image.network(logo,
                      height: 64,
                      fit: BoxFit.contain,
                      alignment: Alignment.centerLeft,
                      errorBuilder: (_, __, ___) => _titleText(item.name))
                else
                  _titleText(item.name),
                const SizedBox(height: TvDesignTokens.spacingSm),
                Row(
                  children: [
                    if (item.communityRating != null) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: TvDesignTokens.spacingSm, vertical: 4),
                        decoration: BoxDecoration(
                          color: TvDesignTokens.brand,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '★ ${item.communityRating!.toStringAsFixed(1)}',
                          style: const TextStyle(
                            fontSize: TvDesignTokens.fontSizeSm,
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: TvDesignTokens.spacingMd),
                    ],
                    Expanded(
                      child: Text(
                        _metaLine(item),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: TvDesignTokens.fontSizeSm,
                          color: TvDesignTokens.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ).animate().fadeIn(duration: TvDesignTokens.contentFadeDuration),
          ),
        ],
      ),
    );
  }

  Widget _titleText(String name) => Text(
        name,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: TvDesignTokens.fontSizeXxl,
          color: TvDesignTokens.textPrimary,
          fontWeight: FontWeight.bold,
        ),
      );

  String _metaLine(MediaItem item) {
    final parts = <String>[];
    if (item.productionYear != null) parts.add('${item.productionYear}');
    final genres = item.genres;
    if (genres != null && genres.isNotEmpty) {
      parts.addAll(genres.take(3));
    }
    return parts.join(' · ');
  }

  Widget _buildActionButtons(MediaItem item) {
    final favorited = _favoriteOverride ?? (item.userData?.isFavorite ?? false);
    final resumeTicks = item.userData?.playbackPositionTicks ?? 0;
    final hasResume =
        item.type != 'Series' && !(item.userData?.played ?? false) && resumeTicks > 0;
    return Row(
      children: [
        TvButton(
          text: hasResume ? '继续观看' : '播放',
          icon: Icons.play_arrow,
          autofocus: true,
          onPressed: () => _onPlayMain(item),
        ),
        const SizedBox(width: TvDesignTokens.spacingMd),
        TvButton(
          text: favorited ? '已收藏' : '收藏',
          icon: favorited ? Icons.favorite : Icons.favorite_border,
          outlined: true,
          onPressed: () => _toggleFavorite(item, favorited),
        ),
      ],
    );
  }

  /// 顶部「播放/继续观看」：影片直接播；剧集挑「进行中 → 首个未看 → 第一集」。
  Future<void> _onPlayMain(MediaItem item) async {
    if (item.type != 'Series') {
      context.push('/tv/player?mediaId=${item.id}');
      return;
    }
    try {
      final api = ref.read(apiClientProvider);
      final seasons = await api.media.getSeasons(item.id);
      final seasonId = seasons.isNotEmpty ? seasons.first.id : null;
      final episodes = await api.media.getEpisodes(item.id, seasonId: seasonId);
      if (episodes.isEmpty) return;
      Episode? target;
      for (final e in episodes) {
        final pos = e.userData?.playbackPositionTicks ?? 0;
        if (!(e.userData?.played ?? false) && pos > 0) {
          target = e;
          break;
        }
      }
      target ??= episodes.firstWhere(
        (e) => !(e.userData?.played ?? false),
        orElse: () => episodes.first,
      );
      if (mounted) context.push('/tv/player?mediaId=${target.id}');
    } catch (_) {
      if (mounted) context.push('/tv/player?mediaId=${item.id}');
    }
  }

  Future<void> _toggleFavorite(MediaItem item, bool current) async {
    setState(() => _favoriteOverride = !current);
    try {
      final api = ref.read(apiClientProvider);
      if (current) {
        await api.favorite.removeFavorite(item.id);
      } else {
        await api.favorite.addFavorite(item.id);
      }
      if (mounted) TvToast.show(context, current ? '已取消收藏' : '已收藏');
    } catch (e) {
      if (mounted) {
        setState(() => _favoriteOverride = current);
        TvToast.show(context, '操作失败');
      }
    }
  }

  Widget _buildSynopsis(String overview) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '简介',
          style: TextStyle(
            fontSize: TvDesignTokens.fontSizeLg,
            color: TvDesignTokens.textPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: TvDesignTokens.spacingSm),
        Text(
          overview,
          style: const TextStyle(
            fontSize: TvDesignTokens.fontSizeSm,
            color: TvDesignTokens.textSecondary,
            height: TvDesignTokens.lineHeightRelaxed,
          ),
        ),
      ],
    );
  }

  Widget _buildSeasonsAndEpisodes(ApiClientFactory api, MediaItem series) {
    final seasonsAsync = ref.watch(seasonsProvider(series.id));
    return seasonsAsync.when(
      data: (seasons) {
        if (seasons.isEmpty) return const SizedBox.shrink();
        final seasonId = _selectedSeasonId ?? seasons.first.id;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '选择季',
              style: TextStyle(
                fontSize: TvDesignTokens.fontSizeLg,
                color: TvDesignTokens.textPrimary,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: TvDesignTokens.spacingSm),
            SizedBox(
              height: 56,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: seasons.length,
                itemBuilder: (context, index) {
                  final season = seasons[index];
                  final selected = season.id == seasonId;
                  return Padding(
                    padding:
                        const EdgeInsets.only(right: TvDesignTokens.spacingSm),
                    child: TvFocusable(
                      onSelect: () =>
                          setState(() => _selectedSeasonId = season.id),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: TvDesignTokens.spacingMd,
                          vertical: TvDesignTokens.spacingXs,
                        ),
                        decoration: BoxDecoration(
                          color: selected
                              ? TvDesignTokens.brand.withValues(alpha: 0.18)
                              : TvDesignTokens.surface,
                          borderRadius: BorderRadius.circular(
                              TvDesignTokens.posterRadius),
                          border: selected
                              ? Border.all(
                                  color: TvDesignTokens.brand, width: 2)
                              : null,
                        ),
                        child: Center(
                          child: Text(
                            season.name,
                            style: TextStyle(
                              fontSize: TvDesignTokens.fontSizeSm,
                              color: selected
                                  ? TvDesignTokens.brand
                                  : TvDesignTokens.textPrimary,
                              fontWeight: selected
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: TvDesignTokens.spacingLg),
            _buildEpisodeList(api, series.id, seasonId),
          ],
        );
      },
      loading: () => const Padding(
        padding: EdgeInsets.all(TvDesignTokens.spacingLg),
        child: CircularProgressIndicator(color: TvDesignTokens.brand),
      ),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  Widget _buildEpisodeList(
      ApiClientFactory api, String seriesId, String seasonId) {
    final episodesAsync =
        ref.watch(episodesProvider((seriesId: seriesId, seasonId: seasonId)));
    return episodesAsync.when(
      data: (episodes) {
        if (episodes.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '共 ${episodes.length} 集',
              style: const TextStyle(
                fontSize: TvDesignTokens.fontSizeLg,
                color: TvDesignTokens.textPrimary,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: TvDesignTokens.spacingSm),
            ...episodes.asMap().entries.map((entry) {
              final index = entry.key;
              final ep = entry.value;
              return _buildEpisodeRow(api, ep).animate().fadeIn(
                    delay: Duration(milliseconds: 30 * index),
                    duration: TvDesignTokens.contentFadeDuration,
                  );
            }),
          ],
        );
      },
      loading: () => const Padding(
        padding: EdgeInsets.all(TvDesignTokens.spacingLg),
        child: CircularProgressIndicator(color: TvDesignTokens.brand),
      ),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  Widget _buildEpisodeRow(ApiClientFactory api, Episode ep) {
    final thumbUrl = _episodeImageUrl(api, ep);
    final watched = ep.userData?.played ?? false;
    return Padding(
      padding: const EdgeInsets.only(bottom: TvDesignTokens.spacingSm),
      child: TvFocusable(
        padding: const EdgeInsets.all(TvDesignTokens.spacingXs),
        onSelect: () => context.push('/tv/player?mediaId=${ep.id}'),
        child: Container(
          padding: const EdgeInsets.all(TvDesignTokens.spacingMd),
          decoration: BoxDecoration(
            color: TvDesignTokens.surface,
            borderRadius: BorderRadius.circular(TvDesignTokens.posterRadius),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(TvDesignTokens.posterRadius),
                child: SizedBox(
                  width: 132,
                  height: 74,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      thumbUrl != null
                          ? MediaImage(
                              imageUrl: thumbUrl,
                              width: 132,
                              height: 74,
                              fit: BoxFit.cover,
                            )
                          : const ColoredBox(
                              color: TvDesignTokens.surfaceElevated,
                              child: Icon(Icons.movie_outlined,
                                  color: TvDesignTokens.textDisabled),
                            ),
                      if (_episodeProgress(ep) > 0)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: LinearProgressIndicator(
                            value: _episodeProgress(ep),
                            minHeight: 4,
                            backgroundColor: Colors.black54,
                            valueColor: const AlwaysStoppedAnimation(
                                TvDesignTokens.brand),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: TvDesignTokens.spacingMd),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${ep.indexNumber != null ? '${ep.indexNumber}. ' : ''}${ep.name}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: TvDesignTokens.fontSizeMd,
                        color: TvDesignTokens.textPrimary,
                      ),
                    ),
                    if (ep.overview != null && ep.overview!.isNotEmpty) ...[
                      const SizedBox(height: TvDesignTokens.spacingXs),
                      Text(
                        ep.overview!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: TvDesignTokens.fontSizeXs,
                          color: TvDesignTokens.textSecondary,
                          height: TvDesignTokens.lineHeightNormal,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: TvDesignTokens.spacingMd),
              Icon(
                watched ? Icons.check_circle : Icons.play_circle_outline,
                color: watched
                    ? TvDesignTokens.success
                    : TvDesignTokens.brand,
                size: 32,
              ),
            ],
          ),
        ),
      ),
    );
  }

  double _episodeProgress(Episode ep) {
    if (ep.userData?.played ?? false) return 0;
    final pos = ep.userData?.playbackPositionTicks ?? 0;
    final total = ep.runTimeTicks ?? 0;
    if (total <= 0 || pos <= 0) return 0;
    final p = pos / total;
    return p > 0.98 ? 0 : p.clamp(0.0, 1.0).toDouble();
  }

  String? _episodeImageUrl(ApiClientFactory api, Episode ep) {
    if (ep.primaryImageTag != null) {
      return api.image
          .getPrimaryImageUrl(ep.id, tag: ep.primaryImageTag, maxWidth: 400);
    }
    if (ep.thumbImageTag != null) {
      return api.image
          .getThumbImageUrl(ep.id, tag: ep.thumbImageTag, maxWidth: 400);
    }
    return null;
  }

  Widget _errorScaffold(String msg) => Scaffold(
        backgroundColor: TvDesignTokens.background,
        body: _errorBody(msg),
      );

  Widget _errorBody(String msg) => Center(
        child: Text(
          msg,
          style: const TextStyle(
            color: TvDesignTokens.textSecondary,
            fontSize: TvDesignTokens.fontSizeMd,
          ),
        ),
      );
}
