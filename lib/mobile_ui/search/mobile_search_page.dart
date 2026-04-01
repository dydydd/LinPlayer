import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lin_player_server_adapters/lin_player_server_adapters.dart';
import 'package:lin_player_state/lin_player_state.dart';
import 'package:lin_player_ui/lin_player_ui.dart';

import '../../server_adapters/server_access.dart';
import '../../show_detail_page.dart';

class MobileSearchPage extends StatefulWidget {
  const MobileSearchPage({
    super.key,
    required this.appState,
    this.initialQuery = '',
  });

  final AppState appState;
  final String initialQuery;

  @override
  State<MobileSearchPage> createState() => _MobileSearchPageState();
}

class _MobileServerSearchResults {
  const _MobileServerSearchResults({
    required this.server,
    required this.items,
  });

  final ServerProfile server;
  final List<MediaItem> items;
}

class _MobileSearchPageState extends State<MobileSearchPage> {
  static const int _kColumns = 3;
  static const int _kSearchLimitPerServer = 60;

  late final TextEditingController _controller;
  Timer? _debounce;
  int _searchSeq = 0;

  bool _loading = false;
  bool _aggregateSearchEnabled = false;
  String? _error;

  List<MediaItem> _results = const <MediaItem>[];
  List<_MobileServerSearchResults> _aggregateResults =
      const <_MobileServerSearchResults>[];

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialQuery);

    final initial = widget.initialQuery.trim();
    if (initial.isNotEmpty) {
      unawaited(_doSearch(initial));
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

    _debounce = Timer(const Duration(milliseconds: 220), () {
      unawaited(_doSearch(query));
    });
  }

  void _submitSearch(String raw) {
    final query = raw.trim();
    if (query.isEmpty) return;

    _controller.value = TextEditingValue(
      text: query,
      selection: TextSelection.collapsed(offset: query.length),
    );
    _scheduleSearch(query, immediate: true);
  }

  void _toggleAggregateSearch() {
    final query = _controller.text.trim();
    setState(() {
      _aggregateSearchEnabled = !_aggregateSearchEnabled;
      _error = null;
      _results = const <MediaItem>[];
      _aggregateResults = const <_MobileServerSearchResults>[];
    });

    if (query.isNotEmpty) {
      _scheduleSearch(query, immediate: true);
    }
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

  Future<void> _doSearch(String raw) async {
    final query = raw.trim();
    final seq = ++_searchSeq;

    if (query.isEmpty) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = null;
        _results = const <MediaItem>[];
        _aggregateResults = const <_MobileServerSearchResults>[];
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    if (_aggregateSearchEnabled) {
      await _doAggregateSearch(query, seq);
    } else {
      await _doSingleServerSearch(query, seq);
    }

    if (mounted && seq == _searchSeq) {
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _doSingleServerSearch(String query, int seq) async {
    final baseUrl = widget.appState.baseUrl;
    final token = widget.appState.token;
    final userId = widget.appState.userId;
    if (baseUrl == null || token == null || userId == null) {
      if (!mounted || seq != _searchSeq) return;
      setState(() {
        _error = '还没有连接服务器';
        _results = const <MediaItem>[];
        _aggregateResults = const <_MobileServerSearchResults>[];
      });
      return;
    }

    try {
      final access = resolveServerAccess(appState: widget.appState);
      if (access == null) {
        throw Exception('还没有连接服务器');
      }

      final fetched = await access.adapter.fetchItems(
        access.auth,
        searchTerm: query,
        includeItemTypes: 'Series,Movie',
        recursive: true,
        excludeFolders: false,
        limit: _kSearchLimitPerServer,
        sortBy: 'SortName',
        sortOrder: 'Ascending',
      );

      if (!mounted || seq != _searchSeq) return;

      final items = _filterVisibleItems(
        fetched.items,
        hiddenLibraries:
            widget.appState.activeServer?.hiddenLibraries ?? const <String>{},
        query: query,
      );

      setState(() {
        _results = items;
        _aggregateResults = const <_MobileServerSearchResults>[];
      });
    } catch (e) {
      if (!mounted || seq != _searchSeq) return;
      setState(() {
        _error = e.toString();
        _results = const <MediaItem>[];
        _aggregateResults = const <_MobileServerSearchResults>[];
      });
    }
  }

  Future<void> _doAggregateSearch(String query, int seq) async {
    final servers = widget.appState.servers;
    if (servers.isEmpty) {
      if (!mounted || seq != _searchSeq) return;
      setState(() {
        _error = '没有已配置的服务器';
        _results = const <MediaItem>[];
        _aggregateResults = const <_MobileServerSearchResults>[];
      });
      return;
    }

    final sections = <_MobileServerSearchResults>[];
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

          final fetched = await access.adapter.fetchItems(
            access.auth,
            searchTerm: query,
            includeItemTypes: 'Series,Movie',
            recursive: true,
            excludeFolders: false,
            limit: _kSearchLimitPerServer,
            sortBy: 'SortName',
            sortOrder: 'Ascending',
          );

          final items = _filterVisibleItems(
            fetched.items,
            hiddenLibraries: server.hiddenLibraries,
            query: query,
          );
          if (items.isEmpty) return;

          sections.add(
            _MobileServerSearchResults(
              server: server,
              items: items,
            ),
          );
        } catch (e) {
          serverErrors[server.id] = e.toString();
        }
      }),
    );

    if (!mounted || seq != _searchSeq) return;

    final allFailed = serverErrors.length == servers.length;
    setState(() {
      _results = const <MediaItem>[];
      _aggregateResults = sections;
      _error = allFailed ? '聚合搜索失败' : null;
    });
  }

  void _clearSearch() {
    _controller.clear();
    _scheduleSearch('', immediate: true);
    setState(() {});
  }

  void _openDetail(MediaItem item, {ServerProfile? server}) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ShowDetailPage(
          itemId: item.id,
          title: item.name,
          appState: widget.appState,
          server: server,
          isTv: false,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final query = _controller.text.trim();
    final safePadding = MediaQuery.of(context).padding;

    return Scaffold(
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                scheme.surface,
                scheme.surfaceContainerLowest,
              ],
            ),
          ),
          child: SafeArea(
            bottom: false,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: _MobileSearchField(
                    controller: _controller,
                    onChanged: (value) {
                      setState(() {});
                      _scheduleSearch(
                        value,
                        immediate: value.trim().isEmpty,
                      );
                    },
                    onSubmitted: _submitSearch,
                    onClear: query.isEmpty ? null : _clearSearch,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                  child: _MobileAggregateToggle(
                    enabled: _aggregateSearchEnabled,
                    onTap: _toggleAggregateSearch,
                  ),
                ),
                if (_loading && query.isNotEmpty)
                  const LinearProgressIndicator(minHeight: 2),
                Expanded(
                  child: _buildContent(
                    context,
                    query: query,
                    safePadding: safePadding,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(
    BuildContext context, {
    required String query,
    required EdgeInsets safePadding,
  }) {
    if (query.isEmpty) {
      return const SizedBox.expand();
    }

    final showingAggregate = _aggregateSearchEnabled;
    final hasResults = showingAggregate
        ? _aggregateResults.isNotEmpty
        : _results.isNotEmpty;

    if (_loading && !hasResults) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            _error!,
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    if (showingAggregate) {
      if (_aggregateResults.isEmpty) {
        return const Center(child: Text('没有找到相关结果'));
      }

      return ListView.separated(
        padding: EdgeInsets.fromLTRB(12, 8, 12, safePadding.bottom + 20),
        itemCount: _aggregateResults.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final section = _aggregateResults[index];
          return _MobileServerSection(
            section: section,
            appState: widget.appState,
            onOpenItem: (item) => _openDetail(item, server: section.server),
          );
        },
      );
    }

    if (_results.isEmpty) {
      return const Center(child: Text('没有找到相关结果'));
    }

    final access = resolveServerAccess(appState: widget.appState);

    return GridView.builder(
      padding: EdgeInsets.fromLTRB(12, 8, 12, safePadding.bottom + 20),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: _kColumns,
        mainAxisSpacing: 12,
        crossAxisSpacing: 10,
        childAspectRatio: 0.5,
      ),
      itemCount: _results.length,
      itemBuilder: (context, index) {
        final item = _results[index];
        return _MobileSearchPoster(
          item: item,
          access: access,
          onTap: () => _openDetail(item),
        );
      },
    );
  }
}

class _MobileSearchSurface extends StatelessWidget {
  const _MobileSearchSurface({
    required this.child,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _MobileSearchField extends StatelessWidget {
  const _MobileSearchField({
    required this.controller,
    required this.onChanged,
    required this.onSubmitted,
    required this.onClear,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return _MobileSearchSurface(
      child: TextField(
        controller: controller,
        autofocus: true,
        textInputAction: TextInputAction.search,
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        decoration: InputDecoration(
          hintText: '搜索剧集或电影',
          border: InputBorder.none,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 15,
          ),
          suffixIcon: onClear == null
              ? null
              : IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: onClear,
                ),
        ),
      ),
    );
  }
}

class _MobileAggregateToggle extends StatelessWidget {
  const _MobileAggregateToggle({
    required this.enabled,
    required this.onTap,
  });

  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return _MobileSearchSurface(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
            child: Row(
              children: [
                Icon(
                  enabled ? Icons.layers_rounded : Icons.layers_outlined,
                  color: enabled ? scheme.primary : scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '聚合搜索',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  enabled ? '已开启' : '已关闭',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: enabled ? scheme.primary : scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MobileServerSection extends StatelessWidget {
  const _MobileServerSection({
    required this.section,
    required this.appState,
    required this.onOpenItem,
  });

  final _MobileServerSearchResults section;
  final AppState appState;
  final ValueChanged<MediaItem> onOpenItem;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final sectionAccess =
        resolveServerAccess(appState: appState, server: section.server);
    final itemWidth =
        ((MediaQuery.sizeOf(context).width - 72) / 3).clamp(96.0, 132.0)
            .toDouble();
    final rowHeight = itemWidth / 0.68 + 54;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ServerIconAvatar(
                  iconUrl: section.server.iconUrl,
                  name: section.server.name,
                  radius: 18,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    section.server.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  '${section.items.length} 项',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: rowHeight,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: section.items.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (context, index) {
                  final item = section.items[index];
                  return SizedBox(
                    width: itemWidth,
                    child: _MobileSearchPoster(
                      item: item,
                      access: sectionAccess,
                      onTap: () => onOpenItem(item),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MobileSearchPoster extends StatelessWidget {
  const _MobileSearchPoster({
    required this.item,
    required this.access,
    required this.onTap,
  });

  final MediaItem item;
  final ServerAccess? access;
  final VoidCallback onTap;

  String _yearOf() {
    final raw = (item.premiereDate ?? '').trim();
    if (raw.isEmpty) return '';
    final parsed = DateTime.tryParse(raw);
    if (parsed != null) return parsed.year.toString();
    return raw.length >= 4 ? raw.substring(0, 4) : '';
  }

  @override
  Widget build(BuildContext context) {
    final imageUrl = item.hasImage && access != null
        ? access!.adapter.imageUrl(
            access!.auth,
            itemId: item.id,
            imageType: 'Primary',
            maxWidth: 360,
          )
        : null;

    final badgeText = switch (item.type) {
      'Movie' => '电影',
      'Series' => '剧集',
      _ => '',
    };

    return MediaPosterTile(
      title: item.name,
      imageUrl: imageUrl,
      year: _yearOf(),
      badgeText: badgeText.isEmpty ? null : badgeText,
      titleMaxLines: 2,
      showOverlayRating: false,
      posterAspectRatio: 0.68,
      onTap: onTap,
    );
  }
}
