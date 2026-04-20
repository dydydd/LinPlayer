import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:lin_player_server_adapters/lin_player_server_adapters.dart';
import 'package:lin_player_state/lin_player_state.dart';
import 'package:lin_player_ui/lin_player_ui.dart';

import 'mobile_ui/common/mobile_shell_page.dart';
import 'server_adapters/server_access.dart';
import 'show_detail_page.dart';

class AggregateServicePage extends StatefulWidget {
  const AggregateServicePage({
    super.key,
    required this.appState,
    this.initialTabIndex,
    this.initialQuery = '',
    this.embeddedInShell = false,
  });

  final AppState appState;
  final int? initialTabIndex;
  final String initialQuery;
  final bool embeddedInShell;

  @override
  State<AggregateServicePage> createState() => _AggregateServicePageState();
}

class _AggregateServicePageState extends State<AggregateServicePage> {
  PreferredSizeWidget _buildRootTabBar(
    BuildContext context, {
    bool embedded = false,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = scheme.brightness == Brightness.dark;

    return PreferredSize(
      preferredSize: const Size.fromHeight(50),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(
            alpha: embedded ? (isDark ? 0.46 : 0.72) : (isDark ? 0.74 : 0.92),
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: TabBar(
            dividerColor: Colors.transparent,
            indicatorSize: TabBarIndicatorSize.tab,
            indicatorPadding: EdgeInsets.zero,
            splashBorderRadius: BorderRadius.circular(16),
            labelPadding: EdgeInsets.zero,
            labelStyle: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: -0.1,
            ),
            unselectedLabelStyle: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
            labelColor: scheme.onPrimaryContainer,
            unselectedLabelColor: scheme.onSurfaceVariant,
            indicator: BoxDecoration(
              color: scheme.primaryContainer.withValues(
                alpha: isDark ? 0.88 : 0.94,
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: scheme.shadow.withValues(alpha: isDark ? 0.14 : 0.08),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                  spreadRadius: -12,
                ),
              ],
            ),
            tabs: const [
              SizedBox(
                height: 42,
                child: Center(child: Text('观看记录')),
              ),
              SizedBox(
                height: 42,
                child: Center(child: Text('聚合搜索')),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isTv = DeviceType.isTv;
    final enableBlur = !isTv && widget.appState.enableBlurEffects;
    final effectiveInitialIndex =
        (widget.initialTabIndex ?? (widget.initialQuery.trim().isEmpty ? 0 : 1))
            .clamp(0, 1)
            .toInt();
    final body = TabBarView(
      children: [
        _AggregateWatchHistoryTab(appState: widget.appState),
        _AggregateSearchTab(
          appState: widget.appState,
          initialQuery: widget.initialQuery,
        ),
      ],
    );

    return DefaultTabController(
      length: 2,
      initialIndex: effectiveInitialIndex,
      child: widget.embeddedInShell
          ? Builder(
              builder: (context) {
                final colorScheme = Theme.of(context).colorScheme;

                return MobileShellPageFrame(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        colorScheme.surface,
                        colorScheme.surfaceContainerLowest,
                      ],
                    ),
                  ),
                  header: MobileShellPageHeader(
                    title: '聚合服务',
                    subtitle: '观看记录与跨服搜索',
                    enableBlur: enableBlur,
                    bottom: _buildRootTabBar(context, embedded: true),
                  ),
                  child: body,
                );
              },
            )
          : Scaffold(
              appBar: GlassAppBar(
                enableBlur: enableBlur,
                child: AppBar(
                  title: const Text('\u805a\u5408\u670d\u52a1'),
                  bottom: _buildRootTabBar(context),
                ),
              ),
              body: body,
            ),
    );
  }
}

class _ServerContinueWatchingState {
  final bool loading;
  final String? error;
  final List<MediaItem> items;

  const _ServerContinueWatchingState({
    required this.loading,
    required this.error,
    required this.items,
  });
}

class _AggregateServerSearchSection {
  const _AggregateServerSearchSection({
    required this.server,
    required this.items,
  });

  final ServerProfile server;
  final List<MediaItem> items;
}

bool _useCompactAggregateLayout(BuildContext context) =>
    !DeviceType.isTv && MediaQuery.sizeOf(context).shortestSide < 700;

class _AggregateWatchHistoryTab extends StatefulWidget {
  const _AggregateWatchHistoryTab({required this.appState});

  final AppState appState;

  @override
  State<_AggregateWatchHistoryTab> createState() =>
      _AggregateWatchHistoryTabState();
}

class _AggregateWatchHistoryTabState extends State<_AggregateWatchHistoryTab> {
  static const _limit = 60;
  int _loadSeq = 0;
  final Map<String, _ServerContinueWatchingState> _stateByServer = {};

  @override
  void initState() {
    super.initState();
    unawaited(_reload());
  }

  Future<void> _reload() async {
    final seq = ++_loadSeq;
    final servers = widget.appState.servers;
    setState(() {
      for (final s in servers) {
        final prev = _stateByServer[s.id];
        _stateByServer[s.id] = _ServerContinueWatchingState(
          loading: true,
          error: null,
          items: prev?.items ?? const [],
        );
      }
    });

    await Future.wait<void>(
      servers.map((s) => _loadOne(s, seq)),
    );
  }

  Future<void> _loadOne(ServerProfile server, int seq) async {
    final baseUrl = server.baseUrl.trim();
    final token = server.token.trim();
    final userId = server.userId.trim();
    if (baseUrl.isEmpty || token.isEmpty || userId.isEmpty) {
      if (!mounted || seq != _loadSeq) return;
      setState(() {
        _stateByServer[server.id] = const _ServerContinueWatchingState(
          loading: false,
          error: '服务器信息不完整',
          items: [],
        );
      });
      return;
    }

    final access =
        resolveServerAccess(appState: widget.appState, server: server);
    if (access == null) {
      if (!mounted || seq != _loadSeq) return;
      setState(() {
        _stateByServer[server.id] = const _ServerContinueWatchingState(
          loading: false,
          error: 'Unsupported server',
          items: [],
        );
      });
      return;
    }

    try {
      final res = await access.adapter
          .fetchContinueWatching(access.auth, limit: _limit);
      if (!mounted || seq != _loadSeq) return;
      setState(() {
        _stateByServer[server.id] = _ServerContinueWatchingState(
          loading: false,
          error: null,
          items: res.items,
        );
      });
    } catch (e) {
      if (!mounted || seq != _loadSeq) return;
      setState(() {
        _stateByServer[server.id] = _ServerContinueWatchingState(
          loading: false,
          error: e.toString(),
          items: const [],
        );
      });
    }
  }

  Duration _ticksToDuration(int ticks) =>
      Duration(microseconds: (ticks / 10).round());

  String _fmtClock(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  String _episodeTag(MediaItem item) {
    final s = item.seasonNumber ?? 0;
    final e = item.episodeNumber ?? 0;
    if (s <= 0 && e <= 0) return '';
    if (s > 0 && e > 0) {
      return 'S${s.toString().padLeft(2, '0')}E${e.toString().padLeft(2, '0')}';
    }
    if (e > 0) return 'E${e.toString().padLeft(2, '0')}';
    return 'S${s.toString().padLeft(2, '0')}';
  }

  List<MediaItem> _latestWatchPerSeries(List<MediaItem> items) {
    final visible = items.where((e) => e.playbackPositionTicks > 0).toList();
    if (visible.isEmpty) return const [];

    final seenSeries = <String>{};
    final result = <MediaItem>[];
    for (final item in visible) {
      final isEpisode = item.type.toLowerCase() == 'episode';
      if (!isEpisode) {
        result.add(item);
        continue;
      }

      final seriesId = item.seriesId?.trim() ?? '';
      final seriesName = item.seriesName.trim();
      final seriesKey = seriesId.isNotEmpty
          ? seriesId
          : (seriesName.isNotEmpty
              ? 'name:${seriesName.toLowerCase()}'
              : item.id);

      if (seenSeries.add(seriesKey)) {
        result.add(item);
      }
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final servers = widget.appState.servers;
    final isTv = DeviceType.isTv;
    final useCompactLayout = _useCompactAggregateLayout(context);

    if (servers.isEmpty) {
      return const Center(child: Text('暂无服务器'));
    }

    if (useCompactLayout) {
      return RefreshIndicator(
        onRefresh: _reload,
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
          itemCount: servers.length,
          separatorBuilder: (_, __) => const SizedBox(height: 14),
          itemBuilder: (context, index) {
            final server = servers[index];
            final state = _stateByServer[server.id] ??
                const _ServerContinueWatchingState(
                  loading: true,
                  error: null,
                  items: [],
                );
            final visibleItems = _latestWatchPerSeries(state.items);
            final access = resolveServerAccess(
              appState: widget.appState,
              server: server,
            );
            final cardWidth = ((MediaQuery.sizeOf(context).width - 64) / 3.15)
                .clamp(92.0, 118.0)
                .toDouble();
            final rowHeight = cardWidth / (2 / 3) + 52;

            return _AggregateSectionSurface(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _AggregateServerHeader(
                      server: server,
                      trailing: state.loading
                          ? Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '更新中',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant,
                                        fontWeight: FontWeight.w600,
                                      ),
                                ),
                              ],
                            )
                          : Text(
                              visibleItems.isEmpty
                                  ? '暂无记录'
                                  : '${visibleItems.length} 条',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                    ),
                    const SizedBox(height: 14),
                    if (state.error != null)
                      Text(
                        state.error!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.error,
                              fontWeight: FontWeight.w600,
                            ),
                      )
                    else if (state.loading && visibleItems.isEmpty)
                      const SizedBox(
                        height: 108,
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (visibleItems.isEmpty)
                      Text(
                        '这个服务器还没有观看记录',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                      )
                    else
                      SizedBox(
                        height: rowHeight,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: visibleItems.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(width: 10),
                          itemBuilder: (context, i) {
                            final item = visibleItems[i];
                            final isEpisode =
                                item.type.toLowerCase() == 'episode';
                            final title =
                                isEpisode && item.seriesName.trim().isNotEmpty
                                    ? item.seriesName.trim()
                                    : item.name;
                            final pos =
                                _ticksToDuration(item.playbackPositionTicks);
                            final tag = isEpisode ? _episodeTag(item) : '';
                            final captionParts = <String>[
                              if (tag.isNotEmpty) tag,
                              if (pos > Duration.zero) '看到 ${_fmtClock(pos)}',
                            ];

                            return SizedBox(
                              width: cardWidth,
                              child: _AggregatePosterCard(
                                item: item,
                                access: access,
                                titleOverride: title,
                                caption: captionParts.join(' · '),
                                onTap: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => isEpisode
                                          ? EpisodeDetailPage(
                                              episode: item,
                                              appState: widget.appState,
                                              server: server,
                                              isTv: false,
                                            )
                                          : ShowDetailPage(
                                              itemId: item.id,
                                              title: item.name,
                                              appState: widget.appState,
                                              server: server,
                                              isTv: false,
                                            ),
                                    ),
                                  );
                                },
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView.builder(
        padding: const EdgeInsets.only(bottom: 24),
        itemCount: servers.length,
        itemBuilder: (context, index) {
          final server = servers[index];
          final state = _stateByServer[server.id] ??
              const _ServerContinueWatchingState(
                loading: true,
                error: null,
                items: [],
              );

          final visibleItems = _latestWatchPerSeries(state.items);
          final headerSubtitle = state.loading
              ? '加载中…'
              : (state.error != null
                  ? '加载失败'
                  : (visibleItems.isEmpty
                      ? '暂无记录'
                      : '${visibleItems.length} 条'));

          return ExpansionTile(
            initiallyExpanded: index == 0,
            leading: ServerIconAvatar(
              iconUrl: server.iconUrl,
              name: server.name,
              radius: 18,
            ),
            title:
                Text(server.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(headerSubtitle),
            childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            children: [
              if (state.error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    state.error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 12,
                    ),
                  ),
                )
              else if (visibleItems.isEmpty && !state.loading)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Text('暂无观看记录'),
                )
              else if (state.loading && visibleItems.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Center(child: CircularProgressIndicator()),
                )
              else
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: visibleItems.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final item = visibleItems[i];
                    final isEpisode = item.type.toLowerCase() == 'episode';
                    final title = isEpisode && item.seriesName.trim().isNotEmpty
                        ? item.seriesName
                        : item.name;
                    final pos = _ticksToDuration(item.playbackPositionTicks);
                    final tag = isEpisode ? _episodeTag(item) : '';
                    final subParts = <String>[
                      if (tag.isNotEmpty) tag,
                      if (pos > Duration.zero) '续播 ${_fmtClock(pos)}',
                    ];
                    final subtitle = subParts.join(' · ');

                    final access = resolveServerAccess(
                      appState: widget.appState,
                      server: server,
                    );
                    final img = item.hasImage && access != null
                        ? access.adapter.imageUrl(
                            access.auth,
                            itemId: item.id,
                            imageType: 'Primary',
                            maxWidth: 320,
                          )
                        : '';

                    return Card(
                      clipBehavior: Clip.antiAlias,
                      child: ListTile(
                        leading: img.isEmpty
                            ? const SizedBox(
                                width: 56,
                                height: 56,
                                child: Icon(Icons.image_outlined),
                              )
                            : ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: CachedNetworkImage(
                                  imageUrl: img,
                                  cacheManager: CoverCacheManager.instance,
                                  httpHeaders: {
                                    'User-Agent':
                                        LinHttpClientFactory.userAgent,
                                  },
                                  width: 56,
                                  height: 56,
                                  fit: BoxFit.cover,
                                  placeholder: (_, __) => const SizedBox(
                                    width: 56,
                                    height: 56,
                                    child: ColoredBox(
                                      color: Colors.black12,
                                      child: Center(
                                        child: Icon(Icons.image_outlined),
                                      ),
                                    ),
                                  ),
                                  errorWidget: (_, __, ___) => const SizedBox(
                                    width: 56,
                                    height: 56,
                                    child: Center(
                                      child: Icon(Icons.broken_image_outlined),
                                    ),
                                  ),
                                ),
                              ),
                        title: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: subtitle.isEmpty ? null : Text(subtitle),
                        trailing: state.loading
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : null,
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => isEpisode
                                  ? EpisodeDetailPage(
                                      episode: item,
                                      appState: widget.appState,
                                      server: server,
                                      isTv: isTv,
                                    )
                                  : ShowDetailPage(
                                      itemId: item.id,
                                      title: item.name,
                                      appState: widget.appState,
                                      server: server,
                                      isTv: isTv,
                                    ),
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
            ],
          );
        },
      ),
    );
  }
}

class _AggregateSearchTab extends StatelessWidget {
  const _AggregateSearchTab({
    required this.appState,
    this.initialQuery = '',
  });

  final AppState appState;
  final String initialQuery;

  @override
  Widget build(BuildContext context) => _AggregateSearchTabStateful(
        appState: appState,
        initialQuery: initialQuery,
      );
}

class _ServerSearchHit {
  final ServerProfile server;
  final MediaItem item;

  const _ServerSearchHit({required this.server, required this.item});
}

class _WorkGroup {
  final String key;
  final String title;
  final String type; // Series / Movie
  final int? year;
  final List<_ServerSearchHit> hits;

  const _WorkGroup({
    required this.key,
    required this.title,
    required this.type,
    required this.year,
    required this.hits,
  });
}

class _LatestEpisodeResult {
  final MediaItem episode;

  const _LatestEpisodeResult(this.episode);

  int get seasonNumber => episode.seasonNumber ?? 0;
  int get episodeNumber => episode.episodeNumber ?? 0;
}

typedef _LatestEpisodeResolver = Future<_LatestEpisodeResult?> Function(
  ServerProfile server,
  String seriesId,
);

class _AggregateSearchTabStateful extends StatefulWidget {
  const _AggregateSearchTabStateful({
    required this.appState,
    this.initialQuery = '',
  });

  final AppState appState;
  final String initialQuery;

  @override
  State<_AggregateSearchTabStateful> createState() =>
      _AggregateSearchTabStatefulState();
}

class _AggregateSearchTabStatefulState
    extends State<_AggregateSearchTabStateful> {
  static const _searchLimitPerServer = 40;
  static const _debounceMs = 1500;

  final TextEditingController _controller = TextEditingController();
  Timer? _debounce;
  int _searchSeq = 0;

  bool _loading = false;
  String? _error;
  List<_WorkGroup> _groups = const [];
  List<_AggregateServerSearchSection> _serverSections = const [];
  Map<String, String> _serverErrors = const {};

  final Map<String, Future<_LatestEpisodeResult?>> _latestEpisodeFutures = {};
  final Map<String, _LatestEpisodeResult?> _latestEpisodeCache = {};

  @override
  void initState() {
    super.initState();

    final initial = widget.initialQuery.trim();
    if (initial.isNotEmpty) {
      _controller.value = TextEditingValue(
        text: initial,
        selection: TextSelection.collapsed(offset: initial.length),
      );
      _scheduleSearch(initial, immediate: true);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _scheduleSearch(String query, {bool immediate = false}) {
    _debounce?.cancel();
    if (immediate) {
      unawaited(_doSearch(query));
      return;
    }
    _debounce = Timer(const Duration(milliseconds: _debounceMs), () {
      unawaited(_doSearch(query));
    });
  }

  static int? _yearOf(MediaItem item) {
    final d = (item.premiereDate ?? '').trim();
    if (d.isEmpty) return null;
    final parsed = DateTime.tryParse(d);
    if (parsed != null) return parsed.year;
    if (d.length >= 4) {
      final y = int.tryParse(d.substring(0, 4));
      if (y != null && y > 1800 && y < 2200) return y;
    }
    return null;
  }

  List<MediaItem> _filterVisibleItems(
    Iterable<MediaItem> items, {
    required Set<String> hiddenLibraries,
    required String query,
  }) {
    final visibleItems = items.where((item) {
      final type = item.type.toLowerCase();
      if (type != 'series' && type != 'movie') return false;

      final parentId = (item.parentId ?? '').trim();
      if (parentId.isNotEmpty && hiddenLibraries.contains(parentId)) {
        return false;
      }
      return true;
    }).toList(growable: false);

    final normalizedQuery = query.toLowerCase();
    final exactMatches = visibleItems
        .where((item) => item.name.trim().toLowerCase() == normalizedQuery)
        .toList(growable: false);

    return exactMatches.isNotEmpty ? exactMatches : visibleItems;
  }

  static String _normalizeTitle(String raw) {
    var t = raw.trim().toLowerCase();
    if (t.isEmpty) return '';
    t = t.replaceAll(RegExp(r'\s+'), '');
    t = t.replaceAll("'", '');
    t = t.replaceAll(
      RegExp(
        r'[\-_·•:：/\\|｜()（）\[\]【】{}「」“”"’!?！？,，.。]',
      ),
      '',
    );
    return t;
  }

  static int? _seasonFromTitle(String raw) {
    final s = raw.toLowerCase();
    final cn = RegExp(r'第\s*(\d{1,2})\s*季');
    final cnM = cn.firstMatch(s);
    if (cnM != null) return int.tryParse(cnM.group(1) ?? '');
    final en = RegExp(r'season\s*(\d{1,2})');
    final enM = en.firstMatch(s);
    if (enM != null) return int.tryParse(enM.group(1) ?? '');
    final sx = RegExp(r'\bs(\d{1,2})\b');
    final sxM = sx.firstMatch(s);
    if (sxM != null) return int.tryParse(sxM.group(1) ?? '');
    return null;
  }

  static String _providerKey(Map<String, String> providerIds) {
    if (providerIds.isEmpty) return '';
    String? pick(String contains) {
      for (final e in providerIds.entries) {
        if (e.key.toLowerCase().contains(contains) &&
            e.value.trim().isNotEmpty) {
          return e.value.trim();
        }
      }
      return null;
    }

    final tmdb = pick('tmdb');
    if (tmdb != null) return 'tmdb:$tmdb';
    final imdb = pick('imdb');
    if (imdb != null) return 'imdb:$imdb';
    final douban = pick('douban');
    if (douban != null) return 'douban:$douban';
    return '';
  }

  static String _workKeyFor(MediaItem item) {
    final type = item.type.trim().toLowerCase();
    final pk = _providerKey(item.providerIds);
    if (pk.isNotEmpty) return '$type|$pk';

    final year = _yearOf(item);
    final season = _seasonFromTitle(item.name);
    final title = _normalizeTitle(item.name);
    return '$type|$title|${year ?? ''}|${season ?? ''}';
  }

  Future<_LatestEpisodeResult?> _fetchLatestEpisode(
    ServerProfile server,
    String seriesId,
  ) async {
    final baseUrl = server.baseUrl.trim();
    final token = server.token.trim();
    final userId = server.userId.trim();
    if (baseUrl.isEmpty || token.isEmpty || userId.isEmpty) return null;

    final access =
        resolveServerAccess(appState: widget.appState, server: server);
    if (access == null) return null;

    final res = await access.adapter.fetchItems(
      access.auth,
      parentId: seriesId,
      includeItemTypes: 'Episode',
      recursive: true,
      excludeFolders: true,
      limit: 1,
      sortBy: 'DateCreated',
      sortOrder: 'Descending',
    );
    if (res.items.isEmpty) return null;
    return _LatestEpisodeResult(res.items.first);
  }

  Future<_LatestEpisodeResult?> _resolveLatestEpisode(
    ServerProfile server,
    String seriesId,
  ) {
    final key = '${server.id}:$seriesId';
    final cached = _latestEpisodeCache[key];
    if (_latestEpisodeCache.containsKey(key)) {
      return Future.value(cached);
    }
    final existing = _latestEpisodeFutures[key];
    if (existing != null) return existing;

    final future = _fetchLatestEpisode(server, seriesId).then((value) {
      _latestEpisodeCache[key] = value;
      return value;
    });
    _latestEpisodeFutures[key] = future;
    future.whenComplete(() {
      if (mounted) setState(() {});
    });
    return future;
  }

  static int _progressScore(_LatestEpisodeResult? r) {
    if (r == null) return 0;
    return r.seasonNumber * 10000 + r.episodeNumber;
  }

  static String _episodeTag(_LatestEpisodeResult? r) {
    if (r == null) return '更新未知';
    final s = r.seasonNumber;
    final e = r.episodeNumber;
    if (s <= 0 && e <= 0) return '更新未知';
    if (s > 0 && e > 0) {
      return '更新至 S${s.toString().padLeft(2, '0')}E${e.toString().padLeft(2, '0')}';
    }
    if (e > 0) return '更新至 E${e.toString().padLeft(2, '0')}';
    return '更新至 S${s.toString().padLeft(2, '0')}';
  }

  Future<void> _doSearch(String raw) async {
    final query = raw.trim();
    final seq = ++_searchSeq;

    if (query.isEmpty) {
      setState(() {
        _loading = false;
        _error = null;
        _groups = const [];
        _serverSections = const [];
        _serverErrors = const {};
      });
      return;
    }

    final servers = widget.appState.servers;
    if (servers.isEmpty) {
      setState(() {
        _loading = false;
        _error = '暂无服务器';
        _groups = const [];
        _serverSections = const [];
        _serverErrors = const {};
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _serverErrors = const {};
    });

    final hits = <_ServerSearchHit>[];
    final sectionItemsByServer = <String, List<MediaItem>>{};
    final serverErrors = <String, String>{};

    await Future.wait<void>(
      servers.map((server) async {
        final baseUrl = server.baseUrl.trim();
        final token = server.token.trim();
        final userId = server.userId.trim();
        if (baseUrl.isEmpty || token.isEmpty || userId.isEmpty) {
          serverErrors[server.id] = '服务器信息不完整';
          return;
        }
        try {
          final access =
              resolveServerAccess(appState: widget.appState, server: server);
          if (access == null) {
            serverErrors[server.id] = 'Unsupported server';
            return;
          }

          final res = await access.adapter.fetchItems(
            access.auth,
            searchTerm: query,
            includeItemTypes: 'Series,Movie',
            recursive: true,
            excludeFolders: false,
            limit: _searchLimitPerServer,
            sortBy: 'SortName',
            sortOrder: 'Ascending',
          );
          final items = _filterVisibleItems(
            res.items,
            hiddenLibraries: server.hiddenLibraries,
            query: query,
          );
          if (items.isNotEmpty) {
            sectionItemsByServer[server.id] = items;
          }
          for (final item in items) {
            hits.add(_ServerSearchHit(server: server, item: item));
          }
        } catch (e) {
          serverErrors[server.id] = e.toString();
        }
      }),
    );

    if (!mounted || seq != _searchSeq) return;

    final sections = <_AggregateServerSearchSection>[
      for (final server in servers)
        if ((sectionItemsByServer[server.id] ?? const <MediaItem>[]).isNotEmpty)
          _AggregateServerSearchSection(
            server: server,
            items: sectionItemsByServer[server.id]!,
          ),
    ];

    if (hits.isEmpty) {
      final allFailed = serverErrors.length == servers.length;
      setState(() {
        _loading = false;
        _error = allFailed ? '聚合搜索失败' : null;
        _groups = const [];
        _serverSections = sections;
        _serverErrors = serverErrors;
      });
      return;
    }

    final grouped = <String, List<_ServerSearchHit>>{};
    for (final hit in hits) {
      final key = _workKeyFor(hit.item);
      grouped.putIfAbsent(key, () => <_ServerSearchHit>[]).add(hit);
    }

    final groups = <_WorkGroup>[];
    for (final entry in grouped.entries) {
      final list = entry.value;
      if (list.isEmpty) continue;
      final first = list.first.item;
      groups.add(
        _WorkGroup(
          key: entry.key,
          title: first.name,
          type: first.type.trim(),
          year: _yearOf(first),
          hits: list,
        ),
      );
    }

    setState(() {
      _loading = false;
      _error = null;
      _groups = groups;
      _serverSections = sections;
      _serverErrors = serverErrors;
    });
  }

  List<_WorkGroup> _sortedGroups(List<_WorkGroup> input) {
    final groups = List<_WorkGroup>.from(input);
    groups.sort((a, b) {
      if (a.type.toLowerCase() == 'series' &&
          b.type.toLowerCase() != 'series') {
        return -1;
      }
      if (a.type.toLowerCase() != 'series' &&
          b.type.toLowerCase() == 'series') {
        return 1;
      }

      if (a.type.toLowerCase() == 'series') {
        int maxScore(_WorkGroup g) {
          var max = 0;
          for (final h in g.hits) {
            final v = _latestEpisodeCache['${h.server.id}:${h.item.id}'];
            final score = _progressScore(v);
            if (score > max) max = score;
          }
          return max;
        }

        final diff = maxScore(b) - maxScore(a);
        if (diff != 0) return diff;
      }

      final t = a.title.compareTo(b.title);
      if (t != 0) return t;
      return (a.year ?? 0).compareTo(b.year ?? 0);
    });
    return groups;
  }

  List<_ServerSearchHit> _sortedHits(_WorkGroup group) {
    final hits = List<_ServerSearchHit>.from(group.hits);
    if (group.type.toLowerCase() != 'series') {
      hits.sort((a, b) => a.server.name.compareTo(b.server.name));
      return hits;
    }

    hits.sort((a, b) {
      final aKey = '${a.server.id}:${a.item.id}';
      final bKey = '${b.server.id}:${b.item.id}';
      final aScore = _progressScore(_latestEpisodeCache[aKey]);
      final bScore = _progressScore(_latestEpisodeCache[bKey]);
      final diff = bScore - aScore;
      if (diff != 0) return diff;
      return a.server.name.compareTo(b.server.name);
    });
    return hits;
  }

  @override
  Widget build(BuildContext context) {
    final isTv = DeviceType.isTv;
    final query = _controller.text.trim();
    final groups = _sortedGroups(_groups);
    final useCompactLayout = _useCompactAggregateLayout(context);

    Widget content;
    if (query.isEmpty) {
      content = const Center(child: Text('输入剧名开始搜索'));
    } else if (useCompactLayout ? _serverSections.isEmpty : _groups.isEmpty) {
      content = _loading
          ? const Center(child: CircularProgressIndicator())
          : const Center(child: Text('没有结果'));
    } else if (useCompactLayout) {
      content = ListView.separated(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        itemCount: _serverSections.length,
        separatorBuilder: (_, __) => const SizedBox(height: 14),
        itemBuilder: (context, index) {
          final section = _serverSections[index];
          final access = resolveServerAccess(
            appState: widget.appState,
            server: section.server,
          );
          final cardWidth = ((MediaQuery.sizeOf(context).width - 64) / 3.15)
              .clamp(92.0, 118.0)
              .toDouble();
          final rowHeight = cardWidth / (2 / 3) + 52;

          return _AggregateSectionSurface(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _AggregateServerHeader(
                    server: section.server,
                    trailing: Text(
                      '${section.items.length} 项',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    height: rowHeight,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: section.items.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 10),
                      itemBuilder: (context, i) {
                        final item = section.items[i];
                        final type = item.type.toLowerCase();
                        final badgeText = type == 'series'
                            ? '剧集'
                            : (type == 'movie' ? '电影' : '');
                        final year = _yearOf(item)?.toString() ?? '';

                        return SizedBox(
                          width: cardWidth,
                          child: _AggregatePosterCard(
                            item: item,
                            access: access,
                            badgeText: badgeText,
                            caption: year,
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => ShowDetailPage(
                                    itemId: item.id,
                                    title: item.name,
                                    appState: widget.appState,
                                    server: section.server,
                                    isTv: false,
                                  ),
                                ),
                              );
                            },
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    } else {
      content = ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        itemCount: groups.length,
        itemBuilder: (context, index) {
          final group = groups[index];
          final hits = _sortedHits(group);

          final badge = group.type.toLowerCase() == 'series'
              ? '剧集'
              : (group.type.toLowerCase() == 'movie' ? '电影' : '');
          final yearText = group.year == null ? '' : group.year.toString();

          _ServerSearchHit? posterHit;
          for (final h in hits) {
            if (h.item.hasImage) {
              posterHit = h;
              break;
            }
          }
          final posterAccess = posterHit == null
              ? null
              : resolveServerAccess(
                  appState: widget.appState,
                  server: posterHit.server,
                );
          final posterUrl = (posterHit != null &&
                  posterAccess != null &&
                  posterHit.item.hasImage)
              ? posterAccess.adapter.imageUrl(
                  posterAccess.auth,
                  itemId: posterHit.item.id,
                  imageType: 'Primary',
                  maxWidth: 320,
                )
              : '';

          final shownHits = hits.length <= 3 ? hits : hits.take(3).toList();

          return Card(
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => _AggregateWorkDetailPage(
                      appState: widget.appState,
                      group: group,
                      isTv: isTv,
                      resolveLatestEpisode: _resolveLatestEpisode,
                      latestEpisodeCache: _latestEpisodeCache,
                    ),
                  ),
                );
              },
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: posterUrl.isEmpty
                          ? const SizedBox(
                              width: 72,
                              height: 104,
                              child: ColoredBox(
                                color: Colors.black12,
                                child:
                                    Center(child: Icon(Icons.image_outlined)),
                              ),
                            )
                          : CachedNetworkImage(
                              imageUrl: posterUrl,
                              cacheManager: CoverCacheManager.instance,
                              httpHeaders: {
                                'User-Agent': LinHttpClientFactory.userAgent,
                              },
                              width: 72,
                              height: 104,
                              fit: BoxFit.cover,
                              placeholder: (_, __) => const SizedBox(
                                width: 72,
                                height: 104,
                                child: ColoredBox(
                                  color: Colors.black12,
                                  child:
                                      Center(child: Icon(Icons.image_outlined)),
                                ),
                              ),
                              errorWidget: (_, __, ___) => const SizedBox(
                                width: 72,
                                height: 104,
                                child: ColoredBox(
                                  color: Colors.black12,
                                  child: Center(
                                      child: Icon(Icons.broken_image_outlined)),
                                ),
                              ),
                            ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  group.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                              ),
                              if (badge.isNotEmpty) ...[
                                const SizedBox(width: 8),
                                MediaLabelBadge(text: badge),
                              ],
                            ],
                          ),
                          if (yearText.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                yearText,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                              ),
                            ),
                          const SizedBox(height: 10),
                          for (final h in shownHits)
                            _ServerProgressRow(
                              hit: h,
                              isSeries: group.type.toLowerCase() == 'series',
                              resolveLatestEpisode: _resolveLatestEpisode,
                              latestEpisodeCache: _latestEpisodeCache,
                            ),
                          if (hits.length > shownHits.length)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(
                                '还有 ${hits.length - shownHits.length} 个服务器…',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    }

    final serverErrorCount = _serverErrors.length;
    final banner = (query.isNotEmpty && serverErrorCount > 0)
        ? Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
            child: Text(
              '部分服务器搜索失败：$serverErrorCount',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          )
        : const SizedBox.shrink();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
          child: TextField(
            controller: _controller,
            decoration: InputDecoration(
              hintText: '聚合搜索（跨服务器）',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _controller.text.trim().isEmpty
                  ? null
                  : IconButton(
                      tooltip: '清空',
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _controller.clear();
                        _scheduleSearch('', immediate: true);
                        setState(() {});
                      },
                    ),
            ),
            textInputAction: TextInputAction.search,
            onChanged: (v) {
              _scheduleSearch(v);
              setState(() {});
            },
            onSubmitted: (v) => _scheduleSearch(v, immediate: true),
          ),
        ),
        banner,
        if (_error != null)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        if (_loading &&
            query.isNotEmpty &&
            (useCompactLayout
                ? _serverSections.isNotEmpty
                : _groups.isNotEmpty))
          const LinearProgressIndicator(minHeight: 2),
        Expanded(child: content),
      ],
    );
  }
}

class _AggregateSectionSurface extends StatelessWidget {
  const _AggregateSectionSurface({
    required this.child,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = scheme.brightness == Brightness.dark;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: isDark
            ? scheme.surfaceContainerHigh.withValues(alpha: 0.9)
            : scheme.surfaceContainerHighest.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(alpha: isDark ? 0.14 : 0.08),
            blurRadius: 24,
            offset: const Offset(0, 12),
            spreadRadius: -14,
          ),
        ],
      ),
      child: child,
    );
  }
}

class _AggregateServerHeader extends StatelessWidget {
  const _AggregateServerHeader({
    required this.server,
    required this.trailing,
  });

  final ServerProfile server;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        ServerIconAvatar(
          iconUrl: server.iconUrl,
          name: server.name,
          radius: 18,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            server.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(width: 12),
        trailing,
      ],
    );
  }
}

class _AggregatePosterCard extends StatelessWidget {
  const _AggregatePosterCard({
    required this.item,
    required this.access,
    required this.onTap,
    this.titleOverride,
    this.caption,
    this.badgeText,
  });

  final MediaItem item;
  final ServerAccess? access;
  final VoidCallback onTap;
  final String? titleOverride;
  final String? caption;
  final String? badgeText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final imageUrl = item.hasImage && access != null
        ? access!.adapter.imageUrl(
            access!.auth,
            itemId: item.id,
            imageType: 'Primary',
            maxWidth: 320,
          )
        : null;
    final title = (titleOverride ?? item.name).trim();
    final meta = (caption ?? '').trim();
    final badge = (badgeText ?? '').trim();

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            AspectRatio(
              aspectRatio: 2 / 3,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: scheme.shadow.withValues(alpha: 0.12),
                      blurRadius: 18,
                      offset: const Offset(0, 10),
                      spreadRadius: -12,
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (imageUrl == null)
                        const ColoredBox(
                          color: Colors.black12,
                          child: Center(child: Icon(Icons.image_outlined)),
                        )
                      else
                        CachedNetworkImage(
                          imageUrl: imageUrl,
                          cacheManager: CoverCacheManager.instance,
                          httpHeaders: {
                            'User-Agent': LinHttpClientFactory.userAgent,
                          },
                          fit: BoxFit.cover,
                          placeholder: (_, __) => const ColoredBox(
                            color: Colors.black12,
                            child: Center(child: Icon(Icons.image_outlined)),
                          ),
                          errorWidget: (_, __, ___) => const ColoredBox(
                            color: Colors.black12,
                            child: Center(
                                child: Icon(Icons.broken_image_outlined)),
                          ),
                          useOldImageOnUrlChange: true,
                          fadeInDuration: Duration.zero,
                          fadeOutDuration: Duration.zero,
                          placeholderFadeInDuration: Duration.zero,
                        ),
                      if (badge.isNotEmpty)
                        Positioned(
                          left: 8,
                          top: 8,
                          child: MediaLabelBadge(text: badge),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              title,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            if (meta.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(
                  meta,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
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

class _ServerProgressRow extends StatelessWidget {
  const _ServerProgressRow({
    required this.hit,
    required this.isSeries,
    required this.resolveLatestEpisode,
    required this.latestEpisodeCache,
  });

  final _ServerSearchHit hit;
  final bool isSeries;
  final _LatestEpisodeResolver resolveLatestEpisode;
  final Map<String, _LatestEpisodeResult?> latestEpisodeCache;

  @override
  Widget build(BuildContext context) {
    final server = hit.server;
    final item = hit.item;

    final key = '${server.id}:${item.id}';
    final cached = latestEpisodeCache[key];
    final future =
        isSeries ? resolveLatestEpisode(server, item.id) : Future.value(null);

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          ServerIconAvatar(
            iconUrl: server.iconUrl,
            name: server.name,
            radius: 12,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              server.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
          const SizedBox(width: 8),
          if (!isSeries)
            Text(
              '可用',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            )
          else if (cached != null)
            Text(
              _AggregateSearchTabStatefulState._episodeTag(cached),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            )
          else
            FutureBuilder<_LatestEpisodeResult?>(
              future: future,
              builder: (context, snap) {
                final r = snap.data;
                if (snap.connectionState == ConnectionState.waiting) {
                  return Text(
                    '获取中…',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  );
                }
                return Text(
                  _AggregateSearchTabStatefulState._episodeTag(r),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                );
              },
            ),
        ],
      ),
    );
  }
}

class _AggregateWorkDetailPage extends StatefulWidget {
  const _AggregateWorkDetailPage({
    required this.appState,
    required this.group,
    required this.isTv,
    required this.resolveLatestEpisode,
    required this.latestEpisodeCache,
  });

  final AppState appState;
  final _WorkGroup group;
  final bool isTv;
  final _LatestEpisodeResolver resolveLatestEpisode;
  final Map<String, _LatestEpisodeResult?> latestEpisodeCache;

  @override
  State<_AggregateWorkDetailPage> createState() =>
      _AggregateWorkDetailPageState();
}

class _AggregateWorkDetailPageState extends State<_AggregateWorkDetailPage> {
  String? _loadingKey;
  final Map<String, Future<List<_MovieSourceInfo>?>> _movieSourcesFutures = {};
  final Map<String, List<_MovieSourceInfo>?> _movieSourcesCache = {};

  static int? _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  static List<Map<String, dynamic>> _streamsOfType(
      Map<String, dynamic> ms, String type) {
    final streams = (ms['MediaStreams'] as List?) ?? const [];
    return streams
        .where((e) => (e as Map)['Type'] == type)
        .map((e) => e as Map<String, dynamic>)
        .toList();
  }

  static int _heightOf(Map<String, dynamic> ms) {
    final videoStreams = _streamsOfType(ms, 'Video');
    final video = videoStreams.isNotEmpty ? videoStreams.first : null;
    return _asInt(video?['Height']) ?? 0;
  }

  static int _bitrateOf(Map<String, dynamic> ms) => _asInt(ms['Bitrate']) ?? 0;

  static int _sizeOf(Map<String, dynamic> ms) {
    final v = ms['Size'];
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }

  static int _compareMovieQuality(_MovieQualityInfo? a, _MovieQualityInfo? b) {
    final aH = a?.height ?? 0;
    final bH = b?.height ?? 0;
    if (aH != bH) return aH.compareTo(bH);
    final aB = a?.bitrate ?? 0;
    final bB = b?.bitrate ?? 0;
    if (aB != bB) return aB.compareTo(bB);
    final aS = a?.sizeBytes ?? 0;
    final bS = b?.sizeBytes ?? 0;
    return aS.compareTo(bS);
  }

  static _MovieQualityInfo? _bestMovieQuality(List<_MovieSourceInfo>? sources) {
    if (sources == null || sources.isEmpty) return null;
    return sources.first.quality;
  }

  Future<List<_MovieSourceInfo>?> _fetchMovieSources(
    ServerProfile server,
    String itemId,
  ) async {
    final access =
        resolveServerAccess(appState: widget.appState, server: server);
    if (access == null) return null;
    final info = await access.adapter.fetchPlaybackInfo(
      access.auth,
      itemId: itemId,
      exoPlayer: false,
    );
    final rawSources = info.mediaSources.cast<Map<String, dynamic>>();
    final sources =
        rawSources.map((ms) => _MovieSourceInfo.fromMediaSource(ms)).toList();
    sources.sort((a, b) {
      final diff = _compareMovieQuality(b.quality, a.quality);
      if (diff != 0) return diff;
      return a.id.compareTo(b.id);
    });
    return sources;
  }

  Future<List<_MovieSourceInfo>?> _resolveMovieSources(
    ServerProfile server,
    String itemId,
  ) {
    final key = '${server.id}:$itemId';
    final cached = _movieSourcesCache.containsKey(key);
    if (cached) return Future.value(_movieSourcesCache[key]);
    final existing = _movieSourcesFutures[key];
    if (existing != null) return existing;

    final future = _fetchMovieSources(server, itemId).then((value) {
      _movieSourcesCache[key] = value;
      return value;
    }).catchError((_) {
      _movieSourcesCache[key] = null;
      return null;
    });
    _movieSourcesFutures[key] = future;
    future.whenComplete(() {
      if (mounted) setState(() {});
    });
    return future;
  }

  static String _fmtSizeBytes(int bytes) {
    if (bytes <= 0) return '';
    const gb = 1024 * 1024 * 1024;
    const mb = 1024 * 1024;
    if (bytes >= gb) return '${(bytes / gb).toStringAsFixed(1)} GB';
    return '${(bytes / mb).toStringAsFixed(0)} MB';
  }

  static String _fmtBitrate(int bitrate) {
    if (bitrate <= 0) return '';
    return '${(bitrate / 1000000).toStringAsFixed(1)} Mbps';
  }

  static String _fmtMovieQuality(_MovieQualityInfo? q) {
    if (q == null) return '可用';
    final parts = <String>[];
    if (q.height > 0) parts.add('${q.height}p');
    final size = _fmtSizeBytes(q.sizeBytes);
    if (size.isNotEmpty) parts.add(size);
    final br = _fmtBitrate(q.bitrate);
    if (br.isNotEmpty) parts.add(br);
    return parts.isEmpty ? '可用' : parts.join(' / ');
  }

  @override
  Widget build(BuildContext context) {
    final isSeries = widget.group.type.toLowerCase() == 'series';
    final hits = List<_ServerSearchHit>.from(widget.group.hits);
    hits.sort((a, b) {
      if (!isSeries) {
        final aKey = '${a.server.id}:${a.item.id}';
        final bKey = '${b.server.id}:${b.item.id}';
        final aQ = _bestMovieQuality(_movieSourcesCache[aKey]);
        final bQ = _bestMovieQuality(_movieSourcesCache[bKey]);
        final diff = _compareMovieQuality(bQ, aQ);
        if (diff != 0) return diff;
        return a.server.name.compareTo(b.server.name);
      }
      final aKey = '${a.server.id}:${a.item.id}';
      final bKey = '${b.server.id}:${b.item.id}';
      final aScore = _AggregateSearchTabStatefulState._progressScore(
          widget.latestEpisodeCache[aKey]);
      final bScore = _AggregateSearchTabStatefulState._progressScore(
          widget.latestEpisodeCache[bKey]);
      final diff = bScore - aScore;
      if (diff != 0) return diff;
      return a.server.name.compareTo(b.server.name);
    });

    return Scaffold(
      appBar: GlassAppBar(
        enableBlur: !widget.isTv && widget.appState.enableBlurEffects,
        child: AppBar(
          title: Text(widget.group.title),
        ),
      ),
      body: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: hits.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final hit = hits[index];
          final server = hit.server;
          final item = hit.item;
          final rowKey = '${server.id}:${item.id}';
          final busy = _loadingKey == rowKey;

          return Card(
            clipBehavior: Clip.antiAlias,
            child: ListTile(
              leading: ServerIconAvatar(
                iconUrl: server.iconUrl,
                name: server.name,
                radius: 18,
              ),
              title: Text(server.name),
              subtitle: isSeries
                  ? FutureBuilder<_LatestEpisodeResult?>(
                      future: widget.resolveLatestEpisode(server, item.id),
                      builder: (context, snap) {
                        if (snap.connectionState == ConnectionState.waiting) {
                          return const Text('获取更新信息…');
                        }
                        return Text(
                          _AggregateSearchTabStatefulState._episodeTag(
                            snap.data,
                          ),
                        );
                      },
                    )
                  : FutureBuilder<List<_MovieSourceInfo>?>(
                      future: _resolveMovieSources(server, item.id),
                      builder: (context, snap) {
                        if (snap.connectionState == ConnectionState.waiting) {
                          return const Text('获取参数信息…');
                        }
                        final sources = snap.data ?? _movieSourcesCache[rowKey];
                        if (sources == null || sources.isEmpty) {
                          return Text(_fmtMovieQuality(null));
                        }
                        if (sources.length == 1) {
                          return Text(_fmtMovieQuality(sources.first.quality));
                        }
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (var i = 0; i < sources.length; i++)
                              Text(
                                '${i + 1}. ${_fmtMovieQuality(sources[i].quality)}',
                              ),
                          ],
                        );
                      },
                    ),
              trailing: busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.chevron_right),
              onTap: busy
                  ? null
                  : () async {
                      setState(() => _loadingKey = rowKey);
                      try {
                        if (!isSeries) {
                          if (!mounted) return;
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => ShowDetailPage(
                                itemId: item.id,
                                title: item.name,
                                appState: widget.appState,
                                server: server,
                                isTv: widget.isTv,
                              ),
                            ),
                          );
                          return;
                        }

                        final latest =
                            await widget.resolveLatestEpisode(server, item.id);
                        if (!context.mounted) return;
                        if (latest == null) {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => ShowDetailPage(
                                itemId: item.id,
                                title: item.name,
                                appState: widget.appState,
                                server: server,
                                isTv: widget.isTv,
                              ),
                            ),
                          );
                          return;
                        }

                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => EpisodeDetailPage(
                              episode: latest.episode,
                              appState: widget.appState,
                              server: server,
                              isTv: widget.isTv,
                            ),
                          ),
                        );
                      } finally {
                        if (mounted) setState(() => _loadingKey = null);
                      }
                    },
            ),
          );
        },
      ),
    );
  }
}

class _MovieSourceInfo {
  const _MovieSourceInfo({
    required this.id,
    required this.label,
    required this.quality,
  });

  final String id;
  final String label;
  final _MovieQualityInfo quality;

  factory _MovieSourceInfo.fromMediaSource(Map<String, dynamic> ms) {
    final id = (ms['Id'] ?? '').toString();
    final name = (ms['Name'] ?? '').toString().trim();
    final container = (ms['Container'] ?? '').toString().trim();
    final path = (ms['Path'] ?? '').toString().trim();
    final label = name.isNotEmpty
        ? name
        : (container.isNotEmpty
            ? container
            : (path.isNotEmpty ? path.split(RegExp(r'[\\/]')).last : ''));
    final quality = _MovieQualityInfo.fromMediaSource(ms);
    return _MovieSourceInfo(id: id, label: label, quality: quality);
  }
}

class _MovieQualityInfo {
  const _MovieQualityInfo({
    required this.height,
    required this.bitrate,
    required this.sizeBytes,
  });

  final int height;
  final int bitrate;
  final int sizeBytes;

  factory _MovieQualityInfo.fromMediaSource(Map<String, dynamic> ms) {
    final height = _AggregateWorkDetailPageState._heightOf(ms);
    final bitrate = _AggregateWorkDetailPageState._bitrateOf(ms);
    final sizeBytes = _AggregateWorkDetailPageState._sizeOf(ms);
    return _MovieQualityInfo(
        height: height, bitrate: bitrate, sizeBytes: sizeBytes);
  }
}
