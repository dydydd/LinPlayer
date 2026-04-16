import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lin_player_state/lin_player_state.dart';
import 'package:lin_player_ui/lin_player_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lin_player_server_adapters/lin_player_server_adapters.dart';
import 'mobile_ui/search/mobile_search_page.dart';
import 'server_adapters/server_access.dart';
import 'show_detail_page.dart';

const _kSearchHistoryPrefsKey = 'search_history_v1';
const _kSearchHistoryMaxEntries = 50;
const _kSearchHistoryCollapsedCount = 6;

class SearchPage extends StatelessWidget {
  const SearchPage({
    super.key,
    required this.appState,
    this.initialQuery = '',
  });

  final AppState appState;
  final String initialQuery;

  @override
  Widget build(BuildContext context) {
    final useMobileSearch = !DeviceType.isTv &&
        !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS);
    if (useMobileSearch) {
      return MobileSearchPage(
        appState: appState,
        initialQuery: initialQuery,
      );
    }

    return _FallbackSearchPage(
      appState: appState,
      initialQuery: initialQuery,
    );
  }
}

class _FallbackSearchPage extends StatefulWidget {
  const _FallbackSearchPage({
    required this.appState,
    this.initialQuery = '',
  });

  final AppState appState;
  final String initialQuery;

  @override
  State<_FallbackSearchPage> createState() => _FallbackSearchPageState();
}

class _FallbackSearchPageState extends State<_FallbackSearchPage> {
  late final TextEditingController _controller;
  Timer? _debounce;
  int _searchSeq = 0;

  bool _loading = false;
  String? _error;
  List<MediaItem> _results = const [];

  List<String> _searchHistory = const [];
  bool _historyExpanded = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialQuery);

    unawaited(_loadSearchHistory());

    final initial = widget.initialQuery.trim();
    if (initial.isNotEmpty) _submitSearch(initial);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  bool _isTv(BuildContext context) => DeviceType.isTv;

  void _scheduleSearch(String query, {bool immediate = false}) {
    _debounce?.cancel();
    if (immediate) {
      _doSearch(query);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 280), () {
      _doSearch(query);
    });
  }

  Future<void> _loadSearchHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getStringList(_kSearchHistoryPrefsKey) ?? const [];
      if (!mounted) return;

      setState(() {
        _searchHistory = _dedupSearchHistory([
          ..._searchHistory,
          ...stored,
        ]);
      });
    } catch (_) {
      // Ignore history read errors.
    }
  }

  List<String> _dedupSearchHistory(Iterable<String> items) {
    final seen = <String>{};
    final out = <String>[];
    for (final raw in items) {
      final v = raw.trim();
      if (v.isEmpty) continue;
      final key = v.toLowerCase();
      if (!seen.add(key)) continue;
      out.add(v);
      if (out.length >= _kSearchHistoryMaxEntries) break;
    }
    return out;
  }

  void _submitSearch(String raw) {
    final query = raw.trim();
    if (query.isEmpty) return;

    _controller.value = TextEditingValue(
      text: query,
      selection: TextSelection.collapsed(offset: query.length),
    );

    unawaited(_addToSearchHistory(query));
    _scheduleSearch(query, immediate: true);
  }

  Future<void> _addToSearchHistory(String raw) async {
    final query = raw.trim();
    if (query.isEmpty) return;

    final next = _dedupSearchHistory([query, ..._searchHistory]);
    if (mounted) {
      setState(() {
        _searchHistory = next;
      });
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_kSearchHistoryPrefsKey, next);
    } catch (_) {
      // Ignore history write errors.
    }
  }

  Future<void> _doSearch(String raw) async {
    final query = raw.trim();
    final seq = ++_searchSeq;

    if (query.isEmpty) {
      setState(() {
        _loading = false;
        _error = null;
        _results = const [];
      });
      return;
    }

    final baseUrl = widget.appState.baseUrl;
    final token = widget.appState.token;
    final userId = widget.appState.userId;
    if (baseUrl == null || token == null || userId == null) {
      setState(() {
        _loading = false;
        _error = '未连接服务器';
        _results = const [];
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final access = resolveServerAccess(appState: widget.appState);
      if (access == null) {
        throw Exception('未连接服务器');
      }
      final fetched = await access.adapter.fetchItems(
        access.auth,
        searchTerm: query,
        includeItemTypes: 'Series,Movie',
        recursive: true,
        excludeFolders: false,
        limit: 60,
        sortBy: 'SortName',
        sortOrder: 'Ascending',
      );

      if (!mounted || seq != _searchSeq) return;

      final hiddenLibraries =
          widget.appState.activeServer?.hiddenLibraries ?? const <String>{};
      final visibleItems = hiddenLibraries.isEmpty
          ? fetched.items
          : fetched.items.where((item) {
              final parentId = (item.parentId ?? '').trim();
              if (parentId.isEmpty) return true;
              return !hiddenLibraries.contains(parentId);
            }).toList(growable: false);

      final normalizedQuery = query.toLowerCase();
      final exact = visibleItems
          .where((e) => e.name.trim().toLowerCase() == normalizedQuery)
          .toList(growable: false);
      final results = exact.isNotEmpty ? exact : visibleItems;

      setState(() {
        _results = results;
      });
    } catch (e) {
      if (!mounted || seq != _searchSeq) return;
      setState(() {
        _error = e.toString();
        _results = const [];
      });
    } finally {
      if (mounted && seq == _searchSeq) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final uiScale = context.uiScale;
    final isTv = _isTv(context);
    final enableBlur = !isTv && widget.appState.enableBlurEffects;
    final maxCrossAxisExtent = (isTv ? 160.0 : 180.0) * uiScale;
    final access = resolveServerAccess(appState: widget.appState);

    final query = _controller.text.trim();

    Widget content;
    if (query.isEmpty) {
      if (_searchHistory.isEmpty) {
        content = const Center(child: Text('输入剧名开始搜索'));
      } else {
        final theme = Theme.of(context);
        final visible = _historyExpanded
            ? _searchHistory
            : _searchHistory.take(_kSearchHistoryCollapsedCount).toList();
        final showMore =
            !_historyExpanded && _searchHistory.length > visible.length;
        final padding = 16.0 * uiScale;
        final spacing = 10.0 * uiScale;

        content = SingleChildScrollView(
          padding: EdgeInsets.all(padding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '历史搜索',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              SizedBox(height: 12 * uiScale),
              Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: [
                  for (final item in visible)
                    _historyChip(
                      context,
                      label: item,
                      uiScale: uiScale,
                      onTap: () => _submitSearch(item),
                    ),
                  if (showMore)
                    _historyChip(
                      context,
                      label: '更多',
                      uiScale: uiScale,
                      onTap: () {
                        setState(() {
                          _historyExpanded = true;
                        });
                      },
                    ),
                ],
              ),
            ],
          ),
        );
      }
    } else if (_error != null) {
      content = Center(child: Text(_error!));
    } else if (_results.isEmpty) {
      content = _loading
          ? const Center(child: CircularProgressIndicator())
          : const Center(child: Text('没有结果'));
    } else {
      content = Padding(
        padding: const EdgeInsets.all(12),
        child: GridView.builder(
          gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: maxCrossAxisExtent,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 0.7,
          ),
          itemCount: _results.length,
          itemBuilder: (context, index) {
            final item = _results[index];
            return _SearchGridItem(
              item: item,
              appState: widget.appState,
              access: access,
              onTap: () {
                unawaited(_addToSearchHistory(query));
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ShowDetailPage(
                      itemId: item.id,
                      title: item.name,
                      appState: widget.appState,
                      isTv: isTv,
                    ),
                  ),
                );
              },
            );
          },
        ),
      );
    }

    final body = query.isEmpty
        ? content
        : Column(
            children: [
              if (_loading && _results.isNotEmpty)
                const LinearProgressIndicator(minHeight: 2),
              Expanded(child: content),
            ],
          );

    return Scaffold(
      appBar: GlassAppBar(
        enableBlur: enableBlur,
        child: AppBar(
          titleSpacing: 0,
          title: Padding(
            padding: const EdgeInsets.only(right: 12),
            child: TextField(
              controller: _controller,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: '搜索剧名',
                border: InputBorder.none,
              ),
              textInputAction: TextInputAction.search,
              onChanged: (v) => _scheduleSearch(v),
              onSubmitted: _submitSearch,
            ),
          ),
          actions: [
            IconButton(
              tooltip: '清空',
              icon: const Icon(Icons.clear),
              onPressed: () {
                _controller.clear();
                _scheduleSearch('', immediate: true);
              },
            ),
          ],
        ),
      ),
      body: body,
    );
  }

  Widget _historyChip(
    BuildContext context, {
    required String label,
    required VoidCallback onTap,
    required double uiScale,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = scheme.brightness == Brightness.dark;

    const radius = 18.0;
    final bg = Color.lerp(Colors.black, scheme.primary, 0.12)!.withValues(
      alpha: isDark ? 0.28 : 0.22,
    );
    const fg = Colors.white;
    const border = BorderSide.none;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(radius),
        onTap: onTap,
        child: Ink(
          padding: EdgeInsets.symmetric(
            horizontal: 10 * uiScale,
            vertical: 7 * uiScale,
          ),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(radius),
            border: border == BorderSide.none
                ? null
                : Border.fromBorderSide(border),
          ),
          child: Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
                  color: fg,
                  fontWeight: FontWeight.w700,
                ) ??
                TextStyle(
                  color: fg,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ),
      ),
    );
  }
}

class _SearchGridItem extends StatelessWidget {
  const _SearchGridItem({
    required this.item,
    required this.appState,
    required this.access,
    required this.onTap,
  });

  final MediaItem item;
  final AppState appState;
  final ServerAccess? access;
  final VoidCallback onTap;

  String _yearOf() {
    final d = (item.premiereDate ?? '').trim();
    if (d.isEmpty) return '';
    final parsed = DateTime.tryParse(d);
    if (parsed != null) return parsed.year.toString();
    return d.length >= 4 ? d.substring(0, 4) : '';
  }

  @override
  Widget build(BuildContext context) {
    final access = this.access;
    final image = item.hasImage && access != null
        ? access.adapter.imageUrl(
            access.auth,
            itemId: item.id,
            imageType: 'Primary',
            maxWidth: 320,
          )
        : null;

    final year = _yearOf();
    final rating = item.communityRating;

    final badge =
        item.type == 'Movie' ? '电影' : (item.type == 'Series' ? '剧集' : '');

    return MediaPosterTile(
      title: item.name,
      imageUrl: image,
      year: year,
      rating: rating,
      badgeText: badge,
      onTap: onTap,
    );
  }
}
