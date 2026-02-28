import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lin_player_server_api/services/ass_api.dart';
import 'package:lin_player_state/lin_player_state.dart';
import 'package:lin_player_ui/lin_player_ui.dart';

import 'ass_series_detail_page.dart';
import 'ass_server_access.dart';

class AssHomePage extends StatefulWidget {
  const AssHomePage({
    super.key,
    required this.appState,
    this.desktopLayout = false,
  });

  final AppState appState;
  final bool desktopLayout;

  @override
  State<AssHomePage> createState() => _AssHomePageState();
}

class _AssHomePageState extends State<AssHomePage> {
  bool _loading = true;
  String? _error;
  List<AssAni> _items = const <AssAni>[];
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
        _items = const <AssAni>[];
        _error = 'ASS server not ready (missing baseUrl/token).';
      });
      return;
    }

    final myId = ++_reqId;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final list = await access.api.listAni();
      if (!mounted || myId != _reqId) return;
      setState(() => _items = list);
    } catch (e) {
      if (!mounted || myId != _reqId) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted && myId == _reqId) {
        setState(() => _loading = false);
      }
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
      // Best-effort: TMDB image host.
      return 'https://image.tmdb.org/t/p/w500$poster';
    }
    return poster;
  }

  @override
  Widget build(BuildContext context) {
    final serverName = widget.appState.activeServer?.name.trim();
    final title = (serverName == null || serverName.isEmpty) ? 'ASS' : serverName;

    final maxCross = widget.desktopLayout ? 220.0 : 160.0;

    final body = _loading
        ? const Center(child: CircularProgressIndicator())
        : (_error != null)
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: () => unawaited(_load(forceRefresh: true)),
                        icon: const Icon(Icons.refresh),
                        label: const Text('重试'),
                      ),
                    ],
                  ),
                ),
              )
            : (_items.isEmpty)
                ? const Center(child: Text('暂无订阅'))
                : RefreshIndicator(
                    onRefresh: () => _load(forceRefresh: true),
                    child: GridView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: maxCross,
                        mainAxisSpacing: 14,
                        crossAxisSpacing: 14,
                        childAspectRatio: 2 / 3.55,
                      ),
                      itemCount: _items.length,
                      itemBuilder: (context, i) {
                        final ani = _items[i];
                        final total = ani.totalEpisodeNumber;
                        final badge = (total != null && total > 0)
                            ? EpisodeCountBadge(count: total)
                            : null;
                        return MediaPosterTile(
                          title: ani.title.trim().isEmpty ? '(未命名)' : ani.title,
                          imageUrl: _posterUrlOf(ani),
                          rating: ani.score,
                          topRightBadge: badge,
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => AssSeriesDetailPage(
                                  appState: widget.appState,
                                  ani: ani,
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
                  );

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: _loading ? null : () => unawaited(_load(forceRefresh: true)),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: body,
    );
  }
}
