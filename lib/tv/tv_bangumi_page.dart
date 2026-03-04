import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:lin_player_server_api/network/lin_http_client.dart';
import 'package:lin_player_state/lin_player_state.dart';
import 'package:lin_player_ui/lin_player_ui.dart';

import '../aggregate_service_page.dart';
import '../services/bangumi/bangumi_api.dart';
import 'tv_focusable.dart';

void _pushAggregateSearch(
  BuildContext context, {
  required AppState appState,
  required String query,
}) {
  final q = query.trim();
  if (q.isEmpty) return;
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => AggregateServicePage(
        appState: appState,
        initialTabIndex: 1,
        initialQuery: q,
      ),
    ),
  );
}

class TvBangumiPage extends StatefulWidget {
  const TvBangumiPage({super.key, required this.appState});

  final AppState appState;

  @override
  State<TvBangumiPage> createState() => _TvBangumiPageState();
}

class _TvBangumiPageState extends State<TvBangumiPage> {
  final BangumiApiClient _api = BangumiApiClient();

  late Future<List<BangumiSubject>> _todayAiringFuture;
  late Future<List<BangumiSubject>> _topScoreFuture;
  late Future<List<BangumiSubject>> _topRankFuture;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _api.close();
    super.dispose();
  }

  static String _weekdayCnShort(int weekday) {
    return switch (weekday) {
      DateTime.monday => '周一',
      DateTime.tuesday => '周二',
      DateTime.wednesday => '周三',
      DateTime.thursday => '周四',
      DateTime.friday => '周五',
      DateTime.saturday => '周六',
      DateTime.sunday => '周日',
      _ => '',
    };
  }

  void _reload() {
    setState(() {
      _todayAiringFuture = _loadTodayAiring();
      _topScoreFuture = _api.topAnimeRanking(
        sort: BangumiSubjectSort.score,
        limit: 10,
      );
      _topRankFuture = _loadTopRank();
    });
  }

  Future<List<BangumiSubject>> _loadTodayAiring() async {
    final days = await _api.getCalendar();
    final todayId = DateTime.now().weekday;

    BangumiCalendarDay? picked;
    for (final d in days) {
      if (d.weekday.id == todayId) {
        picked = d;
        break;
      }
    }
    picked ??= days.isEmpty ? null : days.first;

    final items = picked?.items ?? const [];
    if (items.length <= 10) return items;
    return items.take(10).toList(growable: false);
  }

  Future<List<BangumiSubject>> _loadTopRank() async {
    final out = <BangumiSubject>[];
    final seen = <int>{};
    var offset = 0;
    const chunkSize = 50;

    while (out.length < 10) {
      final resp = await _api.browseSubjects(
        type: 2,
        sort: 'rank',
        limit: chunkSize,
        offset: offset,
      );
      if (resp.data.isEmpty) break;

      final canDetectJapan = resp.data.any(
        (s) => s.tags.isNotEmpty || s.metaTags.isNotEmpty,
      );

      for (final s in resp.data) {
        if (canDetectJapan && !s.isJapanAnime) continue;
        if (!seen.add(s.id)) continue;
        out.add(s);
        if (out.length >= 10) break;
      }

      offset = resp.offset + resp.data.length;
      if (offset >= resp.total) break;
      if (resp.data.length < chunkSize) break;
    }

    out.sort((a, b) {
      final ar = a.effectiveRank ?? (1 << 30);
      final br = b.effectiveRank ?? (1 << 30);
      final cmp = ar.compareTo(br);
      if (cmp != 0) return cmp;
      final as = a.effectiveScore ?? -1;
      final bs = b.effectiveScore ?? -1;
      final cmp2 = bs.compareTo(as);
      if (cmp2 != 0) return cmp2;
      return a.id.compareTo(b.id);
    });

    if (out.length <= 10) return out;
    return out.take(10).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final uiScale = context.uiScale;

    final now = DateTime.now();
    final todayLabel = '今天 · ${_weekdayCnShort(now.weekday)}';

    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 28),
      children: [
        Row(
          children: [
            Text(
              'Bangumi',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const Spacer(),
            TvFocusable(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              borderRadius: const BorderRadius.all(Radius.circular(999)),
              onPressed: _reload,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.refresh_rounded,
                    size: (18 * uiScale).clamp(16.0, 20.0),
                    color: scheme.onSurface,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '刷新',
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _BangumiSection(
          title: '每日放送',
          subtitle: todayLabel,
          future: _todayAiringFuture,
          onRetry: _reload,
          onTapSubject: (s) => _pushAggregateSearch(
            context,
            appState: widget.appState,
            query: s.displayName,
          ),
          onOpen: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => TvBangumiCalendarPage(appState: widget.appState),
            ),
          ),
        ),
        const SizedBox(height: 20),
        _BangumiSection(
          title: '评分排行榜',
          subtitle: '按评分从高到低',
          future: _topScoreFuture,
          onRetry: _reload,
          onTapSubject: (s) => _pushAggregateSearch(
            context,
            appState: widget.appState,
            query: s.displayName,
          ),
          onOpen: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => TvBangumiRankingPage(
                appState: widget.appState,
                title: '评分排行榜',
                sort: BangumiSubjectSort.score,
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
        _BangumiSection(
          title: '排名排行榜',
          subtitle: '按排名从 1 往下',
          future: _topRankFuture,
          onRetry: _reload,
          onTapSubject: (s) => _pushAggregateSearch(
            context,
            appState: widget.appState,
            query: s.displayName,
          ),
          onOpen: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => TvBangumiRankingPage(
                appState: widget.appState,
                title: '排名排行榜',
                sort: BangumiSubjectSort.rank,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _BangumiSection extends StatelessWidget {
  const _BangumiSection({
    required this.title,
    required this.subtitle,
    required this.future,
    required this.onRetry,
    required this.onTapSubject,
    this.onOpen,
  });

  final String title;
  final String subtitle;
  final Future<List<BangumiSubject>> future;
  final VoidCallback onRetry;
  final ValueChanged<BangumiSubject> onTapSubject;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final uiScale = context.uiScale;

    final titleStyle = theme.textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.w800,
    );
    final subtitleStyle = theme.textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
      fontWeight: FontWeight.w600,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: titleStyle),
                  if (subtitle.trim().isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(subtitle, style: subtitleStyle),
                  ],
                ],
              ),
            ),
            if (onOpen != null)
              TvFocusable(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                borderRadius: const BorderRadius.all(Radius.circular(999)),
                onPressed: onOpen,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '详情',
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: (18 * uiScale).clamp(16.0, 20.0),
                      color: scheme.onSurface,
                    ),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        FutureBuilder<List<BangumiSubject>>(
          future: future,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const _BangumiLoadingRow();
            }
            if (snap.hasError) {
              return _BangumiErrorRow(onRetry: onRetry);
            }
            final items = snap.data ?? const [];
            if (items.isEmpty) {
              return Text(
                '暂无数据',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              );
            }

            final count = items.length > 10 ? 10 : items.length;
            final height = (260 * uiScale).clamp(220.0, 300.0);
            final cardWidth = (150 * uiScale).clamp(120.0, 190.0);

            return SizedBox(
              height: height,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                clipBehavior: Clip.none,
                itemCount: count,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, index) => _BangumiPosterCard(
                  subject: items[index],
                  onPressed: () => onTapSubject(items[index]),
                  width: cardWidth,
                  autofocus: index == 0,
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _BangumiLoadingRow extends StatelessWidget {
  const _BangumiLoadingRow();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: (260 * context.uiScale).clamp(220.0, 300.0),
      child: Center(
        child: CircularProgressIndicator(color: scheme.primary),
      ),
    );
  }
}

class _BangumiErrorRow extends StatelessWidget {
  const _BangumiErrorRow({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return SizedBox(
      height: (260 * context.uiScale).clamp(220.0, 300.0),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '加载失败',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            TvFocusable(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              borderRadius: const BorderRadius.all(Radius.circular(999)),
              onPressed: onRetry,
              child: Text(
                '重试',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BangumiPosterCard extends StatelessWidget {
  const _BangumiPosterCard({
    required this.subject,
    required this.onPressed,
    this.width,
    this.autofocus = false,
  });

  final BangumiSubject subject;
  final VoidCallback onPressed;
  final double? width;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final uiScale = context.uiScale;

    final radius = (14 * uiScale).clamp(10.0, 16.0);

    final imageUrl = subject.imageUrl;
    final imageWidget = imageUrl == null || imageUrl.trim().isEmpty
        ? const ColoredBox(
            color: Colors.black26,
            child: Center(child: Icon(Icons.image_outlined)),
          )
        : CachedNetworkImage(
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
          );

    final score = subject.effectiveScore;
    final rank = subject.effectiveRank;

    final metaStyle = theme.textTheme.labelSmall?.copyWith(
      color: scheme.onSurfaceVariant,
      fontWeight: FontWeight.w700,
    );

    final card = TvFocusable(
      autofocus: autofocus,
      borderRadius: BorderRadius.circular(radius + 2),
      onPressed: onPressed,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 2 / 3,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(radius),
                child: imageWidget,
              ),
            ),
            SizedBox(height: (8 * uiScale).clamp(6.0, 10.0)),
            Text(
              subject.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 3),
            Row(
              children: [
                if (score != null && score > 0) ...[
                  const Icon(
                    Icons.star_rounded,
                    size: 16,
                    color: Colors.amber,
                  ),
                  const SizedBox(width: 2),
                  Text(score.toStringAsFixed(1), style: metaStyle),
                ],
                if (rank != null && rank > 0) ...[
                  if (score != null && score > 0) const SizedBox(width: 8),
                  Text('#$rank', style: metaStyle),
                ],
              ],
            ),
          ],
        ),
      ),
    );

    final fixedWidth = width;
    if (fixedWidth == null) return card;
    return SizedBox(width: fixedWidth, child: card);
  }
}

class TvBangumiCalendarPage extends StatefulWidget {
  const TvBangumiCalendarPage({super.key, required this.appState});

  final AppState appState;

  @override
  State<TvBangumiCalendarPage> createState() => _TvBangumiCalendarPageState();
}

class _TvBangumiCalendarPageState extends State<TvBangumiCalendarPage> {
  final BangumiApiClient _api = BangumiApiClient();

  bool _loading = true;
  Object? _error;
  List<BangumiCalendarDay> _days = const [];

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _api.close();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final days = await _api.getCalendar();
      if (!mounted) return;
      setState(() {
        _days = days;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('每日放送')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : (_error != null)
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '加载失败',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 12),
                        TvFocusable(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 12,
                          ),
                          borderRadius:
                              const BorderRadius.all(Radius.circular(999)),
                          onPressed: () => unawaited(_load()),
                          child: Text(
                            '重试',
                            style: theme.textTheme.labelLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    itemCount: _days.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 18),
                    itemBuilder: (context, index) {
                      final day = _days[index];
                      final title = day.weekday.cn.trim().isEmpty
                          ? 'Day ${day.weekday.id}'
                          : day.weekday.cn.trim();
                      final items = day.items.length > 20
                          ? day.items.take(20).toList(growable: false)
                          : day.items;
                      return _BangumiSection(
                        title: title,
                        subtitle: '',
                        future: Future.value(items),
                        onRetry: () => unawaited(_load()),
                        onTapSubject: (s) => _pushAggregateSearch(
                          context,
                          appState: widget.appState,
                          query: s.displayName,
                        ),
                        onOpen: null,
                      );
                    },
                  ),
      ),
    );
  }
}

class TvBangumiRankingPage extends StatefulWidget {
  const TvBangumiRankingPage({
    super.key,
    required this.appState,
    required this.title,
    required this.sort,
  });

  final AppState appState;
  final String title;
  final BangumiSubjectSort sort;

  @override
  State<TvBangumiRankingPage> createState() => _TvBangumiRankingPageState();
}

class _TvBangumiRankingPageState extends State<TvBangumiRankingPage> {
  final BangumiApiClient _api = BangumiApiClient();
  final ScrollController _scrollController = ScrollController();

  final List<BangumiSubject> _items = <BangumiSubject>[];
  final List<BangumiSubject> _rankBuffer = <BangumiSubject>[];
  final Set<int> _seenIds = <int>{};
  bool _loading = true;
  bool _loadingMore = false;
  bool _noMore = false;
  Object? _error;
  int _offset = 0;
  int _total = 0;

  static const int _pageSize = 20;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    unawaited(_load(reset: true));
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _api.close();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    if (_loading || _loadingMore || _noMore) return;
    if (_error != null) return;
    final pos = _scrollController.position;
    if (!pos.hasPixels) return;
    if (pos.extentAfter > 600) return;
    unawaited(_load(reset: false));
  }

  void _sortItems() {
    switch (widget.sort) {
      case BangumiSubjectSort.rank:
        int effRank(BangumiSubject s) {
          final v = s.effectiveRank;
          if (v == null || v <= 0) return 1 << 30;
          return v;
        }

        double effScore(BangumiSubject s) {
          final v = s.effectiveScore;
          if (v == null || v <= 0) return -1;
          return v;
        }

        _items.sort((a, b) {
          final cmp = effRank(a).compareTo(effRank(b));
          if (cmp != 0) return cmp;
          final cmp2 = effScore(b).compareTo(effScore(a));
          if (cmp2 != 0) return cmp2;
          return a.id.compareTo(b.id);
        });
        break;
      case BangumiSubjectSort.score:
        double effScore(BangumiSubject s) {
          final v = s.effectiveScore;
          if (v == null || v <= 0) return -1;
          return v;
        }

        int effRank(BangumiSubject s) {
          final v = s.effectiveRank;
          if (v == null || v <= 0) return 1 << 30;
          return v;
        }

        _items.sort((a, b) {
          final cmp = effScore(b).compareTo(effScore(a));
          if (cmp != 0) return cmp;
          final cmp2 = effRank(a).compareTo(effRank(b));
          if (cmp2 != 0) return cmp2;
          return a.id.compareTo(b.id);
        });
        break;
      case BangumiSubjectSort.heat:
      case BangumiSubjectSort.match:
        break;
    }
  }

  Future<({
    List<BangumiSubject> page,
    List<BangumiSubject> buffer,
    int total,
    int nextOffset,
  })> _fetchJapanRankPage() async {
    final page = <BangumiSubject>[];
    final buffer = List<BangumiSubject>.from(_rankBuffer);
    while (page.length < _pageSize && buffer.isNotEmpty) {
      page.add(buffer.removeAt(0));
    }

    var offset = _offset;
    var total = _total;
    var guard = 0;
    const chunkSize = 50;

    while (page.length < _pageSize && guard < 30) {
      guard++;

      final resp = await _api.browseSubjects(
        type: 2,
        sort: 'rank',
        limit: chunkSize,
        offset: offset,
      );
      total = resp.total;
      if (resp.data.isEmpty) break;

      final canDetectJapan = resp.data.any(
        (s) => s.tags.isNotEmpty || s.metaTags.isNotEmpty,
      );

      final nextOffset = resp.offset + resp.data.length;
      if (nextOffset <= offset) break;
      offset = nextOffset;

      for (final s in resp.data) {
        if (canDetectJapan && !s.isJapanAnime) continue;
        if (page.length < _pageSize) {
          page.add(s);
        } else {
          buffer.add(s);
        }
      }

      if (offset >= total) break;
      if (resp.data.length < chunkSize) break;
    }

    return (
      page: page,
      buffer: buffer,
      total: total,
      nextOffset: offset,
    );
  }

  Future<void> _load({required bool reset}) async {
    if (_loadingMore) return;
    if (!reset && _noMore) return;

    setState(() {
      _error = null;
      if (reset) {
        _loading = true;
        _noMore = false;
        _offset = 0;
        _total = 0;
        _items.clear();
        _rankBuffer.clear();
        _seenIds.clear();
      } else {
        _loadingMore = true;
      }
    });

    try {
      if (widget.sort == BangumiSubjectSort.rank) {
        final resp = await _fetchJapanRankPage();
        final page = resp.page;
        if (!mounted) return;
        setState(() {
          _total = resp.total;
          _offset = resp.nextOffset;
          _rankBuffer
            ..clear()
            ..addAll(resp.buffer);

          var added = 0;
          for (final s in page) {
            if (!_seenIds.add(s.id)) continue;
            _items.add(s);
            added++;
          }

          if (_total > 0 && _offset >= _total && _rankBuffer.isEmpty) {
            _noMore = true;
          }
          if (page.isEmpty || added == 0) _noMore = true;

          _sortItems();
        });
      } else {
        final resp = await _api.topAnimeRankingResponse(
          sort: widget.sort,
          limit: _pageSize,
          offset: _offset,
        );
        final page = resp.data;
        if (!mounted) return;
        setState(() {
          _total = resp.total;

          var added = 0;
          for (final s in page) {
            if (!_seenIds.add(s.id)) continue;
            _items.add(s);
            added++;
          }

          final step = resp.limit > 0 ? resp.limit : page.length;
          final nextOffset = resp.offset + step;
          if (nextOffset <= _offset) {
            _noMore = true;
          } else {
            _offset = nextOffset;
          }

          if (_total > 0 && _offset >= _total) _noMore = true;
          if (page.isEmpty || added == 0) _noMore = true;

          _sortItems();
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadingMore = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final uiScale = context.uiScale;

    Widget buildError() {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '加载失败',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            TvFocusable(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              borderRadius: const BorderRadius.all(Radius.circular(999)),
              onPressed: () => unawaited(_load(reset: true)),
              child: Text(
                '重试',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final maxCrossAxisExtent = (190 * uiScale).clamp(160.0, 220.0);

    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : (_error != null && _items.isEmpty)
                ? buildError()
                : GridView.builder(
                    controller: _scrollController,
                    gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: maxCrossAxisExtent,
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      childAspectRatio: 0.52,
                    ),
                    clipBehavior: Clip.none,
                    itemCount: _items.length + (_noMore ? 0 : 1),
                    itemBuilder: (context, index) {
                      final isLoadMoreTile = index >= _items.length;
                      if (isLoadMoreTile) {
                        final label = _loadingMore
                            ? '加载中…'
                            : (_error != null ? '加载失败，重试' : '加载更多');
                        return TvFocusable(
                          autofocus: _items.isEmpty,
                          onPressed: () => unawaited(_load(reset: false)),
                          child: Center(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Text(
                                label,
                                textAlign: TextAlign.center,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ),
                        );
                      }

                      final subject = _items[index];
                      final position = index + 1;
                      final rank = subject.effectiveRank;
                      final badgeNumber =
                          (widget.sort == BangumiSubjectSort.rank &&
                                  rank != null &&
                                  rank > 0)
                              ? rank
                              : position;

                      return Stack(
                        children: [
                          Positioned.fill(
                            child: _BangumiPosterCard(
                              subject: subject,
                              onPressed: () => _pushAggregateSearch(
                                context,
                                appState: widget.appState,
                                query: subject.displayName,
                              ),
                              autofocus: index == 0,
                            ),
                          ),
                          Positioned(
                            left: 10,
                            top: 10,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: scheme.surfaceContainerHigh.withValues(
                                  alpha: 0.78,
                                ),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: scheme.outlineVariant
                                      .withValues(alpha: 0.55),
                                ),
                              ),
                              child: Text(
                                '#$badgeNumber',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
      ),
    );
  }
}
