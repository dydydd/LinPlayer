import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:lin_player_server_api/network/lin_http_client.dart';
import 'package:lin_player_server_api/services/ass_api.dart';
import 'package:lin_player_state/lin_player_state.dart';
import 'package:lin_player_ui/lin_player_ui.dart';

import 'ass_episode_detail_page.dart';
import 'ass_server_access.dart';

class AssSeriesDetailPage extends StatefulWidget {
  const AssSeriesDetailPage({
    super.key,
    required this.appState,
    required this.ani,
  });

  final AppState appState;
  final AssAni ani;

  @override
  State<AssSeriesDetailPage> createState() => _AssSeriesDetailPageState();
}

class _AssSeriesDetailPageState extends State<AssSeriesDetailPage> {
  bool _loading = true;
  String? _error;
  List<AssPlayItem> _episodes = const <AssPlayItem>[];
  int _reqId = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load(forceRefresh: true));
  }

  Future<void> _load({required bool forceRefresh}) async {
    final access = resolveAssServerAccess(appState: widget.appState);
    if (access == null) {
      setState(() {
        _loading = false;
        _episodes = const <AssPlayItem>[];
        _error = 'ASS server not ready.';
      });
      return;
    }

    final myId = ++_reqId;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final list = await access.api.playList(ani: widget.ani);
      if (!mounted || myId != _reqId) return;
      final sorted = List<AssPlayItem>.from(list);
      sorted.sort((a, b) {
        final ea = a.episode ?? -1;
        final eb = b.episode ?? -1;
        if (ea == eb) return a.title.compareTo(b.title);
        return ea.compareTo(eb);
      });
      setState(() => _episodes = sorted);
    } catch (e) {
      if (!mounted || myId != _reqId) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted && myId == _reqId) {
        setState(() => _loading = false);
      }
    }
  }

  static String _formatEpisode(double? ep) {
    if (ep == null || ep <= 0) return '';
    final rounded = ep.roundToDouble();
    if ((ep - rounded).abs() < 0.00001) return '第${rounded.toInt()}集';
    return '第$ep集';
  }

  static DateTime? _parseEpochMs(int? raw) {
    if (raw == null || raw <= 0) return null;
    // Best-effort: treat small values as seconds, larger as milliseconds.
    final ms = raw < 2000000000 ? raw * 1000 : raw;
    try {
      return DateTime.fromMillisecondsSinceEpoch(ms);
    } catch (_) {
      return null;
    }
  }

  String? _posterUrlOf(AssAni ani) {
    final image = ani.image.trim();
    if (image.startsWith('http://') || image.startsWith('https://')) {
      return image;
    }
    final poster = (ani.tmdb?.posterPath ?? '').trim();
    if (poster.isEmpty) return null;
    if (poster.startsWith('http://') || poster.startsWith('https://')) {
      return poster;
    }
    if (poster.startsWith('/')) {
      return 'https://image.tmdb.org/t/p/w500$poster';
    }
    return poster;
  }

  String? _backdropUrlOf(AssAni ani) {
    final backdrop = (ani.tmdb?.backdropPath ?? '').trim();
    if (backdrop.isEmpty) return null;
    if (backdrop.startsWith('http://') || backdrop.startsWith('https://')) {
      return backdrop;
    }
    if (backdrop.startsWith('/')) {
      return 'https://image.tmdb.org/t/p/w780$backdrop';
    }
    return backdrop;
  }

  Widget _header(BuildContext context) {
    final ani = widget.ani;
    final poster = _posterUrlOf(ani);
    final backdrop = _backdropUrlOf(ani);
    final overview = (ani.tmdb?.overview ?? '').trim();
    final jpTitle = ani.jpTitle.trim();
    final subgroup = ani.subgroup.trim();

    final posterWidget = ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: AspectRatio(
        aspectRatio: 2 / 3,
        child: poster == null
            ? const ColoredBox(color: Colors.black26)
            : CachedNetworkImage(
                imageUrl: poster,
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
              ),
      ),
    );

    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          ani.title.trim().isEmpty ? '(未命名)' : ani.title,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        if (jpTitle.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            jpTitle,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            if (subgroup.isNotEmpty)
              Chip(
                label: Text(subgroup),
                visualDensity: VisualDensity.compact,
              ),
            if (ani.currentEpisodeNumber != null || ani.totalEpisodeNumber != null)
              Chip(
                label: Text(
                  '${ani.currentEpisodeNumber ?? '-'} / ${ani.totalEpisodeNumber ?? '-'}',
                ),
                visualDensity: VisualDensity.compact,
              ),
            if ((ani.tmdb?.voteAverage ?? '').trim().isNotEmpty)
              Chip(
                label: Text('TMDB ${ani.tmdb!.voteAverage}'),
                visualDensity: VisualDensity.compact,
              ),
          ],
        ),
        if (overview.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            overview,
            maxLines: 6,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (backdrop != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: CachedNetworkImage(
                imageUrl: backdrop,
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
              ),
            ),
          ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 120, child: posterWidget),
            const SizedBox(width: 12),
            Expanded(child: details),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          '剧集',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 6),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.ani.title.trim().isEmpty ? '详情' : widget.ani.title;

    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: Text(title)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: Text(title)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_error!, textAlign: TextAlign.center),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () => unawaited(_load(forceRefresh: true)),
                  icon: const Icon(Icons.refresh),
                  label: const Text('重试'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: () => unawaited(_load(forceRefresh: true)),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _load(forceRefresh: true),
        child: ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
          itemCount: 1 + _episodes.length,
          itemBuilder: (context, i) {
            if (i == 0) return _header(context);
            final item = _episodes[i - 1];

            final ep = _formatEpisode(item.episode);
            final dt = _parseEpochMs(item.lastModify);
            final time = dt == null
                ? ''
                : '${dt.year.toString().padLeft(4, '0')}-'
                    '${dt.month.toString().padLeft(2, '0')}-'
                    '${dt.day.toString().padLeft(2, '0')}';

            final subtitleParts = <String>[];
            if (ep.isNotEmpty) subtitleParts.add(ep);
            final size = item.size.trim();
            if (size.isNotEmpty) subtitleParts.add('${size}MB');
            if (time.isNotEmpty) subtitleParts.add(time);

            return Card(
              child: ListTile(
                title: Text(item.title.trim().isEmpty ? item.name : item.title),
                subtitle: subtitleParts.isEmpty
                    ? null
                    : Text(subtitleParts.join('  ')),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => AssEpisodeDetailPage(
                        appState: widget.appState,
                        ani: widget.ani,
                        item: item,
                      ),
                    ),
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }
}
