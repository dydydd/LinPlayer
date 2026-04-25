import 'dart:async';

import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lin_player_player/lin_player_player.dart';
import 'package:lin_player_prefs/lin_player_prefs.dart';
import 'package:lin_player_server_adapters/lin_player_server_adapters.dart';
import 'package:lin_player_state/lin_player_state.dart';
import 'package:lin_player_ui/lin_player_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'mobile_ui/show_detail/episode_detail_mobile_view.dart';
import 'mobile_ui/show_detail/movie_detail_mobile_view.dart';
import 'mobile_ui/show_detail/mobile_text_widgets.dart';
import 'mobile_ui/show_detail/show_detail_mobile_view.dart';
import 'plugins/plugin_slot_area.dart';
import 'server_adapters/server_access.dart';
import 'services/browsing_cache_service.dart';
import 'services/built_in_proxy/built_in_proxy_service.dart';
import 'services/playback/player_core_pages.dart';
import 'services/preload/playback_preload_coordinator.dart';
import 'person_page.dart';
import 'tv/tv_focusable.dart';

class _DetailUiTokens {
  // ignore: unused_field
  static const pagePadding = EdgeInsets.fromLTRB(20, 74, 20, 24);
  static const sectionGap = 16.0;
  static const sectionTitleGap = 8.0;
  static const panelPadding = EdgeInsets.all(16);
  static const cardRadius = 12.0;
  static const heroPosterRadius = 14.0;
  static const actionRadius = 999.0;
  static const horizontalGap = 12.0;
  static const horizontalEpisodeCardWidth = 288.0;
  static const horizontalEpisodeStripHeight = 206.0;
}

enum _MovieMoreAction {
  togglePlayed,
  toggleFavorite,
  togglePlayerCore,
}

String _mediaYearText(MediaItem item) {
  final date = (item.premiereDate ?? '').trim();
  if (date.isEmpty) return '';
  final parsed = DateTime.tryParse(date);
  if (parsed != null) return parsed.year.toString();
  if (date.length >= 4) return date.substring(0, 4);
  return '';
}

String _browsingCacheServerScope({
  required AppState appState,
  ServerProfile? server,
  String? baseUrl,
}) {
  final serverId = (server?.id ?? appState.activeServerId ?? '').trim();
  if (serverId.isNotEmpty) return 'srv:$serverId';
  final normalizedBaseUrl = (baseUrl ?? '').trim();
  if (normalizedBaseUrl.isNotEmpty) return 'url:$normalizedBaseUrl';
  return 'default';
}

Widget _sectionTitle(
  BuildContext context,
  String title, {
  Widget? trailing,
}) {
  final text = Text(
    title,
    style: Theme.of(context).textTheme.titleMedium?.copyWith(
          color: Colors.white.withValues(alpha: 0.96),
          fontWeight: FontWeight.w700,
        ),
  );
  if (trailing == null) return text;
  return Row(
    children: [
      Expanded(child: text),
      const SizedBox(width: _DetailUiTokens.sectionTitleGap),
      trailing,
    ],
  );
}

Widget _detailActionButton(
  BuildContext context, {
  required IconData icon,
  required String label,
  required VoidCallback? onTap,
  bool primary = false,
}) {
  const fg = Colors.white;
  final bg = primary
      ? const Color(0xFF1F9F75).withValues(alpha: 0.84)
      : Colors.black.withValues(alpha: 0.34);
  final borderColor =
      primary ? Colors.transparent : Colors.white.withValues(alpha: 0.20);
  return Material(
    color: Colors.transparent,
    child: InkWell(
      borderRadius: BorderRadius.circular(_DetailUiTokens.actionRadius),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(_DetailUiTokens.actionRadius),
          border: Border.all(color: borderColor),
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 160),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: ScaleTransition(scale: animation, child: child),
          ),
          child: Row(
            key: ValueKey<String>('$icon|$label|$primary'),
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: fg),
              const SizedBox(width: 6),
              Text(
                label,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: fg,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

Widget _detailGlassPanel({
  required Widget child,
  EdgeInsetsGeometry? padding,
  bool enableBlur = true,
  double radius = 16,
  bool showBorder = true,
  Gradient? gradient,
}) {
  final borderRadius = BorderRadius.circular(radius);
  final effectiveGradient = gradient ??
      LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.black.withValues(alpha: 0.46),
          Colors.black.withValues(alpha: 0.34),
        ],
      );
  final surface = Container(
    padding: padding,
    decoration: BoxDecoration(
      borderRadius: borderRadius,
      gradient: effectiveGradient,
      border: showBorder
          ? Border.all(color: Colors.white.withValues(alpha: 0.20))
          : null,
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.22),
          blurRadius: 20,
          offset: const Offset(0, 10),
        ),
      ],
    ),
    child: child,
  );
  if (!enableBlur) return ClipRRect(borderRadius: borderRadius, child: surface);
  return ClipRRect(
    borderRadius: borderRadius,
    child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
      child: surface,
    ),
  );
}

class ShowDetailPage extends StatefulWidget {
  const ShowDetailPage({
    super.key,
    required this.itemId,
    required this.title,
    required this.appState,
    this.server,
    this.isTv = false,
  });

  final String itemId;
  final String title;
  final AppState appState;
  final ServerProfile? server;
  final bool isTv;

  @override
  State<ShowDetailPage> createState() => _ShowDetailPageState();
}

class _ShowDetailPageState extends State<ShowDetailPage> {
  MediaItem? _detail;
  List<MediaItem> _seasons = [];
  bool _seasonsVirtual = false;
  List<MediaItem> _similar = [];
  bool _loading = true;
  String? _error;
  MediaItem? _featuredEpisode;
  String? _selectedSeasonId;
  final Map<String, List<MediaItem>> _episodesCache = {};
  List<String> _album = [];
  PlaybackInfoResult? _playInfo;
  List<ChapterInfo> _chapters = [];
  String? _selectedMediaSourceId;
  int? _selectedAudioStreamIndex; // null = default
  int? _selectedSubtitleStreamIndex; // null = default, -1 = off
  bool _localFavorite = false;
  bool _favoriteLoaded = false;
  bool _markBusy = false;
  late String _preloadOwnerKey;
  PreparedPlaybackPreload? _preparedMoviePreload;

  String? get _baseUrl => widget.server?.baseUrl ?? widget.appState.baseUrl;
  String? get _token => widget.server?.token ?? widget.appState.token;
  String? get _userId => widget.server?.userId ?? widget.appState.userId;

  PlaybackSourcePlayerCoreKind get _moviePlaybackCoreKind {
    return playbackSourcePlayerCoreKindForPlayerCore(
      normalizePlayerCoreForPlatform(widget.appState.playerCore),
    );
  }

  bool get _preferBuiltInProxyForMpvPreload =>
      widget.isTv &&
      widget.appState.tvBuiltInProxyEnabled &&
      BuiltInProxyService.instance.status.state == BuiltInProxyState.running;

  PreparedPlaybackPreload? _preparedMoviePreloadForPlayback(MediaItem item) {
    final prepared = _preparedMoviePreload;
    if (prepared == null) return null;
    if (!prepared.matchesPlayback(
      itemId: item.id,
      playerCore: _moviePlaybackCoreKind,
      selectedMediaSourceId: _selectedMediaSourceId,
      audioStreamIndex: _selectedAudioStreamIndex,
      subtitleStreamIndex: _selectedSubtitleStreamIndex,
    )) {
      return null;
    }
    return prepared;
  }

  String get _detailCacheServerScope => _browsingCacheServerScope(
        appState: widget.appState,
        server: widget.server,
        baseUrl: _baseUrl,
      );

  void _applyShowDetailCache(ShowDetailCachePayload payload) {
    final seasons = List<MediaItem>.from(payload.seasons);
    String? selectedSeasonId = payload.selectedSeasonId;
    if (selectedSeasonId != null &&
        seasons.isNotEmpty &&
        !seasons.any((season) => season.id == selectedSeasonId)) {
      selectedSeasonId = seasons.first.id;
    }
    selectedSeasonId ??=
        seasons.isNotEmpty ? seasons.first.id : payload.detail.id.trim();

    MediaItem? featuredEpisode = payload.featuredEpisode;
    if (featuredEpisode == null) {
      final cachedEpisodes = payload.episodesBySeason[selectedSeasonId];
      if (cachedEpisodes != null && cachedEpisodes.isNotEmpty) {
        featuredEpisode = cachedEpisodes.first;
      }
    }

    final access =
        resolveServerAccess(appState: widget.appState, server: widget.server);
    if (access != null) {
      _album = [
        access.adapter.imageUrl(
          access.auth,
          itemId: widget.itemId,
          imageType: 'Primary',
          maxWidth: 800,
        ),
        access.adapter.imageUrl(
          access.auth,
          itemId: widget.itemId,
          imageType: 'Backdrop',
          maxWidth: 1200,
        ),
      ];
    }

    setState(() {
      _detail = payload.detail;
      _seasons = seasons;
      _seasonsVirtual = payload.seasonsVirtual;
      _similar = List<MediaItem>.from(payload.similar);
      _featuredEpisode = featuredEpisode;
      _selectedSeasonId = selectedSeasonId;
      _episodesCache
        ..clear()
        ..addAll(payload.episodesBySeason);
      _playInfo = payload.playInfo;
      _chapters = List<ChapterInfo>.from(payload.chapters);
      _selectedMediaSourceId = payload.selectedMediaSourceId;
      _selectedAudioStreamIndex = payload.selectedAudioStreamIndex;
      _selectedSubtitleStreamIndex = payload.selectedSubtitleStreamIndex;
      _error = null;
      _loading = false;
    });
  }

  ShowDetailCachePayload? _currentShowDetailCachePayload() {
    final detail = _detail;
    if (detail == null) return null;
    return ShowDetailCachePayload(
      detail: detail,
      seasons: List<MediaItem>.from(_seasons),
      seasonsVirtual: _seasonsVirtual,
      similar: List<MediaItem>.from(_similar),
      featuredEpisode: _featuredEpisode,
      episodesBySeason: _episodesCache.map(
        (key, value) => MapEntry(key, List<MediaItem>.from(value)),
      ),
      playInfo: _playInfo,
      chapters: List<ChapterInfo>.from(_chapters),
      selectedSeasonId: _selectedSeasonId,
      selectedMediaSourceId: _selectedMediaSourceId,
      selectedAudioStreamIndex: _selectedAudioStreamIndex,
      selectedSubtitleStreamIndex: _selectedSubtitleStreamIndex,
    );
  }

  void _persistShowDetailCache() {
    final payload = _currentShowDetailCachePayload();
    if (payload == null) return;
    unawaited(
      BrowsingCacheService.instance.writeShowDetail(
        serverScope: _detailCacheServerScope,
        itemId: widget.itemId,
        payload: payload,
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _preloadOwnerKey =
        PlaybackPreloadCoordinator.createOwnerToken('detail_movie');
    _loadLocalFavorite();
    _load();
  }

  @override
  void dispose() {
    PlaybackPreloadCoordinator.cancelOwner(_preloadOwnerKey);
    super.dispose();
  }

  String get _localFavoriteKey {
    final serverKey =
        (_baseUrl ?? 'default').replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
    return 'show_detail_local_favorite_${serverKey}_${widget.itemId}';
  }

  Future<void> _loadLocalFavorite() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        _localFavorite = prefs.getBool(_localFavoriteKey) ?? false;
        _favoriteLoaded = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _favoriteLoaded = true);
    }
  }

  Future<void> _toggleLocalFavorite() async {
    final next = !_localFavorite;
    setState(() => _localFavorite = next);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_localFavoriteKey, next);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(next ? '已加入本地收藏' : '已取消本地收藏'),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _localFavorite = !next);
    }
  }

  Future<void> _refreshProgressAfterReturn(
      {Duration delay = const Duration(milliseconds: 350)}) async {
    final access =
        resolveServerAccess(appState: widget.appState, server: widget.server);
    if (access == null) return;

    final before = _detail?.playbackPositionTicks;
    for (var attempt = 0; attempt < 3; attempt++) {
      final attemptDelay =
          attempt == 0 ? delay : const Duration(milliseconds: 300);
      if (attemptDelay > Duration.zero) {
        await Future<void>.delayed(attemptDelay);
      }

      try {
        final detail = await access.adapter
            .fetchItemDetail(access.auth, itemId: widget.itemId);
        if (!mounted) return;
        setState(() => _detail = detail);
        _persistShowDetailCache();
        if (before == null || detail.playbackPositionTicks != before) return;
      } catch (_) {
        // Best-effort refresh. Keep existing state on failure.
      }
    }
  }

  Future<void> _preloadMovieBestEffort({
    required ServerAccess access,
    required String itemId,
    String? selectedMediaSourceId,
    int? audioStreamIndex,
    int? subtitleStreamIndex,
  }) async {
    if (!widget.appState.preloadEnabled) return;
    late final PreparedPlaybackPreload prepared;
    StreamPreloadResult result;
    try {
      prepared = await PlaybackPreloadCoordinator.prepareItem(
        PlaybackPreloadBuildRequest(
          access: access,
          appState: widget.appState,
          itemId: itemId,
          playerCore: _moviePlaybackCoreKind,
          targetKind: PlaybackPreloadTargetKind.currentItem,
          triggerSource: 'detail_current',
          selectedMediaSourceId: selectedMediaSourceId,
          audioStreamIndex: audioStreamIndex,
          subtitleStreamIndex: subtitleStreamIndex,
          preferredVideoVersion: widget.appState.preferredVideoVersion,
          preferBuiltInProxy:
              _moviePlaybackCoreKind == PlaybackSourcePlayerCoreKind.mpv &&
                  _preferBuiltInProxyForMpvPreload,
          ownerKey: _preloadOwnerKey,
          scopeKey: 'detail_current',
        ),
      );
      if (itemId.trim() == widget.itemId.trim()) {
        _preparedMoviePreload = prepared;
      }
      result = await PlaybackPreloadCoordinator.preloadPrepared(prepared);
    } catch (_) {
      return;
    }

    if (!mounted) return;
    if (result.disabledNow) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('预加载失败，当前源将暂时跳过')),
      );
    }
  }

  Future<void> _load() async {
    _preparedMoviePreload = null;
    final baseUrl = _baseUrl;
    final token = _token;
    final userId = _userId;
    if (baseUrl == null || token == null || userId == null) {
      setState(() {
        _error = '未连接服务器';
      });
      return;
    }

    final access =
        resolveServerAccess(appState: widget.appState, server: widget.server);
    if (access == null) {
      setState(() {
        _error = 'Unsupported server';
        _loading = false;
      });
      return;
    }

    final cached = await BrowsingCacheService.instance.readShowDetail(
      serverScope: _detailCacheServerScope,
      itemId: widget.itemId,
    );
    final cachedPayload = cached?.value;
    if (cachedPayload != null) {
      _applyShowDetailCache(cachedPayload);
      if (cached!.isFresh) return;
    } else {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final detail = await access.adapter.fetchItemDetail(
        access.auth,
        itemId: widget.itemId,
      );
      final isSeries = detail.type.toLowerCase() == 'series';
      final isMovie = detail.type.toLowerCase() == 'movie';

      if (isMovie) {
        unawaited(
          _preloadMovieBestEffort(
            access: access,
            itemId: widget.itemId,
            selectedMediaSourceId: _selectedMediaSourceId,
            audioStreamIndex: _selectedAudioStreamIndex,
            subtitleStreamIndex: _selectedSubtitleStreamIndex,
          ),
        );
      }

      final seasons = isSeries
          ? await access.adapter.fetchSeasons(
              access.auth,
              seriesId: widget.itemId,
            )
          : PagedResult<MediaItem>(const [], 0);

      final seasonItems = isSeries
          ? seasons.items
              .where((s) => s.type.toLowerCase() == 'season')
              .toList()
          : <MediaItem>[];
      seasonItems.sort((a, b) {
        final aNo = a.seasonNumber ?? a.episodeNumber ?? 0;
        final bNo = b.seasonNumber ?? b.episodeNumber ?? 0;
        return aNo.compareTo(bNo);
      });

      final virtualSeason = isSeries && seasonItems.isEmpty;
      final seasonsForUi = isSeries
          ? (virtualSeason
              ? [
                  MediaItem(
                    id: widget.itemId,
                    name: '第1季',
                    type: 'Season',
                    overview: '',
                    communityRating: null,
                    premiereDate: null,
                    genres: const [],
                    runTimeTicks: null,
                    sizeBytes: null,
                    container: null,
                    providerIds: const {},
                    seriesId: widget.itemId,
                    seriesName: detail.name,
                    seasonName: '第1季',
                    seasonNumber: 1,
                    episodeNumber: null,
                    hasImage: detail.hasImage,
                    playbackPositionTicks: 0,
                    people: const [],
                    parentId: widget.itemId,
                  ),
                ]
              : seasonItems)
          : <MediaItem>[];

      MediaItem? firstEp;
      if (isSeries) {
        final previousSeasonId = _selectedSeasonId;
        final defaultSeasonId = (virtualSeason
                ? widget.itemId
                : (seasonItems.isNotEmpty ? seasonItems.first.id : null)) ??
            '';
        final selectedSeasonId = (previousSeasonId != null &&
                seasonsForUi.any((s) => s.id == previousSeasonId))
            ? previousSeasonId
            : defaultSeasonId;

        if (selectedSeasonId.isNotEmpty) {
          try {
            final eps = await access.adapter.fetchEpisodes(
              access.auth,
              seasonId: selectedSeasonId,
            );
            final items = List<MediaItem>.from(eps.items);
            items.sort((a, b) {
              final aNo = a.episodeNumber ?? 0;
              final bNo = b.episodeNumber ?? 0;
              return aNo.compareTo(bNo);
            });
            _episodesCache[selectedSeasonId] = items;
            if (items.isNotEmpty) firstEp = items.first;
          } catch (_) {}
        }
      }
      PagedResult<MediaItem> similar = PagedResult(const [], 0);
      try {
        similar = await access.adapter
            .fetchSimilar(access.auth, itemId: widget.itemId, limit: 12);
      } catch (_) {}

      PlaybackInfoResult? playInfo;
      List<ChapterInfo> chaps = const [];
      String? selectedMediaSourceId = _selectedMediaSourceId;
      int? selectedAudioStreamIndex = _selectedAudioStreamIndex;
      int? selectedSubtitleStreamIndex = _selectedSubtitleStreamIndex;
      if (!isSeries) {
        try {
          playInfo = await access.adapter.fetchPlaybackInfo(
            access.auth,
            itemId: widget.itemId,
            profile: playbackInfoProfileKindForPlaybackSourceCore(
              _moviePlaybackCoreKind,
            ),
          );
          final sources = playInfo.mediaSources.cast<Map<String, dynamic>>();
          if (sources.isNotEmpty) {
            final validSelection = selectedMediaSourceId != null &&
                sources.any(
                    (s) => (s['Id'] as String? ?? '') == selectedMediaSourceId);
            if (!validSelection) {
              selectedMediaSourceId = _pickPreferredMediaSourceId(
                    sources,
                    widget.appState.preferredVideoVersion,
                  ) ??
                  (sources.first['Id'] as String?);
              selectedAudioStreamIndex = null;
              selectedSubtitleStreamIndex = null;
            }
          }
        } catch (_) {
          // PlaybackInfo is optional for the detail UI.
        }
        try {
          chaps = await access.adapter
              .fetchChapters(access.auth, itemId: widget.itemId);
        } catch (_) {
          // Chapters are optional; hide section when unavailable.
        }
      }
      _album = [
        access.adapter.imageUrl(
          access.auth,
          itemId: widget.itemId,
          imageType: 'Primary',
          maxWidth: 800,
        ),
        access.adapter.imageUrl(
          access.auth,
          itemId: widget.itemId,
          imageType: 'Backdrop',
          maxWidth: 1200,
        ),
      ];
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _seasons = seasonsForUi;
        _seasonsVirtual = virtualSeason;
        _featuredEpisode = firstEp;
        _selectedSeasonId = isSeries && seasonsForUi.isNotEmpty
            ? ((_selectedSeasonId != null &&
                    seasonsForUi.any((s) => s.id == _selectedSeasonId))
                ? _selectedSeasonId
                : seasonsForUi.first.id)
            : null;
        _similar = similar.items;
        _playInfo = playInfo;
        _chapters = chaps;
        _selectedMediaSourceId = selectedMediaSourceId;
        _selectedAudioStreamIndex = selectedAudioStreamIndex;
        _selectedSubtitleStreamIndex = selectedSubtitleStreamIndex;
        _error = null;
        _loading = false;
      });
      _persistShowDetailCache();
    } catch (e) {
      if (!mounted) return;
      if (cachedPayload == null) {
        setState(() => _error = e.toString());
      }
    } finally {
      if (mounted && cachedPayload == null) {
        setState(() => _loading = false);
      }
    }
  }

  String _seasonLabel(MediaItem season, int index) {
    final name = season.name.trim();
    final seasonNo = season.seasonNumber ?? season.episodeNumber;
    return seasonNo != null
        ? '第$seasonNo季'
        : (name.isNotEmpty ? name : '第${index + 1}季');
  }

  MediaItem? get _selectedSeason {
    if (_seasons.isEmpty) return null;
    final selectedId = _selectedSeasonId;
    if (selectedId == null || selectedId.isEmpty) return _seasons.first;
    for (final s in _seasons) {
      if (s.id == selectedId) return s;
    }
    return _seasons.first;
  }

  String _selectedSeasonLabel() {
    if (_seasons.isEmpty) return '选择季';
    final selectedId = _selectedSeasonId;
    for (int i = 0; i < _seasons.length; i++) {
      final s = _seasons[i];
      if (selectedId != null && s.id == selectedId) return _seasonLabel(s, i);
    }
    return _seasonLabel(_seasons.first, 0);
  }

  Future<List<MediaItem>> _episodesForSeason(MediaItem season) async {
    final cached = _episodesCache[season.id];
    if (cached != null) return cached;

    final access =
        resolveServerAccess(appState: widget.appState, server: widget.server);
    if (access == null) return const [];

    final eps = await access.adapter.fetchEpisodes(
      access.auth,
      seasonId: season.id,
    );
    final items = List<MediaItem>.from(eps.items);
    items.sort((a, b) {
      final aNo = a.episodeNumber ?? 0;
      final bNo = b.episodeNumber ?? 0;
      return aNo.compareTo(bNo);
    });
    _episodesCache[season.id] = items;
    _persistShowDetailCache();
    return items;
  }

  Future<void> _pickSeason(BuildContext context) async {
    if (_seasons.isEmpty) return;

    final selected = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: ListView(
            children: [
              const ListTile(title: Text('季选择')),
              ..._seasons.asMap().entries.map((entry) {
                final idx = entry.key;
                final s = entry.value;
                final selectedNow = s.id == _selectedSeasonId;
                return ListTile(
                  leading: Icon(
                      selectedNow ? Icons.check_circle : Icons.circle_outlined),
                  title: Text(_seasonLabel(s, idx)),
                  onTap: () => Navigator.of(ctx).pop(s.id),
                );
              }),
            ],
          ),
        );
      },
    );

    if (!mounted) return;
    if (selected == null || selected.isEmpty || selected == _selectedSeasonId) {
      return;
    }

    setState(() {
      _selectedSeasonId = selected;
      _featuredEpisode = null;
    });
    _persistShowDetailCache();

    final season = _selectedSeason;
    if (season == null) return;
    try {
      final episodes = await _episodesForSeason(season);
      if (!mounted || _selectedSeasonId != selected) return;
      setState(() {
        _featuredEpisode = episodes.isNotEmpty ? episodes.first : null;
      });
    } catch (_) {
      // Episode list is optional for the detail UI.
    }
  }

  String _episodeLabel(MediaItem episode, int index) {
    final epNo = episode.episodeNumber ?? (index + 1);
    final epName = episode.name.trim();
    return epName.isNotEmpty ? '$epNo. $epName' : '$epNo. 第$epNo集';
  }

  Future<void> _pickEpisode(BuildContext context) async {
    final season = _selectedSeason;
    if (season == null) return;

    final seasonLabel = _selectedSeasonLabel();
    final selectedEp = await showModalBottomSheet<MediaItem>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return SafeArea(
          child: DraggableScrollableSheet(
            expand: false,
            initialChildSize: widget.isTv ? 0.5 : 0.75,
            minChildSize: 0.4,
            maxChildSize: 0.95,
            builder: (ctx, controller) {
              return FutureBuilder<List<MediaItem>>(
                future: _episodesForSeason(season),
                builder: (ctx, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return ListView(
                      controller: controller,
                      children: const [
                        ListTile(title: Text('选集')),
                        SizedBox(height: 24),
                        Center(child: CircularProgressIndicator()),
                      ],
                    );
                  }
                  if (snapshot.hasError) {
                    return ListView(
                      controller: controller,
                      children: [
                        const ListTile(title: Text('选集')),
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text('加载失败：${snapshot.error}'),
                        ),
                      ],
                    );
                  }
                  final eps = snapshot.data ?? const <MediaItem>[];
                  if (eps.isEmpty) {
                    return ListView(
                      controller: controller,
                      children: const [
                        ListTile(title: Text('选集')),
                        Padding(
                          padding: EdgeInsets.all(16),
                          child: Text('暂无剧集'),
                        ),
                      ],
                    );
                  }

                  return ListView.separated(
                    controller: controller,
                    itemCount: eps.length + 1,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (ctx, index) {
                      if (index == 0) {
                        return ListTile(title: Text('选集（$seasonLabel）'));
                      }
                      final epIndex = index - 1;
                      final ep = eps[epIndex];
                      return ListTile(
                        leading: const Icon(Icons.play_circle_outline),
                        title: Text(_episodeLabel(ep, epIndex)),
                        onTap: () => Navigator.of(ctx).pop(ep),
                      );
                    },
                  );
                },
              );
            },
          ),
        );
      },
    );

    if (!context.mounted) return;
    if (selectedEp == null) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EpisodeDetailPage(
          episode: selectedEp,
          appState: widget.appState,
          server: widget.server,
          isTv: widget.isTv,
        ),
      ),
    );
  }

  Future<void> _openEpisode(BuildContext context, MediaItem episode) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EpisodeDetailPage(
          episode: episode,
          appState: widget.appState,
          server: widget.server,
          isTv: widget.isTv,
        ),
      ),
    );
  }

  String _yearText(MediaItem item) {
    return _mediaYearText(item);
  }

  String _episodeTitle(MediaItem ep) {
    final epNo = ep.episodeNumber ?? 1;
    final name = ep.name.trim();
    return name.isNotEmpty
        ? 'S${ep.seasonNumber ?? 1}:E$epNo - $name'
        : 'S${ep.seasonNumber ?? 1}:E$epNo';
  }

  void _showTopActionHint(String label) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label 功能待接入')),
    );
  }

  Future<void> _playMovie(MediaItem item) async {
    final start = item.playbackPositionTicks > 0
        ? _ticksToDuration(item.playbackPositionTicks)
        : null;
    final preparedPreload = _preparedMoviePreloadForPlayback(item);
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => buildNetworkPlayerPage(
          title: item.name,
          itemId: item.id,
          appState: widget.appState,
          server: widget.server,
          isTv: widget.isTv,
          startPosition: start,
          mediaSourceId: _selectedMediaSourceId,
          audioStreamIndex: _selectedAudioStreamIndex,
          subtitleStreamIndex: _selectedSubtitleStreamIndex,
          preparedPreload: preparedPreload,
        ),
      ),
    );
    if (!mounted) return;
    await _refreshProgressAfterReturn();
  }

  Future<void> _toggleItemPlayedMark() async {
    if (_markBusy) return;
    final access =
        resolveServerAccess(appState: widget.appState, server: widget.server);
    if (access == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('未连接服务器')),
      );
      return;
    }

    final currentPlayed = _detail?.played ?? false;
    final nextPlayed = !currentPlayed;

    setState(() => _markBusy = true);
    try {
      await access.adapter.updatePlaybackPosition(
        access.auth,
        itemId: widget.itemId,
        positionTicks: 0,
        played: nextPlayed,
      );

      final detail = await access.adapter
          .fetchItemDetail(access.auth, itemId: widget.itemId);
      if (!mounted) return;
      setState(() => _detail = detail);
      _persistShowDetailCache();

      unawaited(
        widget.appState.loadContinueWatching(
          forceRefresh: true,
          forceNewRequest: true,
        ),
      );
      unawaited(widget.appState.loadHome(forceRefresh: true));

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(nextPlayed ? '已标记为已播放' : '已标记为未播放')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('标记失败：$e')),
      );
    } finally {
      if (mounted) setState(() => _markBusy = false);
    }
  }

  Future<void> _togglePlayerCore() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    final next = widget.appState.playerCore == PlayerCore.exo
        ? PlayerCore.mpv
        : PlayerCore.exo;
    try {
      await widget.appState.setPlayerCore(next);
      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(next == PlayerCore.exo ? '已切换到 ExoPlayer' : '已切换到 mpv'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('切换失败：$e')),
      );
    }
  }

  Future<void> _showMovieMoreSheet(BuildContext context) async {
    final played = _detail?.played ?? false;
    final canSwitchCore =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

    final action = await showModalBottomSheet<_MovieMoreAction>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(
                  played ? Icons.radio_button_unchecked : Icons.check_circle,
                ),
                title: Text(played ? '标记为未播放' : '标记为已播放'),
                onTap: _markBusy
                    ? null
                    : () => Navigator.of(sheetContext)
                        .pop(_MovieMoreAction.togglePlayed),
              ),
              ListTile(
                leading: Icon(
                  _localFavorite
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  color: _localFavorite ? Colors.pinkAccent : null,
                ),
                title: Text(_localFavorite ? '取消本地收藏' : '加入本地收藏'),
                onTap: !_favoriteLoaded
                    ? null
                    : () => Navigator.of(sheetContext)
                        .pop(_MovieMoreAction.toggleFavorite),
              ),
              if (canSwitchCore)
                ListTile(
                  leading: const Icon(Icons.memory_rounded),
                  title: Text(
                    widget.appState.playerCore == PlayerCore.exo
                        ? '切换到 mpv'
                        : '切换到 ExoPlayer',
                  ),
                  onTap: () => Navigator.of(sheetContext)
                      .pop(_MovieMoreAction.togglePlayerCore),
                ),
            ],
          ),
        );
      },
    );

    if (!mounted || action == null) return;

    switch (action) {
      case _MovieMoreAction.togglePlayed:
        if (!_markBusy) {
          await _toggleItemPlayedMark();
        }
        break;
      case _MovieMoreAction.toggleFavorite:
        if (_favoriteLoaded) {
          await _toggleLocalFavorite();
        }
        break;
      case _MovieMoreAction.togglePlayerCore:
        await _togglePlayerCore();
        break;
    }
  }

  List<String> _movieMediaBadges(
    MediaItem item, {
    required Duration? runtime,
    Map<String, dynamic>? mediaSource,
  }) {
    final badges = <String>[
      if (_yearText(item).isNotEmpty) _yearText(item),
      if (item.officialRating?.trim().isNotEmpty == true)
        item.officialRating!.trim(),
      ...item.genres.take(2),
      if (item.communityRating != null &&
          item.communityRating!.isFinite &&
          item.communityRating! > 0)
        '评分 ${item.communityRating!.toStringAsFixed(1)}',
    ];

    final resolution = _ShowDetailPageState._mediaSourceResolutionText(
      mediaSource,
    );
    if (resolution.isNotEmpty) {
      badges.add('分辨率 $resolution');
    }

    final bitrate = _ShowDetailPageState._mediaSourceBitrateText(
      mediaSource,
      fallbackSizeBytes: item.sizeBytes,
      fallbackRuntimeTicks: item.runTimeTicks,
    );
    if (bitrate.isNotEmpty) {
      badges.add('码率 $bitrate');
    }

    final size = _ShowDetailPageState._mediaSourceSizeText(
      mediaSource,
      fallbackSizeBytes: item.sizeBytes,
    );
    if (size.isNotEmpty) {
      badges.add('大小 $size');
    }

    final runtimeText = _movieRuntimeText(runtime);
    if (runtimeText.isNotEmpty) {
      badges.add('时长 $runtimeText');
    }

    return badges;
  }

  String _movieRuntimeText(Duration? runtime) {
    if (runtime == null || runtime <= Duration.zero) return '';
    return _fmt(runtime);
  }

  String _movieSelectedAudioText(Map<String, dynamic> mediaSource) {
    final audioStreams = _ShowDetailPageState._streamsOfType(
      mediaSource,
      'Audio',
    );
    final defaultAudio = _ShowDetailPageState._defaultStream(audioStreams);
    final selectedAudio = _selectedAudioStreamIndex != null
        ? audioStreams.firstWhere(
            (stream) =>
                _ShowDetailPageState._asInt(stream['Index']) ==
                _selectedAudioStreamIndex,
            orElse: () => defaultAudio ?? const <String, dynamic>{},
          )
        : defaultAudio;
    if (selectedAudio == null || selectedAudio.isEmpty) return '默认';

    return _ShowDetailPageState._streamLabel(
          selectedAudio,
          includeCodec: false,
        ) +
        (selectedAudio == defaultAudio ? ' (默认)' : '');
  }

  String _movieSelectedSubtitleText(Map<String, dynamic> mediaSource) {
    final subtitleStreams = _ShowDetailPageState._streamsOfType(
      mediaSource,
      'Subtitle',
    );
    final defaultSubtitle =
        _ShowDetailPageState._defaultStream(subtitleStreams);
    final Map<String, dynamic>? selectedSubtitle;
    if (_selectedSubtitleStreamIndex == -1) {
      selectedSubtitle = null;
    } else if (_selectedSubtitleStreamIndex != null) {
      selectedSubtitle = subtitleStreams.firstWhere(
        (stream) =>
            _ShowDetailPageState._asInt(stream['Index']) ==
            _selectedSubtitleStreamIndex,
        orElse: () => defaultSubtitle ?? const <String, dynamic>{},
      );
    } else {
      selectedSubtitle = defaultSubtitle;
    }

    final hasSubtitles = subtitleStreams.isNotEmpty;
    if (_selectedSubtitleStreamIndex == -1) return '关闭';
    if (selectedSubtitle != null && selectedSubtitle.isNotEmpty) {
      return _ShowDetailPageState._streamLabel(
        selectedSubtitle,
        includeCodec: false,
      );
    }
    return hasSubtitles ? '默认' : '关闭';
  }

  Widget _heroActionButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
    bool primary = false,
  }) {
    return _detailActionButton(
      context,
      icon: icon,
      label: label,
      onTap: onTap,
      primary: primary,
    );
  }

  Map<String, Object?> _buildDetailPluginParams(MediaItem item) {
    final yearText = _mediaYearText(item);
    final year = int.tryParse(yearText);
    return <String, Object?>{
      'page': 'detail',
      'itemId': item.id,
      'title': item.name,
      'media': <String, Object?>{
        'id': item.id,
        'type': item.type,
        'title': item.name,
        if (year != null) 'year': year,
      },
      'item': <String, Object?>{
        'id': item.id,
        'name': item.name,
        'type': item.type,
        if (year != null) 'year': year,
      },
    };
  }

  void _openPersonPage(BuildContext context, MediaPerson person) {
    final id = person.id.trim();
    if (id.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PersonPage(
          appState: widget.appState,
          server: widget.server,
          personId: id,
          seedName: person.name,
          isTv: widget.isTv,
          onOpenItem: (ctx, entry) {
            Navigator.of(ctx).push(
              MaterialPageRoute(
                builder: (_) => ShowDetailPage(
                  itemId: entry.id,
                  title: entry.name,
                  appState: widget.appState,
                  server: widget.server,
                  isTv: widget.isTv,
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  String _episodeStripLabel(MediaItem episode, int index) {
    final seasonNo = episode.seasonNumber;
    final episodeNo = episode.episodeNumber ?? (index + 1);
    if (seasonNo != null && seasonNo > 0) {
      return 'S${seasonNo.toString().padLeft(2, '0')}E${episodeNo.toString().padLeft(2, '0')}';
    }
    return '第$episodeNo集';
  }

  Widget _buildMobileDetailPage(
    BuildContext context, {
    required MediaItem item,
    required ServerAccess? access,
    required bool isSeries,
    required Duration? runtime,
    required PlaybackInfoResult? playInfo,
    required bool enableBlur,
    required String heroImageUrl,
  }) {
    if (!isSeries) {
      return _buildMobileMovieDetailPage(
        context,
        item: item,
        access: access,
        runtime: runtime,
        playInfo: playInfo,
        enableBlur: enableBlur,
      );
    }

    final sections = <Widget>[
      if (_seasons.isNotEmpty)
        _mobileSeriesEpisodesSection(
          context,
          enableBlur: enableBlur,
          seriesItem: item,
          access: access,
        ),
      if (item.people.isNotEmpty && access != null)
        _mobilePeopleSection(
          context,
          access: access,
          enableBlur: enableBlur,
          people: item.people,
        ),
      if (_chapters.isNotEmpty)
        _detailGlassPanel(
          enableBlur: enableBlur,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
          radius: 22,
          showBorder: false,
          child: _chaptersSection(context, _chapters),
        ),
      if (_similar.isNotEmpty)
        _detailGlassPanel(
          enableBlur: enableBlur,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
          radius: 22,
          showBorder: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionTitle(context, '更多类似'),
              const SizedBox(height: 12),
              SizedBox(
                height: 236,
                child: _withHorizontalEdgeFade(
                  context,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _similar.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 12),
                    itemBuilder: (context, index) {
                      final similar = _similar[index];
                      final img = similar.hasImage && access != null
                          ? access.adapter.imageUrl(
                              access.auth,
                              itemId: similar.id,
                              maxWidth: 400,
                            )
                          : null;
                      final year = _yearText(similar);
                      final badge = similar.type == 'Movie'
                          ? '电影'
                          : (similar.type == 'Series' ? '剧集' : '');
                      return _HoverScale(
                        child: SizedBox(
                          width: 138,
                          child: MediaPosterTile(
                            title: similar.name,
                            titleMaxLines: 2,
                            imageUrl: img,
                            year: year,
                            rating: similar.communityRating,
                            badgeText: badge,
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => ShowDetailPage(
                                    itemId: similar.id,
                                    title: similar.name,
                                    appState: widget.appState,
                                    server: widget.server,
                                    isTv: widget.isTv,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      _detailGlassPanel(
        enableBlur: enableBlur,
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
        radius: 22,
        showBorder: false,
        child: _externalLinksSection(context, item, widget.appState),
      ),
      PluginSlotArea(
        appState: widget.appState,
        slotId: 'detail.sections.bottom',
        params: _buildDetailPluginParams(item),
      ),
    ];

    return ShowDetailMobileView(
      heroImageUrl: heroImageUrl,
      onRefresh: _load,
      heroSection: _mobileHeroSection(
        context,
        item: item,
        access: access,
        isSeries: true,
        runtime: runtime,
      ),
      sections: sections,
      bottomDock: null,
    );
  }

  Widget _buildMobileMovieDetailPage(
    BuildContext context, {
    required MediaItem item,
    required ServerAccess? access,
    required Duration? runtime,
    required PlaybackInfoResult? playInfo,
    required bool enableBlur,
  }) {
    final currentMediaSource = playInfo == null
        ? null
        : _ShowDetailPageState._findMediaSource(
            playInfo,
            _selectedMediaSourceId,
          );
    final audioStreams = currentMediaSource == null
        ? const <Map<String, dynamic>>[]
        : _ShowDetailPageState._streamsOfType(currentMediaSource, 'Audio');
    final subtitleStreams = currentMediaSource == null
        ? const <Map<String, dynamic>>[]
        : _ShowDetailPageState._streamsOfType(currentMediaSource, 'Subtitle');
    final coverUrl = access == null
        ? ''
        : access.adapter.imageUrl(
            access.auth,
            itemId: item.id,
            imageType: 'Primary',
            maxWidth: 900,
          );
    final backdropUrl = access == null
        ? ''
        : access.adapter.imageUrl(
            access.auth,
            itemId: item.id,
            imageType: 'Backdrop',
            maxWidth: 1600,
          );
    final playLabel = item.playbackPositionTicks > 0
        ? '继续播放 ${_fmtClock(_ticksToDuration(item.playbackPositionTicks))}'
        : '播放';
    final versionValue = playInfo == null
        ? '加载中'
        : (currentMediaSource == null
            ? '暂无版本'
            : _ShowDetailPageState._mediaSourceTitle(currentMediaSource));
    final audioValue = currentMediaSource == null
        ? '默认'
        : _movieSelectedAudioText(currentMediaSource);
    final subtitleValue = currentMediaSource == null
        ? (_selectedSubtitleStreamIndex == -1 ? '关闭' : '默认')
        : _movieSelectedSubtitleText(currentMediaSource);

    final sections = <Widget>[
      if (playInfo != null)
        _episodeMediaInfoSection(
          context,
          playInfo,
          selectedMediaSourceId: _selectedMediaSourceId,
        ),
      if (item.people.isNotEmpty && access != null)
        _mobilePeopleSection(
          context,
          access: access,
          enableBlur: enableBlur,
          people: item.people,
        ),
      if (_chapters.isNotEmpty)
        _detailGlassPanel(
          enableBlur: enableBlur,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
          radius: 22,
          showBorder: false,
          child: _chaptersSection(context, _chapters),
        ),
      if (_similar.isNotEmpty)
        _detailGlassPanel(
          enableBlur: enableBlur,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
          radius: 22,
          showBorder: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionTitle(context, '更多类似'),
              const SizedBox(height: 12),
              SizedBox(
                height: 236,
                child: _withHorizontalEdgeFade(
                  context,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _similar.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 12),
                    itemBuilder: (context, index) {
                      final similar = _similar[index];
                      final imageUrl = similar.hasImage && access != null
                          ? access.adapter.imageUrl(
                              access.auth,
                              itemId: similar.id,
                              maxWidth: 400,
                            )
                          : null;
                      final year = _yearText(similar);
                      final badge = similar.type == 'Movie'
                          ? '电影'
                          : (similar.type == 'Series' ? '剧集' : '');
                      return _HoverScale(
                        child: SizedBox(
                          width: 138,
                          child: MediaPosterTile(
                            title: similar.name,
                            titleMaxLines: 2,
                            imageUrl: imageUrl,
                            year: year,
                            rating: similar.communityRating,
                            badgeText: badge,
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => ShowDetailPage(
                                    itemId: similar.id,
                                    title: similar.name,
                                    appState: widget.appState,
                                    server: widget.server,
                                    isTv: widget.isTv,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      _detailGlassPanel(
        enableBlur: enableBlur,
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
        radius: 22,
        showBorder: false,
        child: _externalLinksSection(context, item, widget.appState),
      ),
      PluginSlotArea(
        appState: widget.appState,
        slotId: 'detail.sections.bottom',
        params: _buildDetailPluginParams(item),
      ),
    ];

    return MovieDetailMobileView(
      title: item.name,
      overview: item.overview.trim(),
      runtimeText: _movieRuntimeText(runtime),
      mediaBadges: _movieMediaBadges(
        item,
        runtime: runtime,
        mediaSource: currentMediaSource,
      ),
      coverUrl: coverUrl,
      backdropUrl: backdropUrl,
      versionValue: versionValue,
      audioValue: audioValue,
      subtitleValue: subtitleValue,
      playLabel: playLabel,
      onRefresh: _load,
      onPlay: () => _playMovie(item),
      onMore: () => _showMovieMoreSheet(context),
      onPickVersion:
          playInfo == null ? null : () => _pickMediaSource(context, playInfo),
      onPickAudio: audioStreams.isEmpty
          ? null
          : () => _pickAudioStream(context, currentMediaSource!),
      onPickSubtitle: subtitleStreams.isEmpty
          ? null
          : () => _pickSubtitleStream(context, currentMediaSource!),
      sections: sections,
    );
  }

  Widget _mobileHeroSection(
    BuildContext context, {
    required MediaItem item,
    required ServerAccess? access,
    required bool isSeries,
    required Duration? runtime,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final width = MediaQuery.of(context).size.width;
    final posterWidth = width >= 440 ? 142.0 : 118.0;
    final posterUrl = access == null
        ? ''
        : access.adapter.imageUrl(
            access.auth,
            itemId: item.id,
            imageType: 'Primary',
            maxWidth: 720,
          );
    final year = _yearText(item);
    final meta = <String>[
      if (year.isNotEmpty) year,
      if (item.officialRating?.trim().isNotEmpty == true)
        item.officialRating!.trim(),
      ...item.genres.take(2),
      if (item.communityRating != null &&
          item.communityRating!.isFinite &&
          item.communityRating! > 0)
        '★ ${item.communityRating!.toStringAsFixed(1)}',
      if (isSeries && _seasons.isNotEmpty) '${_seasons.length}季',
      if (!isSeries && runtime != null) _fmt(runtime),
    ];
    final overview = item.overview.trim();
    final playLabel = item.playbackPositionTicks > 0
        ? '继续播放 ${_fmtClock(_ticksToDuration(item.playbackPositionTicks))}'
        : '播放';

    return _detailGlassPanel(
      enableBlur: !widget.isTv && widget.appState.enableBlurEffects,
      radius: 22,
      showBorder: false,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: posterWidth,
            child: Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: AspectRatio(
                    aspectRatio: 2 / 3,
                    child: posterUrl.isEmpty
                        ? DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  scheme.primary.withValues(alpha: 0.28),
                                  Colors.black.withValues(alpha: 0.52),
                                ],
                              ),
                            ),
                            child: const Center(
                              child: Icon(Icons.movie_creation_outlined),
                            ),
                          )
                        : LinNetworkImage(
                            imageUrl: posterUrl,
                            fit: BoxFit.cover,
                            errorWidget:
                                const ColoredBox(color: Colors.black26),
                          ),
                  ),
                ),
                Align(
                  alignment: Alignment.topRight,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 8, right: 8),
                    child: Material(
                      color: Colors.black.withValues(alpha: 0.58),
                      borderRadius: BorderRadius.circular(999),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(999),
                        onTap: _favoriteLoaded ? _toggleLocalFavorite : null,
                        child: Container(
                          width: 32,
                          height: 32,
                          alignment: Alignment.center,
                          child: Icon(
                            _localFavorite
                                ? Icons.favorite_rounded
                                : Icons.favorite_border_rounded,
                            size: 18,
                            color: _localFavorite
                                ? const Color(0xFFFF8CA8)
                                : Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    height: 1.12,
                  ),
                ),
                if (meta.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: meta
                        .map(
                          (value) => Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              value,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ],
                if (overview.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  ExpandableText(
                    overview,
                    collapsedLines: 5,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: Colors.white.withValues(alpha: 0.78),
                      height: 1.4,
                    ),
                  ),
                ],
                if (!isSeries) ...[
                  const SizedBox(height: 12),
                  _heroActionButton(
                    context,
                    icon: Icons.play_arrow_rounded,
                    label: playLabel,
                    primary: true,
                    onTap: () => _playMovie(item),
                  ),
                ],
                const SizedBox(height: 12),
                PluginSlotArea(
                  appState: widget.appState,
                  slotId: 'detail.hero.actions',
                  axis: Axis.horizontal,
                  gap: 8,
                  params: _buildDetailPluginParams(item),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _mobileSeriesEpisodesSection(
    BuildContext context, {
    required bool enableBlur,
    required MediaItem seriesItem,
    required ServerAccess? access,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final selectedSeason = _selectedSeason;
    const episodeStripHeight = 160.0;
    final buttonStyle = OutlinedButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      foregroundColor: Colors.white,
      backgroundColor: Colors.white.withValues(alpha: 0.08),
      side: BorderSide.none,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      textStyle: theme.textTheme.labelLarge?.copyWith(
        fontWeight: FontWeight.w700,
      ),
    );

    Widget buildEpisodeList() {
      if (selectedSeason == null) {
        return Text(
          '暂无可用剧集',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: Colors.white70,
            fontWeight: FontWeight.w600,
          ),
        );
      }

      return FutureBuilder<List<MediaItem>>(
        future: _episodesForSeason(selectedSeason),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return SizedBox(
              height: episodeStripHeight,
              child: Center(child: CircularProgressIndicator()),
            );
          }
          if (snapshot.hasError) {
            return Text(
              '剧集加载失败',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.error,
                fontWeight: FontWeight.w600,
              ),
            );
          }

          final episodes = snapshot.data ?? const <MediaItem>[];
          if (episodes.isEmpty) {
            return Text(
              '这一季还没有剧集',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.white70,
                fontWeight: FontWeight.w600,
              ),
            );
          }

          return SizedBox(
            height: episodeStripHeight,
            child: _withHorizontalEdgeFade(
              context,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: episodes.length,
                separatorBuilder: (_, __) => const SizedBox(width: 14),
                itemBuilder: (context, index) {
                  final episode = episodes[index];
                  final coverUrl = access == null
                      ? ''
                      : access.adapter.imageUrl(
                          access.auth,
                          itemId: episode.hasImage
                              ? episode.id
                              : (selectedSeason.id.isNotEmpty
                                  ? selectedSeason.id
                                  : seriesItem.id),
                          maxWidth: 640,
                        );
                  final episodeName = episode.name.trim();
                  return SizedBox(
                    width: 168,
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(22),
                        onTap: () => _openEpisode(context, episode),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              DecoratedBox(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(22),
                                  boxShadow: [
                                    BoxShadow(
                                      color:
                                          Colors.black.withValues(alpha: 0.18),
                                      blurRadius: 18,
                                      offset: const Offset(0, 10),
                                    ),
                                  ],
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(22),
                                  child: AspectRatio(
                                    aspectRatio: 16 / 9,
                                    child: coverUrl.isEmpty
                                        ? ColoredBox(
                                            color: Colors.white.withValues(
                                              alpha: 0.08,
                                            ),
                                          )
                                        : LinNetworkImage(
                                            imageUrl: coverUrl,
                                            fit: BoxFit.cover,
                                            errorWidget: const ColoredBox(
                                              color: Colors.black26,
                                            ),
                                          ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                _episodeStripLabel(episode, index),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 4),
                              SizedBox(
                                height: 18,
                                child: episodeName.isEmpty
                                    ? const SizedBox.shrink()
                                    : CenteredMarqueeText(
                                        episodeName,
                                        style:
                                            theme.textTheme.bodySmall?.copyWith(
                                          color: Colors.white.withValues(
                                            alpha: 0.74,
                                          ),
                                          height: 1.2,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          );
        },
      );
    }

    return _detailGlassPanel(
      enableBlur: enableBlur,
      radius: 22,
      showBorder: false,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(
            context,
            '选集',
            trailing: Text(
              _selectedSeasonLabel(),
              style: theme.textTheme.labelMedium?.copyWith(
                color: Colors.white70,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: buttonStyle,
                  onPressed: () => _pickSeason(context),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.layers_outlined, size: 18),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          _selectedSeasonLabel(),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.expand_more_rounded, size: 18),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(
                  style: buttonStyle,
                  onPressed: selectedSeason == null
                      ? null
                      : () => _pickEpisode(context),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.format_list_numbered_rounded, size: 18),
                      SizedBox(width: 8),
                      Text('集数'),
                      SizedBox(width: 4),
                      Icon(Icons.expand_more_rounded, size: 18),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          buildEpisodeList(),
        ],
      ),
    );
  }

  Widget _mobilePeopleSection(
    BuildContext context, {
    required ServerAccess access,
    required bool enableBlur,
    required List<MediaPerson> people,
  }) {
    final theme = Theme.of(context);
    final cast = people.where((person) => person.id.trim().isNotEmpty).toList();
    if (cast.isEmpty) return const SizedBox.shrink();

    return _detailGlassPanel(
      enableBlur: enableBlur,
      radius: 22,
      showBorder: false,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(context, '演职人员'),
          const SizedBox(height: 12),
          SizedBox(
            height: 188,
            child: _withHorizontalEdgeFade(
              context,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: cast.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  final person = cast[index];
                  final imageUrl = access.adapter.personImageUrl(
                    access.auth,
                    personId: person.id,
                    maxWidth: 320,
                  );
                  return SizedBox(
                    width: 104,
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => _openPersonPage(context, person),
                        child: Ink(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.12),
                                blurRadius: 14,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: AspectRatio(
                                  aspectRatio: 3 / 4,
                                  child: imageUrl.isEmpty
                                      ? const ColoredBox(
                                          color: Colors.black26,
                                          child: Icon(Icons.person),
                                        )
                                      : LinNetworkImage(
                                          imageUrl: imageUrl,
                                          fit: BoxFit.cover,
                                          errorWidget: const ColoredBox(
                                            color: Colors.black26,
                                            child: Icon(Icons.person),
                                          ),
                                        ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                person.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: theme.textTheme.labelLarge?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                person.role.trim().isEmpty
                                    ? person.type
                                    : person.role,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: Colors.white70,
                                  height: 1.2,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailHeroSection(
    BuildContext context, {
    required MediaItem item,
    required ServerAccess? access,
    required bool isSeries,
    required Duration? runtime,
  }) {
    final theme = Theme.of(context);
    final width = MediaQuery.of(context).size.width;
    final wide = width >= 980;
    const heroTextColor = Colors.white;
    final heroMutedTextColor = Colors.white.withValues(alpha: 0.88);
    final heroMetaBg = Colors.black.withValues(alpha: 0.32);
    final heroMetaBorder = Colors.white.withValues(alpha: 0.22);
    final posterUrl = access == null
        ? ''
        : access.adapter.imageUrl(
            access.auth,
            itemId: item.id,
            imageType: 'Primary',
            maxWidth: 720,
          );
    final year = _yearText(item);
    final meta = <String>[
      if (item.communityRating != null)
        '★ ${item.communityRating!.toStringAsFixed(1)}',
      if (year.isNotEmpty) year,
      'MBS',
      'SG-PG13',
      if (isSeries) '共${_seasons.length}季',
      if (!isSeries && runtime != null) _fmt(runtime),
    ];
    final featuredLabel =
        _featuredEpisode == null ? '' : _episodeTitle(_featuredEpisode!);

    final posterCard = SizedBox(
      width: wide ? 290 : 220,
      child: Stack(
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.pinkAccent.withValues(alpha: 0.82),
              borderRadius:
                  BorderRadius.circular(_DetailUiTokens.heroPosterRadius),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 24,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(_DetailUiTokens.cardRadius),
              child: AspectRatio(
                aspectRatio: 2 / 3,
                child: posterUrl.isEmpty
                    ? const ColoredBox(color: Colors.black26)
                    : LinNetworkImage(
                        imageUrl: posterUrl,
                        fit: BoxFit.cover,
                        errorWidget: const ColoredBox(color: Colors.black26),
                      ),
              ),
            ),
          ),
          Positioned(
            top: 10,
            left: 10,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                item.communityRating?.toStringAsFixed(1) ?? '--',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: Material(
              color: Colors.black.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(999),
              child: IconButton(
                onPressed: _favoriteLoaded ? _toggleLocalFavorite : null,
                icon: Icon(
                  _localFavorite ? Icons.star : Icons.star_border_rounded,
                  color: _localFavorite ? Colors.pinkAccent : heroTextColor,
                ),
              ),
            ),
          ),
        ],
      ),
    );

    final infoContent = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          item.name,
          style: (wide
                  ? theme.textTheme.headlineMedium
                  : theme.textTheme.headlineSmall)
              ?.copyWith(
            color: heroTextColor,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: meta
              .map(
                (m) => Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: heroMetaBg,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: heroMetaBorder),
                  ),
                  child: Text(
                    m,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: heroTextColor,
                    ),
                  ),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: item.genres.take(3).map((g) => _pill(context, g)).toList(),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            if (!isSeries)
              _heroActionButton(
                context,
                icon: Icons.play_arrow,
                label: '播放',
                primary: true,
                onTap: () => _playMovie(item),
              ),
            if (!isSeries)
              _heroActionButton(
                context,
                icon: item.played
                    ? Icons.check_circle
                    : Icons.radio_button_unchecked,
                label: item.played ? '已播放' : '未播放',
                onTap: null,
              ),
            _heroActionButton(
              context,
              icon: _localFavorite ? Icons.favorite : Icons.favorite_border,
              label: _localFavorite ? '已收藏' : '收藏',
              onTap: _favoriteLoaded ? _toggleLocalFavorite : null,
            ),
            _heroActionButton(
              context,
              icon: Icons.more_horiz,
              label: '更多',
              onTap: () => _showTopActionHint('更多'),
            ),
          ],
        ),
        PluginSlotArea(
          appState: widget.appState,
          slotId: 'detail.hero.actions',
          axis: Axis.horizontal,
          gap: 8,
          params: _buildDetailPluginParams(item),
        ),
        if (featuredLabel.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            featuredLabel,
            style: theme.textTheme.titleSmall?.copyWith(
              color: heroTextColor,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
        const SizedBox(height: 8),
        Text(
          item.overview,
          maxLines: 4,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: heroMutedTextColor,
            height: 1.45,
          ),
        ),
      ],
    );

    final logoText = Text(
      item.name,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.headlineSmall?.copyWith(
        color: heroTextColor,
        fontWeight: FontWeight.w700,
        shadows: const [
          Shadow(color: Colors.black54, blurRadius: 10),
        ],
      ),
    );

    final infoPanel = wide
        ? Stack(
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 240),
                child: infoContent,
              ),
              Positioned(
                right: 0,
                top: 8,
                child: SizedBox(width: 220, child: logoText),
              ),
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              infoContent,
              const SizedBox(height: 12),
              logoText,
            ],
          );

    return _detailGlassPanel(
      enableBlur: !widget.isTv && widget.appState.enableBlurEffects,
      padding: _DetailUiTokens.panelPadding,
      child: wide
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                posterCard,
                const SizedBox(width: 18),
                Expanded(child: infoPanel),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Align(alignment: Alignment.centerLeft, child: posterCard),
                const SizedBox(height: 16),
                infoPanel,
              ],
            ),
    );
  }

  Widget _unwatchedEpisodesSection(
    BuildContext context, {
    required MediaItem seriesItem,
    required ServerAccess? access,
  }) {
    final season = _selectedSeason;
    if (season == null) return const SizedBox.shrink();

    return FutureBuilder<List<MediaItem>>(
      future: _episodesForSeason(season),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const SizedBox(
            height: 200,
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return Text(
            '加载剧集失败：${snapshot.error}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.white70,
                ),
          );
        }

        final episodes = snapshot.data ?? const <MediaItem>[];
        final unwatched = episodes.where((ep) => !ep.played).toList();
        if (unwatched.isEmpty) {
          return Text(
            '暂无未观看剧集',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.white70,
                ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle(context, '尚未观看'),
            const SizedBox(height: 8),
            SizedBox(
              height: _DetailUiTokens.horizontalEpisodeStripHeight,
              child: _withHorizontalEdgeFade(
                context,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  itemCount: unwatched.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(width: _DetailUiTokens.horizontalGap),
                  itemBuilder: (context, index) {
                    final ep = unwatched[index];
                    final epNo = ep.episodeNumber ?? (index + 1);
                    final seasonNo =
                        ep.seasonNumber ?? season.seasonNumber ?? 1;
                    final imageUrl = access == null
                        ? ''
                        : access.adapter.imageUrl(
                            access.auth,
                            itemId: ep.hasImage
                                ? ep.id
                                : (season.id.isNotEmpty
                                    ? season.id
                                    : seriesItem.id),
                            maxWidth: 640,
                          );
                    return _HoverScale(
                      child: SizedBox(
                        width: _DetailUiTokens.horizontalEpisodeCardWidth,
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () => _openEpisode(context, ep),
                            borderRadius: BorderRadius.circular(
                                _DetailUiTokens.cardRadius),
                            child: Ink(
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.26),
                                borderRadius: BorderRadius.circular(
                                    _DetailUiTokens.cardRadius),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.22),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  ClipRRect(
                                    borderRadius: const BorderRadius.vertical(
                                      top: Radius.circular(
                                          _DetailUiTokens.cardRadius),
                                    ),
                                    child: AspectRatio(
                                      aspectRatio: 16 / 9,
                                      child: Stack(
                                        fit: StackFit.expand,
                                        children: [
                                          imageUrl.isEmpty
                                              ? const ColoredBox(
                                                  color: Colors.black26,
                                                )
                                              : LinNetworkImage(
                                                  imageUrl: imageUrl,
                                                  fit: BoxFit.cover,
                                                  errorWidget: const ColoredBox(
                                                    color: Colors.black26,
                                                  ),
                                                ),
                                          Align(
                                            alignment: Alignment.bottomCenter,
                                            child: DecoratedBox(
                                              decoration: BoxDecoration(
                                                gradient: LinearGradient(
                                                  begin: Alignment.topCenter,
                                                  end: Alignment.bottomCenter,
                                                  colors: [
                                                    Colors.transparent,
                                                    Colors.black.withValues(
                                                        alpha: 0.78),
                                                  ],
                                                ),
                                              ),
                                              child: const SizedBox(
                                                width: double.infinity,
                                                height: 52,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                        10, 8, 10, 10),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'S$seasonNo:E$epNo',
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelMedium
                                              ?.copyWith(color: Colors.white70),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          ep.name.trim().isNotEmpty
                                              ? ep.name.trim()
                                              : '第$epNo集',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodyMedium
                                              ?.copyWith(
                                                color: Colors.white,
                                                fontWeight: FontWeight.w600,
                                              ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _seasonEpisodeControlPanel(
    BuildContext context, {
    required bool enableBlur,
  }) {
    if (_seasons.isEmpty) return const SizedBox.shrink();
    final textTheme = Theme.of(context).textTheme;
    final outlinedStyle = OutlinedButton.styleFrom(
      foregroundColor: Colors.white,
      side: BorderSide(color: Colors.white.withValues(alpha: 0.28)),
      textStyle: (textTheme.labelLarge ?? const TextStyle()).copyWith(
        fontWeight: FontWeight.w600,
      ),
    );
    return _detailGlassPanel(
      enableBlur: enableBlur,
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              style: outlinedStyle,
              onPressed: () => _pickSeason(context),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.layers_outlined, size: 18),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      '季：${_selectedSeasonLabel()}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.arrow_drop_down),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: OutlinedButton(
              style: outlinedStyle,
              onPressed:
                  _selectedSeason == null ? null : () => _pickEpisode(context),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.format_list_numbered, size: 18),
                  SizedBox(width: 8),
                  Text('选集'),
                  SizedBox(width: 4),
                  Icon(Icons.arrow_drop_down),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static int? _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  static Map<String, dynamic>? _findMediaSource(
      PlaybackInfoResult info, String? id) {
    final sources = info.mediaSources.cast<Map<String, dynamic>>();
    if (sources.isEmpty) return null;
    if (id != null && id.isNotEmpty) {
      for (final s in sources) {
        if ((s['Id'] as String? ?? '') == id) return s;
      }
    }
    return sources.first;
  }

  static List<Map<String, dynamic>> _streamsOfType(
      Map<String, dynamic> ms, String type) {
    final streams = (ms['MediaStreams'] as List?) ?? const [];
    return streams
        .where((e) => (e as Map)['Type'] == type)
        .map((e) => e as Map<String, dynamic>)
        .toList();
  }

  static Map<String, dynamic>? _defaultStream(
      List<Map<String, dynamic>> streams) {
    for (final s in streams) {
      if (s['IsDefault'] == true) return s;
    }
    return streams.isNotEmpty ? streams.first : null;
  }

  static String _streamLabel(Map<String, dynamic> stream,
      {bool includeCodec = true}) {
    final title = (stream['DisplayTitle'] as String?) ??
        (stream['Title'] as String?) ??
        (stream['Language'] as String?) ??
        '未知';
    final codec = (stream['Codec'] as String?) ?? '';
    return includeCodec && codec.isNotEmpty ? '$title ($codec)' : title;
  }

  static String _mediaSourceTitle(Map<String, dynamic> ms) {
    return (ms['Name'] as String?) ?? (ms['Container'] as String?) ?? '默认版本';
  }

  static int? _estimateBitrateFromSizeAndRuntime(
    int? sizeBytes,
    int? runtimeTicks,
  ) {
    if (sizeBytes == null || sizeBytes <= 0) return null;
    final ticks = runtimeTicks ?? 0;
    if (ticks <= 0) return null;
    final seconds = ticks / 10000000.0;
    if (!seconds.isFinite || seconds <= 0) return null;
    return ((sizeBytes * 8) / seconds).round();
  }

  static String _formatCompactBitrate(int? bitrate) {
    if (bitrate == null || bitrate <= 0) return '';
    if (bitrate >= 1000000) {
      final value = bitrate / 1000000;
      return '${value.toStringAsFixed(value >= 10 ? 0 : 1)} Mbps';
    }
    if (bitrate >= 1000) {
      return '${(bitrate / 1000).toStringAsFixed(0)} Kbps';
    }
    return '$bitrate bps';
  }

  static String _formatCompactFileSize(int? bytes) {
    if (bytes == null || bytes <= 0) return '';
    const kb = 1024;
    const mb = kb * 1024;
    const gb = mb * 1024;
    if (bytes >= gb) {
      final value = bytes / gb;
      return '${value.toStringAsFixed(value >= 10 ? 0 : 1)} GB';
    }
    if (bytes >= mb) {
      final value = bytes / mb;
      return '${value.toStringAsFixed(value >= 10 ? 0 : 1)} MB';
    }
    if (bytes >= kb) return '${(bytes / kb).toStringAsFixed(0)} KB';
    return '$bytes B';
  }

  static String _mediaSourceResolutionText(Map<String, dynamic>? ms) {
    if (ms == null) return '';
    final videoStreams = _streamsOfType(ms, 'Video');
    final video = videoStreams.isNotEmpty ? videoStreams.first : null;
    final width = _asInt(video?['Width']);
    final height = _asInt(video?['Height']);
    if (width != null && height != null && width > 0 && height > 0) {
      return '${width}x$height';
    }
    if (height != null && height > 0) return '${height}P';
    return '';
  }

  static String _mediaSourceBitrateText(
    Map<String, dynamic>? ms, {
    required int? fallbackSizeBytes,
    required int? fallbackRuntimeTicks,
  }) {
    final sizeBytes = _asInt(ms?['Size']) ?? fallbackSizeBytes;
    var bitrate = _asInt(ms?['Bitrate']);
    bitrate ??=
        _estimateBitrateFromSizeAndRuntime(sizeBytes, fallbackRuntimeTicks);
    return _formatCompactBitrate(bitrate);
  }

  static String _mediaSourceSizeText(
    Map<String, dynamic>? ms, {
    required int? fallbackSizeBytes,
  }) {
    final sizeBytes = _asInt(ms?['Size']) ?? fallbackSizeBytes;
    return _formatCompactFileSize(sizeBytes);
  }

  static int _compareMediaSourcesByQuality(
    Map<String, dynamic> a,
    Map<String, dynamic> b,
  ) {
    int heightOf(Map<String, dynamic> ms) {
      final videoStreams = _streamsOfType(ms, 'Video');
      final video = videoStreams.isNotEmpty ? videoStreams.first : null;
      return _asInt(video?['Height']) ?? 0;
    }

    int bitrateOf(Map<String, dynamic> ms) => _asInt(ms['Bitrate']) ?? 0;

    int sizeOf(Map<String, dynamic> ms) {
      final v = ms['Size'];
      if (v is int) return v;
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v) ?? 0;
      return 0;
    }

    final h = heightOf(b) - heightOf(a);
    if (h != 0) return h;
    final br = bitrateOf(b) - bitrateOf(a);
    if (br != 0) return br;
    return sizeOf(b) - sizeOf(a);
  }

  static String? _pickPreferredMediaSourceId(
    List<Map<String, dynamic>> sources,
    VideoVersionPreference pref,
  ) {
    if (sources.isEmpty) return null;

    int heightOf(Map<String, dynamic> ms) {
      final videos = _streamsOfType(ms, 'Video');
      final video = videos.isNotEmpty ? videos.first : null;
      return _asInt(video?['Height']) ?? 0;
    }

    int bitrateOf(Map<String, dynamic> ms) => _asInt(ms['Bitrate']) ?? 0;

    String codecOf(Map<String, dynamic> ms) {
      final videos = _streamsOfType(ms, 'Video');
      final video = videos.isNotEmpty ? videos.first : null;
      return ((ms['VideoCodec'] as String?) ??
              (video?['Codec'] as String?) ??
              '')
          .toLowerCase();
    }

    bool isHevc(Map<String, dynamic> ms) {
      final c = codecOf(ms);
      return c.contains('hevc') || c.contains('h265') || c.contains('x265');
    }

    bool isAvc(Map<String, dynamic> ms) {
      final c = codecOf(ms);
      return c.contains('h264') || c.contains('avc') || c.contains('x264');
    }

    Map<String, dynamic> pickBest(
      Iterable<Map<String, dynamic>> list, {
      required int Function(Map<String, dynamic>) primary,
      required int Function(Map<String, dynamic>) secondary,
      required bool higherIsBetter,
    }) {
      return list.reduce((a, b) {
        final ap = primary(a);
        final bp = primary(b);
        if (ap != bp) {
          return (higherIsBetter ? ap > bp : ap < bp) ? a : b;
        }
        final as = secondary(a);
        final bs = secondary(b);
        if (as != bs) {
          return (higherIsBetter ? as > bs : as < bs) ? a : b;
        }
        return a;
      });
    }

    late final Map<String, dynamic> chosen;
    switch (pref) {
      case VideoVersionPreference.highestResolution:
        chosen = pickBest(
          sources,
          primary: heightOf,
          secondary: bitrateOf,
          higherIsBetter: true,
        );
        break;
      case VideoVersionPreference.lowestBitrate:
        chosen = pickBest(
          sources,
          primary: (ms) => bitrateOf(ms) == 0 ? 1 << 30 : bitrateOf(ms),
          secondary: heightOf,
          higherIsBetter: false,
        );
        break;
      case VideoVersionPreference.preferHevc:
        final hevc = sources.where(isHevc).toList();
        chosen = pickBest(
          hevc.isNotEmpty ? hevc : sources,
          primary: heightOf,
          secondary: bitrateOf,
          higherIsBetter: true,
        );
        break;
      case VideoVersionPreference.preferAvc:
        final avc = sources.where(isAvc).toList();
        chosen = pickBest(
          avc.isNotEmpty ? avc : sources,
          primary: heightOf,
          secondary: bitrateOf,
          higherIsBetter: true,
        );
        break;
      case VideoVersionPreference.defaultVersion:
        chosen = (List<Map<String, dynamic>>.from(sources)
              ..sort(_compareMediaSourcesByQuality))
            .first;
        break;
    }

    final id = chosen['Id']?.toString();
    return (id == null || id.trim().isEmpty) ? null : id.trim();
  }

  String _mediaSourceSubtitle(Map<String, dynamic> ms) {
    final size = ms['Size'];
    final sizeGb =
        size is num ? (size / (1024 * 1024 * 1024)).toStringAsFixed(1) : null;
    final bitrate = _asInt(ms['Bitrate']);
    final bitrateMbps =
        bitrate != null ? (bitrate / 1000000).toStringAsFixed(1) : null;

    final videoStreams = _streamsOfType(ms, 'Video');
    final video = videoStreams.isNotEmpty ? videoStreams.first : null;
    final height = _asInt(video?['Height']);
    final vCodec =
        (ms['VideoCodec'] as String?) ?? (video?['Codec'] as String?);

    final parts = <String>[];
    if (height != null) parts.add('${height}p');
    if (vCodec != null && vCodec.isNotEmpty) parts.add(vCodec.toUpperCase());
    if (sizeGb != null) parts.add('$sizeGb GB');
    if (bitrateMbps != null) parts.add('$bitrateMbps Mbps');
    return parts.isEmpty ? '直连播放' : parts.join(' / ');
  }

  Widget _floatingPlaybackSettingsDock(
    BuildContext context,
    PlaybackInfoResult info, {
    required bool enableBlur,
  }) {
    final ms = _findMediaSource(info, _selectedMediaSourceId);
    if (ms == null) return const SizedBox.shrink();

    final audioStreams = _streamsOfType(ms, 'Audio');
    final subtitleStreams = _streamsOfType(ms, 'Subtitle');

    final defaultAudio = _defaultStream(audioStreams);
    final selectedAudio = _selectedAudioStreamIndex != null
        ? audioStreams.firstWhere(
            (s) => _asInt(s['Index']) == _selectedAudioStreamIndex,
            orElse: () => defaultAudio ?? const <String, dynamic>{},
          )
        : defaultAudio;

    final audioText = selectedAudio != null && selectedAudio.isNotEmpty
        ? _streamLabel(selectedAudio, includeCodec: false) +
            (selectedAudio == defaultAudio ? ' (默认)' : '')
        : '默认';

    final defaultSub = _defaultStream(subtitleStreams);
    final Map<String, dynamic>? selectedSub;
    if (_selectedSubtitleStreamIndex == -1) {
      selectedSub = null;
    } else if (_selectedSubtitleStreamIndex != null) {
      selectedSub = subtitleStreams.firstWhere(
        (s) => _asInt(s['Index']) == _selectedSubtitleStreamIndex,
        orElse: () => defaultSub ?? const <String, dynamic>{},
      );
    } else {
      selectedSub = defaultSub;
    }

    final hasSubs = subtitleStreams.isNotEmpty;
    final subtitleText = _selectedSubtitleStreamIndex == -1
        ? '关闭'
        : selectedSub != null && selectedSub.isNotEmpty
            ? _streamLabel(selectedSub, includeCodec: false)
            : hasSubs
                ? '默认'
                : '关闭';

    final scheme = Theme.of(context).colorScheme;
    final disabledColor = scheme.onSurface.withValues(alpha: 0.38);

    const radius = 24.0;
    final dividerColor = scheme.outlineVariant.withValues(alpha: 0.35);

    Widget divider() => Container(width: 1, height: 26, color: dividerColor);

    Widget segment({
      required IconData icon,
      required String tooltip,
      required VoidCallback? onTap,
      required BorderRadius borderRadius,
    }) {
      final enabled = onTap != null;
      return Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: onTap,
          borderRadius: borderRadius,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Icon(
              icon,
              size: 20,
              color: enabled ? scheme.onSurface : disabledColor,
            ),
          ),
        ),
      );
    }

    return FrostedCard(
      enableBlur: enableBlur,
      borderRadius: radius,
      padding: EdgeInsets.zero,
      child: Material(
        type: MaterialType.transparency,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            segment(
              icon: Icons.video_file_outlined,
              tooltip:
                  '版本：${_mediaSourceTitle(ms)}\n${_mediaSourceSubtitle(ms)}',
              onTap: () => _pickMediaSource(context, info),
              borderRadius:
                  const BorderRadius.horizontal(left: Radius.circular(radius)),
            ),
            divider(),
            segment(
              icon: Icons.audiotrack,
              tooltip: '音轨：$audioText',
              onTap: audioStreams.isEmpty
                  ? null
                  : () => _pickAudioStream(context, ms),
              borderRadius: BorderRadius.zero,
            ),
            divider(),
            segment(
              icon: Icons.subtitles,
              tooltip: '字幕：$subtitleText',
              onTap: hasSubs ? () => _pickSubtitleStream(context, ms) : null,
              borderRadius:
                  const BorderRadius.horizontal(right: Radius.circular(radius)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _moviePlaybackOptionsCard(
      BuildContext context, PlaybackInfoResult info) {
    final ms = _findMediaSource(info, _selectedMediaSourceId);
    if (ms == null) return const SizedBox.shrink();

    final audioStreams = _streamsOfType(ms, 'Audio');
    final subtitleStreams = _streamsOfType(ms, 'Subtitle');

    final defaultAudio = _defaultStream(audioStreams);
    final selectedAudio = _selectedAudioStreamIndex != null
        ? audioStreams.firstWhere(
            (s) => _asInt(s['Index']) == _selectedAudioStreamIndex,
            orElse: () => defaultAudio ?? const <String, dynamic>{},
          )
        : defaultAudio;

    final defaultSub = _defaultStream(subtitleStreams);
    final Map<String, dynamic>? selectedSub;
    if (_selectedSubtitleStreamIndex == -1) {
      selectedSub = null;
    } else if (_selectedSubtitleStreamIndex != null) {
      selectedSub = subtitleStreams.firstWhere(
        (s) => _asInt(s['Index']) == _selectedSubtitleStreamIndex,
        orElse: () => defaultSub ?? const <String, dynamic>{},
      );
    } else {
      selectedSub = defaultSub;
    }

    final hasSubs = subtitleStreams.isNotEmpty;
    final subtitleText = _selectedSubtitleStreamIndex == -1
        ? '关闭'
        : selectedSub != null && selectedSub.isNotEmpty
            ? _streamLabel(selectedSub, includeCodec: false)
            : hasSubs
                ? '默认'
                : '关闭';

    final audioText = selectedAudio != null && selectedAudio.isNotEmpty
        ? _streamLabel(selectedAudio, includeCodec: false) +
            (selectedAudio == defaultAudio ? ' (默认)' : '')
        : '默认';

    return _detailGlassPanel(
      enableBlur: !widget.isTv && widget.appState.enableBlurEffects,
      radius: 22,
      showBorder: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.video_file, color: Colors.white),
            title: Text(
              _mediaSourceTitle(ms),
              style: const TextStyle(color: Colors.white),
            ),
            subtitle: Text(
              _mediaSourceSubtitle(ms),
              style: const TextStyle(color: Colors.white70),
            ),
            trailing: const Icon(Icons.arrow_drop_down, color: Colors.white70),
            onTap: () => _pickMediaSource(context, info),
          ),
          Divider(height: 1, color: Colors.white.withValues(alpha: 0.20)),
          ListTile(
            leading: const Icon(Icons.audiotrack, color: Colors.white),
            title: Text(audioText, style: const TextStyle(color: Colors.white)),
            trailing: const Icon(Icons.arrow_drop_down, color: Colors.white70),
            onTap: audioStreams.isEmpty
                ? null
                : () => _pickAudioStream(context, ms),
          ),
          Divider(height: 1, color: Colors.white.withValues(alpha: 0.20)),
          ListTile(
            leading: const Icon(Icons.subtitles, color: Colors.white),
            title:
                Text(subtitleText, style: const TextStyle(color: Colors.white)),
            trailing: const Icon(Icons.arrow_drop_down, color: Colors.white70),
            onTap: hasSubs ? () => _pickSubtitleStream(context, ms) : null,
          ),
        ],
      ),
    );
  }

  Future<void> _pickMediaSource(
      BuildContext context, PlaybackInfoResult info) async {
    final sources = info.mediaSources.cast<Map<String, dynamic>>();
    if (sources.isEmpty) return;

    final sortedSources = List<Map<String, dynamic>>.from(sources)
      ..sort(_compareMediaSourcesByQuality);

    final selected = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: ListView(
            children: [
              const ListTile(title: Text('版本选择')),
              ...sortedSources.map((ms) {
                final id = ms['Id'] as String? ?? '';
                final selectedNow =
                    id.isNotEmpty && id == _selectedMediaSourceId;
                return ListTile(
                  leading: Icon(
                      selectedNow ? Icons.check_circle : Icons.circle_outlined),
                  title: Text(_mediaSourceTitle(ms)),
                  subtitle: Text(_mediaSourceSubtitle(ms)),
                  onTap: () => Navigator.of(ctx).pop(id),
                );
              }),
            ],
          ),
        );
      },
    );

    if (!mounted) return;
    if (selected == null || selected.isEmpty) return;
    setState(() {
      _selectedMediaSourceId = selected;
      // Streams differ between sources; reset to defaults.
      _selectedAudioStreamIndex = null;
      _selectedSubtitleStreamIndex = null;
    });
  }

  Future<void> _pickAudioStream(
      BuildContext context, Map<String, dynamic> ms) async {
    final audioStreams = _streamsOfType(ms, 'Audio');
    if (audioStreams.isEmpty) return;

    final selected = await showModalBottomSheet<int?>(
      context: context,
      builder: (ctx) {
        final def = _defaultStream(audioStreams);
        final defIndex = _asInt(def?['Index']);
        return SafeArea(
          child: ListView(
            children: [
              const ListTile(title: Text('音轨选择')),
              ListTile(
                leading: Icon(_selectedAudioStreamIndex == null
                    ? Icons.check
                    : Icons.circle_outlined),
                title: const Text('默认'),
                onTap: () => Navigator.of(ctx).pop(null),
              ),
              ...audioStreams.map((s) {
                final idx = _asInt(s['Index']);
                final selectedNow =
                    idx != null && idx == _selectedAudioStreamIndex;
                final title = _streamLabel(s, includeCodec: false);
                return ListTile(
                  leading: Icon(
                      selectedNow ? Icons.check_circle : Icons.circle_outlined),
                  title: Text(idx == defIndex ? '$title (默认)' : title),
                  subtitle: (s['Codec'] as String?)?.isNotEmpty == true
                      ? Text(s['Codec'] as String)
                      : null,
                  onTap: idx == null ? null : () => Navigator.of(ctx).pop(idx),
                );
              }),
            ],
          ),
        );
      },
    );

    if (!mounted) return;
    setState(() => _selectedAudioStreamIndex = selected);
  }

  Future<void> _pickSubtitleStream(
      BuildContext context, Map<String, dynamic> ms) async {
    final subtitleStreams = _streamsOfType(ms, 'Subtitle');
    if (subtitleStreams.isEmpty) return;

    final selected = await showModalBottomSheet<int?>(
      context: context,
      builder: (ctx) {
        final def = _defaultStream(subtitleStreams);
        final defIndex = _asInt(def?['Index']);
        final isOff = _selectedSubtitleStreamIndex == -1;
        final isDefault = _selectedSubtitleStreamIndex == null;
        return SafeArea(
          child: ListView(
            children: [
              const ListTile(title: Text('字幕选择')),
              ListTile(
                leading: Icon(isOff ? Icons.check : Icons.circle_outlined),
                title: const Text('关闭'),
                onTap: () => Navigator.of(ctx).pop(-1),
              ),
              ListTile(
                leading: Icon(isDefault ? Icons.check : Icons.circle_outlined),
                title: const Text('默认'),
                onTap: () => Navigator.of(ctx).pop(null),
              ),
              ...subtitleStreams.map((s) {
                final idx = _asInt(s['Index']);
                final selectedNow =
                    idx != null && idx == _selectedSubtitleStreamIndex;
                final title = _streamLabel(s, includeCodec: false);
                return ListTile(
                  leading: Icon(
                      selectedNow ? Icons.check_circle : Icons.circle_outlined),
                  title: Text(idx == defIndex ? '$title (默认)' : title),
                  subtitle: (s['Codec'] as String?)?.isNotEmpty == true
                      ? Text(s['Codec'] as String)
                      : null,
                  onTap: idx == null ? null : () => Navigator.of(ctx).pop(idx),
                );
              }),
            ],
          ),
        );
      },
    );

    if (!mounted) return;
    setState(() => _selectedSubtitleStreamIndex = selected);
  }

  static const int _kTvPickerDefault = -99999;

  Future<T?> _showTvPicker<T>(
    BuildContext context, {
    required String title,
    required List<({T value, String label, String? subtitle, bool selected})>
        options,
  }) async {
    if (options.isEmpty) return null;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = scheme.brightness == Brightness.dark;
    final uiScale = context.uiScale;

    final radius = (18 * uiScale).clamp(14.0, 22.0);
    final insetH = (28 * uiScale).clamp(18.0, 44.0);
    final insetV = (22 * uiScale).clamp(14.0, 34.0);
    final padding = (14 * uiScale).clamp(10.0, 18.0);
    final maxWidth = (760 * uiScale).clamp(520.0, 920.0);
    final maxHeight = MediaQuery.sizeOf(context).height * 0.72;

    final gradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        scheme.primary.withValues(alpha: isDark ? 0.14 : 0.10),
        Colors.black.withValues(alpha: 0.58),
      ],
    );

    return showDialog<T>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.64),
      builder: (ctx) {
        var autofocusAssigned = false;
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding:
              EdgeInsets.symmetric(horizontal: insetH, vertical: insetV),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: maxWidth,
              maxHeight: maxHeight,
            ),
            child: _detailGlassPanel(
              enableBlur: false,
              showBorder: false,
              gradient: gradient,
              radius: radius,
              padding: EdgeInsets.all(padding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  SizedBox(height: (10 * uiScale).clamp(8.0, 14.0)),
                  Divider(
                    height: 1,
                    color: Colors.white.withValues(alpha: 0.18),
                  ),
                  SizedBox(height: (10 * uiScale).clamp(8.0, 14.0)),
                  Expanded(
                    child: ListView.separated(
                      itemCount: options.length,
                      separatorBuilder: (_, __) => SizedBox(
                        height: (10 * uiScale).clamp(8.0, 14.0),
                      ),
                      itemBuilder: (context, index) {
                        final opt = options[index];
                        final shouldAutofocus =
                            !autofocusAssigned && (opt.selected || index == 0);
                        if (shouldAutofocus) autofocusAssigned = true;

                        return TvFocusable(
                          autofocus: shouldAutofocus,
                          onPressed: () => Navigator.of(ctx).pop<T>(opt.value),
                          borderRadius: BorderRadius.circular(
                            (16 * uiScale).clamp(12.0, 20.0),
                          ),
                          surfaceColor: Colors.black.withValues(alpha: 0.28),
                          focusedSurfaceColor: scheme.primary.withValues(
                            alpha: isDark ? 0.20 : 0.16,
                          ),
                          padding: EdgeInsets.symmetric(
                            horizontal: (14 * uiScale).clamp(10.0, 18.0),
                            vertical: (12 * uiScale).clamp(10.0, 16.0),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                opt.selected
                                    ? Icons.check_circle
                                    : Icons.circle_outlined,
                                color: opt.selected
                                    ? scheme.primary
                                    : Colors.white70,
                              ),
                              SizedBox(width: (12 * uiScale).clamp(10.0, 16.0)),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      opt.label,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style:
                                          theme.textTheme.titleSmall?.copyWith(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    if ((opt.subtitle ?? '').trim().isNotEmpty)
                                      Padding(
                                        padding: EdgeInsets.only(
                                          top: (4 * uiScale).clamp(2.0, 6.0),
                                        ),
                                        child: Text(
                                          opt.subtitle!,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                            color: Colors.white70,
                                            height: 1.25,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
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

  Future<void> _pickMediaSourceTv(
    BuildContext context,
    PlaybackInfoResult info,
  ) async {
    final sources = info.mediaSources.cast<Map<String, dynamic>>();
    if (sources.isEmpty) return;

    final sortedSources = List<Map<String, dynamic>>.from(sources)
      ..sort(_compareMediaSourcesByQuality);

    final options = sortedSources
        .map((ms) {
          final id = (ms['Id'] as String? ?? '').trim();
          if (id.isEmpty) return null;
          return (
            value: id,
            label: _mediaSourceTitle(ms),
            subtitle: _mediaSourceSubtitle(ms),
            selected: id == _selectedMediaSourceId,
          );
        })
        .whereType<
            ({String value, String label, String? subtitle, bool selected})>()
        .toList();

    final selected = await _showTvPicker<String>(
      context,
      title: '视频版本',
      options: options,
    );

    if (!mounted) return;
    if (selected == null ||
        selected.isEmpty ||
        selected == _selectedMediaSourceId) {
      return;
    }
    setState(() {
      _selectedMediaSourceId = selected;
      _selectedAudioStreamIndex = null;
      _selectedSubtitleStreamIndex = null;
    });
  }

  Future<void> _pickAudioStreamTv(
    BuildContext context,
    Map<String, dynamic> ms,
  ) async {
    final audioStreams = _streamsOfType(ms, 'Audio');
    if (audioStreams.isEmpty) return;

    final def = _defaultStream(audioStreams);
    final defIndex = _asInt(def?['Index']);

    final options =
        <({int value, String label, String? subtitle, bool selected})>[
      (
        value: _kTvPickerDefault,
        label: '默认',
        subtitle: defIndex == null ? null : '默认音轨',
        selected: _selectedAudioStreamIndex == null,
      ),
      ...audioStreams.map((s) {
        final idx = _asInt(s['Index']);
        if (idx == null) return null;
        final selectedNow = idx == _selectedAudioStreamIndex;
        final title = _streamLabel(s, includeCodec: false);
        final codec = (s['Codec'] as String?)?.trim();
        return (
          value: idx,
          label: idx == defIndex ? '$title (默认)' : title,
          subtitle: codec?.isEmpty == true ? null : codec,
          selected: selectedNow,
        );
      }).whereType<
          ({int value, String label, String? subtitle, bool selected})>(),
    ];

    final selected = await _showTvPicker<int>(
      context,
      title: '音轨选择',
      options: options,
    );

    if (!mounted) return;
    if (selected == null) return;
    setState(() {
      _selectedAudioStreamIndex =
          selected == _kTvPickerDefault ? null : selected;
    });
  }

  Future<void> _pickSubtitleStreamTv(
    BuildContext context,
    Map<String, dynamic> ms,
  ) async {
    final subtitleStreams = _streamsOfType(ms, 'Subtitle');
    if (subtitleStreams.isEmpty) return;

    final def = _defaultStream(subtitleStreams);
    final defIndex = _asInt(def?['Index']);

    final options =
        <({int value, String label, String? subtitle, bool selected})>[
      (
        value: -1,
        label: '关闭',
        subtitle: null,
        selected: _selectedSubtitleStreamIndex == -1,
      ),
      (
        value: _kTvPickerDefault,
        label: '默认',
        subtitle: defIndex == null ? null : '默认字幕',
        selected: _selectedSubtitleStreamIndex == null,
      ),
      ...subtitleStreams.map((s) {
        final idx = _asInt(s['Index']);
        if (idx == null) return null;
        final selectedNow = idx == _selectedSubtitleStreamIndex;
        final title = _streamLabel(s, includeCodec: false);
        final codec = (s['Codec'] as String?)?.trim();
        return (
          value: idx,
          label: idx == defIndex ? '$title (默认)' : title,
          subtitle: codec?.isEmpty == true ? null : codec,
          selected: selectedNow,
        );
      }).whereType<
          ({int value, String label, String? subtitle, bool selected})>(),
    ];

    final selected = await _showTvPicker<int>(
      context,
      title: '字幕选择',
      options: options,
    );

    if (!mounted) return;
    if (selected == null) return;
    setState(() {
      _selectedSubtitleStreamIndex =
          selected == _kTvPickerDefault ? null : selected;
    });
  }

  Widget _buildTvDetailPage(
    BuildContext context, {
    required MediaItem item,
    required ServerAccess? access,
    required bool isSeries,
    required Duration? runtime,
    required PlaybackInfoResult? playInfo,
    required String heroBackdropUrl,
    required String heroPrimaryUrl,
    required ColorFilter? heroFilter,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = scheme.brightness == Brightness.dark;
    final uiScale = context.uiScale;

    final heroUrl =
        heroBackdropUrl.isNotEmpty ? heroBackdropUrl : heroPrimaryUrl;
    final posterUrl = heroPrimaryUrl.isNotEmpty ? heroPrimaryUrl : heroUrl;

    String fmtDate(String? raw) {
      final v = (raw ?? '').trim();
      if (v.isEmpty) return '';
      if (v.contains('T')) return v.split('T').first;
      final parsed = DateTime.tryParse(v);
      if (parsed == null) return v;
      final y = parsed.year.toString().padLeft(4, '0');
      final m = parsed.month.toString().padLeft(2, '0');
      final d = parsed.day.toString().padLeft(2, '0');
      return '$y-$m-$d';
    }

    String fmtRuntime(Duration? d) {
      if (d == null) return '';
      final h = d.inHours;
      final m = d.inMinutes.remainder(60);
      if (h > 0) return '${h}h ${m}m';
      return '${d.inMinutes}m';
    }

    final rating = item.communityRating;
    final runtimeText = fmtRuntime(runtime);
    final date = fmtDate(item.premiereDate);
    final dateLabel = isSeries ? '首播日期' : '首映日期';
    final dateLine = date.isEmpty ? '' : '$dateLabel：$date';

    final played = item.played;
    final hasResume = item.playbackPositionTicks > 0 && !played && !isSeries;
    final playLabel =
        isSeries ? '播放' : (hasResume ? '继续播放' : (played ? '重播' : '播放'));

    final canSwitchCore =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    final coreLabel = '内核：${widget.appState.playerCore.label}';

    final posterWidth = (320 * uiScale).clamp(220.0, 420.0);
    final posterRadius = (20 * uiScale).clamp(14.0, 26.0);
    final contentPadding = EdgeInsets.fromLTRB(
      (32 * uiScale).clamp(18.0, 44.0),
      (22 * uiScale).clamp(14.0, 32.0),
      (32 * uiScale).clamp(18.0, 44.0),
      (30 * uiScale).clamp(18.0, 44.0),
    );

    final buttonHeight = (52 * uiScale).clamp(44.0, 62.0);
    final buttonPaddingH = (16 * uiScale).clamp(12.0, 18.0);
    final buttonIconSize = (22 * uiScale).clamp(18.0, 26.0);
    final buttonGap = (14 * uiScale).clamp(10.0, 18.0);

    Widget pillButton({
      required IconData icon,
      required String label,
      required VoidCallback? onPressed,
      bool autofocus = false,
      bool primary = false,
    }) {
      final fg = Colors.white;
      final surface = primary
          ? const Color(0xFF1F9F75).withValues(alpha: 0.86)
          : Colors.black.withValues(alpha: 0.30);
      final focusedSurface = primary
          ? const Color(0xFF1F9F75).withValues(alpha: 0.96)
          : scheme.primary.withValues(alpha: isDark ? 0.20 : 0.16);
      return TvFocusable(
        autofocus: autofocus,
        enabled: onPressed != null,
        onPressed: onPressed,
        borderRadius: BorderRadius.circular(999),
        surfaceColor: surface,
        focusedSurfaceColor: focusedSurface,
        padding: EdgeInsets.zero,
        child: SizedBox(
          height: buttonHeight,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: buttonPaddingH),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: buttonIconSize, color: fg),
                SizedBox(width: (10 * uiScale).clamp(8.0, 14.0)),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: fg,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    Widget menuButton({
      required IconData icon,
      required String label,
      required VoidCallback? onPressed,
    }) {
      final fg = Colors.white;
      final surface = Colors.black.withValues(alpha: 0.26);
      final focusedSurface =
          scheme.primary.withValues(alpha: isDark ? 0.18 : 0.14);
      final radius = (18 * uiScale).clamp(14.0, 22.0);
      return TvFocusable(
        enabled: onPressed != null,
        onPressed: onPressed,
        borderRadius: BorderRadius.circular(radius),
        surfaceColor: surface,
        focusedSurfaceColor: focusedSurface,
        padding: EdgeInsets.zero,
        child: SizedBox(
          height: buttonHeight,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: buttonPaddingH),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: buttonIconSize, color: fg),
                SizedBox(width: (10 * uiScale).clamp(8.0, 14.0)),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: fg,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    Widget ratingLine() {
      if (rating == null && runtimeText.isEmpty) return const SizedBox.shrink();
      final value = rating ?? 0;
      final starValue = (value / 2).clamp(0.0, 5.0);
      final full = starValue.floor();
      final hasHalf = (starValue - full) >= 0.5;
      final empty = 5 - full - (hasHalf ? 1 : 0);

      return Row(
        children: [
          if (rating != null) ...[
            for (int i = 0; i < full; i++)
              const Icon(Icons.star_rounded, size: 18, color: Colors.amber),
            if (hasHalf)
              const Icon(Icons.star_half_rounded,
                  size: 18, color: Colors.amber),
            for (int i = 0; i < empty; i++)
              Icon(
                Icons.star_border_rounded,
                size: 18,
                color: Colors.amber.withValues(alpha: 0.7),
              ),
            const SizedBox(width: 8),
            Text(
              value.toStringAsFixed(1),
              style: theme.textTheme.labelLarge?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
          if (rating != null && runtimeText.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text(
                '·',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: Colors.white70,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          if (runtimeText.isNotEmpty)
            Text(
              runtimeText,
              style: theme.textTheme.labelLarge?.copyWith(
                color: Colors.white70,
                fontWeight: FontWeight.w700,
              ),
            ),
        ],
      );
    }

    Widget background = heroUrl.isEmpty
        ? const ColoredBox(color: Colors.black26)
        : LinNetworkImage(
            imageUrl: heroUrl,
            fit: BoxFit.cover,
            errorWidget: const ColoredBox(color: Colors.black26),
          );
    if (heroFilter != null) {
      background = ColorFiltered(colorFilter: heroFilter, child: background);
    }

    final scrim = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        Colors.black.withValues(alpha: 0.82),
        Colors.black.withValues(alpha: 0.60),
        Colors.black.withValues(alpha: 0.78),
      ],
    );

    Future<void> playPrimary() async {
      if (isSeries) {
        final season = _selectedSeason;
        if (season == null) return;
        final eps = await _episodesForSeason(season);
        if (!context.mounted) return;
        final ep = _featuredEpisode ?? (eps.isNotEmpty ? eps.first : null);
        if (ep == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('暂无剧集')),
          );
          return;
        }
        await _openEpisode(context, ep);
        return;
      }
      await _playMovie(item);
    }

    final ms = playInfo == null
        ? null
        : _findMediaSource(playInfo, _selectedMediaSourceId);

    String currentVideoText() => ms == null ? '' : _mediaSourceSubtitle(ms);

    String currentAudioText() {
      if (ms == null) return '';
      final streams = _streamsOfType(ms, 'Audio');
      if (streams.isEmpty) return '默认';
      final def = _defaultStream(streams);
      final selected = _selectedAudioStreamIndex != null
          ? streams.firstWhere(
              (s) => _asInt(s['Index']) == _selectedAudioStreamIndex,
              orElse: () => def ?? const <String, dynamic>{},
            )
          : def;
      if (selected == null || selected.isEmpty) return '默认';
      final label = _streamLabel(selected, includeCodec: false);
      return label.isEmpty ? '默认' : label;
    }

    String currentSubtitleText() {
      if (ms == null) return '';
      final streams = _streamsOfType(ms, 'Subtitle');
      if (streams.isEmpty) return '关闭';
      final def = _defaultStream(streams);
      if (_selectedSubtitleStreamIndex == -1) return '关闭';
      final Map<String, dynamic>? selected;
      if (_selectedSubtitleStreamIndex != null) {
        selected = streams.firstWhere(
          (s) => _asInt(s['Index']) == _selectedSubtitleStreamIndex,
          orElse: () => def ?? const <String, dynamic>{},
        );
      } else {
        selected = def;
      }
      if (selected == null || selected.isEmpty) return '默认';
      final label = _streamLabel(selected, includeCodec: false);
      return label.isEmpty ? '默认' : label;
    }

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(child: background),
          Positioned.fill(
            child: DecoratedBox(decoration: BoxDecoration(gradient: scrim)),
          ),
          SafeArea(
            child: FocusTraversalGroup(
              policy: ReadingOrderTraversalPolicy(),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1600),
                  child: ListView(
                    padding: contentPadding,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: posterWidth,
                            child: AspectRatio(
                              aspectRatio: 2 / 3,
                              child: ClipRRect(
                                borderRadius:
                                    BorderRadius.circular(posterRadius),
                                child: posterUrl.isEmpty
                                    ? const ColoredBox(
                                        color: Colors.black26,
                                        child: Center(child: Icon(Icons.image)),
                                      )
                                    : LinNetworkImage(
                                        imageUrl: posterUrl,
                                        fit: BoxFit.cover,
                                        errorWidget: const ColoredBox(
                                          color: Colors.black26,
                                        ),
                                      ),
                              ),
                            ),
                          ),
                          SizedBox(width: (26 * uiScale).clamp(18.0, 34.0)),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.name,
                                  style:
                                      theme.textTheme.headlineSmall?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w900,
                                    height: 1.08,
                                  ),
                                ),
                                SizedBox(
                                    height: (10 * uiScale).clamp(8.0, 14.0)),
                                ratingLine(),
                                if (dateLine.isNotEmpty) ...[
                                  SizedBox(
                                      height: (8 * uiScale).clamp(6.0, 12.0)),
                                  Text(
                                    dateLine,
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: Colors.white70,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                                SizedBox(
                                    height: (16 * uiScale).clamp(12.0, 22.0)),
                                Wrap(
                                  spacing: buttonGap,
                                  runSpacing: buttonGap,
                                  children: [
                                    if (!isSeries)
                                      pillButton(
                                        icon: Icons.play_arrow_rounded,
                                        label: playLabel,
                                        onPressed: _markBusy
                                            ? null
                                            : () => unawaited(playPrimary()),
                                        autofocus: true,
                                        primary: true,
                                      ),
                                    if (!isSeries)
                                      pillButton(
                                        icon: played
                                            ? Icons.visibility_off_outlined
                                            : Icons
                                                .check_circle_outline_rounded,
                                        label: played ? '标记未播放' : '标记已播放',
                                        onPressed: _markBusy
                                            ? null
                                            : _toggleItemPlayedMark,
                                      ),
                                    pillButton(
                                      icon: _localFavorite
                                          ? Icons.favorite_rounded
                                          : Icons.favorite_border_rounded,
                                      label: _localFavorite ? '已喜欢' : '喜欢',
                                      onPressed: _favoriteLoaded
                                          ? _toggleLocalFavorite
                                          : null,
                                      autofocus: isSeries,
                                    ),
                                    if (!isSeries)
                                      pillButton(
                                        icon: Icons.memory_rounded,
                                        label: coreLabel,
                                        onPressed: canSwitchCore
                                            ? _togglePlayerCore
                                            : null,
                                      ),
                                  ],
                                ),
                                if (!isSeries) ...[
                                  SizedBox(
                                      height: (14 * uiScale).clamp(10.0, 18.0)),
                                  Wrap(
                                    spacing: buttonGap,
                                    runSpacing: buttonGap,
                                    children: [
                                      menuButton(
                                        icon: Icons.movie_filter_rounded,
                                        label: ms == null
                                            ? '视频'
                                            : '视频：${currentVideoText()}',
                                        onPressed: playInfo == null
                                            ? null
                                            : () => unawaited(
                                                  _pickMediaSourceTv(
                                                      context, playInfo),
                                                ),
                                      ),
                                      menuButton(
                                        icon: Icons.audiotrack_rounded,
                                        label: ms == null
                                            ? '音频'
                                            : '音频：${currentAudioText()}',
                                        onPressed: ms == null
                                            ? null
                                            : () => unawaited(
                                                  _pickAudioStreamTv(
                                                      context, ms),
                                                ),
                                      ),
                                      menuButton(
                                        icon: Icons.closed_caption_rounded,
                                        label: ms == null
                                            ? '字幕'
                                            : '字幕：${currentSubtitleText()}',
                                        onPressed: ms == null
                                            ? null
                                            : () => unawaited(
                                                  _pickSubtitleStreamTv(
                                                      context, ms),
                                                ),
                                      ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: (22 * uiScale).clamp(16.0, 30.0)),
                      if (isSeries) ...[
                        _tvSeasonSelectorSection(context, access: access),
                        SizedBox(height: (18 * uiScale).clamp(14.0, 26.0)),
                        _tvEpisodeSelectorSection(context, access: access),
                        SizedBox(height: (18 * uiScale).clamp(14.0, 26.0)),
                      ],
                      _tvPeopleSection(context, access: access),
                      if (!isSeries) ...[
                        SizedBox(height: (18 * uiScale).clamp(14.0, 26.0)),
                        _tvMediaInfoSection(
                          context,
                          item: item,
                          playInfo: playInfo,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tvSeasonSelectorSection(
    BuildContext context, {
    required ServerAccess? access,
  }) {
    if (_seasons.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = scheme.brightness == Brightness.dark;
    final uiScale = context.uiScale;

    final cardWidth = (260 * uiScale).clamp(180.0, 340.0);
    final cardRadius = (18 * uiScale).clamp(14.0, 22.0);
    final imgRadius = (14 * uiScale).clamp(10.0, 18.0);
    final gap = (14 * uiScale).clamp(10.0, 18.0);
    final cardPadding = (8 * uiScale).clamp(6.0, 12.0);
    final labelGap = (8 * uiScale).clamp(6.0, 10.0);
    final listHeight = (cardWidth / (16 / 9) + (54 * uiScale).clamp(40.0, 70.0))
        .clamp(150.0, 300.0);

    final selectedId = _selectedSeasonId;

    String labelOf(MediaItem season, int index) {
      final no = season.seasonNumber ?? season.episodeNumber ?? (index + 1);
      return '第$no季';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(context, '季度选择'),
        SizedBox(height: (10 * uiScale).clamp(8.0, 14.0)),
        SizedBox(
          height: listHeight,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _seasons.length,
            separatorBuilder: (_, __) => SizedBox(width: gap),
            itemBuilder: (context, index) {
              final s = _seasons[index];
              final img = access == null
                  ? ''
                  : access.adapter.imageUrl(
                      access.auth,
                      itemId: s.id,
                      imageType: 'Primary',
                      maxWidth: 900,
                    );
              final selectedNow = selectedId != null && s.id == selectedId;
              final surface = selectedNow
                  ? scheme.primary.withValues(alpha: isDark ? 0.16 : 0.12)
                  : Colors.black.withValues(alpha: 0.24);

              return SizedBox(
                width: cardWidth,
                child: TvFocusable(
                  onPressed: () {
                    if (s.id == _selectedSeasonId) return;
                    setState(() {
                      _selectedSeasonId = s.id;
                      _featuredEpisode = null;
                    });
                    unawaited(() async {
                      try {
                        final eps = await _episodesForSeason(s);
                        if (!mounted || _selectedSeasonId != s.id) return;
                        setState(() {
                          _featuredEpisode = eps.isNotEmpty ? eps.first : null;
                        });
                      } catch (_) {}
                    }());
                  },
                  borderRadius: BorderRadius.circular(cardRadius),
                  surfaceColor: surface,
                  focusedSurfaceColor:
                      scheme.primary.withValues(alpha: isDark ? 0.20 : 0.16),
                  padding: EdgeInsets.all(cardPadding),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AspectRatio(
                        aspectRatio: 16 / 9,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(imgRadius),
                          child: img.isEmpty
                              ? const ColoredBox(
                                  color: Colors.black26,
                                  child: Center(child: Icon(Icons.image)),
                                )
                              : LinNetworkImage(
                                  imageUrl: img,
                                  fit: BoxFit.cover,
                                  errorWidget:
                                      const ColoredBox(color: Colors.black26),
                                ),
                        ),
                      ),
                      SizedBox(height: labelGap),
                      Text(
                        labelOf(s, index),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _tvEpisodeSelectorSection(
    BuildContext context, {
    required ServerAccess? access,
  }) {
    if (_seasons.isEmpty) return const SizedBox.shrink();
    final season = _selectedSeason;
    if (season == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = scheme.brightness == Brightness.dark;
    final uiScale = context.uiScale;

    final cardWidth = (260 * uiScale).clamp(180.0, 340.0);
    final cardRadius = (18 * uiScale).clamp(14.0, 22.0);
    final imgRadius = (14 * uiScale).clamp(10.0, 18.0);
    final gap = (14 * uiScale).clamp(10.0, 18.0);
    final cardPadding = (8 * uiScale).clamp(6.0, 12.0);
    final labelGap = (8 * uiScale).clamp(6.0, 10.0);
    final listHeight = (cardWidth / (16 / 9) + (54 * uiScale).clamp(40.0, 74.0))
        .clamp(160.0, 320.0);

    return FutureBuilder<List<MediaItem>>(
      future: _episodesForSeason(season),
      builder: (context, snapshot) {
        final eps = snapshot.data ?? const <MediaItem>[];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle(context, '集数选择'),
            SizedBox(height: (10 * uiScale).clamp(8.0, 14.0)),
            SizedBox(
              height: listHeight,
              child: eps.isEmpty
                  ? const Center(
                      child:
                          Text('暂无剧集', style: TextStyle(color: Colors.white70)),
                    )
                  : ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: eps.length,
                      separatorBuilder: (_, __) => SizedBox(width: gap),
                      itemBuilder: (context, index) {
                        final ep = eps[index];
                        final epNo = ep.episodeNumber ?? (index + 1);
                        final img = access == null
                            ? ''
                            : access.adapter.imageUrl(
                                access.auth,
                                itemId: ep.hasImage ? ep.id : season.id,
                                imageType: 'Primary',
                                maxWidth: 900,
                              );
                        return SizedBox(
                          width: cardWidth,
                          child: TvFocusable(
                            onPressed: () =>
                                unawaited(_openEpisode(context, ep)),
                            borderRadius: BorderRadius.circular(cardRadius),
                            surfaceColor: Colors.black.withValues(alpha: 0.24),
                            focusedSurfaceColor: scheme.primary.withValues(
                              alpha: isDark ? 0.20 : 0.16,
                            ),
                            padding: EdgeInsets.all(cardPadding),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                AspectRatio(
                                  aspectRatio: 16 / 9,
                                  child: ClipRRect(
                                    borderRadius:
                                        BorderRadius.circular(imgRadius),
                                    child: img.isEmpty
                                        ? const ColoredBox(
                                            color: Colors.black26,
                                            child: Center(
                                                child: Icon(Icons.image)),
                                          )
                                        : LinNetworkImage(
                                            imageUrl: img,
                                            fit: BoxFit.cover,
                                            errorWidget: const ColoredBox(
                                              color: Colors.black26,
                                            ),
                                          ),
                                  ),
                                ),
                                SizedBox(height: labelGap),
                                Text(
                                  '第$epNo集',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.labelLarge?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _tvPeopleSection(
    BuildContext context, {
    required ServerAccess? access,
  }) {
    final item = _detail;
    if (item == null || item.people.isEmpty || access == null) {
      return const SizedBox.shrink();
    }

    final people = item.people.where((p) => p.id.trim().isNotEmpty).toList();
    if (people.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = scheme.brightness == Brightness.dark;
    final uiScale = context.uiScale;

    final cardWidth = (170 * uiScale).clamp(132.0, 220.0);
    final cardRadius = (18 * uiScale).clamp(14.0, 22.0);
    final imgRadius = (14 * uiScale).clamp(10.0, 18.0);
    final gap = (14 * uiScale).clamp(10.0, 18.0);

    void openPerson(MediaPerson p) {
      final id = p.id.trim();
      if (id.isEmpty) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PersonPage(
            appState: widget.appState,
            server: widget.server,
            personId: id,
            seedName: p.name,
            isTv: widget.isTv,
            onOpenItem: (ctx, entry) {
              Navigator.of(ctx).push(
                MaterialPageRoute(
                  builder: (_) => ShowDetailPage(
                    itemId: entry.id,
                    title: entry.name,
                    appState: widget.appState,
                    server: widget.server,
                    isTv: widget.isTv,
                  ),
                ),
              );
            },
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(context, '演职人员'),
        SizedBox(height: (10 * uiScale).clamp(8.0, 14.0)),
        SizedBox(
          height: (cardWidth * 1.72).clamp(240.0, 420.0),
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: people.length,
            separatorBuilder: (_, __) => SizedBox(width: gap),
            itemBuilder: (context, index) {
              final p = people[index];
              final img = access.adapter.personImageUrl(
                access.auth,
                personId: p.id,
                maxWidth: 520,
              );
              return SizedBox(
                width: cardWidth,
                child: TvFocusable(
                  onPressed: () => openPerson(p),
                  borderRadius: BorderRadius.circular(cardRadius),
                  surfaceColor: Colors.black.withValues(alpha: 0.22),
                  focusedSurfaceColor:
                      scheme.primary.withValues(alpha: isDark ? 0.20 : 0.16),
                  padding: EdgeInsets.all((10 * uiScale).clamp(8.0, 12.0)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AspectRatio(
                        aspectRatio: 2 / 3,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(imgRadius),
                          child: img.isEmpty
                              ? const ColoredBox(
                                  color: Colors.black26,
                                  child: Center(child: Icon(Icons.person)),
                                )
                              : LinNetworkImage(
                                  imageUrl: img,
                                  fit: BoxFit.cover,
                                  errorWidget:
                                      const ColoredBox(color: Colors.black26),
                                ),
                        ),
                      ),
                      SizedBox(height: (10 * uiScale).clamp(8.0, 12.0)),
                      Text(
                        p.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _tvMediaInfoSection(
    BuildContext context, {
    required MediaItem item,
    required PlaybackInfoResult? playInfo,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = scheme.brightness == Brightness.dark;
    final uiScale = context.uiScale;

    final info = playInfo;
    if (info == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(context, '媒体信息'),
          SizedBox(height: (10 * uiScale).clamp(8.0, 14.0)),
          Text(
            item.type.toLowerCase() == 'series' ? '请进入单集查看媒体信息' : '暂无媒体信息',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: Colors.white70,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      );
    }

    final ms = _findMediaSource(info, _selectedMediaSourceId) ??
        (info.mediaSources.first as Map<String, dynamic>);
    final streams = (ms['MediaStreams'] as List?) ?? const [];
    final videos = streams
        .where((e) => (e as Map)['Type'] == 'Video')
        .map((e) => e as Map<String, dynamic>)
        .toList();
    final audios = streams
        .where((e) => (e as Map)['Type'] == 'Audio')
        .map((e) => e as Map<String, dynamic>)
        .toList();
    final subs = streams
        .where((e) => (e as Map)['Type'] == 'Subtitle')
        .map((e) => e as Map<String, dynamic>)
        .toList();

    String fmtSize(dynamic raw) {
      final bytes = raw is num ? raw.toInt() : int.tryParse('$raw');
      if (bytes == null || bytes <= 0) return '';
      const kb = 1024;
      const mb = kb * 1024;
      const gb = mb * 1024;
      if (bytes >= gb) return '${(bytes / gb).toStringAsFixed(1)} GB';
      if (bytes >= mb) return '${(bytes / mb).toStringAsFixed(0)} MB';
      if (bytes >= kb) return '${(bytes / kb).toStringAsFixed(0)} KB';
      return '$bytes B';
    }

    String yn(dynamic v) => v == true ? '是' : '否';

    List<({String k, String v})> videoLines(Map<String, dynamic> v) {
      final out = <({String k, String v})>[];
      final title = (v['DisplayTitle'] ?? '').toString().trim();
      final codec = (v['Codec'] ?? '').toString().trim();
      final width = _asInt(v['Width']);
      final height = _asInt(v['Height']);
      final aspect = _formatVideoAspectRatio(v);
      final bitrate = _asInt(v['BitRate']);
      final fr = v['RealFrameRate'] ?? v['AverageFrameRate'];

      if (title.isNotEmpty) out.add((k: '标题名称', v: title));
      if (codec.isNotEmpty) out.add((k: '编码格式', v: codec.toUpperCase()));
      if (width != null && height != null) {
        out.add((k: '源分辨率', v: '${width}x$height'));
      }
      if (aspect != null) out.add((k: '视频比例', v: aspect));
      if (fr != null) out.add((k: '帧速率', v: fr.toString()));
      if (bitrate != null && bitrate > 0) {
        out.add(
            (k: '比特率', v: '${(bitrate / 1000000).toStringAsFixed(1)} Mbps'));
      }
      out.add((k: '默认', v: yn(v['IsDefault'])));
      return out;
    }

    List<({String k, String v})> audioLines(Map<String, dynamic> a) {
      final out = <({String k, String v})>[];
      final title = (a['DisplayTitle'] ?? '').toString().trim();
      final lang = (a['Language'] ?? '').toString().trim();
      final codec = (a['Codec'] ?? '').toString().trim();
      final channels = _asInt(a['Channels']);
      final bitrate = _asInt(a['BitRate']);
      final sample = _asInt(a['SampleRate']);

      if (title.isNotEmpty) out.add((k: '标题名称', v: title));
      if (lang.isNotEmpty) out.add((k: '语言种类', v: lang));
      if (codec.isNotEmpty) out.add((k: '编码格式', v: codec.toUpperCase()));
      if (channels != null) out.add((k: '音频声道', v: '$channels ch'));
      if (bitrate != null && bitrate > 0) {
        out.add((k: '比特率', v: '${(bitrate / 1000).toStringAsFixed(0)} Kbps'));
      }
      if (sample != null && sample > 0) out.add((k: '采样率', v: '$sample Hz'));
      out.add((k: '默认', v: yn(a['IsDefault'])));
      return out;
    }

    List<({String k, String v})> subLines(Map<String, dynamic> s) {
      final out = <({String k, String v})>[];
      final title =
          (s['DisplayTitle'] ?? s['Language'] ?? '').toString().trim();
      final lang = (s['Language'] ?? '').toString().trim();
      final codec = (s['Codec'] ?? '').toString().trim();
      if (title.isNotEmpty) out.add((k: '标题名称', v: title));
      if (lang.isNotEmpty) out.add((k: '语言种类', v: lang));
      if (codec.isNotEmpty) out.add((k: '编码格式', v: codec.toUpperCase()));
      out.add((k: '默认', v: yn(s['IsDefault'])));
      out.add((k: '强制', v: yn(s['IsForced'])));
      out.add((k: '外部', v: yn(s['IsExternal'])));
      return out;
    }

    Widget infoCard({
      required IconData icon,
      required String title,
      required List<({String k, String v})> lines,
    }) {
      final cardWidth = (360 * uiScale).clamp(280.0, 520.0);
      final radius = (18 * uiScale).clamp(14.0, 22.0);
      final iconSize = (22 * uiScale).clamp(18.0, 26.0);
      final labelWidth = (96 * uiScale).clamp(84.0, 124.0);

      return SizedBox(
        width: cardWidth,
        child: TvFocusable(
          borderRadius: BorderRadius.circular(radius),
          surfaceColor: Colors.black.withValues(alpha: 0.22),
          focusedSurfaceColor:
              scheme.primary.withValues(alpha: isDark ? 0.18 : 0.14),
          padding: EdgeInsets.all((14 * uiScale).clamp(10.0, 18.0)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, color: Colors.white, size: iconSize),
                  const SizedBox(width: 10),
                  Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              SizedBox(height: (10 * uiScale).clamp(8.0, 14.0)),
              ...lines.take(14).map(
                    (e) => Padding(
                      padding: EdgeInsets.only(
                        bottom: (6 * uiScale).clamp(4.0, 8.0),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: labelWidth,
                            child: Text(
                              e.k,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: Colors.white70,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              e.v,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
            ],
          ),
        ),
      );
    }

    final container = (ms['Container'] ?? item.container ?? ms['Name'] ?? '')
        .toString()
        .trim();
    final sizeText = fmtSize(ms['Size'] ?? item.sizeBytes);

    final fileCardRadius = (18 * uiScale).clamp(14.0, 22.0);
    final fileGradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        scheme.primary.withValues(alpha: isDark ? 0.18 : 0.14),
        scheme.secondary.withValues(alpha: isDark ? 0.10 : 0.08),
      ],
    );

    final streamCards = <Widget>[
      ...videos.map(
        (v) => infoCard(
          icon: Icons.videocam_rounded,
          title: '视频',
          lines: videoLines(v),
        ),
      ),
      ...audios.map(
        (a) => infoCard(
          icon: Icons.music_note_rounded,
          title: '音频',
          lines: audioLines(a),
        ),
      ),
      ...subs.map(
        (s) => infoCard(
          icon: Icons.closed_caption_rounded,
          title: '字幕',
          lines: subLines(s),
        ),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(context, '媒体信息'),
        SizedBox(height: (10 * uiScale).clamp(8.0, 14.0)),
        _detailGlassPanel(
          enableBlur: false,
          showBorder: false,
          gradient: fileGradient,
          radius: fileCardRadius,
          padding: EdgeInsets.all((16 * uiScale).clamp(12.0, 20.0)),
          child: Row(
            children: [
              Text(
                container.isEmpty ? '媒体源' : container.toUpperCase(),
                style: theme.textTheme.titleMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (sizeText.isNotEmpty) ...[
                SizedBox(width: (16 * uiScale).clamp(12.0, 20.0)),
                Text(
                  sizeText,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: Colors.white70,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ],
          ),
        ),
        SizedBox(height: (12 * uiScale).clamp(10.0, 18.0)),
        if (streamCards.isEmpty)
          Text(
            '暂无流信息',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: Colors.white70,
              fontWeight: FontWeight.w600,
            ),
          )
        else
          SizedBox(
            height: (440 * uiScale).clamp(320.0, 620.0),
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: streamCards.length,
              separatorBuilder: (_, __) =>
                  SizedBox(width: (14 * uiScale).clamp(10.0, 18.0)),
              itemBuilder: (context, index) => streamCards[index],
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final enableBlur = !widget.isTv && widget.appState.enableBlurEffects;
    if (_error != null || _detail == null) {
      return widget.isTv
          ? Scaffold(body: Center(child: Text(_error ?? '加载失败')))
          : Scaffold(
              body: SafeArea(
                child: Center(child: Text(_error ?? '加载失败')),
              ),
            );
    }
    final item = _detail!;
    final access = resolveServerAccess(
      appState: widget.appState,
      server: widget.server,
    );
    final isSeries = item.type.toLowerCase() == 'series';
    final playInfo = _playInfo;
    final showFloatingSettings = !widget.isTv &&
        !isSeries &&
        playInfo != null &&
        _findMediaSource(playInfo, _selectedMediaSourceId) != null;
    final runtime = item.runTimeTicks != null
        ? Duration(microseconds: item.runTimeTicks! ~/ 10)
        : null;
    final heroBackdrop = (access == null)
        ? ''
        : access.adapter.imageUrl(
            access.auth,
            itemId: item.id,
            imageType: 'Backdrop',
            maxWidth: 1600,
          );
    final heroPrimary = (access == null)
        ? ''
        : access.adapter.imageUrl(
            access.auth,
            itemId: item.id,
            imageType: 'Primary',
            maxWidth: 1200,
          );
    final hero = heroBackdrop.isNotEmpty ? heroBackdrop : heroPrimary;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = scheme.brightness == Brightness.dark;
    final heroFilter = ColorFilter.mode(
      scheme.secondary.withValues(alpha: isDark ? 0.10 : 0.08),
      BlendMode.softLight,
    );

    final scrimBottom = Colors.black.withValues(alpha: 0.72);

    const heroTitleColor = Colors.white;

    if (widget.isTv) {
      return _buildTvDetailPage(
        context,
        item: item,
        access: access,
        isSeries: isSeries,
        runtime: runtime,
        playInfo: playInfo,
        heroBackdropUrl: heroBackdrop,
        heroPrimaryUrl: heroPrimary,
        heroFilter: heroFilter,
      );
    }

    return _buildMobileDetailPage(
      context,
      item: item,
      access: access,
      isSeries: isSeries,
      runtime: runtime,
      playInfo: playInfo,
      enableBlur: enableBlur,
      heroImageUrl: hero,
    );

    // ignore: dead_code
    final heroImage = hero.isEmpty
        ? const ColoredBox(color: Colors.black26)
        : LinNetworkImage(
            imageUrl: hero,
            fit: BoxFit.cover,
            errorWidget: const ColoredBox(color: Colors.black26),
          );

    return Scaffold(
      body: Stack(
        children: [
          RefreshIndicator(
            onRefresh: _load,
            child: CustomScrollView(
              slivers: [
                SliverAppBar(
                  automaticallyImplyLeading: false,
                  backgroundColor: Colors.transparent,
                  surfaceTintColor: Colors.transparent,
                  elevation: 0,
                  pinned: true,
                  expandedHeight: 340,
                  flexibleSpace: FlexibleSpaceBar(
                    background: Stack(
                      fit: StackFit.expand,
                      children: [
                        ColorFiltered(
                          colorFilter: heroFilter,
                          child: heroImage,
                        ),
                        DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Colors.transparent, scrimBottom],
                            ),
                          ),
                        ),
                        if (widget.itemId.isEmpty)
                          Positioned(
                            left: 16,
                            bottom: 16,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(item.name,
                                    style: theme.textTheme.headlineSmall
                                        ?.copyWith(
                                            color: heroTitleColor,
                                            fontWeight: FontWeight.w700)),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 8,
                                  children: [
                                    if (item.communityRating != null)
                                      _pill(context,
                                          '★ ${item.communityRating!.toStringAsFixed(1)}'),
                                    if (item.premiereDate != null)
                                      _pill(context,
                                          item.premiereDate!.split('T').first),
                                    if (item.genres.isNotEmpty)
                                      _pill(context, item.genres.first),
                                    if (isSeries)
                                      _pill(context, '${_seasons.length} 季')
                                    else if (runtime != null)
                                      _pill(context, _fmt(runtime)),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        if (widget.itemId.isEmpty)
                          Positioned(
                            right: 16,
                            top: MediaQuery.of(context).padding.top + 16,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                if (item.communityRating != null)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 6),
                                    decoration: BoxDecoration(
                                      color:
                                          Colors.green.withValues(alpha: 0.85),
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: Text(
                                      item.communityRating!.toStringAsFixed(1),
                                      style:
                                          theme.textTheme.labelMedium?.copyWith(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                const SizedBox(height: 8),
                                Material(
                                  color: Colors.black.withValues(alpha: 0.55),
                                  borderRadius: BorderRadius.circular(999),
                                  child: IconButton(
                                    onPressed: _favoriteLoaded
                                        ? _toggleLocalFavorite
                                        : null,
                                    tooltip:
                                        _localFavorite ? '已本地收藏' : '添加到本地收藏',
                                    icon: Icon(
                                      _localFavorite
                                          ? Icons.star
                                          : Icons.star_border_rounded,
                                      color: _localFavorite
                                          ? Colors.pinkAccent
                                          : Colors.white,
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
                SliverToBoxAdapter(
                  child: Padding(
                    padding: _DetailUiTokens.panelPadding,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _detailHeroSection(
                          context,
                          item: item,
                          access: access,
                          isSeries: isSeries,
                          runtime: runtime,
                        ),
                        const SizedBox(height: 16),
                        if (widget.itemId.isEmpty && !isSeries) ...[
                          if (playInfo != null && !showFloatingSettings)
                            _moviePlaybackOptionsCard(context, playInfo),
                          if (playInfo != null && !showFloatingSettings)
                            const SizedBox(height: 12),
                          _playButton(
                            context,
                            label: item.playbackPositionTicks > 0
                                ? '继续播放（${_fmtClock(_ticksToDuration(item.playbackPositionTicks))}）'
                                : '播放',
                            onTap: () => _playMovie(item),
                          ),
                        ],
                        if (isSeries && _seasons.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          _seasonEpisodeControlPanel(
                            context,
                            enableBlur: enableBlur,
                          ),
                          const SizedBox(height: 12),
                        ] else
                          const SizedBox(height: 12),
                        if (isSeries) ...[
                          _unwatchedEpisodesSection(
                            context,
                            seriesItem: item,
                            access: access,
                          ),
                          const SizedBox(height: 16),
                        ],
                        if (widget.itemId.isEmpty)
                          Text(
                            item.overview,
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  color: Colors.white.withValues(alpha: 0.88),
                                ),
                          ),
                        const SizedBox(height: 16),
                        if (_chapters.isNotEmpty) ...[
                          _chaptersSection(context, _chapters),
                          const SizedBox(height: 16),
                        ],
                        if (item.people.isNotEmpty && access != null) ...[
                          _peopleSection(
                            context,
                            item.people,
                            access: access,
                          ),
                          const SizedBox(height: 16),
                        ],
                        if (widget.itemId.isEmpty && _album.isNotEmpty) ...[
                          _sectionTitle(context, '相册'),
                          const SizedBox(height: 8),
                          SizedBox(
                            height: 140,
                            child: _withHorizontalEdgeFade(
                              context,
                              child: ListView.separated(
                                scrollDirection: Axis.horizontal,
                                itemCount: _album.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(width: 10),
                                itemBuilder: (context, index) {
                                  final url = _album[index];
                                  return _HoverScale(
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(12),
                                      child: SizedBox(
                                        width: 220,
                                        height: 140,
                                        child: LinNetworkImage(
                                          imageUrl: url,
                                          fit: BoxFit.cover,
                                          errorWidget: const ColoredBox(
                                            color: Colors.black26,
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                        if (widget.itemId.isEmpty && _seasons.isNotEmpty) ...[
                          _sectionTitle(context, '全部剧季'),
                          const SizedBox(height: 8),
                          SizedBox(
                            height: 220,
                            child: _withHorizontalEdgeFade(
                              context,
                              child: ListView.separated(
                                scrollDirection: Axis.horizontal,
                                itemCount: _seasons.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(width: 12),
                                itemBuilder: (context, index) {
                                  final s = _seasons[index];
                                  final label = _seasonLabel(s, index);
                                  final img = access?.adapter.imageUrl(
                                    access.auth,
                                    itemId: s.hasImage ? s.id : item.id,
                                    maxWidth: 400,
                                  );
                                  return _HoverScale(
                                    child: SizedBox(
                                      width: 140,
                                      child: MediaPosterTile(
                                        title: label,
                                        imageUrl: img,
                                        onTap: () {
                                          Navigator.of(context).push(
                                            MaterialPageRoute(
                                              builder: (_) =>
                                                  SeasonEpisodesPage(
                                                season: s,
                                                appState: widget.appState,
                                                server: widget.server,
                                                isTv: widget.isTv,
                                                isVirtual: _seasonsVirtual,
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                        if (_seasons.isNotEmpty) ...[
                          _sectionTitle(context, '全部剧季'),
                          const SizedBox(height: 8),
                          Column(
                            children: _seasons.asMap().entries.map((entry) {
                              final index = entry.key;
                              final s = entry.value;
                              final label = _seasonLabel(s, index);
                              final count = _episodesCache[s.id]?.length;
                              final img = access?.adapter.imageUrl(
                                access.auth,
                                itemId: s.hasImage ? s.id : item.id,
                                maxWidth: 240,
                              );
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: _HoverScale(
                                  child: _detailGlassPanel(
                                    enableBlur: enableBlur,
                                    padding: const EdgeInsets.all(10),
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(12),
                                      onTap: () {
                                        Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (_) => SeasonEpisodesPage(
                                              season: s,
                                              appState: widget.appState,
                                              server: widget.server,
                                              isTv: widget.isTv,
                                              isVirtual: _seasonsVirtual,
                                            ),
                                          ),
                                        );
                                      },
                                      child: Row(
                                        children: [
                                          Stack(
                                            children: [
                                              ClipRRect(
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                                child: SizedBox(
                                                  width: 74,
                                                  height: 106,
                                                  child: img == null
                                                      ? const ColoredBox(
                                                          color: Colors.black26)
                                                      : LinNetworkImage(
                                                          imageUrl: img,
                                                          fit: BoxFit.cover,
                                                          errorWidget:
                                                              const ColoredBox(
                                                            color:
                                                                Colors.black26,
                                                          ),
                                                        ),
                                                ),
                                              ),
                                              if (count != null)
                                                Positioned(
                                                  right: 4,
                                                  top: 4,
                                                  child: Container(
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                        horizontal: 6,
                                                        vertical: 2),
                                                    decoration: BoxDecoration(
                                                      color: Colors.green
                                                          .withValues(
                                                              alpha: 0.9),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              999),
                                                    ),
                                                    child: Text(
                                                      '$count',
                                                      style: Theme.of(context)
                                                          .textTheme
                                                          .labelSmall
                                                          ?.copyWith(
                                                            color: Colors.white,
                                                            fontWeight:
                                                                FontWeight.w700,
                                                          ),
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Text(
                                              label,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .titleMedium
                                                  ?.copyWith(
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                            ),
                                          ),
                                          const Icon(
                                            Icons.chevron_right_rounded,
                                            color: Colors.white70,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ],
                        if (_similar.isNotEmpty) ...[
                          _sectionTitle(context, '更多类似'),
                          const SizedBox(height: 8),
                          SizedBox(
                            height: 240,
                            child: _withHorizontalEdgeFade(
                              context,
                              child: ListView.separated(
                                scrollDirection: Axis.horizontal,
                                itemCount: _similar.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(width: 12),
                                itemBuilder: (context, index) {
                                  final s = _similar[index];
                                  final img = s.hasImage && access != null
                                      ? access.adapter.imageUrl(
                                          access.auth,
                                          itemId: s.id,
                                          maxWidth: 400,
                                        )
                                      : null;
                                  final date = (s.premiereDate ?? '').trim();
                                  final parsed = date.isEmpty
                                      ? null
                                      : DateTime.tryParse(date);
                                  final year = parsed != null
                                      ? parsed.year.toString()
                                      : (date.length >= 4
                                          ? date.substring(0, 4)
                                          : '');
                                  final badge = s.type == 'Movie'
                                      ? '电影'
                                      : (s.type == 'Series' ? '剧集' : '');

                                  return _HoverScale(
                                    child: SizedBox(
                                      width: 140,
                                      child: MediaPosterTile(
                                        title: s.name,
                                        titleMaxLines: 2,
                                        imageUrl: img,
                                        year: year,
                                        rating: s.communityRating,
                                        badgeText: badge,
                                        onTap: () {
                                          Navigator.of(context).push(
                                            MaterialPageRoute(
                                              builder: (_) => ShowDetailPage(
                                                itemId: s.id,
                                                title: s.name,
                                                appState: widget.appState,
                                                server: widget.server,
                                                isTv: widget.isTv,
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        _externalLinksSection(context, item, widget.appState),
                        const SizedBox(height: _DetailUiTokens.sectionGap),
                        PluginSlotArea(
                          appState: widget.appState,
                          slotId: 'detail.sections.bottom',
                          params: _buildDetailPluginParams(item),
                        ),
                        if (showFloatingSettings) const SizedBox(height: 88),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (showFloatingSettings)
            Align(
              alignment: Alignment.bottomCenter,
              child: SafeArea(
                top: false,
                left: false,
                right: false,
                minimum: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: _floatingPlaybackSettingsDock(
                  context,
                  playInfo,
                  enableBlur: enableBlur,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class SeasonEpisodesPage extends StatefulWidget {
  const SeasonEpisodesPage({
    super.key,
    required this.season,
    required this.appState,
    this.server,
    this.isTv = false,
    this.isVirtual = false,
  });

  final MediaItem season;
  final AppState appState;
  final ServerProfile? server;
  final bool isTv;
  final bool isVirtual;

  @override
  State<SeasonEpisodesPage> createState() => _SeasonEpisodesPageState();
}

class _SeasonEpisodesPageState extends State<SeasonEpisodesPage> {
  List<MediaItem> _episodes = [];
  bool _loading = true;
  String? _error;
  MediaItem? _detailSeason;

  String? get _baseUrl => widget.server?.baseUrl ?? widget.appState.baseUrl;
  String? get _token => widget.server?.token ?? widget.appState.token;
  String? get _userId => widget.server?.userId ?? widget.appState.userId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final baseUrl = _baseUrl;
    final token = _token;
    final userId = _userId;
    if (baseUrl == null || token == null || userId == null) {
      setState(() {
        _error = '未连接服务器';
        _loading = false;
      });
      return;
    }

    final access =
        resolveServerAccess(appState: widget.appState, server: widget.server);
    if (access == null) {
      setState(() {
        _error = 'Unsupported server';
        _loading = false;
      });
      return;
    }
    try {
      final eps = await access.adapter.fetchEpisodes(
        access.auth,
        seasonId: widget.season.id,
      );
      final items = List<MediaItem>.from(eps.items);
      items.sort((a, b) {
        final aNo = a.episodeNumber ?? 0;
        final bNo = b.episodeNumber ?? 0;
        return aNo.compareTo(bNo);
      });
      MediaItem? detail;
      if (!widget.isVirtual) {
        try {
          detail = await access.adapter.fetchItemDetail(
            access.auth,
            itemId: widget.season.id,
          );
        } catch (_) {}
      }
      setState(() {
        _episodes = items;
        _detailSeason = detail;
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final seasonName = _detailSeason?.name ?? widget.season.name;
    final enableBlur = !widget.isTv && widget.appState.enableBlurEffects;
    final access =
        resolveServerAccess(appState: widget.appState, server: widget.server);
    return Scaffold(
      appBar: GlassAppBar(
        enableBlur: enableBlur,
        child: AppBar(title: Text(seasonName)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : _episodes.isEmpty
                  ? const Center(child: Text('暂无剧集'))
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: _episodes.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final e = _episodes[index];
                        final epNo = e.episodeNumber ?? (index + 1);
                        final epName = e.name.trim();
                        final titleText = epName.isNotEmpty
                            ? '$epNo. $epName'
                            : '$epNo. 第$epNo集';
                        final dur = e.runTimeTicks != null
                            ? Duration(
                                microseconds: (e.runTimeTicks! / 10).round())
                            : null;
                        final img = access == null
                            ? ''
                            : access.adapter.imageUrl(
                                access.auth,
                                itemId: e.hasImage ? e.id : widget.season.id,
                                maxWidth: 700,
                              );
                        return Card(
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => EpisodeDetailPage(
                                    episode: e,
                                    appState: widget.appState,
                                    server: widget.server,
                                    isTv: widget.isTv,
                                  ),
                                ),
                              );
                            },
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      SizedBox(
                                        width: 170,
                                        child: AspectRatio(
                                          aspectRatio: 16 / 9,
                                          child: ClipRRect(
                                            borderRadius:
                                                BorderRadius.circular(12),
                                            child: LinNetworkImage(
                                              imageUrl: img,
                                              fit: BoxFit.cover,
                                              errorWidget: const ColoredBox(
                                                color: Colors.black26,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              titleText,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .titleMedium
                                                  ?.copyWith(
                                                      fontWeight:
                                                          FontWeight.w700),
                                            ),
                                            if (dur != null) ...[
                                              const SizedBox(height: 6),
                                              Text(
                                                _fmt(dur),
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .bodySmall
                                                    ?.copyWith(
                                                      color: Theme.of(context)
                                                          .colorScheme
                                                          .onSurfaceVariant,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (e.overview.isNotEmpty) ...[
                                    const SizedBox(height: 10),
                                    Text(
                                      e.overview,
                                      maxLines: 4,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
    );
  }
}

enum _EpisodeMoreAction {
  pickEpisode,
  pickSeason,
  openSeasonEpisodes,
  togglePlayed,
  toggleFavorite,
  togglePlayerCore,
}

class EpisodeDetailPage extends StatefulWidget {
  const EpisodeDetailPage({
    super.key,
    required this.episode,
    required this.appState,
    this.server,
    this.isTv = false,
  });

  final MediaItem episode;
  final AppState appState;
  final ServerProfile? server;
  final bool isTv;

  @override
  State<EpisodeDetailPage> createState() => _EpisodeDetailPageState();
}

class _EpisodeDetailPageState extends State<EpisodeDetailPage> {
  late MediaItem _episode;
  int _loadSeq = 0;

  PlaybackInfoResult? _playInfo;
  String? _selectedMediaSourceId;
  int? _selectedAudioStreamIndex; // null = default
  int? _selectedSubtitleStreamIndex; // null = default, -1 = off
  String? _error;
  bool _loading = true;
  MediaItem? _detail;
  List<ChapterInfo> _chapters = [];
  String? _seriesId;
  String _seriesName = '';
  List<MediaItem> _seasons = [];
  bool _seasonsVirtual = false;
  String? _selectedSeasonId;
  final Map<String, List<MediaItem>> _episodesCache = {};
  String? _seriesError;
  bool _seriesLoading = false;
  bool _markBusy = false;
  bool _localFavorite = false;
  bool _favoriteLoaded = false;
  String _preloadOwnerKey = '';
  final Map<String, PreparedPlaybackPreload> _preparedEpisodePreloads =
      <String, PreparedPlaybackPreload>{};

  Map<String, Object?> _buildDetailPluginParams(MediaItem item) {
    final yearText = _mediaYearText(item);
    final year = int.tryParse(yearText);
    return <String, Object?>{
      'page': 'detail',
      'itemId': item.id,
      'title': item.name,
      'media': <String, Object?>{
        'id': item.id,
        'type': item.type,
        'title': item.name,
        if (year != null) 'year': year,
      },
      'item': <String, Object?>{
        'id': item.id,
        'name': item.name,
        'type': item.type,
        if (year != null) 'year': year,
      },
      if ((_seriesId ?? '').trim().isNotEmpty)
        'series': <String, Object?>{
          'id': _seriesId!,
          'name': _seriesName,
        },
    };
  }

  Future<void> _switchEpisode(MediaItem episode) async {
    final id = episode.id.trim();
    if (id.isEmpty || id == _episode.id) return;

    setState(() {
      _episode = episode;
      _playInfo = null;
      _selectedMediaSourceId = null;
      _selectedAudioStreamIndex = null;
      _selectedSubtitleStreamIndex = null;
      _error = null;
      _loading = true;
      _detail = null;
      _chapters = const [];
      _favoriteLoaded = false;
      _localFavorite = false;
    });

    unawaited(_loadLocalFavorite());
    unawaited(_load());
  }

  Future<void> _toggleEpisodePlayedMark() async {
    if (_markBusy) return;
    final access =
        resolveServerAccess(appState: widget.appState, server: widget.server);
    if (access == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('未连接服务器')),
      );
      return;
    }

    final currentPlayed = _detail?.played ?? false;
    final nextPlayed = !currentPlayed;

    setState(() => _markBusy = true);
    try {
      await access.adapter.updatePlaybackPosition(
        access.auth,
        itemId: _episode.id,
        positionTicks: 0,
        played: nextPlayed,
      );

      final detail = await access.adapter
          .fetchItemDetail(access.auth, itemId: _episode.id);
      if (!mounted) return;
      setState(() => _detail = detail);
      _persistEpisodeDetailCache();

      unawaited(
        widget.appState.loadContinueWatching(
          forceRefresh: true,
          forceNewRequest: true,
        ),
      );
      unawaited(widget.appState.loadHome(forceRefresh: true));

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(nextPlayed ? '已标记为已播放' : '已标记为未播放')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('标记失败：$e')),
      );
    } finally {
      if (mounted) setState(() => _markBusy = false);
    }
  }

  String? get _baseUrl => widget.server?.baseUrl ?? widget.appState.baseUrl;
  String? get _token => widget.server?.token ?? widget.appState.token;
  String? get _userId => widget.server?.userId ?? widget.appState.userId;

  String get _episodeFavoriteKey {
    final serverKey =
        (_baseUrl ?? 'default').replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
    return 'episode_detail_local_favorite_${serverKey}_${_episode.id}';
  }

  PlaybackSourcePlayerCoreKind get _episodePlaybackCoreKind {
    return playbackSourcePlayerCoreKindForPlayerCore(
      normalizePlayerCoreForPlatform(widget.appState.playerCore),
    );
  }

  bool get _preferBuiltInProxyForMpvPreload =>
      widget.isTv &&
      widget.appState.tvBuiltInProxyEnabled &&
      BuiltInProxyService.instance.status.state == BuiltInProxyState.running;

  PreparedPlaybackPreload? _preparedEpisodePreloadForPlayback(String itemId) {
    final prepared = _preparedEpisodePreloads[itemId.trim()];
    if (prepared == null) return null;
    if (!prepared.matchesPlayback(
      itemId: itemId,
      playerCore: _episodePlaybackCoreKind,
      selectedMediaSourceId: _selectedMediaSourceId,
      audioStreamIndex: _selectedAudioStreamIndex,
      subtitleStreamIndex: _selectedSubtitleStreamIndex,
    )) {
      return null;
    }
    return prepared;
  }

  String get _episodeCacheServerScope => _browsingCacheServerScope(
        appState: widget.appState,
        server: widget.server,
        baseUrl: _baseUrl,
      );

  void _applyEpisodeDetailCache(EpisodeDetailCachePayload payload) {
    final seasons = List<MediaItem>.from(payload.seasons);
    String? selectedSeasonId = payload.selectedSeasonId;
    if (selectedSeasonId != null &&
        seasons.isNotEmpty &&
        !seasons.any((season) => season.id == selectedSeasonId)) {
      selectedSeasonId = seasons.first.id;
    }
    selectedSeasonId ??=
        seasons.isNotEmpty ? seasons.first.id : payload.detail.parentId;

    setState(() {
      _episode = payload.detail;
      _detail = payload.detail;
      _playInfo = payload.playInfo;
      _chapters = List<ChapterInfo>.from(payload.chapters);
      _seriesId = payload.seriesId;
      _seriesName = payload.seriesName;
      _seasons = seasons;
      _seasonsVirtual = payload.seasonsVirtual;
      _selectedSeasonId = selectedSeasonId;
      _episodesCache
        ..clear()
        ..addAll(payload.episodesBySeason);
      _selectedMediaSourceId = payload.selectedMediaSourceId;
      _selectedAudioStreamIndex = payload.selectedAudioStreamIndex;
      _selectedSubtitleStreamIndex = payload.selectedSubtitleStreamIndex;
      _seriesError = null;
      _seriesLoading = false;
      _error = null;
      _loading = false;
    });
  }

  EpisodeDetailCachePayload? _currentEpisodeDetailCachePayload() {
    final detail = _detail;
    if (detail == null) return null;
    return EpisodeDetailCachePayload(
      detail: detail,
      playInfo: _playInfo,
      chapters: List<ChapterInfo>.from(_chapters),
      seriesId: _seriesId,
      seriesName: _seriesName,
      seasons: List<MediaItem>.from(_seasons),
      seasonsVirtual: _seasonsVirtual,
      selectedSeasonId: _selectedSeasonId,
      episodesBySeason: _episodesCache.map(
        (key, value) => MapEntry(key, List<MediaItem>.from(value)),
      ),
      selectedMediaSourceId: _selectedMediaSourceId,
      selectedAudioStreamIndex: _selectedAudioStreamIndex,
      selectedSubtitleStreamIndex: _selectedSubtitleStreamIndex,
    );
  }

  void _persistEpisodeDetailCache() {
    final payload = _currentEpisodeDetailCachePayload();
    if (payload == null) return;
    unawaited(
      BrowsingCacheService.instance.writeEpisodeDetail(
        serverScope: _episodeCacheServerScope,
        itemId: _episode.id,
        payload: payload,
      ),
    );
  }

  Future<void> _preloadEpisodeBestEffort({
    required ServerAccess access,
    required String itemId,
    required int loadSeq,
    String? selectedMediaSourceId,
    int? audioStreamIndex,
    int? subtitleStreamIndex,
  }) async {
    if (!widget.appState.preloadEnabled) return;
    late final PreparedPlaybackPreload prepared;
    StreamPreloadResult result;
    try {
      final serverId = widget.server?.id ?? widget.appState.activeServerId;
      final seriesId = (_seriesId ?? _episode.seriesId ?? '').trim();
      final preferredMediaSourceIndex =
          serverId == null || serverId.trim().isEmpty || seriesId.isEmpty
              ? null
              : widget.appState.seriesMediaSourceIndex(
                  serverId: serverId.trim(),
                  seriesId: seriesId,
                );
      final triggerSource = itemId.trim() == _episode.id.trim()
          ? 'detail_current'
          : 'detail_next';
      final preloadScopeKey = itemId.trim() == _episode.id.trim()
          ? 'detail_current'
          : 'detail_next';
      final targetKind = itemId.trim() == _episode.id.trim()
          ? PlaybackPreloadTargetKind.currentItem
          : PlaybackPreloadTargetKind.nextItem;
      prepared = await PlaybackPreloadCoordinator.prepareItem(
        PlaybackPreloadBuildRequest(
          access: access,
          appState: widget.appState,
          itemId: itemId,
          playerCore: _episodePlaybackCoreKind,
          targetKind: targetKind,
          triggerSource: triggerSource,
          selectedMediaSourceId: selectedMediaSourceId,
          preferredMediaSourceIndex: preferredMediaSourceIndex,
          audioStreamIndex: audioStreamIndex,
          subtitleStreamIndex: subtitleStreamIndex,
          preferredVideoVersion: widget.appState.preferredVideoVersion,
          preferBuiltInProxy:
              _episodePlaybackCoreKind == PlaybackSourcePlayerCoreKind.mpv &&
                  _preferBuiltInProxyForMpvPreload,
          ownerKey: _preloadOwnerKey,
          scopeKey: preloadScopeKey,
        ),
      );
      if (loadSeq == _loadSeq) {
        _preparedEpisodePreloads[itemId.trim()] = prepared;
      }
      result = await PlaybackPreloadCoordinator.preloadPrepared(prepared);
    } catch (_) {
      return;
    }

    if (!mounted || loadSeq != _loadSeq) return;
    if (result.disabledNow) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('预加载失败，当前源将暂时跳过')),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _episode = widget.episode;
    _preloadOwnerKey =
        PlaybackPreloadCoordinator.createOwnerToken('detail_episode');
    _loadLocalFavorite();
    _load();
  }

  @override
  void dispose() {
    PlaybackPreloadCoordinator.cancelOwner(_preloadOwnerKey);
    super.dispose();
  }

  Future<void> _loadLocalFavorite() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        _localFavorite = prefs.getBool(_episodeFavoriteKey) ?? false;
        _favoriteLoaded = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _favoriteLoaded = true);
    }
  }

  Future<void> _toggleLocalFavorite() async {
    final next = !_localFavorite;
    setState(() => _localFavorite = next);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_episodeFavoriteKey, next);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(next ? '已加入本地收藏' : '已取消本地收藏')),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _localFavorite = !next);
    }
  }

  Future<void> _togglePlayerCore() async {
    final next = widget.appState.playerCore == PlayerCore.exo
        ? PlayerCore.mpv
        : PlayerCore.exo;
    if (next == PlayerCore.exo &&
        (kIsWeb || defaultTargetPlatform != TargetPlatform.android)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Exo 内核仅支持 Android')),
      );
      return;
    }

    try {
      await widget.appState.setPlayerCore(next);
    } catch (_) {}

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(next == PlayerCore.exo ? '已切换到 ExoPlayer' : '已切换到 mpv'),
      ),
    );
  }

  Future<void> _refreshProgressAfterReturn(
      {Duration delay = const Duration(milliseconds: 350)}) async {
    final access =
        resolveServerAccess(appState: widget.appState, server: widget.server);
    if (access == null) return;

    final before = _detail?.playbackPositionTicks;
    final episodeId = _episode.id;
    for (var attempt = 0; attempt < 3; attempt++) {
      final attemptDelay =
          attempt == 0 ? delay : const Duration(milliseconds: 300);
      if (attemptDelay > Duration.zero) {
        await Future<void>.delayed(attemptDelay);
      }

      try {
        final detail = await access.adapter
            .fetchItemDetail(access.auth, itemId: episodeId);
        if (!mounted) return;
        setState(() => _detail = detail);
        _persistEpisodeDetailCache();
        if (before == null || detail.playbackPositionTicks != before) return;
      } catch (_) {
        // Best-effort refresh. Keep existing state on failure.
      }
    }
  }

  Future<void> _load() async {
    if (_preloadOwnerKey.isNotEmpty) {
      PlaybackPreloadCoordinator.cancelOwner(_preloadOwnerKey);
    }
    _preloadOwnerKey =
        PlaybackPreloadCoordinator.createOwnerToken('detail_episode');
    _preparedEpisodePreloads.clear();
    final baseUrl = _baseUrl;
    final token = _token;
    final userId = _userId;
    if (baseUrl == null || token == null || userId == null) {
      setState(() {
        _error = '未连接服务器';
        _loading = false;
      });
      return;
    }

    final access =
        resolveServerAccess(appState: widget.appState, server: widget.server);
    if (access == null) {
      setState(() {
        _error = 'Unsupported server';
        _loading = false;
      });
      return;
    }

    final cached = await BrowsingCacheService.instance.readEpisodeDetail(
      serverScope: _episodeCacheServerScope,
      itemId: _episode.id,
    );
    final cachedPayload = cached?.value;
    if (cachedPayload != null) {
      _applyEpisodeDetailCache(cachedPayload);
      if (cached!.isFresh) return;
    } else {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    final seq = ++_loadSeq;
    final episodeId = _episode.id.trim();
    try {
      final detail =
          await access.adapter.fetchItemDetail(access.auth, itemId: episodeId);
      if (!mounted || seq != _loadSeq) return;

      final resolvedSeriesId =
          (detail.seriesId ?? _episode.seriesId ?? '').trim();
      final resolvedSeriesName = detail.seriesName.trim().isNotEmpty
          ? detail.seriesName.trim()
          : _episode.seriesName.trim();

      if (resolvedSeriesId.isNotEmpty) {
        setState(() {
          _seriesId = resolvedSeriesId;
          _seriesName = resolvedSeriesName;
          _seriesLoading = true;
        });
        unawaited(
          _loadSeriesEpisodes(
            access: access,
            episodeDetail: detail,
            seriesId: resolvedSeriesId,
            seriesName: resolvedSeriesName,
            loadSeq: seq,
          ),
        );
      }
      final info = await access.adapter.fetchPlaybackInfo(
        access.auth,
        itemId: episodeId,
        profile: playbackInfoProfileKindForPlaybackSourceCore(
          _episodePlaybackCoreKind,
        ),
      );
      if (!mounted || seq != _loadSeq) return;
      final sources = info.mediaSources.cast<Map<String, dynamic>>();
      final preferred = sources.isEmpty
          ? null
          : _ShowDetailPageState._pickPreferredMediaSourceId(
              sources,
              widget.appState.preferredVideoVersion,
            );

      final serverId = widget.server?.id ?? widget.appState.activeServerId;
      final seriesId = resolvedSeriesId.trim();

      String? selectedMediaSourceId = _selectedMediaSourceId;
      if ((selectedMediaSourceId ?? '').trim().isEmpty &&
          serverId != null &&
          serverId.trim().isNotEmpty &&
          seriesId.isNotEmpty &&
          sources.isNotEmpty) {
        final idx = widget.appState.seriesMediaSourceIndex(
            serverId: serverId.trim(), seriesId: seriesId);
        if (idx != null && idx >= 0 && idx < sources.length) {
          selectedMediaSourceId = sources[idx]['Id']?.toString();
        }
      }
      selectedMediaSourceId = (selectedMediaSourceId ?? '').trim();
      if (selectedMediaSourceId.isEmpty) {
        selectedMediaSourceId = (preferred ?? '').trim();
      }
      if (selectedMediaSourceId.isEmpty && sources.isNotEmpty) {
        selectedMediaSourceId = (sources.first['Id']?.toString() ?? '').trim();
      }
      if (selectedMediaSourceId.isEmpty) selectedMediaSourceId = null;

      int? selectedAudioStreamIndex = _selectedAudioStreamIndex;
      int? selectedSubtitleStreamIndex = _selectedSubtitleStreamIndex;
      if (serverId != null &&
          serverId.trim().isNotEmpty &&
          seriesId.isNotEmpty) {
        selectedAudioStreamIndex ??= widget.appState.seriesAudioStreamIndex(
            serverId: serverId.trim(), seriesId: seriesId);
        selectedSubtitleStreamIndex ??=
            widget.appState.seriesSubtitleStreamIndex(
          serverId: serverId.trim(),
          seriesId: seriesId,
        );
      }

      unawaited(
        _preloadEpisodeBestEffort(
          access: access,
          itemId: episodeId,
          loadSeq: seq,
          selectedMediaSourceId: selectedMediaSourceId,
          audioStreamIndex: selectedAudioStreamIndex,
          subtitleStreamIndex: selectedSubtitleStreamIndex,
        ),
      );

      List<ChapterInfo> chaps = const [];
      try {
        chaps =
            await access.adapter.fetchChapters(access.auth, itemId: episodeId);
      } catch (_) {
        // Chapters are optional; hide section when unavailable.
      }
      if (!mounted || seq != _loadSeq) return;
      setState(() {
        _playInfo = info;
        _detail = detail;
        _chapters = chaps;
        _selectedMediaSourceId = selectedMediaSourceId;
        _selectedAudioStreamIndex = selectedAudioStreamIndex;
        _selectedSubtitleStreamIndex = selectedSubtitleStreamIndex;
        _error = null;
        _loading = false;
      });
      _persistEpisodeDetailCache();
    } catch (e) {
      if (!mounted || seq != _loadSeq) return;
      if (cachedPayload == null) {
        setState(() => _error = e.toString());
      }
    } finally {
      if (mounted && seq == _loadSeq && cachedPayload == null) {
        setState(() => _loading = false);
      }
    }
  }

  String _mediaSourceSubtitle(Map<String, dynamic> ms) {
    final size = ms['Size'];
    final sizeGb =
        size is num ? (size / (1024 * 1024 * 1024)).toStringAsFixed(1) : null;
    final bitrate = _ShowDetailPageState._asInt(ms['Bitrate']);
    final bitrateMbps =
        bitrate != null ? (bitrate / 1000000).toStringAsFixed(1) : null;

    final videoStreams = _ShowDetailPageState._streamsOfType(ms, 'Video');
    final video = videoStreams.isNotEmpty ? videoStreams.first : null;
    final height = _ShowDetailPageState._asInt(video?['Height']);
    final vCodec =
        (ms['VideoCodec'] as String?) ?? (video?['Codec'] as String?);

    final parts = <String>[];
    if (height != null) parts.add('${height}p');
    if (vCodec != null && vCodec.isNotEmpty) parts.add(vCodec.toUpperCase());
    if (sizeGb != null) parts.add('$sizeGb GB');
    if (bitrateMbps != null) parts.add('$bitrateMbps Mbps');
    return parts.isEmpty ? '直连播放' : parts.join(' / ');
  }

  // ignore: unused_element
  Widget _episodePlaybackOptionsCard(
      BuildContext context, PlaybackInfoResult info) {
    final ms =
        _ShowDetailPageState._findMediaSource(info, _selectedMediaSourceId);
    if (ms == null) return const SizedBox.shrink();

    final audioStreams = _ShowDetailPageState._streamsOfType(ms, 'Audio');
    final subtitleStreams = _ShowDetailPageState._streamsOfType(ms, 'Subtitle');

    final defaultAudio = _ShowDetailPageState._defaultStream(audioStreams);
    final selectedAudio = _selectedAudioStreamIndex != null
        ? audioStreams.firstWhere(
            (s) =>
                _ShowDetailPageState._asInt(s['Index']) ==
                _selectedAudioStreamIndex,
            orElse: () => defaultAudio ?? const <String, dynamic>{},
          )
        : defaultAudio;

    final defaultSub = _ShowDetailPageState._defaultStream(subtitleStreams);
    final Map<String, dynamic>? selectedSub;
    if (_selectedSubtitleStreamIndex == -1) {
      selectedSub = null;
    } else if (_selectedSubtitleStreamIndex != null) {
      selectedSub = subtitleStreams.firstWhere(
        (s) =>
            _ShowDetailPageState._asInt(s['Index']) ==
            _selectedSubtitleStreamIndex,
        orElse: () => defaultSub ?? const <String, dynamic>{},
      );
    } else {
      selectedSub = defaultSub;
    }

    final hasSubs = subtitleStreams.isNotEmpty;
    final subtitleText = _selectedSubtitleStreamIndex == -1
        ? '关闭'
        : selectedSub != null && selectedSub.isNotEmpty
            ? _ShowDetailPageState._streamLabel(selectedSub,
                includeCodec: false)
            : hasSubs
                ? '默认'
                : '关闭';

    final audioText = selectedAudio != null && selectedAudio.isNotEmpty
        ? _ShowDetailPageState._streamLabel(selectedAudio,
                includeCodec: false) +
            (selectedAudio == defaultAudio ? ' (默认)' : '')
        : '默认';

    final theme = Theme.of(context);
    final dividerColor = Colors.white.withValues(alpha: 0.20);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _detailGlassPanel(
          enableBlur: !widget.isTv && widget.appState.enableBlurEffects,
          radius: 16,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.video_file, color: Colors.white),
                title: Text(
                  _ShowDetailPageState._mediaSourceTitle(ms),
                  style: const TextStyle(color: Colors.white),
                ),
                subtitle: Text(
                  _mediaSourceSubtitle(ms),
                  style: const TextStyle(color: Colors.white70),
                ),
                trailing:
                    const Icon(Icons.arrow_drop_down, color: Colors.white70),
                onTap: () => _pickMediaSource(context, info),
              ),
              Divider(height: 1, color: dividerColor),
              ListTile(
                leading: const Icon(Icons.audiotrack, color: Colors.white),
                title: Text(audioText,
                    style: const TextStyle(color: Colors.white)),
                trailing:
                    const Icon(Icons.arrow_drop_down, color: Colors.white70),
                onTap: audioStreams.isEmpty
                    ? null
                    : () => _pickAudioStream(context, ms),
              ),
              Divider(height: 1, color: dividerColor),
              ListTile(
                leading: const Icon(Icons.subtitles, color: Colors.white),
                title: Text(subtitleText,
                    style: const TextStyle(color: Colors.white)),
                trailing:
                    const Icon(Icons.arrow_drop_down, color: Colors.white70),
                onTap: hasSubs ? () => _pickSubtitleStream(context, ms) : null,
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '提示：以上选择会应用到本剧后续集数',
          style: theme.textTheme.bodySmall?.copyWith(
            color: Colors.white70,
          ),
        ),
      ],
    );
  }

  Future<void> _pickMediaSource(
      BuildContext context, PlaybackInfoResult info) async {
    final sources = info.mediaSources.cast<Map<String, dynamic>>();
    if (sources.isEmpty) return;

    final sortedSources = List<Map<String, dynamic>>.from(sources)
      ..sort(_ShowDetailPageState._compareMediaSourcesByQuality);

    final current = (_selectedMediaSourceId ?? '').trim();
    final selected = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: ListView(
            children: [
              const ListTile(title: Text('版本选择')),
              ...sortedSources.map((ms) {
                final id = (ms['Id']?.toString() ?? '').trim();
                final selectedNow = id.isNotEmpty && id == current;
                return ListTile(
                  leading: Icon(
                      selectedNow ? Icons.check_circle : Icons.circle_outlined),
                  title: Text(_ShowDetailPageState._mediaSourceTitle(ms)),
                  subtitle: Text(_mediaSourceSubtitle(ms)),
                  onTap: id.isEmpty ? null : () => Navigator.of(ctx).pop(id),
                );
              }),
            ],
          ),
        );
      },
    );

    if (!mounted) return;
    final picked = (selected ?? '').trim();
    if (picked.isEmpty || picked == current) return;

    setState(() {
      _selectedMediaSourceId = picked;
    });

    final serverId = widget.server?.id ?? widget.appState.activeServerId;
    final sid = (_seriesId ?? '').trim();
    if (serverId == null || serverId.trim().isEmpty || sid.isEmpty) return;
    final idx = sources
        .indexWhere((ms) => (ms['Id']?.toString() ?? '').trim() == picked);
    if (idx < 0) return;
    unawaited(
      widget.appState.setSeriesMediaSourceIndex(
        serverId: serverId.trim(),
        seriesId: sid,
        mediaSourceIndex: idx,
      ),
    );
  }

  Future<void> _pickAudioStream(
      BuildContext context, Map<String, dynamic> ms) async {
    final audioStreams = _ShowDetailPageState._streamsOfType(ms, 'Audio');
    if (audioStreams.isEmpty) return;

    final selected = await showModalBottomSheet<int?>(
      context: context,
      builder: (ctx) {
        final def = _ShowDetailPageState._defaultStream(audioStreams);
        final defIndex = _ShowDetailPageState._asInt(def?['Index']);
        return SafeArea(
          child: ListView(
            children: [
              const ListTile(title: Text('音轨选择')),
              ListTile(
                leading: Icon(_selectedAudioStreamIndex == null
                    ? Icons.check
                    : Icons.circle_outlined),
                title: const Text('默认'),
                onTap: () => Navigator.of(ctx).pop(null),
              ),
              ...audioStreams.map((s) {
                final idx = _ShowDetailPageState._asInt(s['Index']);
                final selectedNow =
                    idx != null && idx == _selectedAudioStreamIndex;
                final title =
                    _ShowDetailPageState._streamLabel(s, includeCodec: false);
                return ListTile(
                  leading: Icon(
                      selectedNow ? Icons.check_circle : Icons.circle_outlined),
                  title: Text(idx == defIndex ? '$title (默认)' : title),
                  subtitle: (s['Codec'] as String?)?.isNotEmpty == true
                      ? Text(s['Codec'] as String)
                      : null,
                  onTap: idx == null ? null : () => Navigator.of(ctx).pop(idx),
                );
              }),
            ],
          ),
        );
      },
    );

    if (!mounted) return;
    setState(() => _selectedAudioStreamIndex = selected);

    final serverId = widget.server?.id ?? widget.appState.activeServerId;
    final sid = (_seriesId ?? '').trim();
    if (serverId == null || serverId.trim().isEmpty || sid.isEmpty) return;
    unawaited(
      widget.appState.setSeriesAudioStreamIndex(
        serverId: serverId.trim(),
        seriesId: sid,
        audioStreamIndex: selected,
      ),
    );
  }

  Future<void> _pickSubtitleStream(
      BuildContext context, Map<String, dynamic> ms) async {
    final subtitleStreams = _ShowDetailPageState._streamsOfType(ms, 'Subtitle');
    if (subtitleStreams.isEmpty) return;

    final selected = await showModalBottomSheet<int?>(
      context: context,
      builder: (ctx) {
        final def = _ShowDetailPageState._defaultStream(subtitleStreams);
        final defIndex = _ShowDetailPageState._asInt(def?['Index']);
        final isOff = _selectedSubtitleStreamIndex == -1;
        final isDefault = _selectedSubtitleStreamIndex == null;
        return SafeArea(
          child: ListView(
            children: [
              const ListTile(title: Text('字幕选择')),
              ListTile(
                leading: Icon(isOff ? Icons.check : Icons.circle_outlined),
                title: const Text('关闭'),
                onTap: () => Navigator.of(ctx).pop(-1),
              ),
              ListTile(
                leading: Icon(isDefault ? Icons.check : Icons.circle_outlined),
                title: const Text('默认'),
                onTap: () => Navigator.of(ctx).pop(null),
              ),
              ...subtitleStreams.map((s) {
                final idx = _ShowDetailPageState._asInt(s['Index']);
                final selectedNow =
                    idx != null && idx == _selectedSubtitleStreamIndex;
                final title =
                    _ShowDetailPageState._streamLabel(s, includeCodec: false);
                return ListTile(
                  leading: Icon(
                      selectedNow ? Icons.check_circle : Icons.circle_outlined),
                  title: Text(idx == defIndex ? '$title (默认)' : title),
                  subtitle: (s['Codec'] as String?)?.isNotEmpty == true
                      ? Text(s['Codec'] as String)
                      : null,
                  onTap: idx == null ? null : () => Navigator.of(ctx).pop(idx),
                );
              }),
            ],
          ),
        );
      },
    );

    if (!mounted) return;
    setState(() => _selectedSubtitleStreamIndex = selected);

    final serverId = widget.server?.id ?? widget.appState.activeServerId;
    final sid = (_seriesId ?? '').trim();
    if (serverId == null || serverId.trim().isEmpty || sid.isEmpty) return;
    unawaited(
      widget.appState.setSeriesSubtitleStreamIndex(
        serverId: serverId.trim(),
        seriesId: sid,
        subtitleStreamIndex: selected,
      ),
    );
  }

  // ignore: unused_element
  String _episodeLine(MediaItem ep) {
    final seasonNo = ep.seasonNumber ?? 1;
    final epNo = ep.episodeNumber ?? 1;
    final name = ep.name.trim();
    return name.isNotEmpty ? 'S$seasonNo:E$epNo - $name' : 'S$seasonNo:E$epNo';
  }

  String _episodeDateText(MediaItem ep) {
    final raw = (ep.premiereDate ?? '').trim();
    if (raw.isEmpty) return '';
    final dt = DateTime.tryParse(raw);
    if (dt == null) return raw.length >= 10 ? raw.substring(0, 10) : raw;
    return '${dt.year}/${dt.month}/${dt.day}';
  }

  Map<String, dynamic>? _currentMediaSource() {
    final info = _playInfo;
    if (info == null) return null;
    return _ShowDetailPageState._findMediaSource(info, _selectedMediaSourceId);
  }

  String _currentVideoText() {
    final ms = _currentMediaSource();
    if (ms == null) return '未知';
    return _mediaSourceSubtitle(ms);
  }

  String _currentAudioText() {
    final ms = _currentMediaSource();
    if (ms == null) return '默认';
    final streams = _ShowDetailPageState._streamsOfType(ms, 'Audio');
    if (streams.isEmpty) return '默认';
    final def = _ShowDetailPageState._defaultStream(streams);
    final selected = _selectedAudioStreamIndex != null
        ? streams.firstWhere(
            (s) =>
                _ShowDetailPageState._asInt(s['Index']) ==
                _selectedAudioStreamIndex,
            orElse: () => def ?? const <String, dynamic>{},
          )
        : def;
    if (selected == null || selected.isEmpty) return '默认';
    return _ShowDetailPageState._streamLabel(selected, includeCodec: false);
  }

  String _currentSubtitleText() {
    if (_selectedSubtitleStreamIndex == -1) return '关闭';
    final ms = _currentMediaSource();
    if (ms == null) return '默认';
    final streams = _ShowDetailPageState._streamsOfType(ms, 'Subtitle');
    if (streams.isEmpty) return '默认';
    final def = _ShowDetailPageState._defaultStream(streams);
    final selected = _selectedSubtitleStreamIndex != null
        ? streams.firstWhere(
            (s) =>
                _ShowDetailPageState._asInt(s['Index']) ==
                _selectedSubtitleStreamIndex,
            orElse: () => def ?? const <String, dynamic>{},
          )
        : def;
    if (selected == null || selected.isEmpty) return '默认';
    return _ShowDetailPageState._streamLabel(selected, includeCodec: false);
  }

  List<String> _episodeMediaBadges(
    MediaItem episode, {
    required Duration? runtime,
    Map<String, dynamic>? mediaSource,
  }) {
    final badges = <String>[];
    final resolution = _ShowDetailPageState._mediaSourceResolutionText(
      mediaSource,
    );
    if (resolution.isNotEmpty) {
      badges.add('分辨率 $resolution');
    }

    final bitrate = _ShowDetailPageState._mediaSourceBitrateText(
      mediaSource,
      fallbackSizeBytes: episode.sizeBytes,
      fallbackRuntimeTicks: episode.runTimeTicks,
    );
    if (bitrate.isNotEmpty) {
      badges.add('码率 $bitrate');
    }

    final size = _ShowDetailPageState._mediaSourceSizeText(
      mediaSource,
      fallbackSizeBytes: episode.sizeBytes,
    );
    if (size.isNotEmpty) {
      badges.add('大小 $size');
    }

    final durationText = _episodeRuntimeText(runtime).trim();
    if (durationText.isNotEmpty) {
      badges.add('时长 $durationText');
    }
    return badges;
  }

  Future<void> _playCurrentEpisode({Duration? startPosition}) async {
    final ep = _detail ?? _episode;
    final preparedPreload = _preparedEpisodePreloadForPlayback(ep.id);
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => buildNetworkPlayerPage(
          title: ep.name,
          itemId: ep.id,
          appState: widget.appState,
          server: widget.server,
          isTv: widget.isTv,
          seriesId: _seriesId,
          startPosition: startPosition,
          mediaSourceId: _selectedMediaSourceId,
          audioStreamIndex: _selectedAudioStreamIndex,
          subtitleStreamIndex: _selectedSubtitleStreamIndex,
          preparedPreload: preparedPreload,
        ),
      ),
    );
    if (!mounted) return;
    await _refreshProgressAfterReturn();
  }

  // ignore: unused_element
  Widget _episodeActionButton({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
    bool primary = false,
  }) {
    return _detailActionButton(
      context,
      icon: icon,
      label: label,
      onTap: onTap,
      primary: primary,
    );
  }

  static const int _kTvPickerDefault = -99999;

  String _episodeMark(MediaItem ep) {
    final season = (ep.seasonNumber ?? 0).clamp(0, 999);
    final episode = (ep.episodeNumber ?? 0).clamp(0, 999);
    if (season <= 0 || episode <= 0) return '';
    return 'S${season.toString().padLeft(2, '0')}'
        'E${episode.toString().padLeft(2, '0')}';
  }

  Future<T?> _showTvPicker<T>(
    BuildContext context, {
    required String title,
    required List<({T value, String label, String? subtitle, bool selected})>
        options,
  }) async {
    if (options.isEmpty) return null;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = scheme.brightness == Brightness.dark;
    final uiScale = context.uiScale;

    final radius = (18 * uiScale).clamp(14.0, 22.0);
    final insetH = (28 * uiScale).clamp(18.0, 44.0);
    final insetV = (22 * uiScale).clamp(14.0, 34.0);
    final padding = (14 * uiScale).clamp(10.0, 18.0);
    final maxWidth = (760 * uiScale).clamp(520.0, 920.0);
    final maxHeight = MediaQuery.sizeOf(context).height * 0.72;

    final gradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        scheme.primary.withValues(alpha: isDark ? 0.14 : 0.10),
        Colors.black.withValues(alpha: 0.58),
      ],
    );

    return showDialog<T>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.64),
      builder: (ctx) {
        var autofocusAssigned = false;
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding:
              EdgeInsets.symmetric(horizontal: insetH, vertical: insetV),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: maxWidth,
              maxHeight: maxHeight,
            ),
            child: _detailGlassPanel(
              enableBlur: false,
              showBorder: false,
              gradient: gradient,
              radius: radius,
              padding: EdgeInsets.all(padding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  SizedBox(height: (10 * uiScale).clamp(8.0, 14.0)),
                  Divider(
                    height: 1,
                    color: Colors.white.withValues(alpha: 0.18),
                  ),
                  SizedBox(height: (10 * uiScale).clamp(8.0, 14.0)),
                  Expanded(
                    child: ListView.separated(
                      itemCount: options.length,
                      separatorBuilder: (_, __) => SizedBox(
                        height: (10 * uiScale).clamp(8.0, 14.0),
                      ),
                      itemBuilder: (context, index) {
                        final opt = options[index];
                        final shouldAutofocus =
                            !autofocusAssigned && (opt.selected || index == 0);
                        if (shouldAutofocus) autofocusAssigned = true;

                        return TvFocusable(
                          autofocus: shouldAutofocus,
                          onPressed: () => Navigator.of(ctx).pop<T>(opt.value),
                          borderRadius: BorderRadius.circular(
                            (16 * uiScale).clamp(12.0, 20.0),
                          ),
                          surfaceColor: Colors.black.withValues(alpha: 0.28),
                          focusedSurfaceColor: scheme.primary.withValues(
                            alpha: isDark ? 0.20 : 0.16,
                          ),
                          padding: EdgeInsets.symmetric(
                            horizontal: (14 * uiScale).clamp(10.0, 18.0),
                            vertical: (12 * uiScale).clamp(10.0, 16.0),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                opt.selected
                                    ? Icons.check_circle
                                    : Icons.circle_outlined,
                                color: opt.selected
                                    ? scheme.primary
                                    : Colors.white70,
                              ),
                              SizedBox(width: (12 * uiScale).clamp(10.0, 16.0)),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      opt.label,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style:
                                          theme.textTheme.titleSmall?.copyWith(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    if ((opt.subtitle ?? '').trim().isNotEmpty)
                                      Padding(
                                        padding: EdgeInsets.only(
                                          top: (4 * uiScale).clamp(2.0, 6.0),
                                        ),
                                        child: Text(
                                          opt.subtitle!,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                            color: Colors.white70,
                                            height: 1.25,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
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

  Future<void> _pickMediaSourceTv(
    BuildContext context,
    PlaybackInfoResult info,
  ) async {
    final sources = info.mediaSources.cast<Map<String, dynamic>>();
    if (sources.isEmpty) return;

    final sortedSources = List<Map<String, dynamic>>.from(sources)
      ..sort(_ShowDetailPageState._compareMediaSourcesByQuality);

    final options = sortedSources
        .map((ms) {
          final id = (ms['Id']?.toString() ?? '').trim();
          if (id.isEmpty) return null;
          return (
            value: id,
            label: _ShowDetailPageState._mediaSourceTitle(ms),
            subtitle: _mediaSourceSubtitle(ms),
            selected: id == _selectedMediaSourceId,
          );
        })
        .whereType<
            ({String value, String label, String? subtitle, bool selected})>()
        .toList();

    final selected = await _showTvPicker<String>(
      context,
      title: '视频版本',
      options: options,
    );

    if (!mounted) return;
    if (selected == null ||
        selected.isEmpty ||
        selected == _selectedMediaSourceId) {
      return;
    }

    setState(() {
      _selectedMediaSourceId = selected;
      _selectedAudioStreamIndex = null;
      _selectedSubtitleStreamIndex = null;
    });

    final serverId = widget.server?.id ?? widget.appState.activeServerId;
    final sid = (_seriesId ?? '').trim();
    if (serverId == null || serverId.trim().isEmpty || sid.isEmpty) return;
    final idx = sources
        .indexWhere((ms) => (ms['Id']?.toString() ?? '').trim() == selected);
    if (idx < 0) return;
    unawaited(
      widget.appState.setSeriesMediaSourceIndex(
        serverId: serverId.trim(),
        seriesId: sid,
        mediaSourceIndex: idx,
      ),
    );
  }

  Future<void> _pickAudioStreamTv(
    BuildContext context,
    Map<String, dynamic> ms,
  ) async {
    final audioStreams = _ShowDetailPageState._streamsOfType(ms, 'Audio');
    if (audioStreams.isEmpty) return;

    final def = _ShowDetailPageState._defaultStream(audioStreams);
    final defIndex = _ShowDetailPageState._asInt(def?['Index']);

    final options =
        <({int value, String label, String? subtitle, bool selected})>[
      (
        value: _kTvPickerDefault,
        label: '默认',
        subtitle: defIndex == null ? null : '默认音轨',
        selected: _selectedAudioStreamIndex == null,
      ),
      ...audioStreams.map((s) {
        final idx = _ShowDetailPageState._asInt(s['Index']);
        if (idx == null) return null;
        final selectedNow = idx == _selectedAudioStreamIndex;
        final title = _ShowDetailPageState._streamLabel(s, includeCodec: false);
        final codec = (s['Codec'] as String?)?.trim();
        return (
          value: idx,
          label: idx == defIndex ? '$title (默认)' : title,
          subtitle: codec?.isEmpty == true ? null : codec,
          selected: selectedNow,
        );
      }).whereType<
          ({int value, String label, String? subtitle, bool selected})>(),
    ];

    final selected = await _showTvPicker<int>(
      context,
      title: '音轨选择',
      options: options,
    );

    if (!mounted) return;
    if (selected == null) return;
    final effective = selected == _kTvPickerDefault ? null : selected;
    setState(() => _selectedAudioStreamIndex = effective);

    final serverId = widget.server?.id ?? widget.appState.activeServerId;
    final sid = (_seriesId ?? '').trim();
    if (serverId == null || serverId.trim().isEmpty || sid.isEmpty) return;
    unawaited(
      widget.appState.setSeriesAudioStreamIndex(
        serverId: serverId.trim(),
        seriesId: sid,
        audioStreamIndex: effective,
      ),
    );
  }

  Future<void> _pickSubtitleStreamTv(
    BuildContext context,
    Map<String, dynamic> ms,
  ) async {
    final subtitleStreams = _ShowDetailPageState._streamsOfType(ms, 'Subtitle');
    if (subtitleStreams.isEmpty) return;

    final def = _ShowDetailPageState._defaultStream(subtitleStreams);
    final defIndex = _ShowDetailPageState._asInt(def?['Index']);

    final options =
        <({int value, String label, String? subtitle, bool selected})>[
      (
        value: -1,
        label: '关闭',
        subtitle: null,
        selected: _selectedSubtitleStreamIndex == -1,
      ),
      (
        value: _kTvPickerDefault,
        label: '默认',
        subtitle: defIndex == null ? null : '默认字幕',
        selected: _selectedSubtitleStreamIndex == null,
      ),
      ...subtitleStreams.map((s) {
        final idx = _ShowDetailPageState._asInt(s['Index']);
        if (idx == null) return null;
        final selectedNow = idx == _selectedSubtitleStreamIndex;
        final title = _ShowDetailPageState._streamLabel(s, includeCodec: false);
        final codec = (s['Codec'] as String?)?.trim();
        return (
          value: idx,
          label: idx == defIndex ? '$title (默认)' : title,
          subtitle: codec?.isEmpty == true ? null : codec,
          selected: selectedNow,
        );
      }).whereType<
          ({int value, String label, String? subtitle, bool selected})>(),
    ];

    final selected = await _showTvPicker<int>(
      context,
      title: '字幕选择',
      options: options,
    );

    if (!mounted) return;
    if (selected == null) return;
    final effective = selected == _kTvPickerDefault ? null : selected;
    setState(() => _selectedSubtitleStreamIndex = effective);

    final serverId = widget.server?.id ?? widget.appState.activeServerId;
    final sid = (_seriesId ?? '').trim();
    if (serverId == null || serverId.trim().isEmpty || sid.isEmpty) return;
    unawaited(
      widget.appState.setSeriesSubtitleStreamIndex(
        serverId: serverId.trim(),
        seriesId: sid,
        subtitleStreamIndex: effective,
      ),
    );
  }

  Widget _buildTvEpisodeDetailPage(
    BuildContext context, {
    required MediaItem ep,
    required ServerAccess? access,
    required String playLabel,
    required bool played,
    required bool hasResume,
    required int ticks,
    required Duration? runtime,
    required String dateText,
    required String backdropUrl,
    required String coverUrl,
    required String seriesTitle,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = scheme.brightness == Brightness.dark;
    final uiScale = context.uiScale;

    String fmtRuntime(Duration? d) {
      if (d == null) return '';
      final h = d.inHours;
      final m = d.inMinutes.remainder(60);
      if (h > 0) return '${h}h ${m}m';
      return '${d.inMinutes}m';
    }

    final mark = _episodeMark(ep);
    final runtimeText = fmtRuntime(runtime);
    final dateLine = dateText.isEmpty ? '' : '播出日期：$dateText';

    final canSwitchCore =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    final coreLabel = '内核：${widget.appState.playerCore.label}';

    final posterWidth = (320 * uiScale).clamp(220.0, 420.0);
    final posterRadius = (20 * uiScale).clamp(14.0, 26.0);
    final contentPadding = EdgeInsets.fromLTRB(
      (32 * uiScale).clamp(18.0, 44.0),
      (22 * uiScale).clamp(14.0, 32.0),
      (32 * uiScale).clamp(18.0, 44.0),
      (30 * uiScale).clamp(18.0, 44.0),
    );

    final buttonHeight = (52 * uiScale).clamp(44.0, 62.0);
    final buttonPaddingH = (16 * uiScale).clamp(12.0, 18.0);
    final buttonIconSize = (22 * uiScale).clamp(18.0, 26.0);
    final buttonGap = (14 * uiScale).clamp(10.0, 18.0);

    Widget pillButton({
      required IconData icon,
      required String label,
      required VoidCallback? onPressed,
      bool autofocus = false,
      bool primary = false,
    }) {
      final fg = Colors.white;
      final surface = primary
          ? const Color(0xFF1F9F75).withValues(alpha: 0.86)
          : Colors.black.withValues(alpha: 0.30);
      final focusedSurface = primary
          ? const Color(0xFF1F9F75).withValues(alpha: 0.96)
          : scheme.primary.withValues(alpha: isDark ? 0.20 : 0.16);
      return TvFocusable(
        autofocus: autofocus,
        enabled: onPressed != null,
        onPressed: onPressed,
        borderRadius: BorderRadius.circular(999),
        surfaceColor: surface,
        focusedSurfaceColor: focusedSurface,
        padding: EdgeInsets.zero,
        child: SizedBox(
          height: buttonHeight,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: buttonPaddingH),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: buttonIconSize, color: fg),
                SizedBox(width: (10 * uiScale).clamp(8.0, 14.0)),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: fg,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    Widget menuButton({
      required IconData icon,
      required String label,
      required VoidCallback? onPressed,
    }) {
      final fg = Colors.white;
      final surface = Colors.black.withValues(alpha: 0.26);
      final focusedSurface =
          scheme.primary.withValues(alpha: isDark ? 0.18 : 0.14);
      final radius = (18 * uiScale).clamp(14.0, 22.0);
      return TvFocusable(
        enabled: onPressed != null,
        onPressed: onPressed,
        borderRadius: BorderRadius.circular(radius),
        surfaceColor: surface,
        focusedSurfaceColor: focusedSurface,
        padding: EdgeInsets.zero,
        child: SizedBox(
          height: buttonHeight,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: buttonPaddingH),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: buttonIconSize, color: fg),
                SizedBox(width: (10 * uiScale).clamp(8.0, 14.0)),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: fg,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    Widget markLine() {
      if (mark.isEmpty && runtimeText.isEmpty) return const SizedBox.shrink();
      return Row(
        children: [
          if (mark.isNotEmpty)
            Text(
              mark,
              style: theme.textTheme.labelLarge?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w900,
              ),
            ),
          if (mark.isNotEmpty && runtimeText.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text(
                '·',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: Colors.white70,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          if (runtimeText.isNotEmpty)
            Text(
              runtimeText,
              style: theme.textTheme.labelLarge?.copyWith(
                color: Colors.white70,
                fontWeight: FontWeight.w700,
              ),
            ),
        ],
      );
    }

    Widget background = backdropUrl.isEmpty
        ? const ColoredBox(color: Colors.black26)
        : LinNetworkImage(
            imageUrl: backdropUrl,
            fit: BoxFit.cover,
            errorWidget: const ColoredBox(color: Colors.black26),
          );

    final scrim = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        Colors.black.withValues(alpha: 0.82),
        Colors.black.withValues(alpha: 0.60),
        Colors.black.withValues(alpha: 0.78),
      ],
    );

    final playInfo = _playInfo;
    final currentMs = _currentMediaSource();

    String posterUrl = coverUrl;
    final sid = (_seriesId ?? ep.seriesId ?? '').trim();
    if (access != null && sid.isNotEmpty) {
      final seriesPosterUrl = access.adapter.imageUrl(
        access.auth,
        itemId: sid,
        imageType: 'Primary',
        maxWidth: 520,
      );
      if (seriesPosterUrl.trim().isNotEmpty) {
        posterUrl = seriesPosterUrl;
      }
    }

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(child: background),
          Positioned.fill(
            child: DecoratedBox(decoration: BoxDecoration(gradient: scrim)),
          ),
          SafeArea(
            child: FocusTraversalGroup(
              policy: ReadingOrderTraversalPolicy(),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1600),
                  child: ListView(
                    padding: contentPadding,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: posterWidth,
                            child: AspectRatio(
                              aspectRatio: 2 / 3,
                              child: ClipRRect(
                                borderRadius:
                                    BorderRadius.circular(posterRadius),
                                child: posterUrl.isEmpty
                                    ? const ColoredBox(
                                        color: Colors.black26,
                                        child: Center(
                                          child: Icon(Icons.image),
                                        ),
                                      )
                                    : LinNetworkImage(
                                        imageUrl: posterUrl,
                                        fit: BoxFit.cover,
                                        errorWidget: const ColoredBox(
                                          color: Colors.black26,
                                        ),
                                      ),
                              ),
                            ),
                          ),
                          SizedBox(width: (26 * uiScale).clamp(18.0, 34.0)),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  seriesTitle,
                                  style:
                                      theme.textTheme.headlineSmall?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w900,
                                    height: 1.08,
                                  ),
                                ),
                                SizedBox(
                                    height: (10 * uiScale).clamp(8.0, 14.0)),
                                Text(
                                  ep.name.trim().isNotEmpty
                                      ? ep.name.trim()
                                      : '第${ep.episodeNumber ?? 1}集',
                                  style: theme.textTheme.titleLarge?.copyWith(
                                    color: Colors.white.withValues(alpha: 0.96),
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                SizedBox(
                                    height: (10 * uiScale).clamp(8.0, 14.0)),
                                markLine(),
                                if (dateLine.isNotEmpty) ...[
                                  SizedBox(
                                      height: (8 * uiScale).clamp(6.0, 12.0)),
                                  Text(
                                    dateLine,
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: Colors.white70,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                                SizedBox(
                                    height: (16 * uiScale).clamp(12.0, 22.0)),
                                Wrap(
                                  spacing: buttonGap,
                                  runSpacing: buttonGap,
                                  children: [
                                    pillButton(
                                      icon: Icons.play_arrow_rounded,
                                      label: playLabel,
                                      onPressed: () => _playCurrentEpisode(
                                        startPosition: hasResume
                                            ? _ticksToDuration(ticks)
                                            : null,
                                      ),
                                      autofocus: true,
                                      primary: true,
                                    ),
                                    pillButton(
                                      icon: played
                                          ? Icons.visibility_off_outlined
                                          : Icons.check_circle_outline_rounded,
                                      label: played ? '标记未播放' : '标记已播放',
                                      onPressed: _markBusy
                                          ? null
                                          : _toggleEpisodePlayedMark,
                                    ),
                                    pillButton(
                                      icon: _localFavorite
                                          ? Icons.favorite_rounded
                                          : Icons.favorite_border_rounded,
                                      label: _localFavorite ? '已收藏' : '收藏',
                                      onPressed: _favoriteLoaded
                                          ? _toggleLocalFavorite
                                          : null,
                                    ),
                                    pillButton(
                                      icon: Icons.format_list_numbered_rounded,
                                      label: '选集',
                                      onPressed: () => _pickEpisode(context),
                                    ),
                                    pillButton(
                                      icon: Icons.memory_rounded,
                                      label: coreLabel,
                                      onPressed: canSwitchCore
                                          ? _togglePlayerCore
                                          : null,
                                    ),
                                  ],
                                ),
                                PluginSlotArea(
                                  appState: widget.appState,
                                  slotId: 'detail.hero.actions',
                                  axis: Axis.horizontal,
                                  gap: buttonGap,
                                  params: _buildDetailPluginParams(
                                    _detail ?? _episode,
                                  ),
                                ),
                                if (playInfo != null) ...[
                                  SizedBox(
                                      height: (14 * uiScale).clamp(10.0, 18.0)),
                                  Wrap(
                                    spacing: buttonGap,
                                    runSpacing: buttonGap,
                                    children: [
                                      menuButton(
                                        icon: Icons.movie_filter_rounded,
                                        label: currentMs == null
                                            ? '视频'
                                            : '视频：${_currentVideoText()}',
                                        onPressed: () => unawaited(
                                          _pickMediaSourceTv(context, playInfo),
                                        ),
                                      ),
                                      menuButton(
                                        icon: Icons.audiotrack_rounded,
                                        label: currentMs == null
                                            ? '音频'
                                            : '音频：${_currentAudioText()}',
                                        onPressed: currentMs == null
                                            ? null
                                            : () => unawaited(
                                                  _pickAudioStreamTv(
                                                      context, currentMs),
                                                ),
                                      ),
                                      menuButton(
                                        icon: Icons.closed_caption_rounded,
                                        label: currentMs == null
                                            ? '字幕'
                                            : '字幕：${_currentSubtitleText()}',
                                        onPressed: currentMs == null
                                            ? null
                                            : () => unawaited(
                                                  _pickSubtitleStreamTv(
                                                      context, currentMs),
                                                ),
                                      ),
                                    ],
                                  ),
                                ],
                                if ((_detail?.overview ?? '')
                                    .trim()
                                    .isNotEmpty) ...[
                                  SizedBox(
                                      height: (14 * uiScale).clamp(10.0, 18.0)),
                                  Text(
                                    _detail!.overview,
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color:
                                          Colors.white.withValues(alpha: 0.88),
                                      height: 1.45,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: (22 * uiScale).clamp(16.0, 30.0)),
                      if ((_seriesId ?? '').trim().isNotEmpty) ...[
                        _otherEpisodesSection(context),
                        SizedBox(height: (18 * uiScale).clamp(14.0, 26.0)),
                      ],
                      if (_detail?.people.isNotEmpty == true &&
                          access != null) ...[
                        SizedBox(height: (18 * uiScale).clamp(14.0, 26.0)),
                        _castSection(
                          context,
                          _detail!.people,
                          access: access,
                        ),
                      ],
                      if (_chapters.isNotEmpty) ...[
                        SizedBox(height: (18 * uiScale).clamp(14.0, 26.0)),
                        _sectionTitle(context, '章节'),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _chapters
                              .map((c) => Chip(
                                  label: Text('${c.name} ${_fmt(c.start)}')))
                              .toList(),
                        ),
                      ],
                      if (playInfo != null) ...[
                        SizedBox(height: (18 * uiScale).clamp(14.0, 26.0)),
                        _tvMediaSourceInfoSection(
                          context,
                          item: ep,
                          playInfo: playInfo,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tvMediaSourceInfoSection(
    BuildContext context, {
    required MediaItem item,
    required PlaybackInfoResult playInfo,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = scheme.brightness == Brightness.dark;
    final uiScale = context.uiScale;

    if (playInfo.mediaSources.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(context, '媒体源信息'),
          SizedBox(height: (10 * uiScale).clamp(8.0, 14.0)),
          Text(
            '暂无媒体源信息',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: Colors.white70,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      );
    }

    final ms = _ShowDetailPageState._findMediaSource(
          playInfo,
          _selectedMediaSourceId,
        ) ??
        (playInfo.mediaSources.first as Map<String, dynamic>);

    final streams = (ms['MediaStreams'] as List?) ?? const [];
    final videos = streams
        .where((e) => (e as Map)['Type'] == 'Video')
        .map((e) => e as Map<String, dynamic>)
        .toList();
    final audios = streams
        .where((e) => (e as Map)['Type'] == 'Audio')
        .map((e) => e as Map<String, dynamic>)
        .toList();
    final subs = streams
        .where((e) => (e as Map)['Type'] == 'Subtitle')
        .map((e) => e as Map<String, dynamic>)
        .toList();

    String fmtSize(dynamic raw) {
      final bytes = raw is num ? raw.toInt() : int.tryParse('$raw');
      if (bytes == null || bytes <= 0) return '';
      const kb = 1024;
      const mb = kb * 1024;
      const gb = mb * 1024;
      if (bytes >= gb) return '${(bytes / gb).toStringAsFixed(1)} GB';
      if (bytes >= mb) return '${(bytes / mb).toStringAsFixed(0)} MB';
      if (bytes >= kb) return '${(bytes / kb).toStringAsFixed(0)} KB';
      return '$bytes B';
    }

    String yn(dynamic v) => v == true ? '是' : '否';

    String? fmtAdded(dynamic raw) {
      final text = raw == null ? '' : raw.toString().trim();
      if (text.isEmpty) return null;
      final parsed = DateTime.tryParse(text);
      if (parsed == null) return null;
      final local = parsed.toLocal();
      final hh = local.hour.toString().padLeft(2, '0');
      final mm = local.minute.toString().padLeft(2, '0');
      return '${local.year}/${local.month}/${local.day} $hh:$mm';
    }

    String fmtMbps(int? bitrate) {
      if (bitrate == null || bitrate <= 0) return '';
      return '${(bitrate / 1000000).toStringAsFixed(1)} Mbps';
    }

    String fmtKbps(int? bitrate) {
      if (bitrate == null || bitrate <= 0) return '';
      return '${(bitrate / 1000).toStringAsFixed(0)} Kbps';
    }

    List<({String k, String v})> videoLines(Map<String, dynamic> v) {
      final out = <({String k, String v})>[];
      final title = (v['DisplayTitle'] ?? '').toString().trim();
      final innerTitle = (v['Title'] ?? '').toString().trim();
      final codec = (v['Codec'] ?? '').toString().trim();
      final profile = (v['Profile'] ?? '').toString().trim();
      final level = _ShowDetailPageState._asInt(v['Level']);
      final width = _ShowDetailPageState._asInt(v['Width']);
      final height = _ShowDetailPageState._asInt(v['Height']);
      final aspect = _formatVideoAspectRatio(v);
      final interlaced = v['IsInterlaced'] == true;
      final fr = v['RealFrameRate'] ?? v['AverageFrameRate'];
      final bitrate = _ShowDetailPageState._asInt(v['BitRate']);
      final primaries = (v['ColorPrimaries'] ?? '').toString().trim();
      final colorSpace = (v['ColorSpace'] ?? '').toString().trim();
      final transfer = (v['ColorTransfer'] ?? '').toString().trim();
      final bitDepth = _ShowDetailPageState._asInt(v['BitDepth']);
      final pixelFormat = (v['PixelFormat'] ?? '').toString().trim();
      final refFrames = _ShowDetailPageState._asInt(v['RefFrames']);

      if (title.isNotEmpty) out.add((k: '标题名称', v: title));
      if (innerTitle.isNotEmpty && innerTitle != title) {
        out.add((k: '内嵌标题', v: innerTitle));
      }
      if (codec.isNotEmpty) out.add((k: '编码格式', v: codec.toUpperCase()));
      if (profile.isNotEmpty) out.add((k: '编码规格', v: profile));
      if (level != null && level > 0) out.add((k: '编码级别', v: '$level'));
      if (width != null && height != null) {
        out.add((k: '源分辨率', v: '${width}x$height'));
      }
      if (aspect != null) out.add((k: '视频比例', v: aspect));
      out.add((k: '隔行扫描', v: yn(interlaced)));
      if (fr != null) out.add((k: '帧速率', v: fr.toString()));
      final bitrateText = fmtMbps(bitrate);
      if (bitrateText.isNotEmpty) out.add((k: '比特率', v: bitrateText));
      if (primaries.isNotEmpty) out.add((k: '原始色域', v: primaries));
      if (colorSpace.isNotEmpty) out.add((k: '色彩空间', v: colorSpace));
      if (transfer.isNotEmpty) out.add((k: '色彩转换', v: transfer));
      if (bitDepth != null && bitDepth > 0) {
        out.add((k: '比特位深', v: '$bitDepth Bit'));
      }
      if (pixelFormat.isNotEmpty) out.add((k: '像素格式', v: pixelFormat));
      if (refFrames != null && refFrames > 0) {
        out.add((k: '参考帧', v: '$refFrames'));
      }
      out.add((k: '默认', v: yn(v['IsDefault'])));
      return out;
    }

    List<({String k, String v})> audioLines(Map<String, dynamic> a) {
      final out = <({String k, String v})>[];
      final title = (a['DisplayTitle'] ?? '').toString().trim();
      final innerTitle = (a['Title'] ?? '').toString().trim();
      final lang = (a['Language'] ?? '').toString().trim();
      final codec = (a['Codec'] ?? '').toString().trim();
      final profile = (a['Profile'] ?? '').toString().trim();
      final channels = _ShowDetailPageState._asInt(a['Channels']);
      final layout = (a['ChannelLayout'] ?? '').toString().trim();
      final bitrate = _ShowDetailPageState._asInt(a['BitRate']);
      final sample = _ShowDetailPageState._asInt(a['SampleRate']);

      if (title.isNotEmpty) out.add((k: '标题名称', v: title));
      if (innerTitle.isNotEmpty && innerTitle != title) {
        out.add((k: '内嵌标题', v: innerTitle));
      }
      if (lang.isNotEmpty) out.add((k: '语言种类', v: lang));
      if (codec.isNotEmpty) out.add((k: '编码格式', v: codec.toUpperCase()));
      if (profile.isNotEmpty) out.add((k: '编码规格', v: profile));
      if (layout.isNotEmpty) out.add((k: '音效布局', v: layout));
      if (channels != null) out.add((k: '音频声道', v: '$channels ch'));
      final bitrateText = fmtKbps(bitrate);
      if (bitrateText.isNotEmpty) out.add((k: '比特率', v: bitrateText));
      if (sample != null && sample > 0) out.add((k: '采样率', v: '$sample Hz'));
      out.add((k: '默认', v: yn(a['IsDefault'])));
      return out;
    }

    List<({String k, String v})> subLines(Map<String, dynamic> s) {
      final out = <({String k, String v})>[];
      final title =
          (s['DisplayTitle'] ?? s['Language'] ?? '').toString().trim();
      final innerTitle = (s['Title'] ?? '').toString().trim();
      final lang = (s['Language'] ?? '').toString().trim();
      final codec = (s['Codec'] ?? '').toString().trim();
      if (title.isNotEmpty) out.add((k: '标题名称', v: title));
      if (innerTitle.isNotEmpty && innerTitle != title) {
        out.add((k: '内嵌标题', v: innerTitle));
      }
      if (lang.isNotEmpty) out.add((k: '语言种类', v: lang));
      if (codec.isNotEmpty) out.add((k: '编码格式', v: codec.toUpperCase()));
      out.add((k: '默认', v: yn(s['IsDefault'])));
      out.add((k: '强制', v: yn(s['IsForced'])));
      out.add((k: '外部', v: yn(s['IsExternal'])));
      return out;
    }

    Widget infoCard({
      required IconData icon,
      required String title,
      required List<({String k, String v})> lines,
    }) {
      final cardWidth = (360 * uiScale).clamp(280.0, 520.0);
      final radius = (18 * uiScale).clamp(14.0, 22.0);
      final iconSize = (22 * uiScale).clamp(18.0, 26.0);
      final labelWidth = (96 * uiScale).clamp(84.0, 124.0);

      return SizedBox(
        width: cardWidth,
        child: TvFocusable(
          borderRadius: BorderRadius.circular(radius),
          surfaceColor: Colors.black.withValues(alpha: 0.22),
          focusedSurfaceColor:
              scheme.primary.withValues(alpha: isDark ? 0.18 : 0.14),
          padding: EdgeInsets.all((14 * uiScale).clamp(10.0, 18.0)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, color: Colors.white, size: iconSize),
                  const SizedBox(width: 10),
                  Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              SizedBox(height: (10 * uiScale).clamp(8.0, 14.0)),
              ...lines.take(18).map(
                    (e) => Padding(
                      padding: EdgeInsets.only(
                        bottom: (6 * uiScale).clamp(4.0, 8.0),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: labelWidth,
                            child: Text(
                              e.k,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: Colors.white70,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              e.v,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
            ],
          ),
        ),
      );
    }

    final container = (ms['Container'] ?? item.container ?? ms['Name'] ?? '')
        .toString()
        .trim()
        .toUpperCase();
    final sizeText = fmtSize(ms['Size'] ?? item.sizeBytes);
    final addedTime = fmtAdded(
      ms['DateCreated'] ??
          ms['DateAdded'] ??
          ms['DateCreatedUtc'] ??
          ms['DateModified'],
    );
    final headerParts = <String>[
      container.isEmpty ? '媒体源' : container,
      if (sizeText.isNotEmpty) sizeText,
      addedTime == null ? '添加时间未知' : '媒体于 $addedTime 添加',
    ];
    final header = headerParts.join('  ');

    final streamCards = <Widget>[
      ...videos.asMap().entries.map(
            (entry) => infoCard(
              icon: Icons.videocam_rounded,
              title: videos.length > 1 ? '视频 ${entry.key + 1}' : '视频',
              lines: videoLines(entry.value),
            ),
          ),
      ...audios.asMap().entries.map(
            (entry) => infoCard(
              icon: Icons.music_note_rounded,
              title: audios.length > 1 ? '音频 ${entry.key + 1}' : '音频',
              lines: audioLines(entry.value),
            ),
          ),
      ...subs.asMap().entries.map(
            (entry) => infoCard(
              icon: Icons.closed_caption_rounded,
              title: subs.length > 1 ? '字幕 ${entry.key + 1}' : '字幕',
              lines: subLines(entry.value),
            ),
          ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(context, '媒体源信息'),
        SizedBox(height: (10 * uiScale).clamp(8.0, 14.0)),
        Text(
          header,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleSmall?.copyWith(
            color: Colors.white70,
            fontWeight: FontWeight.w800,
          ),
        ),
        SizedBox(height: (12 * uiScale).clamp(10.0, 18.0)),
        if (streamCards.isEmpty)
          Text(
            '暂无流信息',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: Colors.white70,
              fontWeight: FontWeight.w600,
            ),
          )
        else
          SizedBox(
            height: (440 * uiScale).clamp(320.0, 620.0),
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: streamCards.length,
              separatorBuilder: (_, __) =>
                  SizedBox(width: (14 * uiScale).clamp(10.0, 18.0)),
              itemBuilder: (context, index) => streamCards[index],
            ),
          ),
      ],
    );
  }

  String _episodeDisplayTitle(MediaItem ep) {
    final episodeNo = ep.episodeNumber ?? 1;
    final name = ep.name.trim();
    return name.isNotEmpty ? '第$episodeNo集 $name' : '第$episodeNo集';
  }

  String _episodeRuntimeText(Duration? runtime) {
    if (runtime == null) return '';
    final hours = runtime.inHours;
    final minutes = runtime.inMinutes.remainder(60);
    if (hours > 0) {
      return minutes > 0 ? '$hours小时$minutes分' : '$hours小时';
    }
    if (runtime.inMinutes > 0) return '${runtime.inMinutes}分钟';
    return '${runtime.inSeconds}秒';
  }

  Future<void> _showEpisodeMoreSheet(
    BuildContext context, {
    required bool played,
  }) async {
    final season = _selectedSeason;
    final canSwitchCore =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    final current = _detail ?? _episode;
    final currentSeriesTitle = _seriesName.trim().isNotEmpty
        ? _seriesName.trim()
        : current.seriesName.trim();

    final action = await showModalBottomSheet<_EpisodeMoreAction>(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text(_episodeDisplayTitle(current)),
                subtitle: currentSeriesTitle.isEmpty
                    ? null
                    : Text(currentSeriesTitle),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.format_list_numbered_rounded),
                title: const Text('选集'),
                onTap: season == null
                    ? null
                    : () => Navigator.of(sheetContext)
                        .pop(_EpisodeMoreAction.pickEpisode),
              ),
              ListTile(
                leading: const Icon(Icons.layers_outlined),
                title: const Text('切换季'),
                onTap: _seasons.isEmpty
                    ? null
                    : () => Navigator.of(sheetContext)
                        .pop(_EpisodeMoreAction.pickSeason),
              ),
              ListTile(
                leading: const Icon(Icons.grid_view_rounded),
                title: const Text('查看本季全部'),
                onTap: season == null
                    ? null
                    : () => Navigator.of(sheetContext)
                        .pop(_EpisodeMoreAction.openSeasonEpisodes),
              ),
              ListTile(
                leading: Icon(
                  played
                      ? Icons.visibility_off_outlined
                      : Icons.check_circle_outline_rounded,
                ),
                title: Text(played ? '标记为未播放' : '标记为已播放'),
                onTap: _markBusy
                    ? null
                    : () => Navigator.of(sheetContext)
                        .pop(_EpisodeMoreAction.togglePlayed),
              ),
              ListTile(
                leading: Icon(
                  _localFavorite
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                ),
                title: Text(_localFavorite ? '取消本地收藏' : '加入本地收藏'),
                onTap: !_favoriteLoaded
                    ? null
                    : () => Navigator.of(sheetContext)
                        .pop(_EpisodeMoreAction.toggleFavorite),
              ),
              if (canSwitchCore)
                ListTile(
                  leading: const Icon(Icons.memory_rounded),
                  title: Text(
                    widget.appState.playerCore == PlayerCore.exo
                        ? '切换到 mpv'
                        : '切换到 ExoPlayer',
                  ),
                  onTap: () => Navigator.of(sheetContext)
                      .pop(_EpisodeMoreAction.togglePlayerCore),
                ),
            ],
          ),
        );
      },
    );

    if (!mounted || action == null) return;

    switch (action) {
      case _EpisodeMoreAction.pickEpisode:
        await _pickEpisode(this.context);
        break;
      case _EpisodeMoreAction.pickSeason:
        await _pickSeason(this.context);
        break;
      case _EpisodeMoreAction.openSeasonEpisodes:
        final currentSeason = _selectedSeason;
        if (currentSeason != null) {
          _openSeasonEpisodesPage(this.context, currentSeason);
        }
        break;
      case _EpisodeMoreAction.togglePlayed:
        if (!_markBusy) {
          await _toggleEpisodePlayedMark();
        }
        break;
      case _EpisodeMoreAction.toggleFavorite:
        if (_favoriteLoaded) {
          await _toggleLocalFavorite();
        }
        break;
      case _EpisodeMoreAction.togglePlayerCore:
        await _togglePlayerCore();
        break;
    }
  }

  Widget _buildMobileEpisodeDetailPage(
    BuildContext context, {
    required MediaItem ep,
    required ServerAccess? access,
    required String playLabel,
    required bool played,
    required bool hasResume,
    required int ticks,
    required Duration? runtime,
    required String backdropUrl,
    required String coverUrl,
    required bool enableBlur,
  }) {
    final playInfo = _playInfo;
    final currentMs = _currentMediaSource();
    final audioStreams = currentMs == null
        ? const <Map<String, dynamic>>[]
        : _ShowDetailPageState._streamsOfType(currentMs, 'Audio');
    final subtitleStreams = currentMs == null
        ? const <Map<String, dynamic>>[]
        : _ShowDetailPageState._streamsOfType(currentMs, 'Subtitle');

    final versionValue = playInfo == null
        ? '加载中'
        : (currentMs == null
            ? '暂无版本'
            : _ShowDetailPageState._mediaSourceTitle(currentMs));
    final audioText = _currentAudioText().trim();
    final subtitleText = _currentSubtitleText().trim();
    final mediaBadges = _episodeMediaBadges(
      ep,
      runtime: runtime,
      mediaSource: currentMs,
    );
    final audioValue =
        currentMs == null ? '默认' : (audioText.isEmpty ? '默认' : audioText);
    final subtitleValue = currentMs == null
        ? (_selectedSubtitleStreamIndex == -1 ? '关闭' : '默认')
        : (subtitleText.isEmpty ? '默认' : subtitleText);

    final sections = <Widget>[
      if (playInfo != null)
        _episodeMediaInfoSection(
          context,
          playInfo,
          selectedMediaSourceId: _selectedMediaSourceId,
        ),
      if (_detail?.people.isNotEmpty == true && access != null)
        _castSection(
          context,
          _detail!.people,
          access: access,
        ),
      if (_chapters.isNotEmpty)
        _detailGlassPanel(
          enableBlur: enableBlur,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
          radius: 22,
          showBorder: false,
          child: _chaptersSection(context, _chapters),
        ),
      PluginSlotArea(
        appState: widget.appState,
        slotId: 'detail.sections.bottom',
        params: _buildDetailPluginParams(_detail ?? _episode),
      ),
    ];

    return EpisodeDetailMobileView(
      title: _episodeDisplayTitle(ep),
      overview: (_detail?.overview ?? ep.overview).trim(),
      runtimeText: _episodeRuntimeText(runtime),
      mediaBadges: mediaBadges,
      coverUrl: coverUrl,
      backdropUrl: backdropUrl,
      versionValue: versionValue,
      audioValue: audioValue,
      subtitleValue: subtitleValue,
      playLabel: playLabel,
      onRefresh: _load,
      onPlay: () => _playCurrentEpisode(
        startPosition: hasResume ? _ticksToDuration(ticks) : null,
      ),
      onMore: () => _showEpisodeMoreSheet(context, played: played),
      onPickVersion:
          playInfo == null ? null : () => _pickMediaSource(context, playInfo),
      onPickAudio: audioStreams.isEmpty
          ? null
          : () => _pickAudioStream(context, currentMs!),
      onPickSubtitle: subtitleStreams.isEmpty
          ? null
          : () => _pickSubtitleStream(context, currentMs!),
      sections: sections,
    );
  }

  @override
  Widget build(BuildContext context) {
    final enableBlur = !widget.isTv && widget.appState.enableBlurEffects;
    final access = resolveServerAccess(
      appState: widget.appState,
      server: widget.server,
    );
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_error != null) {
      return Scaffold(
        body: SafeArea(
          child: Center(child: Text(_error!)),
        ),
      );
    }

    final ep = _detail ?? _episode;
    final played = _detail?.played ?? false;
    final ticks = _detail?.playbackPositionTicks ?? 0;
    final hasResume = ticks > 0 && !played;
    final playLabel = hasResume
        ? '继续播放（${_fmtClock(_ticksToDuration(ticks))}）'
        : (played ? '重播' : '播放');
    final runtime = ep.runTimeTicks != null
        ? Duration(microseconds: (ep.runTimeTicks! / 10).round())
        : null;
    final dateText = _episodeDateText(ep);
    final backdropUrl = access == null
        ? ''
        : access.adapter.imageUrl(
            access.auth,
            itemId: ep.id,
            imageType: 'Backdrop',
            maxWidth: 1600,
          );
    final thumbUrl = access == null
        ? ''
        : access.adapter.imageUrl(
            access.auth,
            itemId: ep.hasImage ? ep.id : (_selectedSeason?.id ?? ep.id),
            maxWidth: 900,
          );
    final seriesTitle = _seriesName.trim().isNotEmpty
        ? _seriesName.trim()
        : (ep.seriesName.trim().isNotEmpty ? ep.seriesName.trim() : ep.name);

    if (widget.isTv) {
      return _buildTvEpisodeDetailPage(
        context,
        ep: ep,
        access: access,
        playLabel: playLabel,
        played: played,
        hasResume: hasResume,
        ticks: ticks,
        runtime: runtime,
        dateText: dateText,
        backdropUrl: backdropUrl,
        coverUrl: thumbUrl,
        seriesTitle: seriesTitle,
      );
    }

    return _buildMobileEpisodeDetailPage(
      context,
      ep: ep,
      access: access,
      playLabel: playLabel,
      played: played,
      hasResume: hasResume,
      ticks: ticks,
      runtime: runtime,
      backdropUrl: backdropUrl,
      coverUrl: thumbUrl,
      enableBlur: enableBlur,
    );
  }

  Future<void> _loadSeriesEpisodes({
    required ServerAccess access,
    required MediaItem episodeDetail,
    required String seriesId,
    required String seriesName,
    required int loadSeq,
  }) async {
    try {
      final seasons =
          await access.adapter.fetchSeasons(access.auth, seriesId: seriesId);
      final seasonItems =
          seasons.items.where((s) => s.type.toLowerCase() == 'season').toList();
      seasonItems.sort((a, b) {
        final aNo = a.seasonNumber ?? a.episodeNumber ?? 0;
        final bNo = b.seasonNumber ?? b.episodeNumber ?? 0;
        return aNo.compareTo(bNo);
      });

      final seasonsVirtual = seasonItems.isEmpty;
      final seasonsForUi = seasonsVirtual
          ? [
              MediaItem(
                id: seriesId,
                name: '全部剧集',
                type: 'Season',
                overview: '',
                communityRating: null,
                premiereDate: null,
                genres: const [],
                runTimeTicks: null,
                sizeBytes: null,
                container: null,
                providerIds: const {},
                seriesId: seriesId,
                seriesName: seriesName,
                seasonName: '全部剧集',
                seasonNumber: null,
                episodeNumber: null,
                hasImage: episodeDetail.hasImage,
                playbackPositionTicks: 0,
                people: const [],
                parentId: seriesId,
              ),
            ]
          : seasonItems;

      final currentSeasonId =
          (episodeDetail.parentId ?? _episode.parentId ?? '').trim();
      final previousSeasonId = _selectedSeasonId;
      final selectedSeasonId = currentSeasonId.isNotEmpty &&
              seasonsForUi.any((s) => s.id == currentSeasonId)
          ? currentSeasonId
          : (previousSeasonId != null &&
                  seasonsForUi.any((s) => s.id == previousSeasonId))
              ? previousSeasonId
              : (seasonsForUi.isNotEmpty ? seasonsForUi.first.id : null);

      final episodesCacheForUi = <String, List<MediaItem>>{};
      if (selectedSeasonId != null && selectedSeasonId.isNotEmpty) {
        final eps = await access.adapter.fetchEpisodes(
          access.auth,
          seasonId: selectedSeasonId,
        );
        final items = List<MediaItem>.from(eps.items);
        items.sort((a, b) {
          final aNo = a.episodeNumber ?? 0;
          final bNo = b.episodeNumber ?? 0;
          return aNo.compareTo(bNo);
        });
        episodesCacheForUi[selectedSeasonId] = items;
      }

      final shouldPreload = widget.appState.preloadEnabled;
      if (shouldPreload &&
          selectedSeasonId != null &&
          selectedSeasonId.isNotEmpty) {
        final currentEpisodeId = episodeDetail.id.trim();
        final episodes =
            episodesCacheForUi[selectedSeasonId] ?? const <MediaItem>[];
        final idx = episodes.indexWhere((e) => e.id.trim() == currentEpisodeId);
        final nextEpisode =
            (idx >= 0 && idx + 1 < episodes.length) ? episodes[idx + 1] : null;
        if (nextEpisode != null) {
          unawaited(
            _preloadEpisodeBestEffort(
              access: access,
              itemId: nextEpisode.id,
              loadSeq: loadSeq,
              audioStreamIndex: _selectedAudioStreamIndex,
              subtitleStreamIndex: _selectedSubtitleStreamIndex,
            ),
          );
        } else if (!seasonsVirtual) {
          final seasonIdx =
              seasonsForUi.indexWhere((s) => s.id == selectedSeasonId);
          if (seasonIdx >= 0 && seasonIdx + 1 < seasonsForUi.length) {
            final nextSeasonId = seasonsForUi[seasonIdx + 1].id;
            unawaited(() async {
              try {
                if (!mounted || loadSeq != _loadSeq) return;
                final eps = await access.adapter.fetchEpisodes(
                  access.auth,
                  seasonId: nextSeasonId,
                );
                final items = List<MediaItem>.from(eps.items);
                items.sort((a, b) {
                  final aNo = a.episodeNumber ?? 0;
                  final bNo = b.episodeNumber ?? 0;
                  return aNo.compareTo(bNo);
                });
                final next = items.isNotEmpty ? items.first : null;
                if (next == null) return;
                await _preloadEpisodeBestEffort(
                  access: access,
                  itemId: next.id,
                  loadSeq: loadSeq,
                  audioStreamIndex: _selectedAudioStreamIndex,
                  subtitleStreamIndex: _selectedSubtitleStreamIndex,
                );
              } catch (_) {
                // Best-effort only.
              }
            }());
          }
        }
      }

      if (!mounted || loadSeq != _loadSeq) return;
      setState(() {
        _seasons = seasonsForUi;
        _seasonsVirtual = seasonsVirtual;
        _selectedSeasonId = selectedSeasonId;
        _episodesCache
          ..clear()
          ..addAll(episodesCacheForUi);
        _seriesError = null;
      });
      _persistEpisodeDetailCache();
    } catch (e) {
      if (!mounted || loadSeq != _loadSeq) return;
      setState(() {
        _seriesError = e.toString();
        _seasons = const [];
        _seasonsVirtual = false;
        _selectedSeasonId = null;
        _episodesCache.clear();
      });
    } finally {
      if (mounted && loadSeq == _loadSeq) {
        setState(() {
          _seriesLoading = false;
        });
      }
    }
  }

  String _seasonLabel(MediaItem season, int index) {
    final name = season.name.trim();
    final seasonNo = season.seasonNumber ?? season.episodeNumber;
    return seasonNo != null
        ? '第$seasonNo季'
        : (name.isNotEmpty ? name : '第${index + 1}季');
  }

  MediaItem? get _selectedSeason {
    if (_seasons.isEmpty) return null;
    final selectedId = _selectedSeasonId;
    if (selectedId == null || selectedId.isEmpty) return _seasons.first;
    for (final s in _seasons) {
      if (s.id == selectedId) return s;
    }
    return _seasons.first;
  }

  String _selectedSeasonLabel() {
    if (_seasons.isEmpty) return '选择季';
    final selectedId = _selectedSeasonId;
    for (int i = 0; i < _seasons.length; i++) {
      final s = _seasons[i];
      if (selectedId != null && s.id == selectedId) return _seasonLabel(s, i);
    }
    return _seasonLabel(_seasons.first, 0);
  }

  Future<List<MediaItem>> _episodesForSeason(MediaItem season) async {
    final cached = _episodesCache[season.id];
    if (cached != null) return cached;
    final access =
        resolveServerAccess(appState: widget.appState, server: widget.server);
    if (access == null) return const [];

    final eps = await access.adapter.fetchEpisodes(
      access.auth,
      seasonId: season.id,
    );
    final items = List<MediaItem>.from(eps.items);
    items.sort((a, b) {
      final aNo = a.episodeNumber ?? 0;
      final bNo = b.episodeNumber ?? 0;
      return aNo.compareTo(bNo);
    });
    _episodesCache[season.id] = items;
    _persistEpisodeDetailCache();
    return items;
  }

  Future<void> _pickSeason(BuildContext context) async {
    if (_seasons.isEmpty) return;

    final selected = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: ListView(
            children: [
              const ListTile(title: Text('季选择')),
              ..._seasons.asMap().entries.map((entry) {
                final idx = entry.key;
                final s = entry.value;
                final selectedNow = s.id == _selectedSeasonId;
                return ListTile(
                  leading: Icon(
                      selectedNow ? Icons.check_circle : Icons.circle_outlined),
                  title: Text(_seasonLabel(s, idx)),
                  onTap: () => Navigator.of(ctx).pop(s.id),
                );
              }),
            ],
          ),
        );
      },
    );

    if (!mounted) return;
    if (selected == null || selected.isEmpty || selected == _selectedSeasonId) {
      return;
    }

    setState(() {
      _selectedSeasonId = selected;
    });
    _persistEpisodeDetailCache();

    final season = _selectedSeason;
    if (season == null) return;
    try {
      await _episodesForSeason(season);
    } catch (_) {
      // Episode list is optional for the UI.
    }
  }

  String _episodeLabel(MediaItem episode, int index) {
    final epNo = episode.episodeNumber ?? (index + 1);
    final epName = episode.name.trim();
    return epName.isNotEmpty ? '$epNo. $epName' : '第$epNo集';
  }

  Future<void> _pickEpisode(BuildContext context) async {
    final season = _selectedSeason;
    if (season == null) return;

    final seasonLabel = _selectedSeasonLabel();
    final selectedEp = await showModalBottomSheet<MediaItem>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return SafeArea(
          child: DraggableScrollableSheet(
            expand: false,
            initialChildSize: widget.isTv ? 0.5 : 0.75,
            minChildSize: 0.4,
            maxChildSize: 0.95,
            builder: (ctx, controller) {
              return FutureBuilder<List<MediaItem>>(
                future: _episodesForSeason(season),
                builder: (ctx, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return ListView(
                      controller: controller,
                      children: const [
                        ListTile(title: Text('选集')),
                        SizedBox(height: 24),
                        Center(child: CircularProgressIndicator()),
                      ],
                    );
                  }
                  if (snapshot.hasError) {
                    return ListView(
                      controller: controller,
                      children: [
                        const ListTile(title: Text('选集')),
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text('加载失败：${snapshot.error}'),
                        ),
                      ],
                    );
                  }
                  final eps = snapshot.data ?? const [];
                  if (eps.isEmpty) {
                    return ListView(
                      controller: controller,
                      children: const [
                        ListTile(title: Text('选集')),
                        Padding(
                          padding: EdgeInsets.all(16),
                          child: Text('暂无剧集'),
                        ),
                      ],
                    );
                  }
                  return ListView.builder(
                    controller: controller,
                    itemCount: eps.length + 1,
                    itemBuilder: (ctx, idx) {
                      if (idx == 0) {
                        return ListTile(title: Text('选集（$seasonLabel）'));
                      }
                      final epIndex = idx - 1;
                      final ep = eps[epIndex];
                      final isCurrent = ep.id == _episode.id;
                      return ListTile(
                        leading: Icon(
                          isCurrent
                              ? Icons.check_circle
                              : Icons.play_circle_outline,
                        ),
                        title: Text(_episodeLabel(ep, epIndex)),
                        onTap: () => Navigator.of(ctx).pop(ep),
                      );
                    },
                  );
                },
              );
            },
          ),
        );
      },
    );

    if (!mounted ||
        !context.mounted ||
        selectedEp == null ||
        selectedEp.id.isEmpty) {
      return;
    }
    unawaited(_switchEpisode(selectedEp));
  }

  void _openSeasonEpisodesPage(BuildContext context, MediaItem season) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SeasonEpisodesPage(
          season: season,
          appState: widget.appState,
          server: widget.server,
          isTv: widget.isTv,
          isVirtual: _seasonsVirtual,
        ),
      ),
    );
  }

  Widget _otherEpisodesSection(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    final isDark = scheme.brightness == Brightness.dark;
    final uiScale = context.uiScale;
    final season = _selectedSeason;
    final seasonText = _selectedSeasonLabel();
    final epAccess =
        resolveServerAccess(appState: widget.appState, server: widget.server);

    Widget tvFocus(Widget child, {BorderRadius? borderRadius}) {
      if (!widget.isTv) return child;
      final radius = borderRadius ??
          BorderRadius.circular((18 * uiScale).clamp(14.0, 22.0));
      return TvFocusFrame(
        borderRadius: radius,
        surfaceColor: Colors.transparent,
        focusedSurfaceColor:
            scheme.primary.withValues(alpha: isDark ? 0.22 : 0.16),
        borderColor: Colors.transparent,
        focusedBorderColor: scheme.primary,
        padding: EdgeInsets.zero,
        focusScale: 1.04,
        child: child,
      );
    }

    final controlStyle = FilledButton.styleFrom(
      foregroundColor: Colors.white,
      backgroundColor: Colors.black.withValues(alpha: 0.28),
      side: BorderSide(color: Colors.white.withValues(alpha: 0.24)),
      textStyle: (textTheme.labelLarge ?? const TextStyle()).copyWith(
        fontWeight: FontWeight.w700,
      ),
    );
    final controls = Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        tvFocus(
          FilledButton.tonalIcon(
            style: controlStyle,
            onPressed: season == null
                ? null
                : () => _openSeasonEpisodesPage(context, season),
            icon: const Icon(Icons.grid_view_rounded, size: 16),
            label: const Text('查看全部'),
          ),
        ),
        tvFocus(
          FilledButton.tonalIcon(
            style: controlStyle,
            onPressed: _seasons.isEmpty ? null : () => _pickSeason(context),
            icon: const Icon(Icons.layers_outlined, size: 16),
            label: const Text('切换季'),
          ),
        ),
        tvFocus(
          FilledButton.tonalIcon(
            style: controlStyle,
            onPressed: season == null ? null : () => _pickEpisode(context),
            icon: const Icon(Icons.format_list_numbered, size: 16),
            label: const Text('选集'),
          ),
        ),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(context, '更多来自：$seasonText'),
        const SizedBox(height: 8),
        controls,
        if (_seriesError != null) ...[
          const SizedBox(height: 8),
          Text(
            '加载剧集失败：$_seriesError',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.error,
            ),
          ),
        ],
        const SizedBox(height: 8),
        if (season == null && _seriesLoading)
          const SizedBox(
            height: 180,
            child: Center(child: CircularProgressIndicator()),
          ),
        if (season != null)
          SizedBox(
            height: _DetailUiTokens.horizontalEpisodeStripHeight,
            child: FutureBuilder<List<MediaItem>>(
              future: _episodesForSeason(season),
              builder: (ctx, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      '加载剧集失败：${snapshot.error}',
                      style: const TextStyle(color: Colors.white70),
                    ),
                  );
                }
                final eps = snapshot.data ?? const [];
                if (eps.isEmpty) {
                  return const Center(
                    child: Text(
                      '暂无剧集',
                      style: TextStyle(color: Colors.white70),
                    ),
                  );
                }
                return _withHorizontalEdgeFade(
                  context,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: eps.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(width: _DetailUiTokens.horizontalGap),
                    itemBuilder: (context, index) {
                      final e = eps[index];
                      final isCurrent = e.id == _episode.id;
                      final epNo = e.episodeNumber ?? (index + 1);
                      final img = epAccess == null
                          ? ''
                          : epAccess.adapter.imageUrl(
                              epAccess.auth,
                              itemId: e.hasImage ? e.id : season.id,
                              maxWidth: 700,
                            );
                      final card = _HoverScale(
                        child: SizedBox(
                          width: _DetailUiTokens.horizontalEpisodeCardWidth,
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(
                                _DetailUiTokens.cardRadius,
                              ),
                              onTap: () {
                                if (isCurrent) return;
                                unawaited(_switchEpisode(e));
                              },
                              child: Ink(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(
                                    _DetailUiTokens.cardRadius,
                                  ),
                                  border: Border.all(
                                    color: isCurrent
                                        ? scheme.primary
                                        : Colors.white.withValues(alpha: 0.24),
                                    width: isCurrent ? 1.4 : 1.0,
                                  ),
                                ),
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(
                                        _DetailUiTokens.cardRadius,
                                      ),
                                      child: img.isEmpty
                                          ? const ColoredBox(
                                              color: Colors.black26)
                                          : LinNetworkImage(
                                              imageUrl: img,
                                              fit: BoxFit.cover,
                                              errorWidget: const ColoredBox(
                                                color: Colors.black26,
                                              ),
                                            ),
                                    ),
                                    Align(
                                      alignment: Alignment.bottomCenter,
                                      child: DecoratedBox(
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            begin: Alignment.topCenter,
                                            end: Alignment.bottomCenter,
                                            colors: [
                                              Colors.transparent,
                                              Colors.black
                                                  .withValues(alpha: 0.8),
                                            ],
                                          ),
                                        ),
                                        child: SizedBox(
                                          width: double.infinity,
                                          child: Padding(
                                            padding: const EdgeInsets.fromLTRB(
                                                10, 18, 10, 10),
                                            child: Text(
                                              '$epNo. ${e.name.trim().isNotEmpty ? e.name.trim() : '第$epNo集'}',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: theme.textTheme.bodyMedium
                                                  ?.copyWith(
                                                color: Colors.white,
                                                fontWeight: isCurrent
                                                    ? FontWeight.w700
                                                    : FontWeight.w500,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                      return tvFocus(
                        card,
                        borderRadius: BorderRadius.circular(
                          _DetailUiTokens.cardRadius,
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}

String _fmt(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  final s = d.inSeconds.remainder(60);
  if (h > 0) return '${h}h ${m}m ${s}s';
  return '${m}m ${s}s';
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

Widget _chaptersSection(BuildContext context, List<ChapterInfo> chapters) {
  final width = MediaQuery.of(context).size.width;
  final crossAxisCount = width >= 900 ? 4 : (width >= 600 ? 3 : 2);
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _sectionTitle(context, '章节'),
      const SizedBox(height: 8),
      GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 16 / 9,
        ),
        itemCount: chapters.length,
        itemBuilder: (context, index) {
          final c = chapters[index];
          return _detailGlassPanel(
            radius: 12,
            enableBlur: true,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  const Icon(Icons.menu_book, size: 28, color: Colors.white70),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          c.name.isNotEmpty ? c.name : 'Chapter ${index + 1}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _fmt(c.start),
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Colors.white70,
                                  ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    ],
  );
}

Widget _pill(BuildContext context, String text) {
  final theme = Theme.of(context);
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: 0.30),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: Colors.white.withValues(alpha: 0.24)),
    ),
    child: Text(
      text,
      style: theme.textTheme.labelMedium?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ) ??
          const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
    ),
  );
}

Widget _playButton(BuildContext context,
    {required String label, required VoidCallback onTap}) {
  final theme = Theme.of(context);
  const radius = 30.0;
  final bg = const Color(0xFF1F9F75).withValues(alpha: 0.86);
  const fg = Colors.white;
  final glow = const Color(0xFF1F9F75).withValues(alpha: 0.24);

  return Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(radius),
      child: Ink(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(radius),
          border: null,
          boxShadow: glow == Colors.transparent
              ? null
              : [
                  BoxShadow(
                    color: glow,
                    blurRadius: 22,
                    spreadRadius: 1,
                  ),
                ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.play_arrow, color: Colors.white),
            const SizedBox(width: 6),
            Text(
              label,
              style: theme.textTheme.titleSmall?.copyWith(
                    color: fg,
                    fontWeight: FontWeight.w700,
                  ) ??
                  const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
            ),
          ],
        ),
      ),
    ),
  );
}

Widget _withHorizontalEdgeFade(
  BuildContext context, {
  required Widget child,
  double fadeWidth = 18,
}) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final background = Colors.black.withValues(alpha: isDark ? 0.42 : 0.34);
  return Stack(
    fit: StackFit.expand,
    children: [
      child,
      IgnorePointer(
        child: Row(
          children: [
            Container(
              width: fadeWidth,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    background,
                    background.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
            const Spacer(),
            Container(
              width: fadeWidth,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    background.withValues(alpha: 0),
                    background,
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

class _HoverScale extends StatefulWidget {
  const _HoverScale({
    required this.child,
  });

  final Widget child;

  @override
  State<_HoverScale> createState() => _HoverScaleState();
}

class _HoverScaleState extends State<_HoverScale> {
  bool _hovered = false;

  bool get _supportsHover {
    if (kIsWeb) return true;
    switch (defaultTargetPlatform) {
      case TargetPlatform.windows:
      case TargetPlatform.macOS:
      case TargetPlatform.linux:
        return true;
      case TargetPlatform.android:
      case TargetPlatform.iOS:
      case TargetPlatform.fuchsia:
        return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_supportsHover) return widget.child;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedScale(
        scale: _hovered ? 1.05 : 1,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

Widget _peopleSection(
  BuildContext context,
  List<MediaPerson> people, {
  required ServerAccess access,
}) {
  final avatarBg = Colors.white.withValues(alpha: 0.14);
  const roleColor = Colors.white70;
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _sectionTitle(context, '演职人员'),
      const SizedBox(height: 8),
      SizedBox(
        height: 150,
        child: _withHorizontalEdgeFade(
          context,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: people.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final p = people[index];
              final img = access.adapter.personImageUrl(
                access.auth,
                personId: p.id,
                maxWidth: 200,
              );
              return _HoverScale(
                child: Column(
                  children: [
                    CircleAvatar(
                      radius: 42,
                      backgroundImage: linNetworkImageProvider(img),
                      backgroundColor: avatarBg,
                      child: img.isEmpty
                          ? Text(p.name.isNotEmpty ? p.name[0] : '?')
                          : null,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      p.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white),
                    ),
                    Text(
                      p.role,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: roleColor,
                          ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    ],
  );
}

Widget _castSection(
  BuildContext context,
  List<MediaPerson> people, {
  required ServerAccess access,
}) {
  final avatarBg = Colors.white.withValues(alpha: 0.14);
  const roleColor = Colors.white70;
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _sectionTitle(context, '演职人员'),
      const SizedBox(height: 8),
      SizedBox(
        height: 162,
        child: _withHorizontalEdgeFade(
          context,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: people.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final p = people[index];
              final img = access.adapter.personImageUrl(
                access.auth,
                personId: p.id,
                maxWidth: 220,
              );
              return _HoverScale(
                child: SizedBox(
                  width: 108,
                  child: Column(
                    children: [
                      CircleAvatar(
                        radius: 42,
                        backgroundImage: linNetworkImageProvider(img),
                        backgroundColor: avatarBg,
                        child: img.isEmpty
                            ? Text(p.name.isNotEmpty ? p.name[0] : '?')
                            : null,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        p.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white),
                      ),
                      Text(
                        p.role,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: roleColor,
                            ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    ],
  );
}

Widget _episodeMediaInfoSection(
  BuildContext context,
  PlaybackInfoResult info, {
  String? selectedMediaSourceId,
}) {
  final theme = Theme.of(context);
  final sources = info.mediaSources.cast<Map<String, dynamic>>();
  final currentSourceId = (selectedMediaSourceId ?? '').trim();

  String fmtSize(dynamic raw) {
    final bytes = raw is num ? raw.toInt() : int.tryParse('$raw');
    if (bytes == null || bytes <= 0) return '';
    const kb = 1024;
    const mb = kb * 1024;
    const gb = mb * 1024;
    if (bytes >= gb) return '${(bytes / gb).toStringAsFixed(1)} GB';
    if (bytes >= mb) return '${(bytes / mb).toStringAsFixed(1)} MB';
    if (bytes >= kb) return '${(bytes / kb).toStringAsFixed(0)} KB';
    return '$bytes B';
  }

  String? fmtAdded(dynamic raw) {
    final text = raw == null ? '' : raw.toString().trim();
    if (text.isEmpty) return null;
    final parsed = DateTime.tryParse(text);
    if (parsed == null) return null;
    final local = parsed.toLocal();
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '${local.year}/${local.month}/${local.day} $hh:$mm';
  }

  String yesNo(dynamic value) => value == true ? '是' : '否';

  String fmtMbps(int? bitrate) {
    if (bitrate == null || bitrate <= 0) return '';
    return '${(bitrate / 1000000).toStringAsFixed(1)} Mbps';
  }

  String fmtKbps(int? bitrate) {
    if (bitrate == null || bitrate <= 0) return '';
    return '${(bitrate / 1000).toStringAsFixed(0)} Kbps';
  }

  List<({String label, String value})> videoLines(Map<String, dynamic> stream) {
    final lines = <({String label, String value})>[];
    final title = (stream['DisplayTitle'] ?? '').toString().trim();
    final innerTitle = (stream['Title'] ?? '').toString().trim();
    final codec = (stream['Codec'] ?? '').toString().trim();
    final profile = (stream['Profile'] ?? '').toString().trim();
    final level = _ShowDetailPageState._asInt(stream['Level']);
    final width = _ShowDetailPageState._asInt(stream['Width']);
    final height = _ShowDetailPageState._asInt(stream['Height']);
    final aspect = _formatVideoAspectRatio(stream);
    final interlaced = stream['IsInterlaced'] == true;
    final frameRate = stream['RealFrameRate'] ?? stream['AverageFrameRate'];
    final bitrate = _ShowDetailPageState._asInt(stream['BitRate']);
    final primaries = (stream['ColorPrimaries'] ?? '').toString().trim();
    final colorSpace = (stream['ColorSpace'] ?? '').toString().trim();
    final transfer = (stream['ColorTransfer'] ?? '').toString().trim();
    final bitDepth = _ShowDetailPageState._asInt(stream['BitDepth']);
    final pixelFormat = (stream['PixelFormat'] ?? '').toString().trim();
    final refFrames = _ShowDetailPageState._asInt(stream['RefFrames']);

    if (title.isNotEmpty) lines.add((label: '标题名称', value: title));
    if (innerTitle.isNotEmpty && innerTitle != title) {
      lines.add((label: '内嵌标题', value: innerTitle));
    }
    if (codec.isNotEmpty) {
      lines.add((label: '编码格式', value: codec.toUpperCase()));
    }
    if (profile.isNotEmpty) lines.add((label: '编码规格', value: profile));
    if (level != null && level > 0) lines.add((label: '编码级别', value: '$level'));
    if (width != null && height != null) {
      lines.add((label: '源分辨率', value: '${width}x$height'));
    }
    if (aspect != null) lines.add((label: '视频比例', value: aspect));
    lines.add((label: '隔行扫描', value: yesNo(interlaced)));
    if (frameRate != null) {
      lines.add((label: '帧速率', value: frameRate.toString()));
    }
    final bitrateText = fmtMbps(bitrate);
    if (bitrateText.isNotEmpty) lines.add((label: '比特率', value: bitrateText));
    if (primaries.isNotEmpty) lines.add((label: '原始色域', value: primaries));
    if (colorSpace.isNotEmpty) lines.add((label: '色彩空间', value: colorSpace));
    if (transfer.isNotEmpty) lines.add((label: '色彩转换', value: transfer));
    if (bitDepth != null && bitDepth > 0) {
      lines.add((label: '比特位深', value: '$bitDepth Bit'));
    }
    if (pixelFormat.isNotEmpty) lines.add((label: '像素格式', value: pixelFormat));
    if (refFrames != null && refFrames > 0) {
      lines.add((label: '参考帧', value: '$refFrames'));
    }
    lines.add((label: '默认', value: yesNo(stream['IsDefault'])));
    return lines;
  }

  List<({String label, String value})> audioLines(Map<String, dynamic> stream) {
    final lines = <({String label, String value})>[];
    final title = (stream['DisplayTitle'] ?? '').toString().trim();
    final innerTitle = (stream['Title'] ?? '').toString().trim();
    final language = (stream['Language'] ?? '').toString().trim();
    final codec = (stream['Codec'] ?? '').toString().trim();
    final profile = (stream['Profile'] ?? '').toString().trim();
    final channels = _ShowDetailPageState._asInt(stream['Channels']);
    final layout = (stream['ChannelLayout'] ?? '').toString().trim();
    final bitrate = _ShowDetailPageState._asInt(stream['BitRate']);
    final sampleRate = _ShowDetailPageState._asInt(stream['SampleRate']);

    if (title.isNotEmpty) lines.add((label: '标题名称', value: title));
    if (innerTitle.isNotEmpty && innerTitle != title) {
      lines.add((label: '内嵌标题', value: innerTitle));
    }
    if (language.isNotEmpty) lines.add((label: '语言种类', value: language));
    if (codec.isNotEmpty) {
      lines.add((label: '编码格式', value: codec.toUpperCase()));
    }
    if (profile.isNotEmpty) lines.add((label: '编码规格', value: profile));
    if (layout.isNotEmpty) lines.add((label: '音效布局', value: layout));
    if (channels != null && channels > 0) {
      lines.add((label: '音频声道', value: '$channels ch'));
    }
    final bitrateText = fmtKbps(bitrate);
    if (bitrateText.isNotEmpty) lines.add((label: '比特率', value: bitrateText));
    if (sampleRate != null && sampleRate > 0) {
      lines.add((label: '采样率', value: '$sampleRate Hz'));
    }
    lines.add((label: '默认', value: yesNo(stream['IsDefault'])));
    return lines;
  }

  List<({String label, String value})> subtitleLines(
    Map<String, dynamic> stream,
  ) {
    final lines = <({String label, String value})>[];
    final title =
        (stream['DisplayTitle'] ?? stream['Language'] ?? '').toString().trim();
    final innerTitle = (stream['Title'] ?? '').toString().trim();
    final language = (stream['Language'] ?? '').toString().trim();
    final codec = (stream['Codec'] ?? '').toString().trim();

    if (title.isNotEmpty) lines.add((label: '标题名称', value: title));
    if (innerTitle.isNotEmpty && innerTitle != title) {
      lines.add((label: '内嵌标题', value: innerTitle));
    }
    if (language.isNotEmpty) lines.add((label: '语言种类', value: language));
    if (codec.isNotEmpty) {
      lines.add((label: '编码格式', value: codec.toUpperCase()));
    }
    lines.add((label: '默认', value: yesNo(stream['IsDefault'])));
    lines.add((label: '强制', value: yesNo(stream['IsForced'])));
    lines.add((label: '外部', value: yesNo(stream['IsExternal'])));
    return lines;
  }

  Widget streamCard({
    required IconData icon,
    required String title,
    required List<({String label, String value})> lines,
  }) {
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: Colors.white),
              const SizedBox(width: 8),
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (lines.isEmpty)
            Text(
              '暂无信息',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.white70,
              ),
            )
          else
            ...lines.map(
              (line) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 88,
                      child: Text(
                        line.label,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.white70,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        line.value,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget sourceCard(Map<String, dynamic> source, int index) {
    final sourceId = (source['Id']?.toString() ?? '').trim();
    final isSelected =
        currentSourceId.isEmpty ? index == 0 : sourceId == currentSourceId;
    final streams = (source['MediaStreams'] as List?) ?? const [];
    final videos = streams
        .where((entry) => (entry as Map)['Type'] == 'Video')
        .map((entry) => Map<String, dynamic>.from(entry as Map))
        .toList();
    final audios = streams
        .where((entry) => (entry as Map)['Type'] == 'Audio')
        .map((entry) => Map<String, dynamic>.from(entry as Map))
        .toList();
    final subtitles = streams
        .where((entry) => (entry as Map)['Type'] == 'Subtitle')
        .map((entry) => Map<String, dynamic>.from(entry as Map))
        .toList();

    final title = _ShowDetailPageState._mediaSourceTitle(source).trim();
    final container = (source['Container'] ?? source['Name'] ?? '')
        .toString()
        .trim()
        .toUpperCase();
    final sizeText = fmtSize(source['Size']);
    final addedText = fmtAdded(
      source['DateCreated'] ??
          source['DateAdded'] ??
          source['DateCreatedUtc'] ??
          source['DateModified'],
    );
    final summaryParts = <String>[
      if (container.isNotEmpty) container,
      if (sizeText.isNotEmpty) sizeText,
      if (addedText != null) '媒体于 $addedText 添加',
    ];

    return _detailGlassPanel(
      enableBlur: true,
      radius: 18,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.video_library_rounded, color: Colors.white),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title.isEmpty ? '版本 ${index + 1}' : title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (isSelected) _pill(context, '当前'),
            ],
          ),
          if (summaryParts.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              summaryParts.join('  '),
              style: theme.textTheme.bodySmall?.copyWith(
                color: Colors.white70,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          if (videos.isEmpty && audios.isEmpty && subtitles.isEmpty) ...[
            const SizedBox(height: 10),
            Text(
              '暂无流信息',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.white70,
              ),
            ),
          ] else ...[
            ...videos.asMap().entries.map(
                  (entry) => streamCard(
                    icon: Icons.videocam_rounded,
                    title: videos.length > 1 ? '视频 ${entry.key + 1}' : '视频信息',
                    lines: videoLines(entry.value),
                  ),
                ),
            ...audios.asMap().entries.map(
                  (entry) => streamCard(
                    icon: Icons.music_note_rounded,
                    title: audios.length > 1 ? '音频 ${entry.key + 1}' : '音频信息',
                    lines: audioLines(entry.value),
                  ),
                ),
            ...subtitles.asMap().entries.map(
                  (entry) => streamCard(
                    icon: Icons.closed_caption_rounded,
                    title:
                        subtitles.length > 1 ? '字幕 ${entry.key + 1}' : '字幕信息',
                    lines: subtitleLines(entry.value),
                  ),
                ),
          ],
        ],
      ),
    );
  }

  if (sources.isEmpty) {
    return _detailGlassPanel(
      enableBlur: true,
      radius: 18,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(context, '媒体信息'),
          const SizedBox(height: 10),
          Text(
            '暂无媒体信息',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: Colors.white70,
            ),
          ),
        ],
      ),
    );
  }

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _sectionTitle(context, '媒体信息'),
      const SizedBox(height: 12),
      ...sources.asMap().entries.map(
            (entry) => Padding(
              padding: EdgeInsets.only(
                bottom: entry.key == sources.length - 1 ? 0 : 12,
              ),
              child: sourceCard(entry.value, entry.key),
            ),
          ),
    ],
  );
}

// ignore: unused_element
Widget _mediaInfo(
  BuildContext context,
  PlaybackInfoResult info, {
  String? selectedMediaSourceId,
}) {
  final map =
      _ShowDetailPageState._findMediaSource(info, selectedMediaSourceId) ??
          (info.mediaSources.first as Map<String, dynamic>);
  final streams = (map['MediaStreams'] as List?) ?? const [];
  final video = streams
      .where((e) => (e as Map)['Type'] == 'Video')
      .map((e) => e as Map)
      .toList();
  final audio = streams
      .where((e) => (e as Map)['Type'] == 'Audio')
      .map((e) => e as Map)
      .toList();
  final subtitle = streams
      .where((e) => (e as Map)['Type'] == 'Subtitle')
      .map((e) => e as Map)
      .toList();
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _sectionTitle(context, '媒体源信息'),
      const SizedBox(height: 8),
      Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          _infoCard(
              '视频',
              video.map((v) {
                final title = (v['DisplayTitle'] ?? '').toString().trim();
                final codec = (v['Codec'] ?? '').toString().trim();
                final aspect =
                    _formatVideoAspectRatio(v.cast<String, dynamic>());
                final parts = <String>[
                  if (title.isNotEmpty) title,
                  if (codec.isNotEmpty) codec,
                  if (aspect != null) '视频比例：$aspect',
                ];
                return parts.join('\n');
              }).join('\n\n')),
          _infoCard(
              '音频',
              audio
                  .map((a) => '${a['DisplayTitle'] ?? ''}\n${a['Codec'] ?? ''}')
                  .join('\n')),
          _infoCard(
              '字幕',
              subtitle.isEmpty
                  ? '无'
                  : subtitle
                      .take(3)
                      .map((s) =>
                          '${s['DisplayTitle'] ?? s['Language'] ?? ''}\n${s['Codec'] ?? ''}')
                      .join('\n\n')),
        ],
      ),
    ],
  );
}

String? _formatVideoAspectRatio(Map<String, dynamic> stream) {
  final raw = stream['AspectRatio'];
  if (raw is String) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    if (trimmed.contains(':')) return trimmed;
    final n = double.tryParse(trimmed);
    if (n != null && n.isFinite && n > 0) return _formatAspectRatioValue(n);
    return trimmed;
  }

  final width = _ShowDetailPageState._asInt(stream['Width']);
  final height = _ShowDetailPageState._asInt(stream['Height']);
  if (width == null || height == null || width <= 0 || height <= 0) {
    return null;
  }
  return _formatAspectRatioValue(width / height, width: width, height: height);
}

String _formatAspectRatioValue(
  double ratio, {
  int? width,
  int? height,
}) {
  const known = <String, double>{
    '1:1': 1.0,
    '4:3': 4 / 3,
    '3:2': 3 / 2,
    '16:9': 16 / 9,
    '21:9': 21 / 9,
    '2:1': 2.0,
    '1.85:1': 1.85,
    '2.39:1': 2.39,
  };
  const tol = 0.03;
  for (final e in known.entries) {
    if ((ratio - e.value).abs() <= tol) return e.key;
  }

  if (width != null &&
      height != null &&
      width > 0 &&
      height > 0 &&
      width < 100000 &&
      height < 100000) {
    final g = _gcd(width, height);
    if (g > 0) {
      final a = (width / g).round();
      final b = (height / g).round();
      if (a > 0 && b > 0 && a <= 100 && b <= 100) return '$a:$b';
    }
  }

  return ratio.toStringAsFixed(2);
}

int _gcd(int a, int b) {
  var x = a.abs();
  var y = b.abs();
  while (y != 0) {
    final t = x % y;
    x = y;
    y = t;
  }
  return x;
}

Widget _infoCard(String title, String body) => SizedBox(
      width: 240,
      child: _detailGlassPanel(
        enableBlur: true,
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              body.isEmpty ? '无' : body,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 12,
                height: 1.4,
              ),
              maxLines: 18,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );

String _providerId(MediaItem item, List<String> providerKeys) {
  for (final entry in item.providerIds.entries) {
    final key = entry.key.toLowerCase();
    if (providerKeys.any((k) => key.contains(k))) {
      final value = entry.value.trim();
      if (value.isNotEmpty) return value;
    }
  }
  return '';
}

Widget _externalLinksSection(
    BuildContext context, MediaItem item, AppState appState) {
  final isSeries = item.type.toLowerCase() == 'series';
  final tmdbId = _providerId(item, const ['tmdb']);
  final imdbId = _providerId(item, const ['imdb']);
  final traktId = _providerId(item, const ['trakt']);

  final tmdbUrl = tmdbId.isEmpty
      ? ''
      : (isSeries
          ? 'https://www.themoviedb.org/tv/$tmdbId'
          : 'https://www.themoviedb.org/movie/$tmdbId');
  final imdbUrl = imdbId.isEmpty ? '' : 'https://www.imdb.com/title/$imdbId';
  final traktUrl = traktId.isNotEmpty
      ? (isSeries
          ? 'https://trakt.tv/shows/$traktId'
          : 'https://trakt.tv/movies/$traktId')
      : (imdbId.isNotEmpty
          ? 'https://trakt.tv/search/imdb/$imdbId'
          : (tmdbId.isNotEmpty ? 'https://trakt.tv/search/tmdb/$tmdbId' : ''));

  final links = <({String label, String url, IconData icon})>[
    if (imdbUrl.isNotEmpty) (label: 'IMDb', url: imdbUrl, icon: Icons.movie),
    if (tmdbUrl.isNotEmpty)
      (label: 'TheMovieDb', url: tmdbUrl, icon: Icons.local_movies),
    if (traktUrl.isNotEmpty) (label: 'Trakt', url: traktUrl, icon: Icons.link),
  ];
  if (links.isEmpty) return const SizedBox.shrink();

  Future<void> openExternal(String url) async {
    final opened = await launchUrlString(url);
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('无法打开链接')),
      );
    }
  }

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _sectionTitle(context, '数据库链接'),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: links
            .map(
              (link) => ActionChip(
                avatar: Icon(link.icon, size: 18),
                label: Text(link.label),
                labelStyle: const TextStyle(color: Colors.white),
                side: BorderSide(color: Colors.white.withValues(alpha: 0.24)),
                backgroundColor: Colors.black.withValues(alpha: 0.30),
                onPressed: () => openExternal(link.url),
              ),
            )
            .toList(),
      )
    ],
  );
}
