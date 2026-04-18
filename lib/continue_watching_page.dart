import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:lin_player_server_adapters/lin_player_server_adapters.dart';
import 'package:lin_player_state/lin_player_state.dart';
import 'package:lin_player_ui/lin_player_ui.dart';

import 'server_adapters/server_access.dart';
import 'show_detail_page.dart';

enum ContinueWatchingMenuAction {
  remove,
  toggleFavorite,
  markPlayed,
}

class ContinueWatchingActionResult {
  const ContinueWatchingActionResult({
    required this.message,
    this.updatedItem,
  });

  final String message;
  final MediaItem? updatedItem;
}

class ContinueWatchingActions {
  static Future<ContinueWatchingMenuAction?> showMenu(
    BuildContext context, {
    required Offset globalPosition,
    required bool favorite,
  }) {
    final media = MediaQuery.of(context);
    const menuWidth = 216.0;
    const menuHeight = 176.0;
    const margin = 12.0;
    final left = globalPosition.dx
        .clamp(margin, media.size.width - menuWidth - margin)
        .toDouble();
    final top = globalPosition.dy
        .clamp(
          media.padding.top + margin,
          media.size.height - media.padding.bottom - menuHeight - margin,
        )
        .toDouble();

    return showGeneralDialog<ContinueWatchingMenuAction>(
      context: context,
      barrierLabel: '继续观看操作',
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.16),
      transitionDuration: const Duration(milliseconds: 140),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return Stack(
          children: [
            Positioned(
              left: left,
              top: top,
              child: FadeTransition(
                opacity: curved,
                child: ScaleTransition(
                  scale: Tween<double>(
                    begin: 0.96,
                    end: 1,
                  ).animate(curved),
                  alignment: Alignment.topLeft,
                  child: _ContinueWatchingContextMenu(
                    favorite: favorite,
                    onSelected: (action) =>
                        Navigator.of(dialogContext).pop(action),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  static Future<ContinueWatchingActionResult> perform({
    required AppState appState,
    required MediaItem item,
    required ContinueWatchingMenuAction action,
  }) async {
    final access = resolveServerAccess(appState: appState);
    if (access == null) {
      throw Exception('当前服务器未连接');
    }

    switch (action) {
      case ContinueWatchingMenuAction.remove:
        await access.adapter.hideFromResume(access.auth, itemId: item.id);
        await appState.removeContinueWatchingEntry(item: item);
        unawaited(appState.loadHome(forceRefresh: true));
        return const ContinueWatchingActionResult(
          message: '已从继续观看中移除',
        );
      case ContinueWatchingMenuAction.toggleFavorite:
        final nextFavorite = !item.favorite;
        await access.adapter.setFavorite(
          access.auth,
          itemId: item.id,
          favorite: nextFavorite,
        );
        final updatedItem = _copyItemWithUserData(
          item,
          favorite: nextFavorite,
        );
        await appState.updateContinueWatchingItem(item: updatedItem);
        unawaited(appState.loadHome(forceRefresh: true));
        return ContinueWatchingActionResult(
          message: nextFavorite ? '已添加到收藏' : '已从收藏中移除',
          updatedItem: updatedItem,
        );
      case ContinueWatchingMenuAction.markPlayed:
        if (!item.played) {
          await access.adapter.updatePlaybackPosition(
            access.auth,
            itemId: item.id,
            positionTicks: 0,
            played: true,
          );
          await appState.updateContinueWatchingAfterPlaybackMark(
            item: item,
            played: true,
          );
          unawaited(appState.loadHome(forceRefresh: true));
        }
        return const ContinueWatchingActionResult(
          message: '已标记为已播放',
        );
    }
  }

  static MediaItem _copyItemWithUserData(
    MediaItem item, {
    bool? favorite,
    bool? played,
    int? playbackPositionTicks,
  }) {
    final json = item.toJson();
    final userData =
        Map<String, dynamic>.from(json['UserData'] as Map? ?? const {});
    if (favorite != null) {
      userData['IsFavorite'] = favorite;
    }
    if (played != null) {
      userData['Played'] = played;
    }
    if (playbackPositionTicks != null) {
      userData['PlaybackPositionTicks'] = playbackPositionTicks;
    }
    json['UserData'] = userData;
    return MediaItem.fromJson(json);
  }
}

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
      if (mounted) {
        setState(() => _loading = false);
      }
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
          Text(_error!, textAlign: TextAlign.center),
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

class ContinueWatchingGrid extends StatefulWidget {
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
  State<ContinueWatchingGrid> createState() => _ContinueWatchingGridState();
}

class _ContinueWatchingGridState extends State<ContinueWatchingGrid> {
  late List<MediaItem> _items;
  final Set<String> _busyItemIds = <String>{};

  @override
  void initState() {
    super.initState();
    _items = List<MediaItem>.of(widget.items);
  }

  @override
  void didUpdateWidget(covariant ContinueWatchingGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_sameItems(oldWidget.items, widget.items)) {
      _items = List<MediaItem>.of(widget.items);
    }
  }

  bool _sameItems(List<MediaItem> a, List<MediaItem> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      final left = a[i];
      final right = b[i];
      if (left.id != right.id ||
          left.favorite != right.favorite ||
          left.played != right.played ||
          left.playbackPositionTicks != right.playbackPositionTicks) {
        return false;
      }
    }
    return true;
  }

  Future<void> _handleLongPress({
    required MediaItem item,
    required Offset globalPosition,
  }) async {
    if (_busyItemIds.contains(item.id)) return;

    final action = await ContinueWatchingActions.showMenu(
      context,
      globalPosition: globalPosition,
      favorite: item.favorite,
    );
    if (action == null || !mounted) return;

    setState(() => _busyItemIds.add(item.id));
    try {
      final result = await ContinueWatchingActions.perform(
        appState: widget.appState,
        item: item,
        action: action,
      );
      if (!mounted) return;
      setState(() {
        _items = List<MediaItem>.of(widget.appState.continueWatching);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.message),
          duration: const Duration(milliseconds: 1400),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('操作失败：$e')),
      );
    } finally {
      if (mounted) {
        setState(() => _busyItemIds.remove(item.id));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final limitedItems = widget.maxItems == null || widget.maxItems! >= _items.length
        ? _items
        : _items.take(widget.maxItems!).toList(growable: false);

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final resolvedPadding = widget.padding.resolve(Directionality.of(context));
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
          shrinkWrap: widget.shrinkWrap,
          physics: widget.physics,
          padding: widget.padding,
          itemCount: limitedItems.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: spacing,
            crossAxisSpacing: spacing,
            childAspectRatio: aspectRatio,
          ),
          itemBuilder: (context, index) {
            final item = limitedItems[index];
            return _ContinueWatchingCard(
              item: item,
              appState: widget.appState,
              busy: _busyItemIds.contains(item.id),
              onLongPressStart: (details) => _handleLongPress(
                item: item,
                globalPosition: details.globalPosition,
              ),
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
    required this.busy,
    required this.onLongPressStart,
  });

  final MediaItem item;
  final AppState appState;
  final bool busy;
  final GestureLongPressStartCallback onLongPressStart;

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
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPressStart: busy ? null : onLongPressStart,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: busy ? null : openDetail,
          child: Stack(
            children: [
              Column(
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
              if (busy)
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2.4),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ContinueWatchingContextMenu extends StatelessWidget {
  const _ContinueWatchingContextMenu({
    required this.favorite,
    required this.onSelected,
  });

  final bool favorite;
  final ValueChanged<ContinueWatchingMenuAction> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final background = Color.alphaBlend(
      Colors.black.withValues(alpha: theme.brightness == Brightness.dark ? 0.24 : 0.08),
      scheme.surface.withValues(alpha: 0.92),
    );

    return Material(
      color: Colors.transparent,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            width: 216,
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.16),
                  blurRadius: 24,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ContinueWatchingContextAction(
                  icon: Icons.remove_circle_outline_rounded,
                  label: '从继续观看中移除',
                  color: scheme.error,
                  onTap: () => onSelected(ContinueWatchingMenuAction.remove),
                ),
                _ContinueWatchingMenuDivider(color: scheme.outlineVariant),
                _ContinueWatchingContextAction(
                  icon: favorite
                      ? Icons.favorite_border_rounded
                      : Icons.favorite_rounded,
                  label: favorite ? '从收藏中移除' : '添加到收藏',
                  color: favorite ? scheme.secondary : const Color(0xFFE11D48),
                  onTap: () =>
                      onSelected(ContinueWatchingMenuAction.toggleFavorite),
                ),
                _ContinueWatchingMenuDivider(color: scheme.outlineVariant),
                _ContinueWatchingContextAction(
                  icon: Icons.check_circle_outline_rounded,
                  label: '标记为已播放',
                  color: const Color(0xFF16A34A),
                  onTap: () => onSelected(ContinueWatchingMenuAction.markPlayed),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ContinueWatchingContextAction extends StatelessWidget {
  const _ContinueWatchingContextAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ContinueWatchingMenuDivider extends StatelessWidget {
  const _ContinueWatchingMenuDivider({
    required this.color,
  });

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 1,
      margin: const EdgeInsets.symmetric(horizontal: 14),
      color: color.withValues(alpha: 0.3),
    );
  }
}
