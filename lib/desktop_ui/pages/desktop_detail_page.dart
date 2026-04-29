import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lin_player_player/lin_player_player.dart';
import 'package:lin_player_server_adapters/lin_player_server_adapters.dart';
import 'package:lin_player_state/lin_player_state.dart';
import 'package:lin_player_ui/lin_player_ui.dart';
import 'package:url_launcher/url_launcher_string.dart';

import '../../server_adapters/server_access.dart';
import '../models/desktop_ui_language.dart';
import '../view_models/desktop_detail_view_model.dart';
import '../view_models/desktop_person_view_model.dart';
import '../widgets/desktop_page_route.dart';
import '../widgets/desktop_media_meta.dart';

typedef DesktopDetailOpenItem = void Function(
  MediaItem item, [
  ServerProfile? server,
]);

void _animateScrollByPointerDelta({
  required ScrollController controller,
  required PointerScrollEvent event,
}) {
  final delta = event.scrollDelta.dy.abs() > event.scrollDelta.dx.abs()
      ? event.scrollDelta.dy
      : event.scrollDelta.dx;
  if (delta == 0) return;
  final position = controller.position;
  final target = (controller.offset + delta).clamp(
    position.minScrollExtent,
    position.maxScrollExtent,
  );
  final distance = (target - controller.offset).abs();
  if (distance < 0.5) return;

  final durationMs = math.max(1, math.min(220, (distance / 1.5).round()));
  unawaited(
    controller.animateTo(
      target,
      duration: Duration(milliseconds: durationMs),
      curve: Curves.linear,
    ),
  );
}

class DesktopDetailPage extends StatefulWidget {
  const DesktopDetailPage({
    super.key,
    required this.viewModel,
    this.language = DesktopUiLanguage.zhCn,
    this.onOpenItem,
    this.onPlayPressed,
    this.posterKey,
    this.posterVisible = true,
    this.onPosterReady,
    this.posterSnapshotImage,
    this.useSharedPosterOverlay = false,
  });

  final DesktopDetailViewModel viewModel;
  final DesktopUiLanguage language;
  final DesktopDetailOpenItem? onOpenItem;
  final VoidCallback? onPlayPressed;
  final Key? posterKey;
  final bool posterVisible;
  final VoidCallback? onPosterReady;
  final ui.Image? posterSnapshotImage;
  final bool useSharedPosterOverlay;

  @override
  State<DesktopDetailPage> createState() => _DesktopDetailPageState();
}

class _DesktopDetailPageState extends State<DesktopDetailPage> {
  String? _selectedMediaSourceId;
  int? _selectedAudioStreamIndex;
  int _selectedSubtitleStreamIndex = -1;
  bool? _playedOverride;
  bool _markingPlayed = false;
  bool _launchingExternalMpv = false;
  bool _jumpingToEpisode = false;

  final TextEditingController _jumpSeasonController = TextEditingController();
  final TextEditingController _jumpEpisodeController = TextEditingController();
  final FocusNode _jumpSeasonFocusNode = FocusNode();
  final FocusNode _jumpEpisodeFocusNode = FocusNode();

  String _t({
    required String zh,
    required String en,
  }) {
    return widget.language.pick(zh: zh, en: en);
  }

  @override
  void initState() {
    super.initState();
    unawaited(widget.viewModel.load());
  }

  @override
  void didUpdateWidget(covariant DesktopDetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.viewModel, widget.viewModel)) {
      _resetTransientState();
      unawaited(widget.viewModel.load(forceRefresh: true));
    }
  }

  void _resetTransientState() {
    _selectedMediaSourceId = null;
    _selectedAudioStreamIndex = null;
    _selectedSubtitleStreamIndex = -1;
    _playedOverride = null;
    _jumpingToEpisode = false;
    _jumpSeasonController.clear();
    _jumpEpisodeController.clear();
  }

  @override
  void dispose() {
    _jumpSeasonController.dispose();
    _jumpEpisodeController.dispose();
    _jumpSeasonFocusNode.dispose();
    _jumpEpisodeFocusNode.dispose();
    super.dispose();
  }

  Future<void> _openExternalLink(String url) async {
    if (url.trim().isEmpty) return;
    final opened = await launchUrlString(url);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              zh: '\u65e0\u6cd5\u6253\u5f00\u94fe\u63a5',
              en: 'Unable to open link',
            ),
          ),
        ),
      );
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _toggleItemPlayedMark({
    required MediaItem item,
    required bool currentPlayed,
  }) async {
    if (_markingPlayed) return;

    final access = resolveServerAccess(
          appState: widget.viewModel.appState,
          server: widget.viewModel.server,
        ) ??
        widget.viewModel.access;
    if (access == null) {
      _showMessage(
        _t(
          zh: '\u672a\u8fde\u63a5\u670d\u52a1\u5668',
          en: 'Not connected to server',
        ),
      );
      return;
    }

    final nextPlayed = !currentPlayed;
    final nextPositionTicks = 0;

    setState(() {
      _markingPlayed = true;
      _playedOverride = nextPlayed;
    });

    try {
      await access.adapter.updatePlaybackPosition(
        access.auth,
        itemId: item.id,
        positionTicks: nextPositionTicks,
        played: nextPlayed,
      );

      unawaited(widget.viewModel.load(forceRefresh: true));
      try {
        if (item.type.trim().toLowerCase() == 'episode') {
          await widget.viewModel.appState
              .updateContinueWatchingAfterPlaybackMark(
            item: item,
            played: nextPlayed,
          );
        } else {
          await widget.viewModel.appState.loadContinueWatching(
            forceRefresh: true,
            forceNewRequest: true,
          );
        }
      } catch (_) {
        // Ignore refresh errors; playback mark already succeeded.
      }
      unawaited(widget.viewModel.appState.loadHome(forceRefresh: true));

      if (!mounted) return;
      _showMessage(
        nextPlayed
            ? _t(
                zh: '\u5df2\u6807\u8bb0\u4e3a\u5df2\u64ad\u653e',
                en: 'Marked as watched',
              )
            : _t(
                zh: '\u5df2\u6807\u8bb0\u4e3a\u672a\u64ad\u653e',
                en: 'Marked as unwatched',
              ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _playedOverride = currentPlayed);
      _showMessage(
        _t(
          zh: '\u6807\u8bb0\u5931\u8d25\uff1a$e',
          en: 'Failed to mark watched: $e',
        ),
      );
    } finally {
      if (mounted) setState(() => _markingPlayed = false);
    }
  }

  MediaItem? _resolvePlayableItemForExternalMpv({
    required MediaItem item,
    required List<MediaItem> episodes,
  }) {
    final type = item.type.trim().toLowerCase();
    if (type == 'series' || type == 'season') {
      if (episodes.isEmpty) return null;
      return episodes.firstWhere(
        (entry) => entry.playbackPositionTicks > 0,
        orElse: () => episodes.first,
      );
    }
    return item;
  }

  String? _currentSeasonIdFor(MediaItem item, DesktopDetailViewModel vm) {
    final type = item.type.trim().toLowerCase();
    if (type == 'season') return item.id;
    if (type == 'episode') return item.parentId;
    return vm.seasons.isNotEmpty ? vm.seasons.first.id : null;
  }

  Future<void> _onJumpSubmitted({
    required DesktopDetailViewModel vm,
    required bool fromSeasonField,
  }) async {
    if (_jumpingToEpisode) return;

    final rawSeason = _jumpSeasonController.text.trim();
    final rawEpisode = _jumpEpisodeController.text.trim();
    if (fromSeasonField && rawSeason.isNotEmpty && rawEpisode.isEmpty) {
      FocusScope.of(context).requestFocus(_jumpEpisodeFocusNode);
      return;
    }
    if (rawSeason.isEmpty && rawEpisode.isEmpty) return;

    final seasonNo = int.tryParse(rawSeason);
    final episodeNo = int.tryParse(rawEpisode);
    await _jumpToSeasonEpisode(
      vm: vm,
      seasonNumber: seasonNo,
      episodeNumber: episodeNo,
    );
  }

  Future<void> _jumpToSeasonEpisode({
    required DesktopDetailViewModel vm,
    required int? seasonNumber,
    required int? episodeNumber,
  }) async {
    final openItem = widget.onOpenItem;
    if (openItem == null) return;

    final access = vm.access;
    if (access == null) {
      _showMessage(
          _t(zh: '\u672a\u8fde\u63a5\u670d\u52a1\u5668', en: 'No server'));
      return;
    }

    final seasons = vm.seasons;
    if (seasons.isEmpty) {
      _showMessage(
        _t(zh: '\u6682\u65e0\u5b63\u5ea6\u4fe1\u606f', en: 'No seasons'),
      );
      return;
    }

    final sortedSeasons = List<MediaItem>.from(seasons);
    sortedSeasons.sort((a, b) {
      final aNo = a.seasonNumber ?? a.episodeNumber ?? 0;
      final bNo = b.seasonNumber ?? b.episodeNumber ?? 0;
      final diff = aNo.compareTo(bNo);
      if (diff != 0) return diff;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });

    MediaItem? pickedSeason;
    if (seasonNumber != null) {
      final desiredSeason = seasonNumber;
      for (final season in sortedSeasons) {
        final no = season.seasonNumber ?? season.episodeNumber ?? 0;
        if (no == desiredSeason) {
          pickedSeason = season;
          break;
        }
      }
      if (pickedSeason == null &&
          desiredSeason > 0 &&
          desiredSeason <= sortedSeasons.length) {
        pickedSeason = sortedSeasons[desiredSeason - 1];
      }
    } else {
      final current = vm.detail;
      final type = current.type.trim().toLowerCase();
      if (type == 'season') {
        for (final season in sortedSeasons) {
          if (season.id == current.id) {
            pickedSeason = season;
            break;
          }
        }
      } else if (type == 'episode') {
        final currentSeasonId = (current.parentId ?? '').trim();
        for (final season in sortedSeasons) {
          if (season.id == currentSeasonId) {
            pickedSeason = season;
            break;
          }
        }
      } else {
        pickedSeason = sortedSeasons.isNotEmpty ? sortedSeasons.first : null;
      }
    }

    if (pickedSeason == null) {
      _showMessage(
        _t(
          zh: '\u672a\u627e\u5230\u5bf9\u5e94\u7684\u5b63\u5ea6',
          en: 'Season not found',
        ),
      );
      return;
    }

    final desiredEpisode = episodeNumber ?? 0;
    if (desiredEpisode <= 0) {
      openItem(pickedSeason, vm.server);
      return;
    }

    setState(() => _jumpingToEpisode = true);
    try {
      final res = await access.adapter.fetchEpisodes(
        access.auth,
        seasonId: pickedSeason.id,
      );
      final episodes = List<MediaItem>.from(res.items);
      episodes.sort((a, b) {
        final aNo = a.episodeNumber ?? 0;
        final bNo = b.episodeNumber ?? 0;
        final diff = aNo.compareTo(bNo);
        if (diff != 0) return diff;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });

      MediaItem? pickedEpisode;
      for (final ep in episodes) {
        if ((ep.episodeNumber ?? 0) == desiredEpisode) {
          pickedEpisode = ep;
          break;
        }
      }

      if (pickedEpisode == null) {
        _showMessage(
          _t(
            zh: '\u672a\u627e\u5230\u7b2c $desiredEpisode \u96c6',
            en: 'Episode $desiredEpisode not found',
          ),
        );
        return;
      }

      _jumpEpisodeController.clear();
      openItem(pickedEpisode, vm.server);
    } catch (e) {
      _showMessage(
        _t(
          zh: '\u8df3\u8f6c\u5931\u8d25\uff1a$e',
          en: 'Jump failed: $e',
        ),
      );
    } finally {
      if (mounted) setState(() => _jumpingToEpisode = false);
    }
  }

  Widget _buildJumpFields({
    required _EpisodeDetailColors colors,
    required DesktopDetailViewModel vm,
  }) {
    final enabled = !_jumpingToEpisode &&
        widget.onOpenItem != null &&
        vm.access != null &&
        vm.seasons.isNotEmpty;
    final textTheme = Theme.of(context).textTheme;
    final baseFieldStyle = textTheme.labelMedium ?? const TextStyle();
    InputDecoration decoration({
      required String prefix,
      required String hint,
    }) {
      return InputDecoration(
        isDense: true,
        hintText: hint,
        hintStyle: baseFieldStyle.copyWith(
          fontSize: 12,
          color: colors.textTertiary,
          fontWeight: FontWeight.w600,
        ),
        prefixText: prefix,
        prefixStyle: baseFieldStyle.copyWith(
          fontSize: 12,
          color: colors.textTertiary,
          fontWeight: FontWeight.w700,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: colors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: colors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: colors.primary, width: 1.4),
        ),
        fillColor: colors.surfaceHover,
        filled: true,
        counterText: '',
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 86,
          child: Tooltip(
            message: _t(
                zh: '\u8f93\u5165\u5b63\u5ea6\uff0c\u56de\u8f66\u8df3\u8f6c',
                en: 'Type season, press Enter'),
            child: TextField(
              controller: _jumpSeasonController,
              focusNode: _jumpSeasonFocusNode,
              enabled: enabled,
              onSubmitted: (_) => unawaited(
                _onJumpSubmitted(vm: vm, fromSeasonField: true),
              ),
              textInputAction: TextInputAction.next,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              maxLength: 3,
              style: baseFieldStyle.copyWith(
                fontSize: 12.5,
                color: colors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
              decoration: decoration(
                prefix: _dtr(language: widget.language, zh: '\u5b63', en: 'S'),
                hint: _dtr(
                    language: widget.language, zh: '\u6570\u5b57', en: 'No.'),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 86,
          child: Tooltip(
            message: _t(
                zh: '\u8f93\u5165\u96c6\u6570\uff0c\u56de\u8f66\u8df3\u8f6c',
                en: 'Type episode, press Enter'),
            child: TextField(
              controller: _jumpEpisodeController,
              focusNode: _jumpEpisodeFocusNode,
              enabled: enabled,
              onSubmitted: (_) => unawaited(
                _onJumpSubmitted(vm: vm, fromSeasonField: false),
              ),
              textInputAction: TextInputAction.go,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              maxLength: 4,
              style: baseFieldStyle.copyWith(
                fontSize: 12.5,
                color: colors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
              decoration: decoration(
                prefix: _dtr(language: widget.language, zh: '\u96c6', en: 'E'),
                hint: _dtr(
                    language: widget.language, zh: '\u6570\u5b57', en: 'No.'),
              ),
            ),
          ),
        ),
      ],
    );
  }

  String _apiUrlWithPrefix({
    required String baseUrl,
    required String apiPrefix,
    required String path,
  }) {
    var base = baseUrl.trim();
    while (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }

    var prefix = apiPrefix.trim();
    while (prefix.startsWith('/')) {
      prefix = prefix.substring(1);
    }
    while (prefix.endsWith('/')) {
      prefix = prefix.substring(0, prefix.length - 1);
    }

    final fixedPath = path.startsWith('/') ? path.substring(1) : path;
    if (prefix.isEmpty) return '$base/$fixedPath';
    return '$base/$prefix/$fixedPath';
  }

  String _buildDirectStreamUrl({
    required ServerAuthSession auth,
    required String itemId,
    required String mediaSourceId,
    required String playSessionId,
    required String deviceId,
  }) {
    final streamPath = 'Videos/$itemId/stream';
    final uri = Uri.parse(
      _apiUrlWithPrefix(
        baseUrl: auth.baseUrl,
        apiPrefix: auth.apiPrefix,
        path: streamPath,
      ),
    ).replace(
      queryParameters: {
        'static': 'true',
        'MediaSourceId': mediaSourceId,
        if (playSessionId.trim().isNotEmpty) 'PlaySessionId': playSessionId,
        if (auth.userId.trim().isNotEmpty) 'UserId': auth.userId.trim(),
        if (deviceId.trim().isNotEmpty) 'DeviceId': deviceId.trim(),
        'api_key': auth.token,
      },
    );
    return uri.toString();
  }

  String? _resolvePlaybackDirectStreamUrl(
    ServerAuthSession auth,
    Map<String, dynamic>? mediaSource,
  ) {
    final directCandidate =
        (mediaSource?['DirectStreamUrl'] as String?)?.trim();
    final pathCandidate = (mediaSource?['Path'] as String?)?.trim();
    final pathUri = (pathCandidate == null || pathCandidate.isEmpty)
        ? null
        : Uri.tryParse(pathCandidate);

    final candidate = (directCandidate != null && directCandidate.isNotEmpty)
        ? directCandidate
        : ((pathUri != null &&
                pathUri.scheme.isNotEmpty &&
                pathUri.host.isNotEmpty)
            ? pathCandidate
            : null);
    if (candidate == null || candidate.isEmpty) return null;

    final resolved = Uri.parse(auth.baseUrl).resolve(candidate);

    bool sameOrigin(Uri a, Uri b) {
      int portOf(Uri u) =>
          u.hasPort ? u.port : (u.scheme == 'https' ? 443 : 80);
      return a.scheme == b.scheme && a.host == b.host && portOf(a) == portOf(b);
    }

    final baseUri = Uri.tryParse(auth.baseUrl);
    if (baseUri != null &&
        resolved.host.isNotEmpty &&
        baseUri.host.isNotEmpty &&
        !sameOrigin(resolved, baseUri)) {
      // External URL (e.g. STRM): do not append server api_key.
      return resolved.toString();
    }

    final params = Map<String, String>.from(resolved.queryParameters);
    if (!params.containsKey('api_key')) params['api_key'] = auth.token;
    return resolved.replace(queryParameters: params).toString();
  }

  Future<void> _launchExternalMpv({
    required MediaItem item,
    required _TrackSelectionState trackState,
  }) async {
    if (_launchingExternalMpv) return;
    final vm = widget.viewModel;
    final access = vm.access;
    if (access == null) {
      _showMessage(
        _t(
          zh: '\u672a\u8fde\u63a5\u5a92\u4f53\u670d\u52a1\u5668',
          en: 'No connected media server',
        ),
      );
      return;
    }

    final playable = _resolvePlayableItemForExternalMpv(
      item: item,
      episodes: vm.episodes,
    );
    if (playable == null || playable.id.trim().isEmpty) {
      _showMessage(
        _t(
          zh: '\u5f53\u524d\u6761\u76ee\u65e0\u53ef\u64ad\u653e\u8d44\u6e90',
          en: 'No playable media found for this item',
        ),
      );
      return;
    }

    setState(() => _launchingExternalMpv = true);
    try {
      final info = await access.adapter.fetchPlaybackInfo(
        access.auth,
        itemId: playable.id,
      );
      final sources = _playbackSources(info);
      final preferredValue =
          playable.id == item.id ? trackState.selectedVideoValue : null;
      Map<String, dynamic>? selectedSource = _resolveSourceFromSelection(
        sources: sources,
        selectedValue: preferredValue,
      );
      selectedSource ??= sources.isEmpty ? null : sources.first;
      final mediaSourceId =
          (selectedSource?['Id'] ?? info.mediaSourceId).toString().trim();
      if (mediaSourceId.isEmpty) {
        _showMessage(
          _t(
            zh: '\u65e0\u6cd5\u89e3\u6790\u5a92\u4f53\u6e90',
            en: 'Unable to resolve media source',
          ),
        );
        return;
      }

      final streamUrl = _buildDirectStreamUrl(
        auth: access.auth,
        itemId: playable.id,
        mediaSourceId: mediaSourceId,
        playSessionId: info.playSessionId,
        deviceId: vm.appState.deviceId,
      );
      final directFromPlaybackInfo =
          _resolvePlaybackDirectStreamUrl(access.auth, selectedSource);

      final source = directFromPlaybackInfo ?? streamUrl;

      bool sameOrigin(Uri a, Uri b) {
        int portOf(Uri u) =>
            u.hasPort ? u.port : (u.scheme == 'https' ? 443 : 80);
        return a.scheme == b.scheme &&
            a.host == b.host &&
            portOf(a) == portOf(b);
      }

      final sourceUri = Uri.tryParse(source);
      final baseUri = Uri.tryParse(access.auth.baseUrl);
      final needsAuthHeaders = sourceUri != null &&
          baseUri != null &&
          sourceUri.host.isNotEmpty &&
          baseUri.host.isNotEmpty &&
          sameOrigin(sourceUri, baseUri);

      final launched = await launchExternalMpv(
        executablePath: vm.appState.externalMpvPath,
        source: source,
        httpHeaders: needsAuthHeaders
            ? access.adapter.buildStreamHeaders(access.auth)
            : null,
      );
      _showMessage(
        launched
            ? _t(
                zh: '\u5df2\u8c03\u7528\u5916\u90e8 MPV',
                en: 'Launched external MPV',
              )
            : _t(
                zh: '\u8c03\u7528\u5916\u90e8 MPV \u5931\u8d25\uff0c\u8bf7\u5728\u8bbe\u7f6e\u4e2d\u914d\u7f6e MPV \u8def\u5f84',
                en: 'Failed to launch MPV. Configure MPV executable path in settings.',
              ),
      );
    } catch (_) {
      _showMessage(
        _t(
          zh: '\u8c03\u7528\u5916\u90e8 MPV \u5931\u8d25',
          en: 'Failed to launch external MPV',
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _launchingExternalMpv = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.viewModel,
      builder: (context, _) {
        final colors = _EpisodeDetailColors.of(context);
        final vm = widget.viewModel;
        final item = vm.detail;
        final detailType = item.type.trim().toLowerCase();
        final isEpisode = detailType == 'episode';
        final isMovie = detailType == 'movie';
        final showTrackSelectors = isEpisode || isMovie;

        if (vm.loading && vm.error == null && item.id.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }

        final trackState = _resolveTrackSelection(
          item: item,
          playbackInfo: vm.playbackInfo,
        );
        final links = _buildExternalLinks(item);
        final watched = _playedOverride ?? item.played;
        final showMediaInfo = showTrackSelectors;

        return DecoratedBox(
          decoration: BoxDecoration(color: colors.background),
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 22, 24, 0),
                  child: _HeroPanel(
                    item: item,
                    access: vm.access,
                    posterKey: widget.posterKey,
                    posterVisible: widget.posterVisible,
                    onPosterReady: widget.onPosterReady,
                    posterSnapshotImage: widget.posterSnapshotImage,
                    useSharedPosterOverlay: widget.useSharedPosterOverlay,
                    watched: watched,
                    isFavorite: vm.favorite,
                    trackState: trackState,
                    showTrackSelectors: showTrackSelectors,
                    onPlay: widget.onPlayPressed,
                    onToggleFavorite: vm.toggleFavorite,
                    onToggleWatched: () {
                      unawaited(
                        _toggleItemPlayedMark(
                          item: item,
                          currentPlayed: watched,
                        ),
                      );
                    },
                    language: widget.language,
                    onLaunchExternalMpv: () {
                      unawaited(
                        _launchExternalMpv(
                          item: item,
                          trackState: trackState,
                        ),
                      );
                    },
                    onSelectVideo: (value) {
                      setState(() {
                        _selectedMediaSourceId = value;
                        _selectedAudioStreamIndex = null;
                        _selectedSubtitleStreamIndex = -1;
                      });
                    },
                    onSelectAudio: (value) {
                      setState(() {
                        _selectedAudioStreamIndex = int.tryParse(value);
                      });
                    },
                    onSelectSubtitle: (value) {
                      setState(() {
                        _selectedSubtitleStreamIndex =
                            value == 'off' ? -1 : (int.tryParse(value) ?? -1);
                      });
                    },
                  ),
                ),
              ),
              if ((vm.error ?? '').trim().isNotEmpty) ...[
                const SliverToBoxAdapter(child: SizedBox(height: 16)),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: _ErrorBanner(message: vm.error!),
                  ),
                ),
              ],
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
              if (!isMovie) ...[
                if (vm.seasons.isNotEmpty) ...[
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: _SeasonsSection(
                        title: _dtr(
                          language: widget.language,
                          zh: '\u5b63\u5ea6\u9009\u62e9',
                          en: 'Seasons',
                        ),
                        seasons: vm.seasons,
                        currentSeasonId: _currentSeasonIdFor(item, vm),
                        access: vm.access,
                        language: widget.language,
                        onTap: widget.onOpenItem == null
                            ? null
                            : (season) => widget.onOpenItem!(season, vm.server),
                      ),
                    ),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 20)),
                ],
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: _SeasonEpisodesSection(
                      title: _seasonSectionTitle(
                        item,
                        language: widget.language,
                      ),
                      episodes: vm.episodes,
                      episodesLoading: vm.episodesLoading,
                      currentItemId: item.id,
                      access: vm.access,
                      language: widget.language,
                      headerTrailing: _buildJumpFields(
                        colors: colors,
                        vm: vm,
                      ),
                      onTap: widget.onOpenItem == null
                          ? null
                          : (entry) => widget.onOpenItem!(entry, vm.server),
                    ),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 20)),
              ],
              if (vm.people.isNotEmpty) ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: _PeopleSection(
                      people: vm.people,
                      access: vm.access,
                      language: widget.language,
                      onTapPerson: (person) {
                        final id = person.id.trim();
                        if (id.isEmpty) return;
                        Navigator.of(context).push(
                          buildDesktopPageRoute(
                            transition: DesktopPageTransitionStyle.push,
                            builder: (_) => DesktopPersonPage(
                              appState: vm.appState,
                              server: vm.server,
                              personId: id,
                              seedName: person.name,
                              language: widget.language,
                              onOpenItem: widget.onOpenItem,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 20)),
              ],
              if (vm.similar.isNotEmpty) ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: _SimilarSection(
                      items: vm.similar,
                      access: vm.access,
                      language: widget.language,
                      onTap: widget.onOpenItem == null
                          ? null
                          : (entry) => widget.onOpenItem!(entry, vm.server),
                    ),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 20)),
              ],
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: _ExternalLinksSection(
                    links: links,
                    language: widget.language,
                    onOpenLink: _openExternalLink,
                  ),
                ),
              ),
              if (showMediaInfo) ...[
                const SliverToBoxAdapter(child: SizedBox(height: 20)),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: _MediaInfoSection(
                      item: item,
                      selectedSource: trackState.selectedSource,
                      selectedAudio: trackState.selectedAudio,
                      selectedSubtitle: trackState.selectedSubtitle,
                      subtitleStreams: trackState.subtitleStreams,
                      language: widget.language,
                    ),
                  ),
                ),
              ],
              const SliverToBoxAdapter(child: SizedBox(height: 28)),
            ],
          ),
        );
      },
    );
  }

  _TrackSelectionState _resolveTrackSelection({
    required MediaItem item,
    required PlaybackInfoResult? playbackInfo,
  }) {
    final sources = _playbackSources(playbackInfo);
    if (sources.isEmpty) {
      return _TrackSelectionState(
        selectedSource: null,
        selectedAudio: null,
        selectedSubtitle: null,
        subtitleStreams: const [],
        selectedVideoValue: '',
        selectedAudioValue: '',
        selectedSubtitleValue: 'off',
        videoDisplay: _fallbackVideoLabel(item),
        audioDisplay: _t(
          zh: '\u9ed8\u8ba4\u97f3\u9891',
          en: 'Default audio',
        ),
        subtitleDisplay: _t(
          zh: '\u5173\u95ed',
          en: 'Off',
        ),
        videoOptions: const [],
        audioOptions: const [],
        subtitleOptions: [
          DropdownOption(
            value: 'off',
            label: _t(
              zh: '\u5173\u95ed',
              en: 'Off',
            ),
          ),
        ],
      );
    }

    var resolvedSource = _resolveSourceFromSelection(
      sources: sources,
      selectedValue: _selectedMediaSourceId,
    );
    resolvedSource ??= sources.first;
    final sourceIndex = sources.indexOf(resolvedSource);
    final selectedVideoValue = _sourceOptionValue(resolvedSource, sourceIndex);

    final videoOptions = <DropdownOption>[];
    for (var i = 0; i < sources.length; i++) {
      final source = sources[i];
      videoOptions.add(
        DropdownOption(
          value: _sourceOptionValue(source, i),
          label: _mediaSourceLabel(source, fallback: _fallbackVideoLabel(item)),
        ),
      );
    }

    final audioStreams = _mediaStreamsByType(resolvedSource, 'audio');
    final subtitleStreams = _mediaStreamsByType(resolvedSource, 'subtitle');

    Map<String, dynamic>? selectedAudio;
    if (_selectedAudioStreamIndex != null) {
      selectedAudio =
          _findStreamByIndex(audioStreams, _selectedAudioStreamIndex);
    }
    selectedAudio ??= audioStreams.isEmpty ? null : audioStreams.first;

    final selectedAudioIndex = _asInt(selectedAudio?['Index']);
    final selectedAudioValue =
        selectedAudioIndex == null ? '' : selectedAudioIndex.toString();

    final audioOptions = <DropdownOption>[
      for (final stream in audioStreams)
        DropdownOption(
          value: (_asInt(stream['Index']) ?? -1).toString(),
          label: _audioStreamLabel(stream),
        ),
    ];

    final subtitleOptions = <DropdownOption>[
      DropdownOption(
        value: 'off',
        label: _t(
          zh: '\u5173\u95ed',
          en: 'Off',
        ),
      ),
      for (final stream in subtitleStreams)
        DropdownOption(
          value: (_asInt(stream['Index']) ?? -1).toString(),
          label: _subtitleStreamLabel(stream),
        ),
    ];

    Map<String, dynamic>? selectedSubtitle;
    String selectedSubtitleValue = 'off';
    if (_selectedSubtitleStreamIndex >= 0) {
      selectedSubtitle =
          _findStreamByIndex(subtitleStreams, _selectedSubtitleStreamIndex);
      if (selectedSubtitle != null) {
        selectedSubtitleValue = _selectedSubtitleStreamIndex.toString();
      }
    }

    return _TrackSelectionState(
      selectedSource: resolvedSource,
      selectedAudio: selectedAudio,
      selectedSubtitle: selectedSubtitle,
      subtitleStreams: subtitleStreams,
      selectedVideoValue: selectedVideoValue,
      selectedAudioValue: selectedAudioValue,
      selectedSubtitleValue: selectedSubtitleValue,
      videoDisplay: _mediaSourceLabel(resolvedSource,
          fallback: _fallbackVideoLabel(item)),
      audioDisplay: selectedAudio == null
          ? _t(
              zh: '\u9ed8\u8ba4\u97f3\u9891',
              en: 'Default audio',
            )
          : _audioStreamLabel(selectedAudio),
      subtitleDisplay: selectedSubtitle == null
          ? _t(
              zh: '\u5173\u95ed',
              en: 'Off',
            )
          : _subtitleStreamLabel(selectedSubtitle),
      videoOptions: videoOptions,
      audioOptions: audioOptions,
      subtitleOptions: subtitleOptions,
    );
  }
}

class _HeroPanel extends StatelessWidget {
  const _HeroPanel({
    required this.item,
    required this.access,
    required this.posterKey,
    required this.posterVisible,
    this.onPosterReady,
    this.posterSnapshotImage,
    this.useSharedPosterOverlay = false,
    required this.language,
    required this.watched,
    required this.isFavorite,
    required this.trackState,
    required this.showTrackSelectors,
    required this.onPlay,
    required this.onToggleFavorite,
    required this.onToggleWatched,
    required this.onLaunchExternalMpv,
    required this.onSelectVideo,
    required this.onSelectAudio,
    required this.onSelectSubtitle,
  });

  final MediaItem item;
  final ServerAccess? access;
  final Key? posterKey;
  final bool posterVisible;
  final VoidCallback? onPosterReady;
  final ui.Image? posterSnapshotImage;
  final bool useSharedPosterOverlay;
  final DesktopUiLanguage language;
  final bool watched;
  final bool isFavorite;
  final _TrackSelectionState trackState;
  final bool showTrackSelectors;
  final VoidCallback? onPlay;
  final VoidCallback? onToggleFavorite;
  final VoidCallback onToggleWatched;
  final VoidCallback onLaunchExternalMpv;
  final ValueChanged<String> onSelectVideo;
  final ValueChanged<String> onSelectAudio;
  final ValueChanged<String> onSelectSubtitle;

  @override
  Widget build(BuildContext context) {
    final colors = _EpisodeDetailColors.of(context);
    final backdropUrl = _imageUrl(
      access: access,
      item: item,
      type: 'Backdrop',
      maxWidth: 1920,
    );
    final posterUrl = _imageUrl(
      access: access,
      item: item,
      type: 'Primary',
      maxWidth: 920,
    );
    final episodeMark = _episodeMark(item);
    final subtitle = _subtitleLine(item);
    final isEpisode = item.type.trim().toLowerCase() == 'episode';
    final metadata = <_MetaValue>[
      _MetaValue(
        icon: Icons.calendar_month_outlined,
        text: _formatDate(item.premiereDate),
      ),
      _MetaValue(
        icon: Icons.schedule_rounded,
        text: _formatRuntime(
          item.runTimeTicks,
          language: language,
        ),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final verticalLayout = maxWidth < 800;
        final episodePosterWidth = verticalLayout
            ? (maxWidth - 56).clamp(220.0, 520.0).toDouble()
            : (maxWidth < 1200 ? 340.0 : 400.0);
        final posterWidth =
            isEpisode ? episodePosterWidth : (maxWidth < 1000 ? 260.0 : 320.0);
        final posterHeight =
            isEpisode ? posterWidth * 9 / 16 : posterWidth * 3 / 2;

        return ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Container(
            decoration: BoxDecoration(
              color: colors.surface,
              boxShadow: [
                BoxShadow(
                  color: colors.shadow,
                  blurRadius: 20,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Stack(
              children: [
                Positioned.fill(
                  child: backdropUrl == null || backdropUrl.isEmpty
                      ? DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                colors.heroFallbackStart,
                                colors.heroFallbackEnd,
                              ],
                            ),
                          ),
                        )
                      : ImageFiltered(
                          imageFilter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                          child: CachedNetworkImage(
                            imageUrl: backdropUrl,
                            cacheManager: CoverCacheManager.instance,
                            httpHeaders: {
                              'User-Agent': LinHttpClientFactory.userAgent,
                            },
                            fit: BoxFit.cover,
                            errorWidget: (_, __, ___) =>
                                const SizedBox.shrink(),
                            placeholder: (_, __) => const SizedBox.shrink(),
                          ),
                        ),
                ),
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          colors.heroOverlayTop,
                          colors.heroOverlayMiddle,
                          colors.heroOverlayBottom,
                        ],
                        stops: [0, 0.4, 1],
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(28),
                  child: verticalLayout
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _PosterCard(
                              key: posterKey,
                              imageUrl: posterUrl,
                              fallbackLabel: item.name,
                              width: posterWidth,
                              height: posterHeight,
                              visible: posterVisible,
                              onReady: onPosterReady,
                              transitionImage: posterSnapshotImage,
                              useSharedPosterOverlay: useSharedPosterOverlay,
                            ),
                            const SizedBox(height: 22),
                            _HeroInfoColumn(
                              item: item,
                              episodeMark: episodeMark,
                              subtitle: subtitle,
                              metadata: metadata,
                              language: language,
                              watched: watched,
                              isFavorite: isFavorite,
                              trackState: trackState,
                              showTrackSelectors: showTrackSelectors,
                              onPlay: onPlay,
                              onToggleFavorite: onToggleFavorite,
                              onToggleWatched: onToggleWatched,
                              onLaunchExternalMpv: onLaunchExternalMpv,
                              onSelectVideo: onSelectVideo,
                              onSelectAudio: onSelectAudio,
                              onSelectSubtitle: onSelectSubtitle,
                            ),
                          ],
                        )
                      : Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _PosterCard(
                              key: posterKey,
                              imageUrl: posterUrl,
                              fallbackLabel: item.name,
                              width: posterWidth,
                              height: posterHeight,
                              visible: posterVisible,
                              onReady: onPosterReady,
                              transitionImage: posterSnapshotImage,
                              useSharedPosterOverlay: useSharedPosterOverlay,
                            ),
                            const SizedBox(width: 32),
                            Expanded(
                              child: _HeroInfoColumn(
                                item: item,
                                episodeMark: episodeMark,
                                subtitle: subtitle,
                                metadata: metadata,
                                language: language,
                                watched: watched,
                                isFavorite: isFavorite,
                                trackState: trackState,
                                showTrackSelectors: showTrackSelectors,
                                onPlay: onPlay,
                                onToggleFavorite: onToggleFavorite,
                                onToggleWatched: onToggleWatched,
                                onLaunchExternalMpv: onLaunchExternalMpv,
                                onSelectVideo: onSelectVideo,
                                onSelectAudio: onSelectAudio,
                                onSelectSubtitle: onSelectSubtitle,
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
    );
  }
}

class _HeroInfoColumn extends StatelessWidget {
  const _HeroInfoColumn({
    required this.item,
    required this.episodeMark,
    required this.subtitle,
    required this.metadata,
    required this.language,
    required this.watched,
    required this.isFavorite,
    required this.trackState,
    required this.showTrackSelectors,
    required this.onPlay,
    required this.onToggleFavorite,
    required this.onToggleWatched,
    required this.onLaunchExternalMpv,
    required this.onSelectVideo,
    required this.onSelectAudio,
    required this.onSelectSubtitle,
  });

  final MediaItem item;
  final String episodeMark;
  final String subtitle;
  final List<_MetaValue> metadata;
  final DesktopUiLanguage language;
  final bool watched;
  final bool isFavorite;
  final _TrackSelectionState trackState;
  final bool showTrackSelectors;
  final VoidCallback? onPlay;
  final VoidCallback? onToggleFavorite;
  final VoidCallback onToggleWatched;
  final VoidCallback onLaunchExternalMpv;
  final ValueChanged<String> onSelectVideo;
  final ValueChanged<String> onSelectAudio;
  final ValueChanged<String> onSelectSubtitle;

  @override
  Widget build(BuildContext context) {
    final colors = _EpisodeDetailColors.of(context);
    final type = item.type.trim().toLowerCase();
    final rawTitle = item.name.trim();
    final rawSeriesTitle = item.seriesName.trim();
    final seasonNo = item.seasonNumber ?? item.episodeNumber ?? 0;

    final title = (type == 'season' && rawSeriesTitle.isNotEmpty)
        ? rawSeriesTitle
        : (rawTitle.isEmpty
            ? _dtr(
                language: language,
                zh: '\u672a\u547d\u540d\u5267\u96c6',
                en: 'Untitled Episode',
              )
            : rawTitle);

    final subtitleLine = (type == 'season' && rawSeriesTitle.isNotEmpty)
        ? (() {
            final labels = <String>[];
            if (seasonNo > 0) {
              labels.add(
                _dtr(
                  language: language,
                  zh: '\u7b2c$seasonNo\u5b63',
                  en: 'Season $seasonNo',
                ),
              );
            }
            final seasonName = rawTitle;
            final computed = labels.isEmpty ? '' : labels.first;
            if (seasonName.isNotEmpty &&
                seasonName != rawSeriesTitle &&
                seasonName.toLowerCase() != computed.toLowerCase()) {
              labels.add(seasonName);
            }
            return labels.join(' \u00b7 ').trim();
          })()
        : <String>[
            if (episodeMark.trim().isNotEmpty) episodeMark.trim(),
            if (subtitle.trim().isNotEmpty) subtitle.trim(),
          ].join(' - ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.w700,
            color: colors.textPrimary,
            height: 1.15,
          ),
        ),
        if (subtitleLine.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            subtitleLine,
            style: TextStyle(
              fontSize: 14,
              color: colors.textSecondary,
            ),
          ),
        ],
        const SizedBox(height: 12),
        Wrap(
          spacing: 16,
          runSpacing: 8,
          children: [
            for (final item in metadata) _MetaInfoLabel(item: item),
          ],
        ),
        if (showTrackSelectors) ...[
          const SizedBox(height: 18),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _TechDropdown(
                label: _dtr(
                  language: language,
                  zh: '\u89c6\u9891',
                  en: 'Video',
                ),
                value: trackState.videoDisplay,
                icon: Icons.videocam_outlined,
                options: trackState.videoOptions,
                selectedValue: trackState.selectedVideoValue,
                onSelected: onSelectVideo,
              ),
              _TechDropdown(
                label: _dtr(
                  language: language,
                  zh: '\u97f3\u9891',
                  en: 'Audio',
                ),
                value: trackState.audioDisplay,
                icon: Icons.audiotrack_outlined,
                options: trackState.audioOptions,
                selectedValue: trackState.selectedAudioValue,
                onSelected: onSelectAudio,
              ),
              _TechDropdown(
                label: _dtr(
                  language: language,
                  zh: '\u5b57\u5e55',
                  en: 'Subtitle',
                ),
                value: trackState.subtitleDisplay,
                icon: Icons.subtitles_outlined,
                options: trackState.subtitleOptions,
                selectedValue: trackState.selectedSubtitleValue,
                onSelected: onSelectSubtitle,
              ),
            ],
          ),
        ],
        SizedBox(height: showTrackSelectors ? 22 : 18),
        _ActionButtons(
          language: language,
          watched: watched,
          isFavorite: isFavorite,
          onPlay: onPlay,
          onToggleWatched: onToggleWatched,
          onToggleFavorite: onToggleFavorite,
          onLaunchExternalMpv: onLaunchExternalMpv,
        ),
        const SizedBox(height: 18),
        _OverviewText(
          language: language,
          overview: item.overview,
        ),
      ],
    );
  }
}

class _PosterCard extends StatefulWidget {
  const _PosterCard({
    super.key,
    required this.imageUrl,
    required this.fallbackLabel,
    required this.width,
    required this.height,
    this.visible = true,
    this.onReady,
    this.transitionImage,
    this.useSharedPosterOverlay = false,
  });

  final String? imageUrl;
  final String fallbackLabel;
  final double width;
  final double height;
  final bool visible;
  final VoidCallback? onReady;
  final ui.Image? transitionImage;
  final bool useSharedPosterOverlay;

  @override
  State<_PosterCard> createState() => _PosterCardState();
}

class _PosterCardState extends State<_PosterCard> {
  bool _readyReported = false;

  @override
  void didUpdateWidget(covariant _PosterCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldImageUrl = (oldWidget.imageUrl ?? '').trim();
    final newImageUrl = (widget.imageUrl ?? '').trim();
    if (oldImageUrl != newImageUrl ||
        oldWidget.fallbackLabel != widget.fallbackLabel ||
        oldWidget.transitionImage != widget.transitionImage) {
      _readyReported = false;
    }
  }

  void _scheduleReadyNotification() {
    if (_readyReported) return;
    _readyReported = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.onReady?.call();
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = _EpisodeDetailColors.of(context);
    final imageUrl = (widget.imageUrl ?? '').trim();
    if (widget.useSharedPosterOverlay) {
      return SizedBox(
        width: widget.width,
        height: widget.height,
      );
    }
    final hasTransitionImage =
        widget.transitionImage != null && !widget.visible;
    final liveLayerOpacity =
        widget.visible || widget.transitionImage == null ? 1.0 : 0.0;
    if (imageUrl.isEmpty) {
      _scheduleReadyNotification();
    }
    return Opacity(
      opacity: 1,
      child: Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: colors.shadow,
              blurRadius: 20,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (hasTransitionImage)
                RawImage(
                  image: widget.transitionImage,
                  fit: BoxFit.cover,
                  filterQuality: FilterQuality.high,
                ),
              Opacity(
                opacity: liveLayerOpacity,
                child: imageUrl.isEmpty
                    ? _FallbackImage(label: widget.fallbackLabel)
                    : Image(
                        image: CachedNetworkImageProvider(
                          imageUrl,
                          cacheManager: CoverCacheManager.instance,
                          headers: {
                            'User-Agent': LinHttpClientFactory.userAgent,
                          },
                        ),
                        fit: BoxFit.cover,
                        gaplessPlayback: true,
                        filterQuality: FilterQuality.high,
                        frameBuilder: (context, child, frame, wasSyncLoaded) {
                          if (wasSyncLoaded || frame != null) {
                            _scheduleReadyNotification();
                          }
                          return child;
                        },
                        errorBuilder: (context, error, stackTrace) {
                          _scheduleReadyNotification();
                          return _FallbackImage(label: widget.fallbackLabel);
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FallbackImage extends StatelessWidget {
  const _FallbackImage({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = _EpisodeDetailColors.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colors.fallbackImageStart,
            colors.fallbackImageEnd,
          ],
        ),
      ),
      child: Center(
        child: Icon(
          Icons.image_outlined,
          color: colors.textTertiary,
          size: 28,
        ),
      ),
    );
  }
}

class _MetaInfoLabel extends StatelessWidget {
  const _MetaInfoLabel({required this.item});

  final _MetaValue item;

  @override
  Widget build(BuildContext context) {
    final colors = _EpisodeDetailColors.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          item.icon,
          size: 16,
          color: colors.textBody,
        ),
        const SizedBox(width: 6),
        Text(
          item.text,
          style: TextStyle(
            fontSize: 14,
            color: colors.textBody,
          ),
        ),
      ],
    );
  }
}

class _OverviewText extends StatefulWidget {
  const _OverviewText({
    required this.language,
    required this.overview,
  });

  final DesktopUiLanguage language;
  final String overview;

  @override
  State<_OverviewText> createState() => _OverviewTextState();
}

class _OverviewTextState extends State<_OverviewText> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final colors = _EpisodeDetailColors.of(context);
    final text = widget.overview.trim().isEmpty
        ? _dtr(
            language: widget.language,
            zh: '\u6682\u65e0\u5267\u60c5\u7b80\u4ecb\u3002',
            en: 'No overview available.',
          )
        : widget.overview.trim();
    final canExpand = text.length > 90;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          text,
          maxLines: _expanded ? null : 3,
          overflow: _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 15,
            color: colors.textBody,
            height: 1.6,
          ),
        ),
        if (canExpand) ...[
          const SizedBox(height: 4),
          GestureDetector(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Text(
              _expanded
                  ? _dtr(
                      language: widget.language,
                      zh: '\u6536\u8d77',
                      en: 'Collapse',
                    )
                  : _dtr(
                      language: widget.language,
                      zh: '\u66f4\u591a',
                      en: 'More',
                    ),
              style: TextStyle(
                fontSize: 13,
                color: colors.textTertiary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _ActionButtons extends StatelessWidget {
  const _ActionButtons({
    required this.language,
    required this.watched,
    required this.isFavorite,
    required this.onPlay,
    required this.onToggleWatched,
    required this.onToggleFavorite,
    required this.onLaunchExternalMpv,
  });

  final DesktopUiLanguage language;
  final bool watched;
  final bool isFavorite;
  final VoidCallback? onPlay;
  final VoidCallback onToggleWatched;
  final VoidCallback? onToggleFavorite;
  final VoidCallback onLaunchExternalMpv;

  @override
  Widget build(BuildContext context) {
    final colors = _EpisodeDetailColors.of(context);
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        SizedBox(
          height: _DetailActionButtonTokens.height,
          child: ElevatedButton.icon(
            onPressed: onPlay,
            icon: const Icon(
              Icons.play_arrow_rounded,
              size: _DetailActionButtonTokens.iconSize,
            ),
            label: Text(
              _dtr(
                language: language,
                zh: '\u64ad\u653e',
                en: 'Play',
              ),
            ),
            style: ButtonStyle(
              backgroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.hovered)) {
                  return colors.primaryHover;
                }
                return colors.primary;
              }),
              foregroundColor:
                  const WidgetStatePropertyAll<Color>(Colors.white),
              elevation: const WidgetStatePropertyAll<double>(0),
              shape: WidgetStatePropertyAll(
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
              ),
              padding: const WidgetStatePropertyAll(
                EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: _DetailActionButtonTokens.verticalPadding,
                ),
              ),
              minimumSize: const WidgetStatePropertyAll(
                Size(0, _DetailActionButtonTokens.height),
              ),
            ),
          ),
        ),
        SizedBox(
          height: _DetailActionButtonTokens.height,
          child: OutlinedButton.icon(
            onPressed: onToggleWatched,
            icon: const Icon(
              Icons.check_rounded,
              size: _DetailActionButtonTokens.iconSize,
            ),
            label: Text(
              watched
                  ? _dtr(
                      language: language,
                      zh: '\u5df2\u64ad\u653e',
                      en: 'Watched',
                    )
                  : _dtr(
                      language: language,
                      zh: '\u6807\u8bb0\u5df2\u64ad\u653e',
                      en: 'Mark watched',
                    ),
            ),
            style: ButtonStyle(
              side: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.hovered)) {
                  return BorderSide(
                    color: colors.successHoverBorder,
                    width: 1.3,
                  );
                }
                return BorderSide(color: colors.success);
              }),
              foregroundColor: WidgetStatePropertyAll<Color>(colors.success),
              backgroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.hovered)) {
                  return colors.successHoverBackground;
                }
                return watched ? colors.successBackground : colors.surface;
              }),
              shape: WidgetStatePropertyAll(
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
              ),
              padding: const WidgetStatePropertyAll(
                EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: _DetailActionButtonTokens.verticalPadding,
                ),
              ),
              minimumSize: const WidgetStatePropertyAll(
                Size(0, _DetailActionButtonTokens.height),
              ),
            ),
          ),
        ),
        _CircleIconButton(
          icon: isFavorite
              ? Icons.favorite_rounded
              : Icons.favorite_border_rounded,
          active: isFavorite,
          onTap: onToggleFavorite,
        ),
        PopupMenuButton<String>(
          padding: EdgeInsets.zero,
          tooltip: _dtr(
            language: language,
            zh: '\u66f4\u591a',
            en: 'More',
          ),
          onSelected: (value) {
            switch (value) {
              case 'mark_unwatched':
                if (watched) onToggleWatched();
                break;
              case 'mark_watched':
                if (!watched) onToggleWatched();
                break;
              case 'launch_external_mpv':
                onLaunchExternalMpv();
                break;
              default:
                break;
            }
          },
          itemBuilder: (context) => [
            PopupMenuItem(
              value: 'add_list',
              child: Text(
                _dtr(
                  language: language,
                  zh: '\u6dfb\u52a0\u5230\u5217\u8868',
                  en: 'Add to list',
                ),
              ),
            ),
            PopupMenuItem(
              value: watched ? 'mark_unwatched' : 'mark_watched',
              child: Text(
                watched
                    ? _dtr(
                        language: language,
                        zh: '\u6807\u8bb0\u4e3a\u672a\u64ad\u653e',
                        en: 'Mark unwatched',
                      )
                    : _dtr(
                        language: language,
                        zh: '\u6807\u8bb0\u4e3a\u5df2\u64ad\u653e',
                        en: 'Mark watched',
                      ),
              ),
            ),
            PopupMenuItem(
              value: 'launch_external_mpv',
              child: Text(
                _dtr(
                  language: language,
                  zh: '\u8c03\u7528\u5916\u90e8 MPV',
                  en: 'Open in external MPV',
                ),
              ),
            ),
          ],
          child: const _CircleIconButton(
            icon: Icons.more_horiz_rounded,
            active: false,
          ),
        ),
      ],
    );
  }
}

class _CircleIconButton extends StatefulWidget {
  const _CircleIconButton({
    required this.icon,
    required this.active,
    this.onTap,
  });

  final IconData icon;
  final bool active;
  final VoidCallback? onTap;

  @override
  State<_CircleIconButton> createState() => _CircleIconButtonState();
}

class _CircleIconButtonState extends State<_CircleIconButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    const buttonSize = _DetailActionButtonTokens.height;
    final colors = _EpisodeDetailColors.of(context);
    final color = widget.active ? colors.heartActive : colors.textSecondary;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: widget.onTap != null
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          width: buttonSize,
          height: buttonSize,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _hovered ? colors.surfaceHover : colors.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _hovered ? colors.primary : colors.border,
            ),
          ),
          child: Icon(
            widget.icon,
            size: _DetailActionButtonTokens.iconSize,
            color: color,
          ),
        ),
      ),
    );
  }
}

class _DetailActionButtonTokens {
  static const double verticalPadding = 14.0;
  static const double iconSize = 24.0;
  static const double height = verticalPadding * 2 + iconSize;
}

class _TechDropdown extends StatefulWidget {
  const _TechDropdown({
    required this.label,
    required this.value,
    required this.icon,
    required this.options,
    required this.selectedValue,
    required this.onSelected,
  });

  final String label;
  final String value;
  final IconData icon;
  final List<DropdownOption> options;
  final String selectedValue;
  final ValueChanged<String> onSelected;

  @override
  State<_TechDropdown> createState() => _TechDropdownState();
}

class _TechDropdownState extends State<_TechDropdown> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = _EpisodeDetailColors.of(context);
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: PopupMenuButton<String>(
        tooltip: '${widget.label} options',
        onSelected: widget.onSelected,
        itemBuilder: (context) {
          if (widget.options.isEmpty) {
            return const [
              PopupMenuItem<String>(
                enabled: false,
                value: '',
                child: Text('No options'),
              ),
            ];
          }
          return widget.options
              .map(
                (option) => PopupMenuItem<String>(
                  value: option.value,
                  child: Row(
                    children: [
                      if (option.value == widget.selectedValue) ...[
                        const Icon(Icons.check_rounded, size: 16),
                        const SizedBox(width: 8),
                      ],
                      Expanded(child: Text(option.label)),
                    ],
                  ),
                ),
              )
              .toList(growable: false);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: _hovered ? colors.surfaceHover : colors.surface,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: _hovered ? colors.primary : colors.border,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon, size: 16, color: colors.textTertiary),
              const SizedBox(width: 6),
              Text(
                '${widget.label}: ',
                style: TextStyle(
                  fontSize: 13,
                  color: colors.textTertiary,
                ),
              ),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 220),
                child: Text(
                  widget.value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 18,
                color: colors.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SeasonsSection extends StatelessWidget {
  const _SeasonsSection({
    required this.title,
    required this.seasons,
    required this.currentSeasonId,
    required this.access,
    required this.language,
    this.onTap,
  });

  final String title;
  final List<MediaItem> seasons;
  final String? currentSeasonId;
  final ServerAccess? access;
  final DesktopUiLanguage language;
  final ValueChanged<MediaItem>? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = _EpisodeDetailColors.of(context);
    final list = List<MediaItem>.from(seasons);
    list.sort((a, b) {
      final aNo = a.seasonNumber ?? a.episodeNumber ?? 0;
      final bNo = b.seasonNumber ?? b.episodeNumber ?? 0;
      final diff = aNo.compareTo(bNo);
      if (diff != 0) return diff;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });

    return _SectionSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: 16),
          if (list.isEmpty)
            SizedBox(
              height: 120,
              child: Center(
                child: Text(
                  _dtr(
                    language: language,
                    zh: '\u6682\u65e0\u5b63\u5ea6',
                    en: 'No seasons',
                  ),
                  style: TextStyle(color: colors.textSecondary),
                ),
              ),
            )
          else
            _SeasonHorizontalList(
              seasons: list,
              currentSeasonId: currentSeasonId,
              access: access,
              language: language,
              onTap: onTap,
            ),
        ],
      ),
    );
  }
}

class _SeasonHorizontalList extends StatefulWidget {
  const _SeasonHorizontalList({
    required this.seasons,
    required this.currentSeasonId,
    required this.access,
    required this.language,
    this.onTap,
  });

  final List<MediaItem> seasons;
  final String? currentSeasonId;
  final ServerAccess? access;
  final DesktopUiLanguage language;
  final ValueChanged<MediaItem>? onTap;

  @override
  State<_SeasonHorizontalList> createState() => _SeasonHorizontalListState();
}

class _SeasonHorizontalListState extends State<_SeasonHorizontalList> {
  static const double _kPosterWidth = 124;
  static const double _kPosterHeight = 174;
  static const double _kCardSpacing = 14;
  final ScrollController _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || !_controller.hasClients) return;
    _animateScrollByPointerDelta(controller: _controller, event: event);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _kPosterHeight + 38,
      child: Listener(
        onPointerSignal: _onPointerSignal,
        child: ListView.separated(
          controller: _controller,
          scrollDirection: Axis.horizontal,
          itemCount: widget.seasons.length,
          separatorBuilder: (_, __) => const SizedBox(width: _kCardSpacing),
          itemBuilder: (context, index) {
            final season = widget.seasons[index];
            final seasonNo =
                season.seasonNumber ?? season.episodeNumber ?? (index + 1);
            final label = _dtr(
              language: widget.language,
              zh: '\u7b2c$seasonNo\u5b63',
              en: 'Season $seasonNo',
            );
            final imageUrls = _seasonImageCandidates(
              access: widget.access,
              season: season,
            );
            final isCurrent =
                (widget.currentSeasonId ?? '').trim().isNotEmpty &&
                    season.id == widget.currentSeasonId;
            return _SeasonPosterCard(
              width: _kPosterWidth,
              height: _kPosterHeight,
              season: season,
              label: label,
              imageUrls: imageUrls,
              isCurrent: isCurrent,
              onTap: widget.onTap == null ? null : () => widget.onTap!(season),
            );
          },
        ),
      ),
    );
  }
}

class _SeasonPosterCard extends StatefulWidget {
  const _SeasonPosterCard({
    required this.width,
    required this.height,
    required this.season,
    required this.label,
    required this.imageUrls,
    required this.isCurrent,
    this.onTap,
  });

  final double width;
  final double height;
  final MediaItem season;
  final String label;
  final List<String> imageUrls;
  final bool isCurrent;
  final VoidCallback? onTap;

  @override
  State<_SeasonPosterCard> createState() => _SeasonPosterCardState();
}

class _SeasonPosterCardState extends State<_SeasonPosterCard> {
  bool _hovered = false;
  int _imageIndex = 0;
  bool _switchingImage = false;

  @override
  void didUpdateWidget(covariant _SeasonPosterCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.season.id != widget.season.id ||
        oldWidget.imageUrls.join('|') != widget.imageUrls.join('|')) {
      _imageIndex = 0;
      _switchingImage = false;
    }
  }

  Widget _buildImage() {
    final urls = widget.imageUrls
        .map((entry) => entry.trim())
        .where((entry) => entry.isNotEmpty)
        .toList(growable: false);
    if (urls.isEmpty || _imageIndex >= urls.length) {
      return const _FallbackImage(label: '');
    }

    final imageUrl = urls[_imageIndex];
    return CachedNetworkImage(
      key: ValueKey<String>('season-${widget.season.id}-$imageUrl'),
      imageUrl: imageUrl,
      cacheManager: CoverCacheManager.instance,
      httpHeaders: {'User-Agent': LinHttpClientFactory.userAgent},
      fit: BoxFit.cover,
      placeholder: (_, __) => const SizedBox.shrink(),
      errorWidget: (_, __, ___) {
        if (_imageIndex < urls.length - 1) {
          if (!_switchingImage) {
            _switchingImage = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              setState(() {
                _imageIndex += 1;
                _switchingImage = false;
              });
            });
          }
          return const SizedBox.shrink();
        }
        return const _FallbackImage(label: '');
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = _EpisodeDetailColors.of(context);
    final canTap = widget.onTap != null;
    final borderColor = widget.isCurrent
        ? colors.primary
        : (_hovered ? colors.borderHover : colors.border);
    final borderWidth = widget.isCurrent ? 2.0 : 1.0;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: canTap ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _hovered ? 1.02 : 1,
          duration: const Duration(milliseconds: 130),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: widget.width,
                height: widget.height,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: borderColor, width: borderWidth),
                  boxShadow: [
                    BoxShadow(
                      color: colors.shadow,
                      blurRadius: 10,
                      offset: Offset(0, 3),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: _buildImage(),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                widget.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: widget.isCurrent
                      ? colors.textPrimary
                      : colors.textSecondary,
                  fontWeight:
                      widget.isCurrent ? FontWeight.w700 : FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SeasonEpisodesSection extends StatelessWidget {
  const _SeasonEpisodesSection({
    required this.title,
    required this.episodes,
    required this.episodesLoading,
    required this.currentItemId,
    required this.access,
    required this.language,
    this.headerTrailing,
    this.onTap,
  });

  final String title;
  final List<MediaItem> episodes;
  final bool episodesLoading;
  final String currentItemId;
  final ServerAccess? access;
  final DesktopUiLanguage language;
  final Widget? headerTrailing;
  final ValueChanged<MediaItem>? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = _EpisodeDetailColors.of(context);
    return _SectionSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: colors.textPrimary,
                  ),
                ),
              ),
              if (headerTrailing != null) ...[
                const SizedBox(width: 12),
                headerTrailing!,
              ],
            ],
          ),
          const SizedBox(height: 16),
          if (episodes.isEmpty)
            SizedBox(
              height: 112,
              child: Center(
                child: episodesLoading
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: colors.textSecondary,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            _dtr(
                              language: language,
                              zh: '\u6b63\u5728\u52a0\u8f7d\u5267\u96c6\u2026',
                              en: 'Loading episodes...',
                            ),
                            style: TextStyle(color: colors.textSecondary),
                          ),
                        ],
                      )
                    : Text(
                        _dtr(
                          language: language,
                          zh: '\u6682\u65e0\u5267\u96c6',
                          en: 'No episodes',
                        ),
                        style: TextStyle(color: colors.textSecondary),
                      ),
              ),
            )
          else
            _EpisodeHorizontalList(
              episodes: episodes,
              currentItemId: currentItemId,
              access: access,
              language: language,
              onTap: onTap,
            ),
        ],
      ),
    );
  }
}

class _EpisodeHorizontalList extends StatefulWidget {
  const _EpisodeHorizontalList({
    required this.episodes,
    required this.currentItemId,
    required this.access,
    required this.language,
    this.onTap,
  });

  final List<MediaItem> episodes;
  final String currentItemId;
  final ServerAccess? access;
  final DesktopUiLanguage language;
  final ValueChanged<MediaItem>? onTap;

  @override
  State<_EpisodeHorizontalList> createState() => _EpisodeHorizontalListState();
}

class _EpisodeHorizontalListState extends State<_EpisodeHorizontalList> {
  static const double _kCardWidth = 200;
  static const double _kCardSpacing = 16;
  final ScrollController _controller = ScrollController();
  bool _canSlideLeft = false;
  bool _canSlideRight = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_updateScrollButtons);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _centerCurrentEpisode(animate: false);
      _updateScrollButtons();
    });
  }

  @override
  void didUpdateWidget(covariant _EpisodeHorizontalList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentItemId != widget.currentItemId ||
        oldWidget.episodes.length != widget.episodes.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _centerCurrentEpisode();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || !_controller.hasClients) return;
    _animateScrollByPointerDelta(controller: _controller, event: event);
  }

  void _updateScrollButtons() {
    if (!_controller.hasClients) return;
    final position = _controller.position;
    final canSlideLeft = position.pixels < position.maxScrollExtent - 0.5;
    final canSlideRight = position.pixels > position.minScrollExtent + 0.5;
    if (canSlideLeft == _canSlideLeft && canSlideRight == _canSlideRight) {
      return;
    }
    if (!mounted) return;
    setState(() {
      _canSlideLeft = canSlideLeft;
      _canSlideRight = canSlideRight;
    });
  }

  double _slideDelta() {
    if (!_controller.hasClients) return (_kCardWidth + _kCardSpacing) * 3;
    final viewport = _controller.position.viewportDimension;
    return math.max((_kCardWidth + _kCardSpacing) * 2, viewport * 0.85);
  }

  void _slideBy(double delta) {
    if (!_controller.hasClients) return;
    final position = _controller.position;
    final target = (_controller.offset + delta).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    _controller.animateTo(
      target,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
    );
  }

  void _centerCurrentEpisode({bool animate = true}) {
    if (!_controller.hasClients) return;
    final index =
        widget.episodes.indexWhere((entry) => entry.id == widget.currentItemId);
    if (index < 0) return;
    _centerIndex(index, animate: animate);
  }

  void _centerIndex(int index, {bool animate = true}) {
    if (!_controller.hasClients) return;
    final viewport = _controller.position.viewportDimension;
    final itemCenter =
        index * (_kCardWidth + _kCardSpacing) + (_kCardWidth / 2);
    final target = (itemCenter - (viewport / 2)).clamp(
      _controller.position.minScrollExtent,
      _controller.position.maxScrollExtent,
    );
    if (animate) {
      _controller.animateTo(
        target,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
      return;
    }
    _controller.jumpTo(target);
  }

  @override
  Widget build(BuildContext context) {
    final colors = _EpisodeDetailColors.of(context);
    return SizedBox(
      height: 140,
      child: Row(
        children: [
          IconButton(
            tooltip: _dtr(
              language: widget.language,
              zh: '向左滑动',
              en: 'Slide left',
            ),
            onPressed: _canSlideLeft ? () => _slideBy(_slideDelta()) : null,
            icon: const Icon(Icons.chevron_left_rounded),
            style: IconButton.styleFrom(
              backgroundColor: colors.surface,
              foregroundColor: colors.textSecondary,
              disabledBackgroundColor: colors.surface,
              disabledForegroundColor: colors.textTertiary,
              side: BorderSide(color: colors.border),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Listener(
              onPointerSignal: _onPointerSignal,
              child: ListView.separated(
                controller: _controller,
                scrollDirection: Axis.horizontal,
                itemCount: widget.episodes.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(width: _kCardSpacing),
                itemBuilder: (context, index) {
                  final episode = widget.episodes[index];
                  final imageUrls = _episodeImageCandidates(
                    access: widget.access,
                    episode: episode,
                  );
                  return _EpisodeThumbnailCard(
                    item: episode,
                    imageUrls: imageUrls,
                    language: widget.language,
                    isCurrent: episode.id == widget.currentItemId,
                    onTap: widget.onTap == null
                        ? null
                        : () {
                            _centerIndex(index);
                            widget.onTap!(episode);
                          },
                  );
                },
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: _dtr(
              language: widget.language,
              zh: '向右滑动',
              en: 'Slide right',
            ),
            onPressed: _canSlideRight ? () => _slideBy(-_slideDelta()) : null,
            icon: const Icon(Icons.chevron_right_rounded),
            style: IconButton.styleFrom(
              backgroundColor: colors.surface,
              foregroundColor: colors.textSecondary,
              disabledBackgroundColor: colors.surface,
              disabledForegroundColor: colors.textTertiary,
              side: BorderSide(color: colors.border),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EpisodeThumbnailCard extends StatefulWidget {
  const _EpisodeThumbnailCard({
    required this.item,
    required this.imageUrls,
    required this.language,
    required this.isCurrent,
    this.onTap,
  });

  final MediaItem item;
  final List<String> imageUrls;
  final DesktopUiLanguage language;
  final bool isCurrent;
  final VoidCallback? onTap;

  @override
  State<_EpisodeThumbnailCard> createState() => _EpisodeThumbnailCardState();
}

class _EpisodeThumbnailCardState extends State<_EpisodeThumbnailCard> {
  bool _hovered = false;
  int _imageIndex = 0;
  bool _switchingImage = false;

  @override
  void didUpdateWidget(covariant _EpisodeThumbnailCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.id != widget.item.id ||
        oldWidget.imageUrls.join('|') != widget.imageUrls.join('|')) {
      _imageIndex = 0;
      _switchingImage = false;
    }
  }

  Widget _buildImage() {
    final urls = widget.imageUrls
        .map((entry) => entry.trim())
        .where((entry) => entry.isNotEmpty)
        .toList(growable: false);
    if (urls.isEmpty || _imageIndex >= urls.length) {
      return const _FallbackImage(label: '');
    }

    final imageUrl = urls[_imageIndex];
    return CachedNetworkImage(
      key: ValueKey<String>('episode-${widget.item.id}-$imageUrl'),
      imageUrl: imageUrl,
      cacheManager: CoverCacheManager.instance,
      httpHeaders: {'User-Agent': LinHttpClientFactory.userAgent},
      fit: BoxFit.cover,
      placeholder: (_, __) => const SizedBox.shrink(),
      errorWidget: (_, __, ___) {
        if (_imageIndex < urls.length - 1) {
          if (!_switchingImage) {
            _switchingImage = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              setState(() {
                _imageIndex += 1;
                _switchingImage = false;
              });
            });
          }
          return const SizedBox.shrink();
        }
        return const _FallbackImage(label: '');
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = _EpisodeDetailColors.of(context);
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: widget.onTap != null
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _hovered ? 1.02 : 1,
          duration: const Duration(milliseconds: 130),
          child: Container(
            width: 200,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: widget.isCurrent
                  ? Border.all(color: colors.primary, width: 2)
                  : null,
              boxShadow: [
                BoxShadow(
                  color: colors.shadow,
                  blurRadius: 8,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _buildImage(),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.72),
                          ],
                        ),
                      ),
                      child: Text(
                        _episodeListLabel(
                          widget.item,
                          language: widget.language,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: widget.isCurrent
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                  if (widget.isCurrent)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: colors.primary,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          _dtr(
                            language: widget.language,
                            zh: '\u5f53\u524d',
                            en: 'Now',
                          ),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
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
  }
}

class _PeopleSection extends StatelessWidget {
  const _PeopleSection({
    required this.people,
    required this.access,
    required this.language,
    this.onTapPerson,
  });

  final List<MediaPerson> people;
  final ServerAccess? access;
  final DesktopUiLanguage language;
  final ValueChanged<MediaPerson>? onTapPerson;

  @override
  Widget build(BuildContext context) {
    final colors = _EpisodeDetailColors.of(context);
    return _GradientSectionSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _dtr(
              language: language,
              zh: '\u6f14\u804c\u4eba\u5458',
              en: 'Cast & Crew',
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: 16),
          _PeopleHorizontalList(
            people: people,
            access: access,
            language: language,
            onTapPerson: onTapPerson,
          ),
        ],
      ),
    );
  }
}

class _PeopleHorizontalList extends StatefulWidget {
  const _PeopleHorizontalList({
    required this.people,
    required this.access,
    required this.language,
    this.onTapPerson,
  });

  final List<MediaPerson> people;
  final ServerAccess? access;
  final DesktopUiLanguage language;
  final ValueChanged<MediaPerson>? onTapPerson;

  @override
  State<_PeopleHorizontalList> createState() => _PeopleHorizontalListState();
}

class _PeopleHorizontalListState extends State<_PeopleHorizontalList> {
  static const double _kPosterWidth = 124;
  static const double _kPosterHeight = 174;
  static const double _kCardSpacing = 16;
  final ScrollController _controller = ScrollController();
  bool _canSlideLeft = false;
  bool _canSlideRight = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_updateScrollButtons);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _updateScrollButtons();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || !_controller.hasClients) return;
    _animateScrollByPointerDelta(controller: _controller, event: event);
  }

  void _updateScrollButtons() {
    if (!_controller.hasClients) return;
    final position = _controller.position;
    final canSlideLeft = position.pixels < position.maxScrollExtent - 0.5;
    final canSlideRight = position.pixels > position.minScrollExtent + 0.5;
    if (canSlideLeft == _canSlideLeft && canSlideRight == _canSlideRight) {
      return;
    }
    if (!mounted) return;
    setState(() {
      _canSlideLeft = canSlideLeft;
      _canSlideRight = canSlideRight;
    });
  }

  double _slideDelta() {
    if (!_controller.hasClients) return (_kPosterWidth + _kCardSpacing) * 3;
    final viewport = _controller.position.viewportDimension;
    return math.max((_kPosterWidth + _kCardSpacing) * 2, viewport * 0.85);
  }

  void _slideBy(double delta) {
    if (!_controller.hasClients) return;
    final position = _controller.position;
    final target = (_controller.offset + delta).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    _controller.animateTo(
      target,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = _EpisodeDetailColors.of(context);
    return SizedBox(
      height: _kPosterHeight + 64,
      child: Row(
        children: [
          IconButton(
            tooltip: _dtr(
              language: widget.language,
              zh: '\u5411\u5de6\u6ed1\u52a8',
              en: 'Slide left',
            ),
            onPressed: _canSlideLeft ? () => _slideBy(_slideDelta()) : null,
            icon: const Icon(Icons.chevron_left_rounded),
            style: IconButton.styleFrom(
              backgroundColor: colors.surface,
              foregroundColor: colors.textSecondary,
              disabledBackgroundColor: colors.surface,
              disabledForegroundColor: colors.textTertiary,
              side: BorderSide(color: colors.border),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Listener(
              onPointerSignal: _onPointerSignal,
              child: ListView.separated(
                controller: _controller,
                scrollDirection: Axis.horizontal,
                itemCount: widget.people.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(width: _kCardSpacing),
                itemBuilder: (context, index) {
                  final person = widget.people[index];
                  final access = widget.access;
                  final imageUrl = access == null
                      ? ''
                      : access.adapter.personImageUrl(
                          access.auth,
                          personId: person.id,
                          maxWidth: 520,
                        );
                  return _PersonCard(
                    width: _kPosterWidth,
                    height: _kPosterHeight,
                    person: person,
                    imageUrl: imageUrl,
                    language: widget.language,
                    onTap: widget.onTapPerson == null
                        ? null
                        : () => widget.onTapPerson!(person),
                  );
                },
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: _dtr(
              language: widget.language,
              zh: '\u5411\u53f3\u6ed1\u52a8',
              en: 'Slide right',
            ),
            onPressed: _canSlideRight ? () => _slideBy(-_slideDelta()) : null,
            icon: const Icon(Icons.chevron_right_rounded),
            style: IconButton.styleFrom(
              backgroundColor: colors.surface,
              foregroundColor: colors.textSecondary,
              disabledBackgroundColor: colors.surface,
              disabledForegroundColor: colors.textTertiary,
              side: BorderSide(color: colors.border),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PersonRoleParts {
  const _PersonRoleParts({
    required this.role,
    required this.voice,
  });

  final String role;
  final bool voice;
}

class _PersonCard extends StatefulWidget {
  const _PersonCard({
    required this.width,
    required this.height,
    required this.person,
    required this.imageUrl,
    required this.language,
    this.onTap,
  });

  final double width;
  final double height;
  final MediaPerson person;
  final String imageUrl;
  final DesktopUiLanguage language;
  final VoidCallback? onTap;

  @override
  State<_PersonCard> createState() => _PersonCardState();
}

class _PersonCardState extends State<_PersonCard> {
  bool _hovered = false;

  _PersonRoleParts _resolveRoleParts() {
    final raw = widget.person.role.trim();
    if (raw.isEmpty) return const _PersonRoleParts(role: '', voice: false);

    final voicePattern = RegExp(r'\\(\\s*voice\\s*\\)', caseSensitive: false);
    final voice = voicePattern.hasMatch(raw);
    final cleaned = raw.replaceAll(voicePattern, '').trim();
    return _PersonRoleParts(role: cleaned, voice: voice);
  }

  String _roleLine(String role) {
    if (role.trim().isEmpty) return '';
    if (widget.person.type.trim().toLowerCase() == 'actor') {
      final prefix = _dtr(
        language: widget.language,
        zh: '\u9970\u6f14: ',
        en: 'As: ',
      );
      return '$prefix${role.trim()}';
    }
    return role.trim();
  }

  Widget _buildImage(String imageUrl) {
    final trimmed = imageUrl.trim();
    if (trimmed.isEmpty) return _PersonAvatarFallback(name: widget.person.name);
    return CachedNetworkImage(
      key: ValueKey<String>('person-${widget.person.id}-$trimmed'),
      imageUrl: trimmed,
      cacheManager: CoverCacheManager.instance,
      httpHeaders: {'User-Agent': LinHttpClientFactory.userAgent},
      fit: BoxFit.cover,
      placeholder: (_, __) => const SizedBox.shrink(),
      errorWidget: (_, __, ___) =>
          _PersonAvatarFallback(name: widget.person.name),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = _EpisodeDetailColors.of(context);
    final parts = _resolveRoleParts();
    final roleLine = _roleLine(parts.role);
    final canTap = widget.onTap != null;
    final borderColor = _hovered ? colors.borderHover : colors.border;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: canTap ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _hovered && canTap ? 1.02 : 1,
          duration: const Duration(milliseconds: 130),
          curve: Curves.easeOut,
          child: SizedBox(
            width: widget.width,
            child: Column(
              children: [
                Container(
                  width: widget.width,
                  height: widget.height,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: borderColor),
                    boxShadow: [
                      BoxShadow(
                        color: colors.shadow,
                        blurRadius: 10,
                        offset: Offset(0, 3),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: _buildImage(widget.imageUrl),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  widget.person.name.trim().isEmpty ? '--' : widget.person.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
                if (roleLine.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    roleLine,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      color: colors.textSecondary,
                    ),
                  ),
                ],
                if (parts.voice) ...[
                  const SizedBox(height: 2),
                  Text(
                    '(voice)',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 10,
                      color: colors.textTertiary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PersonAvatarFallback extends StatelessWidget {
  const _PersonAvatarFallback({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final colors = _EpisodeDetailColors.of(context);
    final trimmed = name.trim();
    final letter = trimmed.isEmpty ? '?' : trimmed[0].toUpperCase();

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colors.fallbackImageStart,
            colors.fallbackImageEnd,
          ],
        ),
      ),
      child: Center(
        child: Text(
          letter,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: colors.textPrimary.withValues(alpha: 0.85),
          ),
        ),
      ),
    );
  }
}

class _SimilarSection extends StatelessWidget {
  const _SimilarSection({
    required this.items,
    required this.access,
    required this.language,
    this.onTap,
  });

  final List<MediaItem> items;
  final ServerAccess? access;
  final DesktopUiLanguage language;
  final ValueChanged<MediaItem>? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = _EpisodeDetailColors.of(context);
    return _GradientSectionSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _dtr(
              language: language,
              zh: '\u66f4\u591a\u7c7b\u4f3c',
              en: 'More Like This',
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: 16),
          _SimilarHorizontalList(
            items: items,
            access: access,
            language: language,
            onTap: onTap,
          ),
        ],
      ),
    );
  }
}

class _SimilarHorizontalList extends StatefulWidget {
  const _SimilarHorizontalList({
    required this.items,
    required this.access,
    required this.language,
    this.onTap,
  });

  final List<MediaItem> items;
  final ServerAccess? access;
  final DesktopUiLanguage language;
  final ValueChanged<MediaItem>? onTap;

  @override
  State<_SimilarHorizontalList> createState() => _SimilarHorizontalListState();
}

class _SimilarHorizontalListState extends State<_SimilarHorizontalList> {
  static const double _kCardWidth = 140;
  static const double _kCardSpacing = 16;
  final ScrollController _controller = ScrollController();
  bool _canSlideLeft = false;
  bool _canSlideRight = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_updateScrollButtons);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _updateScrollButtons();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || !_controller.hasClients) return;
    _animateScrollByPointerDelta(controller: _controller, event: event);
  }

  void _updateScrollButtons() {
    if (!_controller.hasClients) return;
    final position = _controller.position;
    final canSlideLeft = position.pixels < position.maxScrollExtent - 0.5;
    final canSlideRight = position.pixels > position.minScrollExtent + 0.5;
    if (canSlideLeft == _canSlideLeft && canSlideRight == _canSlideRight) {
      return;
    }
    if (!mounted) return;
    setState(() {
      _canSlideLeft = canSlideLeft;
      _canSlideRight = canSlideRight;
    });
  }

  double _slideDelta() {
    if (!_controller.hasClients) return (_kCardWidth + _kCardSpacing) * 3;
    final viewport = _controller.position.viewportDimension;
    return math.max((_kCardWidth + _kCardSpacing) * 2, viewport * 0.85);
  }

  void _slideBy(double delta) {
    if (!_controller.hasClients) return;
    final position = _controller.position;
    final target = (_controller.offset + delta).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    _controller.animateTo(
      target,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = _EpisodeDetailColors.of(context);
    final posterHeight = _kCardWidth * 3 / 2;
    final listHeight = posterHeight + 52;

    return SizedBox(
      height: listHeight,
      child: Row(
        children: [
          IconButton(
            tooltip: _dtr(
              language: widget.language,
              zh: '\u5411\u5de6\u6ed1\u52a8',
              en: 'Slide left',
            ),
            onPressed: _canSlideLeft ? () => _slideBy(_slideDelta()) : null,
            icon: const Icon(Icons.chevron_left_rounded),
            style: IconButton.styleFrom(
              backgroundColor: colors.surface,
              foregroundColor: colors.textSecondary,
              disabledBackgroundColor: colors.surface,
              disabledForegroundColor: colors.textTertiary,
              side: BorderSide(color: colors.border),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Listener(
              onPointerSignal: _onPointerSignal,
              child: ListView.separated(
                controller: _controller,
                scrollDirection: Axis.horizontal,
                itemCount: widget.items.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(width: _kCardSpacing),
                itemBuilder: (context, index) {
                  final item = widget.items[index];
                  return _SimilarPosterCard(
                    width: _kCardWidth,
                    item: item,
                    access: widget.access,
                    onTap:
                        widget.onTap == null ? null : () => widget.onTap!(item),
                  );
                },
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: _dtr(
              language: widget.language,
              zh: '\u5411\u53f3\u6ed1\u52a8',
              en: 'Slide right',
            ),
            onPressed: _canSlideRight ? () => _slideBy(-_slideDelta()) : null,
            icon: const Icon(Icons.chevron_right_rounded),
            style: IconButton.styleFrom(
              backgroundColor: colors.surface,
              foregroundColor: colors.textSecondary,
              disabledBackgroundColor: colors.surface,
              disabledForegroundColor: colors.textTertiary,
              side: BorderSide(color: colors.border),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SimilarPosterCard extends StatefulWidget {
  const _SimilarPosterCard({
    required this.width,
    required this.item,
    required this.access,
    this.onTap,
  });

  final double width;
  final MediaItem item;
  final ServerAccess? access;
  final VoidCallback? onTap;

  @override
  State<_SimilarPosterCard> createState() => _SimilarPosterCardState();
}

class _SimilarPosterCardState extends State<_SimilarPosterCard> {
  bool _hovered = false;

  String _badgeText() {
    final rating = widget.item.communityRating;
    if (rating != null && rating.isFinite && rating > 0) {
      final fixed = rating.toStringAsFixed(1);
      return fixed.endsWith('.0')
          ? fixed.substring(0, fixed.length - 2)
          : fixed;
    }

    final type = widget.item.type.trim().toLowerCase();
    if (type == 'episode') {
      final no = widget.item.episodeNumber ?? 0;
      if (no > 0) return '$no';
    }
    if (type == 'season') {
      final no = widget.item.seasonNumber ?? 0;
      if (no > 0) return '$no';
    }
    return '';
  }

  Widget _buildPosterImage(String? imageUrl) {
    final trimmed = (imageUrl ?? '').trim();
    if (trimmed.isEmpty) return _FallbackImage(label: widget.item.name);
    return CachedNetworkImage(
      key: ValueKey<String>('similar-${widget.item.id}-$trimmed'),
      imageUrl: trimmed,
      cacheManager: CoverCacheManager.instance,
      httpHeaders: {'User-Agent': LinHttpClientFactory.userAgent},
      fit: BoxFit.cover,
      placeholder: (_, __) => const SizedBox.shrink(),
      errorWidget: (_, __, ___) => _FallbackImage(label: widget.item.name),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = _EpisodeDetailColors.of(context);
    final canTap = widget.onTap != null;
    final posterHeight = widget.width * 3 / 2;
    final badgeText = _badgeText();

    final posterUrl = widget.item.hasImage
        ? _imageUrl(
            access: widget.access,
            item: widget.item,
            type: 'Primary',
            maxWidth: 520,
          )
        : null;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: canTap ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _hovered && canTap ? 1.03 : 1,
          duration: const Duration(milliseconds: 130),
          curve: Curves.easeOut,
          child: SizedBox(
            width: widget.width,
            child: Column(
              children: [
                Container(
                  width: widget.width,
                  height: posterHeight,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [
                      BoxShadow(
                        color: colors.shadow,
                        blurRadius: 12,
                        offset: Offset(0, 3),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        _buildPosterImage(posterUrl),
                        if (badgeText.isNotEmpty)
                          Positioned(
                            top: 8,
                            right: 8,
                            child: _CornerBadge(text: badgeText),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  widget.item.name.trim().isEmpty ? '--' : widget.item.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
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

class _CornerBadge extends StatelessWidget {
  const _CornerBadge({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = _EpisodeDetailColors.of(context);
    return Container(
      constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colors.success,
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            color: colors.shadow,
            blurRadius: 10,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: Colors.white,
        ),
      ),
    );
  }
}

class _ExternalLinksSection extends StatelessWidget {
  const _ExternalLinksSection({
    required this.links,
    required this.language,
    required this.onOpenLink,
  });

  final List<_ExternalLink> links;
  final DesktopUiLanguage language;
  final ValueChanged<String> onOpenLink;

  @override
  Widget build(BuildContext context) {
    final colors = _EpisodeDetailColors.of(context);
    return _SectionSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _dtr(
              language: language,
              zh: '\u5916\u90e8\u94fe\u63a5',
              en: 'External Links',
            ),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: links
                .map(
                  (link) => _ExternalLinkButton(
                    label: link.label,
                    iconAssetPath: link.iconAssetPath,
                    enabled: link.url.isNotEmpty,
                    onTap: link.url.isEmpty ? null : () => onOpenLink(link.url),
                  ),
                )
                .toList(growable: false),
          ),
        ],
      ),
    );
  }
}

class _ExternalLinkButton extends StatefulWidget {
  const _ExternalLinkButton({
    required this.label,
    this.iconAssetPath,
    required this.enabled,
    this.onTap,
  });

  final String label;
  final String? iconAssetPath;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  State<_ExternalLinkButton> createState() => _ExternalLinkButtonState();
}

class _ExternalLinkButtonState extends State<_ExternalLinkButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = _EpisodeDetailColors.of(context);
    final borderColor =
        _hovered && widget.enabled ? colors.borderHover : colors.border;
    final textColor =
        widget.enabled ? colors.textSecondary : colors.textTertiary;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor:
          widget.enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: _hovered && widget.enabled
                ? colors.surfaceHover
                : colors.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: borderColor),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ExternalLinkIcon(
                label: widget.label,
                iconAssetPath: widget.iconAssetPath,
              ),
              const SizedBox(width: 8),
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: 13,
                  color: textColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ExternalLinkIcon extends StatelessWidget {
  const _ExternalLinkIcon({
    required this.label,
    this.iconAssetPath,
  });

  final String label;
  final String? iconAssetPath;

  @override
  Widget build(BuildContext context) {
    final assetPath = (iconAssetPath ?? '').trim();
    final normalizedLabel = label.trim();
    final fallbackText =
        normalizedLabel.isEmpty ? '?' : normalizedLabel.substring(0, 1);
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        width: 16,
        height: 16,
        child: assetPath.isEmpty
            ? _ExternalLinkIconFallback(text: fallbackText)
            : Image.asset(
                assetPath,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) {
                  return _ExternalLinkIconFallback(text: fallbackText);
                },
              ),
      ),
    );
  }
}

class _ExternalLinkIconFallback extends StatelessWidget {
  const _ExternalLinkIconFallback({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = _EpisodeDetailColors.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.iconFallbackBackground,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Center(
        child: Text(
          text.toUpperCase(),
          maxLines: 1,
          overflow: TextOverflow.clip,
          style: TextStyle(
            fontSize: 9,
            color: colors.iconFallbackForeground,
            fontWeight: FontWeight.w700,
            height: 1.0,
          ),
        ),
      ),
    );
  }
}

class _MediaInfoSection extends StatelessWidget {
  const _MediaInfoSection({
    required this.item,
    required this.selectedSource,
    required this.selectedAudio,
    required this.selectedSubtitle,
    required this.subtitleStreams,
    required this.language,
  });

  final MediaItem item;
  final Map<String, dynamic>? selectedSource;
  final Map<String, dynamic>? selectedAudio;
  final Map<String, dynamic>? selectedSubtitle;
  final List<Map<String, dynamic>> subtitleStreams;
  final DesktopUiLanguage language;

  @override
  Widget build(BuildContext context) {
    final colors = _EpisodeDetailColors.of(context);
    final fileContainer = _coalesceNonEmpty([
      (selectedSource?['Container'] ?? '').toString(),
      (item.container ?? '').toString(),
      'MKV',
    ]).toUpperCase();

    final sourceSize = _asInt(selectedSource?['Size']) ?? item.sizeBytes;
    final sourceTime = _formatDateTime(item.premiereDate);
    final fileHeader = sourceTime == '--'
        ? '$fileContainer \u00b7 ${_formatBytes(sourceSize)} \u00b7 '
            '${_dtr(language: language, zh: '\u5a92\u4f53\u6dfb\u52a0\u65f6\u95f4\u672a\u77e5', en: 'Added time unknown')}'
        : '$fileContainer \u00b7 ${_formatBytes(sourceSize)} \u00b7 '
            '${_dtr(language: language, zh: '\u5a92\u4f53\u4e8e $sourceTime \u6dfb\u52a0', en: 'Added on $sourceTime')}';

    final videoStreams = _mediaStreamsByType(selectedSource, 'video');
    final video = videoStreams.isEmpty ? null : videoStreams.first;
    final subtitle1 = subtitleStreams.isEmpty ? null : subtitleStreams.first;
    final subtitle2 = subtitleStreams.length > 1 ? subtitleStreams[1] : null;

    final cards = [
      _MediaInfoCardData(
        title: _dtr(language: language, zh: '\u89c6\u9891', en: 'Video'),
        icon: Icons.videocam_outlined,
        specs: _videoSpecs(
          video,
          selectedSource,
          language: language,
        ),
      ),
      _MediaInfoCardData(
        title: _dtr(language: language, zh: '\u97f3\u9891', en: 'Audio'),
        icon: Icons.audiotrack_outlined,
        specs: _audioSpecs(
          selectedAudio,
          language: language,
        ),
      ),
      _MediaInfoCardData(
        title: _dtr(language: language, zh: '\u5b57\u5e55 1', en: 'Subtitle 1'),
        icon: Icons.subtitles_outlined,
        specs: _subtitleSpecs(
          subtitle1,
          language: language,
        ),
      ),
      _MediaInfoCardData(
        title: _dtr(language: language, zh: '\u5b57\u5e55 2', en: 'Subtitle 2'),
        icon: Icons.closed_caption_disabled_outlined,
        specs: _subtitleSpecs(
          subtitle2,
          language: language,
        ),
      ),
    ];

    return _SectionSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            fileHeader,
            style: TextStyle(
              fontSize: 14,
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final crossAxisCount = constraints.maxWidth > 1200 ? 4 : 2;
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  childAspectRatio: 1.2,
                ),
                itemCount: cards.length,
                itemBuilder: (context, index) {
                  final card = cards[index];
                  return _MediaInfoCard(data: card);
                },
              );
            },
          ),
        ],
      ),
    );
  }
}

class _MediaInfoCard extends StatelessWidget {
  const _MediaInfoCard({required this.data});

  final _MediaInfoCardData data;

  @override
  Widget build(BuildContext context) {
    final colors = _EpisodeDetailColors.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(data.icon, size: 16, color: colors.textSecondary),
              const SizedBox(width: 8),
              Text(
                data.title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
            ],
          ),
          Divider(height: 18, color: colors.border),
          Expanded(
            child: ListView.builder(
              itemCount: data.specs.length,
              physics: const NeverScrollableScrollPhysics(),
              itemBuilder: (context, index) {
                final entry = data.specs.entries.elementAt(index);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 74,
                        child: Text(
                          entry.key,
                          style: TextStyle(
                            fontSize: 12,
                            color: colors.textTertiary,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          entry.value,
                          style: TextStyle(
                            fontSize: 12,
                            color: colors.textSecondary,
                          ),
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
    );
  }
}

class _SectionSurface extends StatelessWidget {
  const _SectionSurface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = _EpisodeDetailColors.of(context);
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.border),
      ),
      child: child,
    );
  }
}

class _GradientSectionSurface extends StatelessWidget {
  const _GradientSectionSurface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = _EpisodeDetailColors.of(context);
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colors.heroFallbackStart,
            colors.surface,
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.border),
      ),
      child: child,
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = _EpisodeDetailColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colors.errorBackground,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.errorBorder),
      ),
      child: Row(
        children: [
          Icon(
            Icons.error_outline_rounded,
            color: colors.error,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: colors.errorText),
            ),
          ),
        ],
      ),
    );
  }
}

class _TrackSelectionState {
  const _TrackSelectionState({
    required this.selectedSource,
    required this.selectedAudio,
    required this.selectedSubtitle,
    required this.subtitleStreams,
    required this.selectedVideoValue,
    required this.selectedAudioValue,
    required this.selectedSubtitleValue,
    required this.videoDisplay,
    required this.audioDisplay,
    required this.subtitleDisplay,
    required this.videoOptions,
    required this.audioOptions,
    required this.subtitleOptions,
  });

  final Map<String, dynamic>? selectedSource;
  final Map<String, dynamic>? selectedAudio;
  final Map<String, dynamic>? selectedSubtitle;
  final List<Map<String, dynamic>> subtitleStreams;
  final String selectedVideoValue;
  final String selectedAudioValue;
  final String selectedSubtitleValue;
  final String videoDisplay;
  final String audioDisplay;
  final String subtitleDisplay;
  final List<DropdownOption> videoOptions;
  final List<DropdownOption> audioOptions;
  final List<DropdownOption> subtitleOptions;
}

class DropdownOption {
  const DropdownOption({
    required this.value,
    required this.label,
  });

  final String value;
  final String label;
}

class _MetaValue {
  const _MetaValue({
    required this.icon,
    required this.text,
  });

  final IconData icon;
  final String text;
}

class _MediaInfoCardData {
  const _MediaInfoCardData({
    required this.title,
    required this.icon,
    required this.specs,
  });

  final String title;
  final IconData icon;
  final Map<String, String> specs;
}

class _ExternalLink {
  const _ExternalLink({
    required this.label,
    required this.url,
    required this.iconAssetPath,
  });

  final String label;
  final String url;
  final String iconAssetPath;
}

@immutable
class _EpisodeDetailColors {
  const _EpisodeDetailColors({
    required this.background,
    required this.surface,
    required this.surfaceHover,
    required this.heroFallbackStart,
    required this.heroFallbackEnd,
    required this.heroOverlayTop,
    required this.heroOverlayMiddle,
    required this.heroOverlayBottom,
    required this.fallbackImageStart,
    required this.fallbackImageEnd,
    required this.iconFallbackBackground,
    required this.iconFallbackForeground,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.textBody,
    required this.primary,
    required this.primaryHover,
    required this.success,
    required this.successHoverBorder,
    required this.successHoverBackground,
    required this.successBackground,
    required this.error,
    required this.errorBackground,
    required this.errorBorder,
    required this.errorText,
    required this.heartActive,
    required this.border,
    required this.borderHover,
    required this.shadow,
  });

  final Color background;
  final Color surface;
  final Color surfaceHover;
  final Color heroFallbackStart;
  final Color heroFallbackEnd;
  final Color heroOverlayTop;
  final Color heroOverlayMiddle;
  final Color heroOverlayBottom;
  final Color fallbackImageStart;
  final Color fallbackImageEnd;
  final Color iconFallbackBackground;
  final Color iconFallbackForeground;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color textBody;
  final Color primary;
  final Color primaryHover;
  final Color success;
  final Color successHoverBorder;
  final Color successHoverBackground;
  final Color successBackground;
  final Color error;
  final Color errorBackground;
  final Color errorBorder;
  final Color errorText;
  final Color heartActive;
  final Color border;
  final Color borderHover;
  final Color shadow;

  static const light = _EpisodeDetailColors(
    background: Color(0xFFF5F5F5),
    surface: Colors.white,
    surfaceHover: Color(0xFFF3F7FB),
    heroFallbackStart: Color(0xFFF1F4F7),
    heroFallbackEnd: Color(0xFFE8EEF4),
    heroOverlayTop: Color(0xE6FFFFFF),
    heroOverlayMiddle: Color(0x4DFFFFFF),
    heroOverlayBottom: Color(0xF2FFFFFF),
    fallbackImageStart: Color(0xFFE9EEF2),
    fallbackImageEnd: Color(0xFFDDE4EA),
    iconFallbackBackground: Color(0xFFE8ECF1),
    iconFallbackForeground: Color(0xFF425466),
    textPrimary: Color(0xFF1A1A1A),
    textSecondary: Color(0xFF666666),
    textTertiary: Color(0xFF999999),
    textBody: Color(0xFF555555),
    primary: Color(0xFF1976D2),
    primaryHover: Color(0xFF1565C0),
    success: Color(0xFF4CAF50),
    successHoverBorder: Color(0xFF3F9E43),
    successHoverBackground: Color(0x154CAF50),
    successBackground: Color(0x124CAF50),
    error: Color(0xFFE53935),
    errorBackground: Color(0x1AE53935),
    errorBorder: Color(0x66E53935),
    errorText: Color(0xFF8B1A17),
    heartActive: Color(0xFFE85066),
    border: Color(0xFFE0E0E0),
    borderHover: Color(0xFF1976D2),
    shadow: Color(0x1A000000),
  );

  static const dark = _EpisodeDetailColors(
    background: Color(0xFF0E1116),
    surface: Color(0xFF161B23),
    surfaceHover: Color(0xFF202733),
    heroFallbackStart: Color(0xFF1A2230),
    heroFallbackEnd: Color(0xFF111722),
    heroOverlayTop: Color(0xE611151C),
    heroOverlayMiddle: Color(0x8010151C),
    heroOverlayBottom: Color(0xF2161B24),
    fallbackImageStart: Color(0xFF273141),
    fallbackImageEnd: Color(0xFF1A2330),
    iconFallbackBackground: Color(0xFF2A3342),
    iconFallbackForeground: Color(0xFFD0D9E6),
    textPrimary: Color(0xFFF2F6FB),
    textSecondary: Color(0xFFB7C1CC),
    textTertiary: Color(0xFF95A2B2),
    textBody: Color(0xFFCFD6E0),
    primary: Color(0xFF5EA2FF),
    primaryHover: Color(0xFF4A8FE9),
    success: Color(0xFF62C276),
    successHoverBorder: Color(0xFF54B56A),
    successHoverBackground: Color(0x1F62C276),
    successBackground: Color(0x1858B86D),
    error: Color(0xFFFF8A86),
    errorBackground: Color(0x2AE53935),
    errorBorder: Color(0x66EF5350),
    errorText: Color(0xFFFFC9C7),
    heartActive: Color(0xFFFF8AA5),
    border: Color(0x4052657D),
    borderHover: Color(0xFF5EA2FF),
    shadow: Color(0x55000000),
  );

  static _EpisodeDetailColors of(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return brightness == Brightness.dark ? dark : light;
  }
}

String _dtr({
  required DesktopUiLanguage language,
  required String zh,
  required String en,
}) {
  return language.pick(zh: zh, en: en);
}

String _seasonSectionTitle(
  MediaItem item, {
  required DesktopUiLanguage language,
}) {
  final type = item.type.trim().toLowerCase();
  final season = (type == 'episode' || type == 'season')
      ? (item.seasonNumber ?? item.episodeNumber ?? 1)
      : 1;
  return _dtr(
    language: language,
    zh: '\u66f4\u591a\u6765\u81ea\uff1a\u7b2c $season \u5b63',
    en: 'More from: Season $season',
  );
}

String _episodeMark(MediaItem item) {
  final type = item.type.trim().toLowerCase();
  if (type != 'episode') return '';
  final season = math.max(item.seasonNumber ?? 0, 0);
  final episode = math.max(item.episodeNumber ?? 0, 0);
  if (season <= 0 || episode <= 0) return '';
  return 'S$season:E$episode';
}

String _subtitleLine(MediaItem item) {
  final values = <String>[
    item.seriesName.trim(),
    item.seasonName.trim(),
  ].where((value) => value.isNotEmpty);
  return values.join(' \u00b7 ');
}

String _episodeListLabel(
  MediaItem item, {
  required DesktopUiLanguage language,
}) {
  final index = item.episodeNumber ?? 0;
  final title = item.name.trim();
  if (title.isEmpty) {
    return _dtr(
      language: language,
      zh: '$index. \u7b2c$index\u96c6',
      en: '$index. Episode $index',
    );
  }
  return '$index. $title';
}

String _formatDate(String? raw) {
  final value = (raw ?? '').trim();
  if (value.isEmpty) return '--';
  final date = DateTime.tryParse(value);
  if (date == null) return value;
  return '${date.year}/${date.month}/${date.day}';
}

String _formatDateTime(String? raw) {
  final value = (raw ?? '').trim();
  if (value.isEmpty) return '--';
  final date = DateTime.tryParse(value);
  if (date == null) return value;
  final hh = date.hour.toString().padLeft(2, '0');
  final mm = date.minute.toString().padLeft(2, '0');
  return '${date.year}/${date.month}/${date.day} $hh:$mm';
}

String _formatRuntime(
  int? ticks, {
  required DesktopUiLanguage language,
}) {
  if (ticks == null || ticks <= 0) return '--';
  final totalSeconds = ticks ~/ 10000000;
  if (totalSeconds <= 0) return '--';
  final duration = Duration(seconds: totalSeconds);
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  if (hours <= 0) {
    return _dtr(
      language: language,
      zh: '${duration.inMinutes}\u5206\u949f',
      en: '${duration.inMinutes} min',
    );
  }
  return _dtr(
    language: language,
    zh: '$hours\u5c0f\u65f6$minutes\u5206\u949f',
    en: '${hours}h ${minutes}m',
  );
}

String _formatBytes(int? sizeBytes) {
  if (sizeBytes == null || sizeBytes <= 0) return '--';
  const kb = 1024;
  const mb = kb * 1024;
  const gb = mb * 1024;
  if (sizeBytes >= gb) return '${(sizeBytes / gb).toStringAsFixed(1)} GB';
  if (sizeBytes >= mb) return '${(sizeBytes / mb).toStringAsFixed(1)} MB';
  if (sizeBytes >= kb) return '${(sizeBytes / kb).toStringAsFixed(1)} KB';
  return '$sizeBytes B';
}

String _providerId(MediaItem item, List<String> providerKeys) {
  for (final entry in item.providerIds.entries) {
    final key = entry.key.toLowerCase();
    if (providerKeys.any((target) => key.contains(target))) {
      final value = entry.value.trim();
      if (value.isNotEmpty) return value;
    }
  }
  return '';
}

List<_ExternalLink> _buildExternalLinks(MediaItem item) {
  final type = item.type.trim().toLowerCase();
  final isSeries = type == 'series' ||
      type == 'season' ||
      type == 'episode' ||
      (item.seriesId ?? '').trim().isNotEmpty;
  final imdbId = _providerId(item, const ['imdb']);
  final traktId = _providerId(item, const ['trakt']);
  final tmdbId = _providerId(item, const ['tmdb']);

  final imdbUrl = imdbId.isEmpty ? '' : 'https://www.imdb.com/title/$imdbId';
  final traktUrl = traktId.isNotEmpty
      ? (isSeries
          ? 'https://trakt.tv/shows/$traktId'
          : 'https://trakt.tv/movies/$traktId')
      : (imdbId.isNotEmpty
          ? 'https://trakt.tv/search/imdb/$imdbId'
          : (tmdbId.isNotEmpty ? 'https://trakt.tv/search/tmdb/$tmdbId' : ''));
  final tmdbUrl = tmdbId.isNotEmpty
      ? (isSeries
          ? 'https://www.themoviedb.org/tv/$tmdbId'
          : 'https://www.themoviedb.org/movie/$tmdbId')
      : '';

  return [
    _ExternalLink(
      label: 'IMDb',
      url: imdbUrl,
      iconAssetPath: 'assets/images/imdb.png',
    ),
    _ExternalLink(
      label: 'Trakt',
      url: traktUrl,
      iconAssetPath: 'assets/images/trakt.png',
    ),
    _ExternalLink(
      label: 'TMDB',
      url: tmdbUrl,
      iconAssetPath: 'assets/images/TMDB.png',
    ),
  ];
}

List<String> _seasonImageCandidates({
  required ServerAccess? access,
  required MediaItem season,
}) {
  final currentAccess = access;
  if (currentAccess == null) return const <String>[];
  final urls = <String>[];

  void addUrl({
    required String itemId,
    required String imageType,
    required int maxWidth,
  }) {
    final id = itemId.trim();
    if (id.isEmpty) return;
    final url = currentAccess.adapter.imageUrl(
      currentAccess.auth,
      itemId: id,
      imageType: imageType,
      maxWidth: maxWidth,
    );
    if (url.trim().isEmpty || urls.contains(url)) return;
    urls.add(url);
  }

  addUrl(itemId: season.id, imageType: 'Primary', maxWidth: 720);
  addUrl(itemId: season.id, imageType: 'Thumb', maxWidth: 720);
  addUrl(itemId: season.id, imageType: 'Backdrop', maxWidth: 1280);
  addUrl(itemId: season.parentId ?? '', imageType: 'Primary', maxWidth: 720);
  addUrl(itemId: season.seriesId ?? '', imageType: 'Primary', maxWidth: 720);
  addUrl(itemId: season.seriesId ?? '', imageType: 'Backdrop', maxWidth: 1280);

  return urls;
}

List<String> _episodeImageCandidates({
  required ServerAccess? access,
  required MediaItem episode,
}) {
  final currentAccess = access;
  if (currentAccess == null) return const <String>[];
  final urls = <String>[];

  void addUrl({
    required String itemId,
    required String imageType,
    required int maxWidth,
  }) {
    final id = itemId.trim();
    if (id.isEmpty) return;
    final url = currentAccess.adapter.imageUrl(
      currentAccess.auth,
      itemId: id,
      imageType: imageType,
      maxWidth: maxWidth,
    );
    if (url.trim().isEmpty || urls.contains(url)) return;
    urls.add(url);
  }

  addUrl(itemId: episode.id, imageType: 'Primary', maxWidth: 920);
  addUrl(itemId: episode.id, imageType: 'Thumb', maxWidth: 920);
  addUrl(itemId: episode.id, imageType: 'Backdrop', maxWidth: 1280);
  addUrl(itemId: episode.parentId ?? '', imageType: 'Primary', maxWidth: 920);
  addUrl(itemId: episode.seriesId ?? '', imageType: 'Primary', maxWidth: 920);
  addUrl(itemId: episode.seriesId ?? '', imageType: 'Backdrop', maxWidth: 1280);

  return urls;
}

List<Map<String, dynamic>> _playbackSources(PlaybackInfoResult? info) {
  if (info == null || info.mediaSources.isEmpty) return const [];
  return info.mediaSources
      .whereType<Map>()
      .map((source) => source.map((k, v) => MapEntry('$k', v)))
      .toList(growable: false);
}

Map<String, dynamic>? _resolveSourceFromSelection({
  required List<Map<String, dynamic>> sources,
  required String? selectedValue,
}) {
  if (sources.isEmpty) return null;
  final target = (selectedValue ?? '').trim();
  if (target.isEmpty) return sources.first;
  for (var i = 0; i < sources.length; i++) {
    final candidate = sources[i];
    if (_sourceOptionValue(candidate, i) == target) return candidate;
  }
  return sources.first;
}

String _sourceOptionValue(Map<String, dynamic> source, int index) {
  final id = (source['Id'] ?? '').toString().trim();
  return id.isEmpty ? 'source-$index' : id;
}

List<Map<String, dynamic>> _mediaStreamsByType(
  Map<String, dynamic>? source,
  String type,
) {
  if (source == null) return const [];
  final target = type.toLowerCase();
  final list = (source['MediaStreams'] as List?) ?? const [];
  final result = <Map<String, dynamic>>[];
  for (final entry in list) {
    if (entry is! Map) continue;
    final stream = entry.map((k, v) => MapEntry('$k', v));
    if ((stream['Type'] ?? '').toString().toLowerCase() == target) {
      result.add(stream);
    }
  }
  return result;
}

Map<String, dynamic>? _findStreamByIndex(
  List<Map<String, dynamic>> streams,
  int? streamIndex,
) {
  if (streamIndex == null) return null;
  for (final stream in streams) {
    if (_asInt(stream['Index']) == streamIndex) return stream;
  }
  return null;
}

String _fallbackVideoLabel(MediaItem item) {
  final type = mediaTypeLabel(item);
  final runtime = mediaRuntimeLabel(item);
  if (runtime.isEmpty) return '$type \u00b7 1080p';
  return '$type \u00b7 $runtime';
}

String _mediaSourceLabel(
  Map<String, dynamic>? source, {
  required String fallback,
}) {
  if (source == null) return fallback;
  final name = _normalizeMediaSourceName((source['Name'] ?? '').toString());
  if (name.isNotEmpty) return name;

  final streams = _mediaStreamsByType(source, 'video');
  final stream = streams.isEmpty ? null : streams.first;
  final width = _asInt(stream?['Width']);
  final height = _asInt(stream?['Height']);
  final codec = (stream?['Codec'] ?? '').toString().trim().toUpperCase();
  final quality = (width != null && height != null && width > 0 && height > 0)
      ? '${height}p'
      : '';
  return _coalesceNonEmpty([quality, codec, fallback], separator: ' ');
}

String _normalizeMediaSourceName(String raw) {
  final parts = raw
      .split(RegExp(r'\s*[·|/]+\s*|\s+-\s+'))
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .toList(growable: false);
  if (parts.isEmpty) return '';
  final unique = <String>[];
  for (final part in parts) {
    final marker = part.toUpperCase();
    if (unique.any((entry) => entry.toUpperCase() == marker)) continue;
    unique.add(part);
  }
  if (unique.length == 1) {
    return unique.first.toUpperCase();
  }
  return unique.join(' · ');
}

String _audioStreamLabel(Map<String, dynamic> stream) {
  final title = (stream['DisplayTitle'] ?? '').toString().trim();
  if (title.isNotEmpty) return title;
  final language = (stream['Language'] ?? '').toString().trim();
  final codec = (stream['Codec'] ?? '').toString().trim().toUpperCase();
  final channels =
      (stream['ChannelLayout'] ?? stream['Channels'] ?? '').toString().trim();
  return _coalesceNonEmpty([language, codec, channels], separator: ' ');
}

String _subtitleStreamLabel(Map<String, dynamic> stream) {
  final title = (stream['DisplayTitle'] ?? '').toString().trim();
  if (title.isNotEmpty) return title;
  final language = (stream['Language'] ?? '').toString().trim();
  final codec = (stream['Codec'] ?? '').toString().trim().toUpperCase();
  return _coalesceNonEmpty([language, codec], separator: ' ');
}

Map<String, String> _videoSpecs(
  Map<String, dynamic>? videoStream,
  Map<String, dynamic>? source, {
  required DesktopUiLanguage language,
}) {
  return {
    _dtr(language: language, zh: '\u89c6\u9891\u683c\u5f0f', en: 'Format'):
        _videoFormatLabel(videoStream, source),
    _dtr(language: language, zh: '\u7f16\u7801\u683c\u5f0f', en: 'Codec'):
        _fallback((videoStream?['Codec'] ?? '').toString().toUpperCase()),
    _dtr(language: language, zh: '\u7f16\u7801\u89c4\u683c', en: 'Profile'):
        _fallback((videoStream?['Profile'] ?? '').toString()),
    _dtr(language: language, zh: '\u7f16\u7801\u7ea7\u522b', en: 'Level'):
        _fallback((videoStream?['Level'] ?? '').toString()),
    _dtr(language: language, zh: '\u6e90\u5206\u8fa8\u7387', en: 'Resolution'):
        _formatResolution(
      _asInt(videoStream?['Width']),
      _asInt(videoStream?['Height']),
    ),
    _dtr(language: language, zh: '\u89c6\u9891\u6bd4\u4f8b', en: 'Aspect'):
        _fallback((videoStream?['AspectRatio'] ?? '').toString()),
    _dtr(language: language, zh: '\u5e27\u901f\u7387', en: 'Frame Rate'):
        _formatFrameRate(videoStream),
    _dtr(language: language, zh: '\u6bd4\u7279\u7387', en: 'Bitrate'):
        _formatBitRate(_asInt(videoStream?['BitRate'])),
  };
}

String _videoFormatLabel(
  Map<String, dynamic>? videoStream,
  Map<String, dynamic>? source,
) {
  final candidates = <String>[
    (source?['Container'] ?? '').toString(),
    (videoStream?['Container'] ?? '').toString(),
    (videoStream?['Codec'] ?? '').toString(),
    (source?['Name'] ?? '').toString(),
  ];
  for (final candidate in candidates) {
    final token = _singleFormatText(candidate);
    if (token.isNotEmpty) return token;
  }
  return '--';
}

String _singleFormatText(String raw) {
  final parts = raw
      .split(RegExp(r'[·|/、,]+'))
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .toList(growable: false);
  if (parts.isEmpty) return '';
  final words = parts.first
      .split(RegExp(r'\s+'))
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .toList(growable: false);
  if (words.isEmpty) return parts.first.toUpperCase();
  return words.first.toUpperCase();
}

Map<String, String> _audioSpecs(
  Map<String, dynamic>? audioStream, {
  required DesktopUiLanguage language,
}) {
  return {
    _dtr(language: language, zh: '\u6807\u9898\u540d\u79f0', en: 'Title'):
        audioStream == null ? '--' : _audioStreamLabel(audioStream),
    _dtr(language: language, zh: '\u8bed\u8a00\u79cd\u7c7b', en: 'Language'):
        _fallback((audioStream?['Language'] ?? '').toString()),
    _dtr(language: language, zh: '\u7f16\u7801\u683c\u5f0f', en: 'Codec'):
        _fallback((audioStream?['Codec'] ?? '').toString().toUpperCase()),
    _dtr(language: language, zh: '\u7f16\u7801\u89c4\u683c', en: 'Profile'):
        _fallback((audioStream?['Profile'] ?? '').toString()),
    _dtr(language: language, zh: '\u97f3\u6548\u5e03\u5c40', en: 'Layout'):
        _fallback((audioStream?['ChannelLayout'] ?? '').toString()),
    _dtr(language: language, zh: '\u97f3\u9891\u58f0\u9053', en: 'Channels'):
        _fallback((audioStream?['Channels'] ?? '').toString()),
    _dtr(language: language, zh: '\u6bd4\u7279\u7387', en: 'Bitrate'):
        _formatBitRate(_asInt(audioStream?['BitRate'])),
    _dtr(language: language, zh: '\u91c7\u6837\u7387', en: 'Sample Rate'):
        _formatSampleRate(_asInt(audioStream?['SampleRate'])),
  };
}

Map<String, String> _subtitleSpecs(
  Map<String, dynamic>? subtitleStream, {
  required DesktopUiLanguage language,
}) {
  return {
    _dtr(language: language, zh: '\u6807\u9898\u540d\u79f0', en: 'Title'):
        subtitleStream == null
            ? _dtr(
                language: language, zh: '\u65e0\u5b57\u5e55', en: 'No subtitle')
            : _subtitleStreamLabel(subtitleStream),
    _dtr(language: language, zh: '\u8bed\u8a00\u79cd\u7c7b', en: 'Language'):
        _fallback((subtitleStream?['Language'] ?? '').toString()),
    _dtr(language: language, zh: '\u7f16\u7801\u683c\u5f0f', en: 'Codec'):
        _fallback((subtitleStream?['Codec'] ?? '').toString().toUpperCase()),
    _dtr(language: language, zh: '\u9ed8\u8ba4', en: 'Default'):
        subtitleStream == null
            ? '--'
            : (subtitleStream['IsDefault'] == true
                ? _dtr(language: language, zh: '\u662f', en: 'Yes')
                : _dtr(language: language, zh: '\u5426', en: 'No')),
    _dtr(language: language, zh: '\u5f3a\u5236', en: 'Forced'):
        subtitleStream == null
            ? '--'
            : (subtitleStream['IsForced'] == true
                ? _dtr(language: language, zh: '\u662f', en: 'Yes')
                : _dtr(language: language, zh: '\u5426', en: 'No')),
  };
}

String _formatResolution(int? width, int? height) {
  if (width == null || height == null || width <= 0 || height <= 0) return '--';
  return '${width}x$height';
}

String _formatBitRate(int? bitRate) {
  if (bitRate == null || bitRate <= 0) return '--';
  if (bitRate >= 1000000) {
    return '${(bitRate / 1000000).toStringAsFixed(1)} Mbps';
  }
  if (bitRate >= 1000) return '${(bitRate / 1000).toStringAsFixed(0)} Kbps';
  return '$bitRate bps';
}

String _formatSampleRate(int? value) {
  if (value == null || value <= 0) return '--';
  return '${value.toString()} Hz';
}

String _formatFrameRate(Map<String, dynamic>? stream) {
  final value = _asDouble(stream?['RealFrameRate']) ??
      _asDouble(stream?['AverageFrameRate']);
  if (value == null || !value.isFinite || value <= 0) return '--';
  return value.toStringAsFixed(value >= 100 ? 0 : 3);
}

String _fallback(String value) {
  return value.trim().isEmpty ? '--' : value.trim();
}

String _coalesceNonEmpty(
  List<String> values, {
  String separator = ' \u00b7 ',
}) {
  return values
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .join(separator);
}

int? _asInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value.trim());
  return null;
}

double? _asDouble(dynamic value) {
  if (value is double) return value;
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value.trim());
  return null;
}

String? _imageUrl({
  required ServerAccess? access,
  required MediaItem item,
  required String type,
  required int maxWidth,
}) {
  final currentAccess = access;
  if (currentAccess == null) return null;
  if (item.id.trim().isEmpty) return null;
  return currentAccess.adapter.imageUrl(
    currentAccess.auth,
    itemId: item.id,
    imageType: type,
    maxWidth: maxWidth,
  );
}

class DesktopPersonPage extends StatefulWidget {
  const DesktopPersonPage({
    super.key,
    required this.appState,
    required this.personId,
    this.seedName,
    this.server,
    this.language = DesktopUiLanguage.zhCn,
    this.onOpenItem,
  });

  final AppState appState;
  final String personId;
  final String? seedName;
  final ServerProfile? server;
  final DesktopUiLanguage language;
  final DesktopDetailOpenItem? onOpenItem;

  @override
  State<DesktopPersonPage> createState() => _DesktopPersonPageState();
}

class _DesktopPersonPageState extends State<DesktopPersonPage> {
  late DesktopPersonViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = DesktopPersonViewModel(
      appState: widget.appState,
      server: widget.server,
      personId: widget.personId,
      seedName: widget.seedName,
    );
    unawaited(_viewModel.load());
  }

  @override
  void didUpdateWidget(covariant DesktopPersonPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.personId.trim() != widget.personId.trim() ||
        oldWidget.server?.id != widget.server?.id ||
        oldWidget.appState != widget.appState) {
      final oldViewModel = _viewModel;
      _viewModel = DesktopPersonViewModel(
        appState: widget.appState,
        server: widget.server,
        personId: widget.personId,
        seedName: widget.seedName,
      );
      unawaited(_viewModel.load(forceRefresh: true));
      WidgetsBinding.instance.addPostFrameCallback((_) {
        oldViewModel.dispose();
      });
    }
  }

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
  }

  void _handleOpenItem(MediaItem item) {
    final callback = widget.onOpenItem;
    if (callback == null) return;
    callback(item, widget.server);
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _viewModel,
      builder: (context, _) {
        final colors = _EpisodeDetailColors.of(context);
        final title = _viewModel.displayName.trim().isEmpty
            ? _dtr(language: widget.language, zh: '\u6f14\u5458', en: 'Person')
            : _viewModel.displayName.trim();
        final bio = (_viewModel.person?.overview ?? '').trim();
        final access = _viewModel.access;
        final portraitUrl = access == null
            ? ''
            : access.adapter.personImageUrl(
                access.auth,
                personId: widget.personId,
                maxWidth: 920,
              );

        final credits = _viewModel.credits;
        final loadingCredits = _viewModel.loading && credits.isEmpty;
        final contentCredits = credits.take(48).toList(growable: false);

        return Scaffold(
          backgroundColor: colors.background,
          body: SafeArea(
            child: CustomScrollView(
              slivers: [
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _PersonHeaderDelegate(
                    title: title,
                    biography: bio,
                    portraitUrl: portraitUrl,
                    language: widget.language,
                    onBack: () => Navigator.of(context).maybePop(),
                  ),
                ),
                if ((_viewModel.error ?? '').trim().isNotEmpty) ...[
                  const SliverToBoxAdapter(child: SizedBox(height: 16)),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: _ErrorBanner(message: _viewModel.error!.trim()),
                    ),
                  ),
                ],
                const SliverToBoxAdapter(child: SizedBox(height: 20)),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: _GradientSectionSurface(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _dtr(
                              language: widget.language,
                              zh: '\u51fa\u6f14\u4f5c\u54c1',
                              en: 'Filmography',
                            ),
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: colors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 16),
                          if (loadingCredits)
                            const SizedBox(
                              height: 180,
                              child: Center(child: CircularProgressIndicator()),
                            )
                          else if (contentCredits.isEmpty)
                            SizedBox(
                              height: 180,
                              child: Center(
                                child: Text(
                                  _dtr(
                                    language: widget.language,
                                    zh: '\u6682\u65e0\u76f8\u5173\u4f5c\u54c1',
                                    en: 'No credits found',
                                  ),
                                  style: TextStyle(color: colors.textSecondary),
                                ),
                              ),
                            )
                          else
                            _SimilarHorizontalList(
                              items: contentCredits,
                              access: access,
                              language: widget.language,
                              onTap: widget.onOpenItem == null
                                  ? null
                                  : (entry) => _handleOpenItem(entry),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 28)),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _PersonHeaderDelegate extends SliverPersistentHeaderDelegate {
  _PersonHeaderDelegate({
    required this.title,
    required this.biography,
    required this.portraitUrl,
    required this.language,
    required this.onBack,
  });

  final String title;
  final String biography;
  final String portraitUrl;
  final DesktopUiLanguage language;
  final VoidCallback onBack;

  static const double _kMinHeight = 76;
  static const double _kMaxHeight = 320;

  @override
  double get minExtent => _kMinHeight;

  @override
  double get maxExtent => _kMaxHeight;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    final colors = _EpisodeDetailColors.of(context);
    final t = (shrinkOffset / (maxExtent - minExtent)).clamp(0.0, 1.0);
    final eased = Curves.easeOutCubic.transform(t);

    final expandedOpacity = (1 - eased * 1.15).clamp(0.0, 1.0);
    final collapsedOpacity = ((eased - 0.35) / 0.65).clamp(0.0, 1.0);

    final displayBio = biography.trim().isEmpty
        ? _dtr(
            language: language,
            zh: '\u6682\u65e0\u7b80\u4ecb\u3002',
            en: 'No biography available.',
          )
        : biography.trim();

    return ClipRect(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              colors.heroFallbackStart,
              colors.background,
            ],
          ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.background.withValues(alpha: eased * 0.55),
                ),
              ),
            ),
            Positioned.fill(
              child: Opacity(
                opacity: expandedOpacity,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, _kMinHeight, 24, 18),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final maxWidth = constraints.maxWidth;
                      final verticalLayout = maxWidth < 820;
                      final portraitWidth = verticalLayout ? 158.0 : 186.0;
                      final portraitHeight = portraitWidth * 3 / 2;

                      final portrait = _PersonPortraitCard(
                        width: portraitWidth,
                        height: portraitHeight,
                        imageUrl: portraitUrl,
                        label: title,
                      );

                      final titleWidget = Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w700,
                          color: colors.textPrimary,
                          height: 1.15,
                        ),
                      );

                      final bioWidget = Text(
                        displayBio,
                        maxLines: verticalLayout ? 5 : 6,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          color: colors.textBody,
                          height: 1.6,
                        ),
                      );

                      if (verticalLayout) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            portrait,
                            const SizedBox(height: 18),
                            titleWidget,
                            const SizedBox(height: 12),
                            bioWidget,
                          ],
                        );
                      }

                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          portrait,
                          const SizedBox(width: 26),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                titleWidget,
                                const SizedBox(height: 12),
                                bioWidget,
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
            Align(
              alignment: Alignment.topCenter,
              child: Container(
                height: _kMinHeight,
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: onBack,
                      icon: const Icon(Icons.arrow_back_rounded),
                      tooltip: _dtr(
                        language: language,
                        zh: '\u8fd4\u56de',
                        en: 'Back',
                      ),
                      style: IconButton.styleFrom(
                        foregroundColor: colors.textPrimary,
                        backgroundColor: colors.surface,
                        side: BorderSide(color: colors.border),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Opacity(
                        opacity: collapsedOpacity,
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: colors.textPrimary,
                          ),
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

  @override
  bool shouldRebuild(covariant _PersonHeaderDelegate oldDelegate) {
    return oldDelegate.title != title ||
        oldDelegate.biography != biography ||
        oldDelegate.portraitUrl != portraitUrl ||
        oldDelegate.language != language;
  }
}

class _PersonPortraitCard extends StatelessWidget {
  const _PersonPortraitCard({
    required this.width,
    required this.height,
    required this.imageUrl,
    required this.label,
  });

  final double width;
  final double height;
  final String imageUrl;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = _EpisodeDetailColors.of(context);
    final trimmed = imageUrl.trim();

    Widget child;
    if (trimmed.isEmpty) {
      child = _PersonAvatarFallback(name: label);
    } else {
      child = CachedNetworkImage(
        imageUrl: trimmed,
        cacheManager: CoverCacheManager.instance,
        httpHeaders: {'User-Agent': LinHttpClientFactory.userAgent},
        fit: BoxFit.cover,
        placeholder: (_, __) => const SizedBox.shrink(),
        errorWidget: (_, __, ___) => _PersonAvatarFallback(name: label),
      );
    }

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.border),
        boxShadow: [
          BoxShadow(
            color: colors.shadow,
            blurRadius: 18,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: child,
      ),
    );
  }
}
