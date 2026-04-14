import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lin_player_player/lin_player_player.dart';
import 'package:lin_player_prefs/lin_player_prefs.dart';
import 'package:lin_player_server_adapters/lin_player_server_adapters.dart';
import 'package:lin_player_state/lin_player_state.dart';
import 'package:lin_player_ui/lin_player_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';
import 'package:video_player_android/exo_tracks.dart' as vp_android;
import 'package:video_player_platform_interface/video_player_platform_interface.dart'
    as vp_platform;

import 'play_network_page.dart';
import 'server_adapters/server_access.dart';
import 'services/app_diagnostics_log.dart';
import 'services/app_route_observer.dart';
import 'services/playback/video_display_hint.dart';
import 'services/preload/playback_preload_coordinator.dart';
import 'services/stream_proxy/local_http_stream_proxy.dart';
import 'services/stream_resolver/stream_models.dart';
import 'tv/tv_focusable.dart';
import 'widgets/danmaku_manual_search_dialog.dart';
import 'widgets/mobile_player_status_bars.dart';

class ExoPlayNetworkPage extends StatefulWidget {
  const ExoPlayNetworkPage({
    super.key,
    required this.title,
    required this.itemId,
    required this.appState,
    this.server,
    this.isTv = false,
    this.seriesId,
    this.startPosition,
    this.resumeImmediately = true,
    this.mediaSourceId,
    this.audioStreamIndex,
    this.subtitleStreamIndex,
  });

  final String title;
  final String itemId;
  final AppState appState;
  final ServerProfile? server;
  final bool isTv;
  final String? seriesId;
  final Duration? startPosition;
  final bool resumeImmediately;
  final String? mediaSourceId;
  final int? audioStreamIndex;
  final int? subtitleStreamIndex; // Emby MediaStream Index, -1 = off

  @override
  State<ExoPlayNetworkPage> createState() => _ExoPlayNetworkPageState();
}

class _ExoPlayNetworkPageState extends State<ExoPlayNetworkPage>
    with WidgetsBindingObserver, RouteAware {
  static const String _kLocalPlaybackProgressPrefix =
      'networkPlaybackProgress_v1:';

  ServerAccess? _serverAccess;
  VideoPlayerController? _controller;
  Timer? _uiTimer;
  PageRoute<dynamic>? _route;

  bool _loading = true;
  String? _playError;
  String? _resolvedStream;
  Map<String, String> _resolvedStreamHeaders = const <String, String>{};
  bool _buffering = false;
  Duration _lastBufferedEnd = Duration.zero;
  DateTime? _lastBufferedAt;
  Duration _bufferSpeedSampleEnd = Duration.zero;
  double? _bufferSpeedX;
  double? _netSpeedBytesPerSecond;
  int? _lastAppRxBytes;
  DateTime? _lastAppRxAt;
  bool _systemNetSpeedPollInFlight = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  DateTime? _lastUiTickAt;
  final _OrientationMode _orientationMode = _OrientationMode.auto;
  String? _lastOrientationKey;
  DateTime? _lastAutoOrientationApplyAt;
  DateTime? _suppressLifecyclePauseUntil;
  Duration? _resumeHintPosition;
  bool _showResumeHint = false;
  Timer? _resumeHintTimer;
  Duration? _startOverHintPosition;
  bool _showStartOverHint = false;
  Timer? _startOverHintTimer;
  bool _deferProgressReporting = false;

  IntroTimestamps? _introTimestamps;
  int _introSeq = 0;
  bool _skipIntroPromptVisible = false;
  bool _skipIntroHandled = false;
  bool _nextEpisodePreloadTriggered = false;
  ResolvedPlaybackSource? _resolvedPlaybackSource;
  String? _preloadHttpProxyUrl;
  String? _playbackCacheFingerprint;
  String _preloadOwnerKey = '';
  bool _allowRoutePop = false;
  bool _exitInProgress = false;

  static const Duration _gestureOverlayAutoHideDelay =
      Duration(milliseconds: 800);
  Timer? _gestureOverlayTimer;
  IconData? _gestureOverlayIcon;
  String? _gestureOverlayText;
  Offset? _doubleTapDownPosition;

  static const Duration _tvOkLongPressDelay = Duration(milliseconds: 420);
  Timer? _tvOkLongPressTimer;
  bool _tvOkLongPressTriggered = false;
  double? _tvOkLongPressBaseRate;

  double _screenBrightness = 1.0; // 0.2..1.0 (visual overlay only)
  double _playerVolume = 1.0; // 0..1

  _GestureMode _gestureMode = _GestureMode.none;
  Offset? _gestureStartPos;
  Duration _seekGestureStartPosition = Duration.zero;
  Duration? _seekGesturePreviewPosition;
  double _gestureStartBrightness = 1.0;
  double _gestureStartVolume = 1.0;

  double? _longPressBaseRate;
  Offset? _longPressStartPos;

  static const Duration _controlsAutoHideDelay = Duration(seconds: 3);
  Timer? _controlsHideTimer;
  bool _controlsVisible = true;
  bool _isScrubbing = false;
  bool _remoteEnabled = false;
  final FocusNode _tvSurfaceFocusNode =
      FocusNode(debugLabel: 'network_exo_player_tv_surface');
  final FocusNode _tvPlayPauseFocusNode =
      FocusNode(debugLabel: 'network_exo_player_tv_play_pause');
  final FocusNode _tvEpisodeSelectedFocusNode =
      FocusNode(debugLabel: 'network_exo_player_tv_episode_selected');
  final FocusNode _tvEpisodeFallbackFocusNode =
      FocusNode(debugLabel: 'network_exo_player_tv_episode_fallback');
  final FocusNode _tvSubtitleSelectedFocusNode =
      FocusNode(debugLabel: 'network_exo_player_tv_subtitle_selected');
  final FocusNode _tvSubtitleFallbackFocusNode =
      FocusNode(debugLabel: 'network_exo_player_tv_subtitle_fallback');
  final FocusNode _tvAudioSelectedFocusNode =
      FocusNode(debugLabel: 'network_exo_player_tv_audio_selected');
  final FocusNode _tvAudioFallbackFocusNode =
      FocusNode(debugLabel: 'network_exo_player_tv_audio_fallback');
  final FocusNode _tvCoreMpvFocusNode =
      FocusNode(debugLabel: 'network_exo_player_tv_core_mpv');
  final FocusNode _tvCoreExoFocusNode =
      FocusNode(debugLabel: 'network_exo_player_tv_core_exo');

  int _tvBottomPanelIndex =
      0; // 0=playback, 1=episodes, 2=subtitles, 3=audio, 4=core
  int? _tvPendingBottomPanelFocus;
  DateTime? _tvNetSpeedLastPollAt;

  bool _tvSubtitleTracksLoading = false;
  String? _tvSubtitleTracksError;
  List<vp_android.ExoPlayerSubtitleTrackData> _tvSubtitleTracks = const [];

  bool _tvAudioTracksLoading = false;
  String? _tvAudioTracksError;
  List<vp_platform.VideoAudioTrack> _tvAudioTracks = const [];

  VideoViewType _viewType = VideoViewType.platformView;
  bool _switchingViewType = false;
  static const int _playbackRouteHistoryLimit = 5;
  final List<String> _playbackRouteHistory = <String>[];

  // Subtitle options (EXO).
  final double _subtitleDelaySeconds = 0.0;
  final double _subtitleFontSize = 18.0;
  final int _subtitlePositionStep =
      5; // 0..20, maps to padding-bottom in 5px steps.
  final bool _subtitleBold = false;
  String _subtitleText = '';
  bool _subtitlePollInFlight = false;

  final GlobalKey<DanmakuStageState> _danmakuKey =
      GlobalKey<DanmakuStageState>();
  final List<DanmakuSource> _danmakuSources = [];
  int _danmakuSourceIndex = -1;
  bool _danmakuEnabled = false;
  double _danmakuOpacity = 1.0;
  double _danmakuScale = 1.0;
  double _danmakuSpeed = 1.0;
  bool _danmakuBold = true;
  int _danmakuMaxLines = 10;
  int _danmakuTopMaxLines = 10;
  int _danmakuBottomMaxLines = 10;
  bool _danmakuPreventOverlap = true;
  bool _danmakuShowHeatmap = true;
  List<double> _danmakuHeatmap = const [];
  int _nextDanmakuIndex = 0;
  bool _danmakuPaused = false;

  String? _playSessionId;
  String? _mediaSourceId;
  List<Map<String, dynamic>> _availableMediaSources = const [];
  String? _selectedMediaSourceId;
  int? _selectedAudioStreamIndex;
  int? _selectedSubtitleStreamIndex;
  Duration? _overrideStartPosition;
  bool _overrideResumeImmediately = false;
  int _lastLocalProgressSecond = -1;
  bool _localProgressWriteInFlight = false;
  int? _pendingLocalProgressTicks;
  ServerPlaybackProgressSync? _serverProgressSync;
  bool _reportedStart = false;
  bool _reportedStop = false;
  bool _markPlayedThresholdReached = false;
  bool _autoMarkedPlayed = false;

  MediaItem? _episodePickerItem;
  bool _episodePickerItemLoading = false;
  bool _episodePickerVisible = false;
  _MobilePlayerPanel? _mobilePanel;
  bool _episodePickerLoading = false;
  String? _episodePickerError;
  List<MediaItem> _episodeSeasons = const [];
  String? _episodeSelectedSeasonId;
  Timer? _mobileSpeedAdjustTimer;
  Future<List<RouteEntry>>? _mobileRouteEntriesFuture;
  Future<List<Map<String, dynamic>>>? _mobileVersionSourcesFuture;
  final Map<String, List<MediaItem>> _episodeEpisodesCache = {};
  final Map<String, Future<List<MediaItem>>> _episodeEpisodesFutureCache = {};

  bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  bool get _isPlaying => _controller?.value.isPlaying ?? false;

  String? get _baseUrl => widget.server?.baseUrl ?? widget.appState.baseUrl;
  String? get _token => widget.server?.token ?? widget.appState.token;
  String? get _userId => widget.server?.userId ?? widget.appState.userId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _serverAccess =
        resolveServerAccess(appState: widget.appState, server: widget.server);
    final access = _serverAccess;
    _serverProgressSync = access == null
        ? null
        : ServerPlaybackProgressSync(
            adapter: access.adapter,
            auth: access.auth,
            itemId: widget.itemId,
            getPosition: () {
              final c = _controller;
              if (c != null && c.value.isInitialized) {
                return c.value.position;
              }
              return _position;
            },
            isPlaying: () => _isPlaying,
            getPlaySessionId: () => _playSessionId,
            getMediaSourceId: () => _mediaSourceId,
          );
    _danmakuEnabled = widget.appState.danmakuEnabled;
    _danmakuOpacity = widget.appState.danmakuOpacity;
    _danmakuScale = widget.appState.danmakuScale;
    _danmakuSpeed = widget.appState.danmakuSpeed;
    _danmakuBold = widget.appState.danmakuBold;
    _danmakuMaxLines = widget.appState.danmakuMaxLines;
    _danmakuTopMaxLines = widget.appState.danmakuTopMaxLines;
    _danmakuBottomMaxLines = widget.appState.danmakuBottomMaxLines;
    _danmakuPreventOverlap = widget.appState.danmakuPreventOverlap;
    _danmakuShowHeatmap = widget.appState.danmakuShowHeatmap;
    _selectedMediaSourceId = widget.mediaSourceId;
    _selectedAudioStreamIndex = widget.audioStreamIndex;
    _selectedSubtitleStreamIndex = widget.subtitleStreamIndex;
    final sid = (widget.seriesId ?? '').trim();
    final serverId = widget.server?.id ?? widget.appState.activeServerId;
    if (serverId != null && serverId.isNotEmpty && sid.isNotEmpty) {
      _selectedAudioStreamIndex ??= widget.appState
          .seriesAudioStreamIndex(serverId: serverId, seriesId: sid);
      _selectedSubtitleStreamIndex ??= widget.appState
          .seriesSubtitleStreamIndex(serverId: serverId, seriesId: sid);
    }
    // ignore: unawaited_futures
    _exitImmersiveMode();
    _init();
    // ignore: unawaited_futures
    _loadEpisodePickerItem();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.isTv) _scheduleControlsHide();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute && route != _route) {
      if (_route != null) appRouteObserver.unsubscribe(this);
      _route = route;
      appRouteObserver.subscribe(this, route);
    }
  }

  @override
  void didPushNext() {
    // User navigated away from the playback page: stop playback & buffering.
    _uiTimer?.cancel();
    _uiTimer = null;
    _serverProgressSync?.stop();
    PlaybackPreloadCoordinator.cancelOwner(_preloadOwnerKey);
    _preloadOwnerKey = '';
    _cancelActivePlaybackCacheFills();
    // ignore: unawaited_futures
    _reportPlaybackStoppedBestEffort();
    // ignore: unawaited_futures
    _controller?.dispose();
    _controller = null;
  }

  void _cancelActivePlaybackCacheFills() {
    final fingerprint = _playbackCacheFingerprint;
    final cancelled = LocalHttpStreamProxy.cancelActivePlaybackFills(
      cacheFingerprint: fingerprint,
    );
    if (cancelled == 0 && (fingerprint ?? '').trim().isNotEmpty) {
      LocalHttpStreamProxy.cancelActivePlaybackFills();
    }
    _playbackCacheFingerprint = null;
  }

  Future<void> _requestExitThenPop() async {
    if (_exitInProgress) return;
    _exitInProgress = true;

    await _shutdownPlaybackForRouteExit();

    try {
      await WidgetsBinding.instance.endOfFrame;
    } catch (_) {}

    if (!mounted) return;
    setState(() => _allowRoutePop = true);
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _shutdownPlaybackForRouteExit() async {
    _controlsHideTimer?.cancel();
    _controlsHideTimer = null;
    _uiTimer?.cancel();
    _uiTimer = null;
    _resumeHintTimer?.cancel();
    _resumeHintTimer = null;
    _startOverHintTimer?.cancel();
    _startOverHintTimer = null;
    _gestureOverlayTimer?.cancel();
    _gestureOverlayTimer = null;
    _tvOkLongPressTimer?.cancel();
    _tvOkLongPressTimer = null;
    _mobileSpeedAdjustTimer?.cancel();
    _mobileSpeedAdjustTimer = null;

    _serverProgressSync?.stop();
    if (_preloadOwnerKey.isNotEmpty) {
      PlaybackPreloadCoordinator.cancelOwner(_preloadOwnerKey);
      _preloadOwnerKey = '';
    }
    _cancelActivePlaybackCacheFills();
    unawaited(_reportPlaybackStoppedBestEffort());

    final controller = _controller;
    _controller = null;
    if (controller != null) {
      try {
        if (controller.value.isInitialized && controller.value.isPlaying) {
          await controller.pause();
        }
      } catch (_) {}
      try {
        await controller.dispose();
      } catch (_) {}
    }

    await _exitImmersiveMode(resetOrientations: true);
  }

  @override
  void dispose() {
    if (_route != null) {
      appRouteObserver.unsubscribe(this);
      _route = null;
    }
    WidgetsBinding.instance.removeObserver(this);
    PlaybackPreloadCoordinator.cancelOwner(_preloadOwnerKey);
    _preloadOwnerKey = '';
    _cancelActivePlaybackCacheFills();
    _controlsHideTimer?.cancel();
    _controlsHideTimer = null;
    _uiTimer?.cancel();
    _uiTimer = null;
    _serverProgressSync?.dispose();
    _serverProgressSync = null;
    _resumeHintTimer?.cancel();
    _resumeHintTimer = null;
    _startOverHintTimer?.cancel();
    _startOverHintTimer = null;
    _gestureOverlayTimer?.cancel();
    _gestureOverlayTimer = null;
    _tvOkLongPressTimer?.cancel();
    _tvOkLongPressTimer = null;
    _mobileSpeedAdjustTimer?.cancel();
    _mobileSpeedAdjustTimer = null;
    // ignore: unawaited_futures
    _reportPlaybackStoppedBestEffort();
    // ignore: unawaited_futures
    _exitImmersiveMode(resetOrientations: true);
    // ignore: unawaited_futures
    _controller?.dispose();
    _controller = null;
    _tvSurfaceFocusNode.dispose();
    _tvPlayPauseFocusNode.dispose();
    _tvEpisodeSelectedFocusNode.dispose();
    _tvEpisodeFallbackFocusNode.dispose();
    _tvSubtitleSelectedFocusNode.dispose();
    _tvSubtitleFallbackFocusNode.dispose();
    _tvAudioSelectedFocusNode.dispose();
    _tvAudioFallbackFocusNode.dispose();
    _tvCoreMpvFocusNode.dispose();
    _tvCoreExoFocusNode.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.inactive &&
        state != AppLifecycleState.paused) {
      return;
    }
    if (widget.appState.returnHomeBehavior != ReturnHomeBehavior.pause) return;
    if (_shouldIgnoreLifecyclePause) return;

    final controller = _controller;
    if (controller == null) return;
    if (!controller.value.isInitialized) return;
    if (!controller.value.isPlaying) return;
    // ignore: unawaited_futures
    controller.pause();
    _applyDanmakuPauseState(true);
  }

  void _applyDanmakuPauseState(bool pause) {
    if (_danmakuPaused == pause) return;
    _danmakuPaused = pause;
    final stage = _danmakuKey.currentState;
    if (pause) {
      stage?.pause();
    } else {
      stage?.resume();
    }
  }

  String _buildDanmakuMatchName(MediaItem item) {
    final seriesName = item.seriesName.trim();
    if (seriesName.isNotEmpty) {
      final episodeNo = item.episodeNumber;
      if (episodeNo != null && episodeNo > 0) {
        return '$seriesName 第$episodeNo集';
      }
      return seriesName;
    }
    final name = item.name.trim();
    final raw = name.isNotEmpty ? name : widget.title;
    final hint = suggestDandanplaySearchInput(stripFileExtension(raw));
    return hint.keyword.isNotEmpty ? hint.keyword : raw;
  }

  bool get _canShowEpisodePickerButton {
    if (_episodePickerVisible) return true;
    if (_episodePickerItemLoading) return true;
    final seriesId = (_episodePickerItem?.seriesId ?? '').trim();
    return seriesId.isNotEmpty;
  }

  Future<void> _loadEpisodePickerItem() async {
    if (_episodePickerItemLoading || _episodePickerItem != null) return;
    final baseUrl = _baseUrl;
    final token = _token;
    final userId = _userId;
    if (baseUrl == null || token == null || userId == null) return;

    setState(() => _episodePickerItemLoading = true);
    final access = _serverAccess;
    if (access == null) {
      if (mounted) {
        setState(() => _episodePickerItemLoading = false);
      }
      return;
    }

    try {
      final detail = await access.adapter
          .fetchItemDetail(access.auth, itemId: widget.itemId);
      if (!mounted) return;
      setState(() => _episodePickerItem = detail);
    } catch (_) {
      // Optional: if this fails, we simply hide the entry point.
    } finally {
      if (mounted) {
        setState(() => _episodePickerItemLoading = false);
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

  Future<void> _toggleEpisodePicker() async {
    if (_episodePickerVisible) {
      _closeMobilePanels(scheduleHide: false);
      return;
    }

    _showControls(scheduleHide: false);
    setState(() {
      _mobilePanel = null;
      _episodePickerVisible = true;
      _episodePickerError = null;
    });
    await _ensureEpisodePickerLoaded();
  }

  bool get _mobileSidePanelVisible =>
      _mobilePanel != null || _episodePickerVisible;

  Future<List<RouteEntry>> _ensureMobileRouteEntriesLoaded({
    bool forceRefresh = false,
  }) {
    if (!forceRefresh && _mobileRouteEntriesFuture != null) {
      return _mobileRouteEntriesFuture!;
    }
    final future = _resolvePlaybackRouteEntries(forceRefresh: forceRefresh);
    _mobileRouteEntriesFuture = future;
    return future;
  }

  Future<List<Map<String, dynamic>>> _ensureMobileVersionSourcesLoaded({
    bool forceRefresh = false,
  }) {
    if (!forceRefresh && _availableMediaSources.isNotEmpty) {
      return SynchronousFuture<List<Map<String, dynamic>>>(
        List<Map<String, dynamic>>.from(_availableMediaSources),
      );
    }
    if (!forceRefresh && _mobileVersionSourcesFuture != null) {
      return _mobileVersionSourcesFuture!;
    }
    final future = _loadMobileVersionSources(forceRefresh: forceRefresh);
    _mobileVersionSourcesFuture = future;
    return future;
  }

  void _openMobilePanel(_MobilePlayerPanel panel) {
    if (panel == _MobilePlayerPanel.route) {
      _ensureMobileRouteEntriesLoaded();
    } else if (panel == _MobilePlayerPanel.version) {
      _ensureMobileVersionSourcesLoaded();
    }
    _showControls(scheduleHide: false);
    setState(() {
      _mobilePanel = panel;
      _episodePickerVisible = false;
    });
  }

  void _closeMobilePanels({bool scheduleHide = true}) {
    _mobileSpeedAdjustTimer?.cancel();
    _mobileSpeedAdjustTimer = null;
    if (!_mobileSidePanelVisible) return;
    setState(() {
      _mobilePanel = null;
      _episodePickerVisible = false;
    });
    _showControls(scheduleHide: scheduleHide);
  }

  Future<void> _setMobilePlaybackRate(double rate) async {
    final normalized =
        ((rate.clamp(0.1, 10.0).toDouble() * 10).round() / 10).toDouble();
    await _controller?.setPlaybackSpeed(normalized);
    if (!mounted) return;
    setState(() {});
  }

  void _stepMobilePlaybackRate(double delta) {
    final current = _controller?.value.playbackSpeed ?? 1.0;
    unawaited(_setMobilePlaybackRate(current + delta));
  }

  void _startMobilePlaybackRateAdjust(double delta) {
    _mobileSpeedAdjustTimer?.cancel();
    _stepMobilePlaybackRate(delta);
    _mobileSpeedAdjustTimer = Timer.periodic(
      const Duration(milliseconds: 120),
      (_) => _stepMobilePlaybackRate(delta),
    );
  }

  void _stopMobilePlaybackRateAdjust() {
    _mobileSpeedAdjustTimer?.cancel();
    _mobileSpeedAdjustTimer = null;
  }

  Future<void> _ensureEpisodePickerLoaded() async {
    if (_episodePickerLoading) return;

    final baseUrl = _baseUrl;
    final token = _token;
    final userId = _userId;
    if (baseUrl == null || token == null || userId == null) {
      setState(() => _episodePickerError = '未连接服务器');
      return;
    }

    setState(() {
      _episodePickerLoading = true;
      _episodePickerError = null;
    });

    try {
      await _loadEpisodePickerItem();
      final detail = _episodePickerItem;
      final seriesId = (detail?.seriesId ?? '').trim();
      if (seriesId.isEmpty) {
        throw Exception('当前不是剧集，无法选集');
      }

      final access = _serverAccess;
      if (access == null) {
        throw Exception('Not connected');
      }

      final seasons =
          await access.adapter.fetchSeasons(access.auth, seriesId: seriesId);
      final seasonItems =
          seasons.items.where((s) => s.type.toLowerCase() == 'season').toList();
      seasonItems.sort((a, b) {
        final aNo = a.seasonNumber ?? a.episodeNumber ?? 0;
        final bNo = b.seasonNumber ?? b.episodeNumber ?? 0;
        return aNo.compareTo(bNo);
      });

      final seasonsForUi = seasonItems.isEmpty
          ? [
              MediaItem(
                id: seriesId,
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
                seriesId: seriesId,
                seriesName: (detail?.seriesName ?? '').trim().isNotEmpty
                    ? detail!.seriesName
                    : detail?.name ?? '',
                seasonName: '第1季',
                seasonNumber: 1,
                episodeNumber: null,
                hasImage: detail?.hasImage ?? false,
                playbackPositionTicks: 0,
                people: const [],
                parentId: seriesId,
              ),
            ]
          : seasonItems;

      final previousSelected = _episodeSelectedSeasonId;
      final currentSeasonId = (detail?.parentId ?? '').trim();
      final defaultSeasonId = (currentSeasonId.isNotEmpty &&
              seasonsForUi.any((s) => s.id == currentSeasonId))
          ? currentSeasonId
          : (seasonsForUi.isNotEmpty ? seasonsForUi.first.id : '');
      final selectedSeasonId = (previousSelected != null &&
              seasonsForUi.any((s) => s.id == previousSelected))
          ? previousSelected
          : (defaultSeasonId.isNotEmpty ? defaultSeasonId : null);

      if (!mounted) return;
      setState(() {
        _episodeSeasons = seasonsForUi;
        _episodeSelectedSeasonId = selectedSeasonId;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _episodePickerError = e.toString());
    } finally {
      if (mounted) {
        setState(() => _episodePickerLoading = false);
      }
    }
  }

  Future<List<MediaItem>> _episodesForSeasonId(String seasonId) async {
    final cached = _episodeEpisodesCache[seasonId];
    if (cached != null) return cached;

    final baseUrl = _baseUrl;
    final token = _token;
    final userId = _userId;
    if (baseUrl == null || token == null || userId == null) {
      throw Exception('未连接服务器');
    }

    final access = _serverAccess;
    if (access == null) {
      throw Exception('Not connected');
    }

    final eps =
        await access.adapter.fetchEpisodes(access.auth, seasonId: seasonId);
    final items = List<MediaItem>.from(eps.items);
    items.sort((a, b) {
      final aNo = a.episodeNumber ?? 0;
      final bNo = b.episodeNumber ?? 0;
      return aNo.compareTo(bNo);
    });
    _episodeEpisodesCache[seasonId] = items;
    return items;
  }

  Future<List<MediaItem>> _episodesFutureForSeasonId(String seasonId) {
    final cachedFuture = _episodeEpisodesFutureCache[seasonId];
    if (cachedFuture != null) return cachedFuture;

    final cached = _episodeEpisodesCache[seasonId];
    final future = cached != null
        ? Future<List<MediaItem>>.value(cached)
        : _episodesForSeasonId(seasonId);
    _episodeEpisodesFutureCache[seasonId] = future;
    return future;
  }

  void _playEpisodeFromPicker(MediaItem episode) {
    if (episode.id == widget.itemId) {
      setState(() => _episodePickerVisible = false);
      return;
    }

    setState(() => _episodePickerVisible = false);
    final ticks = episode.playbackPositionTicks;
    final start =
        ticks > 0 ? Duration(microseconds: (ticks / 10).round()) : null;
    final episodeSeriesId = (episode.seriesId ?? '').trim();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => ExoPlayNetworkPage(
          title: episode.name,
          itemId: episode.id,
          appState: widget.appState,
          server: widget.server,
          isTv: widget.isTv,
          seriesId:
              episodeSeriesId.isNotEmpty ? episodeSeriesId : widget.seriesId,
          startPosition: start,
          resumeImmediately: true,
          audioStreamIndex: _selectedAudioStreamIndex,
          subtitleStreamIndex: _selectedSubtitleStreamIndex,
        ),
      ),
    );
  }

  Widget _buildEpisodePickerOverlay({required bool enableBlur}) {
    final size = MediaQuery.sizeOf(context);
    final drawerWidth = math.min(
      344.0,
      size.width * (size.width > size.height ? 0.40 : 0.54),
    );

    final theme = Theme.of(context);
    final accent = theme.colorScheme.secondary;
    final showTitle = widget.appState.episodePickerShowTitle;

    final seasons = _episodeSeasons;
    final selectedSeasonId = _episodeSelectedSeasonId;
    MediaItem? selectedSeason;
    if (selectedSeasonId != null && selectedSeasonId.isNotEmpty) {
      for (final s in seasons) {
        if (s.id == selectedSeasonId) {
          selectedSeason = s;
          break;
        }
      }
    }
    selectedSeason ??= seasons.isNotEmpty ? seasons.first : null;

    return Positioned.fill(
      child: Stack(
        children: [
          IgnorePointer(
            ignoring: !_episodePickerVisible,
            child: AnimatedOpacity(
              opacity: _episodePickerVisible ? 1 : 0,
              duration: const Duration(milliseconds: 180),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _episodePickerVisible = false),
                child: ColoredBox(
                  color: Colors.black.withValues(alpha: 0.25),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),
          AnimatedPositioned(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            top: 0,
            bottom: 0,
            right: _episodePickerVisible ? 0 : -drawerWidth - 12,
            width: drawerWidth,
            child: IgnorePointer(
              ignoring: !_episodePickerVisible,
              child: SafeArea(
                left: false,
                minimum: const EdgeInsets.fromLTRB(0, 8, 0, 8),
                child: GlassCard(
                  enableBlur: enableBlur,
                  margin: EdgeInsets.zero,
                  elevation: 0,
                  shadowColor: Colors.transparent,
                  surfaceTintColor: Colors.transparent,
                  color: Colors.black.withValues(alpha: 0.35),
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.horizontal(
                      left: Radius.circular(16),
                    ),
                  ),
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 10, 8, 8),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.format_list_numbered,
                              color: Colors.white,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              '选集',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(width: 8),
                            if (selectedSeason != null)
                              Expanded(
                                child: Container(
                                  height: 36,
                                  padding:
                                      const EdgeInsets.symmetric(horizontal: 8),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.18),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color:
                                          Colors.white.withValues(alpha: 0.12),
                                    ),
                                  ),
                                  child: DropdownButtonHideUnderline(
                                    child: DropdownButton<String>(
                                      value: selectedSeason.id,
                                      isExpanded: true,
                                      isDense: true,
                                      dropdownColor: const Color(0xFF202020),
                                      iconEnabledColor: Colors.white70,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                      ),
                                      items: [
                                        for (final entry
                                            in seasons.asMap().entries)
                                          DropdownMenuItem(
                                            value: entry.value.id,
                                            child: Text(
                                              _seasonLabel(
                                                entry.value,
                                                entry.key,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                      ],
                                      onChanged: (v) {
                                        if (v == null || v.isEmpty) return;
                                        if (v == _episodeSelectedSeasonId) {
                                          return;
                                        }
                                        setState(() {
                                          _episodeSelectedSeasonId = v;
                                        });
                                      },
                                    ),
                                  ),
                                ),
                              )
                            else
                              const Spacer(),
                            IconButton(
                              tooltip: showTitle ? '仅显示集数' : '显示标题+封面',
                              icon: Icon(
                                showTitle
                                    ? Icons.grid_view_outlined
                                    : Icons.view_agenda_outlined,
                              ),
                              color: Colors.white,
                              onPressed: () {
                                final next =
                                    !widget.appState.episodePickerShowTitle;
                                // ignore: unawaited_futures
                                widget.appState.setEpisodePickerShowTitle(next);
                                setState(() {});
                              },
                            ),
                            IconButton(
                              tooltip: '关闭',
                              icon: const Icon(Icons.close),
                              color: Colors.white,
                              onPressed: () =>
                                  setState(() => _episodePickerVisible = false),
                            ),
                          ],
                        ),
                      ),
                      if (_episodePickerLoading)
                        const Padding(
                          padding: EdgeInsets.all(16),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else if (_episodePickerError != null)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                _episodePickerError!,
                                style: const TextStyle(color: Colors.white70),
                              ),
                              const SizedBox(height: 10),
                              OutlinedButton.icon(
                                onPressed: _ensureEpisodePickerLoaded,
                                icon: const Icon(Icons.refresh),
                                label: const Text('重试'),
                              ),
                            ],
                          ),
                        )
                      else if (selectedSeason == null)
                        const Padding(
                          padding: EdgeInsets.all(16),
                          child: Text(
                            '暂无剧集信息',
                            style: TextStyle(color: Colors.white70),
                          ),
                        )
                      else ...[
                        Expanded(
                          child: FutureBuilder<List<MediaItem>>(
                            future:
                                _episodesFutureForSeasonId(selectedSeason.id),
                            builder: (ctx, snapshot) {
                              if (snapshot.connectionState !=
                                  ConnectionState.done) {
                                return const Center(
                                  child: CircularProgressIndicator(),
                                );
                              }
                              if (snapshot.hasError) {
                                return Padding(
                                  padding:
                                      const EdgeInsets.fromLTRB(16, 0, 16, 16),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Text(
                                        '加载失败：${snapshot.error}',
                                        style: const TextStyle(
                                          color: Colors.white70,
                                        ),
                                      ),
                                      const SizedBox(height: 10),
                                      OutlinedButton.icon(
                                        onPressed: () => setState(() {
                                          final season = selectedSeason;
                                          if (season == null) return;
                                          _episodeEpisodesCache
                                              .remove(season.id);
                                          _episodeEpisodesFutureCache
                                              .remove(season.id);
                                        }),
                                        icon: const Icon(Icons.refresh),
                                        label: const Text('重试'),
                                      ),
                                    ],
                                  ),
                                );
                              }

                              final eps = snapshot.data ?? const <MediaItem>[];
                              if (eps.isEmpty) {
                                return const Center(
                                  child: Text(
                                    '暂无剧集',
                                    style: TextStyle(color: Colors.white70),
                                  ),
                                );
                              }

                              if (showTitle) {
                                return ListView.separated(
                                  padding: const EdgeInsets.fromLTRB(
                                    12,
                                    0,
                                    12,
                                    12,
                                  ),
                                  itemCount: eps.length,
                                  separatorBuilder: (_, __) =>
                                      const SizedBox(height: 10),
                                  itemBuilder: (ctx, index) {
                                    final e = eps[index];
                                    final epNo = e.episodeNumber ?? (index + 1);
                                    final episodeTitle = e.name.trim().isEmpty
                                        ? '第$epNo集'
                                        : e.name.trim();
                                    final isCurrent = e.id == widget.itemId;
                                    final borderColor = isCurrent
                                        ? accent.withValues(alpha: 0.85)
                                        : Colors.white.withValues(alpha: 0.10);
                                    final access = _serverAccess;
                                    final img = access?.adapter.imageUrl(
                                      access.auth,
                                      itemId: e.hasImage
                                          ? e.id
                                          : selectedSeason!.id,
                                      maxWidth: 520,
                                    );
                                    return Material(
                                      color:
                                          Colors.black.withValues(alpha: 0.18),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        side: BorderSide(color: borderColor),
                                      ),
                                      clipBehavior: Clip.antiAlias,
                                      child: InkWell(
                                        onTap: () => _playEpisodeFromPicker(e),
                                        child: Padding(
                                          padding: const EdgeInsets.all(10),
                                          child: Row(
                                            children: [
                                              ClipRRect(
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                                child: SizedBox(
                                                  width: 110,
                                                  height: 62,
                                                  child: Stack(
                                                    fit: StackFit.expand,
                                                    children: [
                                                      if (img != null)
                                                        LinNetworkImage(
                                                          imageUrl: img,
                                                          fit: BoxFit.cover,
                                                          errorWidget:
                                                              const ColoredBox(
                                                            color: Color(
                                                              0x22000000,
                                                            ),
                                                            child: Center(
                                                              child: Icon(
                                                                Icons
                                                                    .image_not_supported_outlined,
                                                                color: Colors
                                                                    .white54,
                                                              ),
                                                            ),
                                                          ),
                                                        )
                                                      else
                                                        const ColoredBox(
                                                          color:
                                                              Color(0x22000000),
                                                          child: Center(
                                                            child: Icon(
                                                              Icons
                                                                  .image_outlined,
                                                              color: Colors
                                                                  .white54,
                                                            ),
                                                          ),
                                                        ),
                                                      Positioned(
                                                        left: 6,
                                                        bottom: 6,
                                                        child: DecoratedBox(
                                                          decoration:
                                                              BoxDecoration(
                                                            color: const Color(
                                                              0xAA000000,
                                                            ),
                                                            borderRadius:
                                                                BorderRadius
                                                                    .circular(
                                                              6,
                                                            ),
                                                          ),
                                                          child: Padding(
                                                            padding:
                                                                const EdgeInsets
                                                                    .symmetric(
                                                              horizontal: 6,
                                                              vertical: 3,
                                                            ),
                                                            child: Text(
                                                              'E$epNo',
                                                              style:
                                                                  const TextStyle(
                                                                color: Colors
                                                                    .white,
                                                                fontSize: 11,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w700,
                                                              ),
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                      if (isCurrent)
                                                        const Positioned(
                                                          right: 6,
                                                          top: 6,
                                                          child: Icon(
                                                            Icons.play_circle,
                                                            color: Colors.white,
                                                          ),
                                                        ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 12),
                                              Expanded(
                                                child: Builder(
                                                  builder: (context) {
                                                    final sizeBytes =
                                                        e.sizeBytes;
                                                    final ticks =
                                                        e.runTimeTicks ?? 0;
                                                    final seconds = ticks > 0
                                                        ? ticks / 10000000.0
                                                        : 0.0;
                                                    final bitrate =
                                                        sizeBytes != null &&
                                                                sizeBytes > 0 &&
                                                                seconds > 0
                                                            ? ((sizeBytes * 8) /
                                                                    seconds)
                                                                .round()
                                                            : null;
                                                    String formatBytes(
                                                        int? value) {
                                                      if (value == null ||
                                                          value <= 0) {
                                                        return '--';
                                                      }
                                                      const kb = 1024;
                                                      const mb = 1024 * 1024;
                                                      const gb =
                                                          1024 * 1024 * 1024;
                                                      if (value >= gb) {
                                                        return '${(value / gb).toStringAsFixed(1)} GB';
                                                      }
                                                      if (value >= mb) {
                                                        return '${(value / mb).toStringAsFixed(1)} MB';
                                                      }
                                                      if (value >= kb) {
                                                        return '${(value / kb).toStringAsFixed(1)} KB';
                                                      }
                                                      return '$value B';
                                                    }

                                                    String formatBitrate(
                                                        int? value) {
                                                      if (value == null ||
                                                          value <= 0) {
                                                        return '--';
                                                      }
                                                      return '${(value / 1000000).toStringAsFixed(1)} Mbps';
                                                    }

                                                    return Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      mainAxisAlignment:
                                                          MainAxisAlignment
                                                              .center,
                                                      children: [
                                                        Text(
                                                          'E${epNo.toString().padLeft(2, '0')}',
                                                          style:
                                                              const TextStyle(
                                                            color: Colors.white,
                                                            fontSize: 14,
                                                            fontWeight:
                                                                FontWeight.w800,
                                                            letterSpacing: 0.3,
                                                          ),
                                                        ),
                                                        const SizedBox(
                                                            height: 4),
                                                        Text(
                                                          episodeTitle,
                                                          maxLines: 2,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                          style:
                                                              const TextStyle(
                                                            color: Colors.white,
                                                            fontSize: 13,
                                                            fontWeight:
                                                                FontWeight.w700,
                                                            height: 1.25,
                                                          ),
                                                        ),
                                                        const SizedBox(
                                                            height: 8),
                                                        Wrap(
                                                          spacing: 6,
                                                          runSpacing: 6,
                                                          children: [
                                                            MobilePlayerInfoTag(
                                                              label:
                                                                  formatBytes(
                                                                sizeBytes,
                                                              ),
                                                            ),
                                                            MobilePlayerInfoTag(
                                                              label:
                                                                  formatBitrate(
                                                                bitrate,
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      ],
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

                              return ListView.separated(
                                padding: const EdgeInsets.fromLTRB(
                                  12,
                                  0,
                                  12,
                                  12,
                                ),
                                itemCount: eps.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 8),
                                itemBuilder: (ctx, index) {
                                  final e = eps[index];
                                  final epNo = e.episodeNumber ?? (index + 1);
                                  final episodeTitle = e.name.trim().isEmpty
                                      ? '第$epNo集'
                                      : e.name.trim();
                                  final isCurrent = e.id == widget.itemId;
                                  final borderColor = isCurrent
                                      ? accent.withValues(alpha: 0.85)
                                      : Colors.white.withValues(alpha: 0.10);

                                  return Material(
                                    color: Colors.black.withValues(alpha: 0.18),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      side: BorderSide(color: borderColor),
                                    ),
                                    clipBehavior: Clip.antiAlias,
                                    child: InkWell(
                                      onTap: () => _playEpisodeFromPicker(e),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 14,
                                          vertical: 12,
                                        ),
                                        child: Row(
                                          children: [
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 10,
                                                vertical: 6,
                                              ),
                                              decoration: BoxDecoration(
                                                color: Colors.white.withValues(
                                                  alpha: 0.10,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(999),
                                              ),
                                              child: Text(
                                                'E${epNo.toString().padLeft(2, '0')}',
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w800,
                                                  letterSpacing: 0.2,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: Text(
                                                episodeTitle,
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w700,
                                                  height: 1.25,
                                                ),
                                              ),
                                            ),
                                            if (isCurrent)
                                              const Padding(
                                                padding:
                                                    EdgeInsets.only(left: 10),
                                                child: Icon(
                                                  Icons.play_circle,
                                                  color: Colors.white,
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              );
                            },
                          ),
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

  void _maybeAutoLoadOnlineDanmaku() {
    final appState = widget.appState;
    if (!appState.danmakuEnabled) return;
    if (appState.danmakuLoadMode != DanmakuLoadMode.online) return;
    if (kIsWeb) return;
    // ignore: unawaited_futures
    _loadOnlineDanmakuForNetwork(showToast: false);
  }

  static bool _looksLikeIntroChapterName(String raw) {
    final name = raw.trim().toLowerCase();
    if (name.isEmpty) return false;
    if (name.contains('片头')) return true;
    if (name.contains('intro') || name.contains('opening')) return true;
    if (RegExp(r'\bop\b').hasMatch(name)) return true;
    return false;
  }

  static IntroTimestamps? _introFromChapters(List<ChapterInfo> chapters) {
    if (chapters.length < 2) return null;
    final sorted = List<ChapterInfo>.from(chapters)
      ..sort((a, b) => a.startTicks.compareTo(b.startTicks));
    for (var i = 0; i < sorted.length - 1; i++) {
      final cur = sorted[i];
      if (!_looksLikeIntroChapterName(cur.name)) continue;
      final next = sorted[i + 1];
      final intro = IntroTimestamps(
        startTicks: cur.startTicks,
        endTicks: next.startTicks,
      );
      if (!intro.isValid) continue;
      if (intro.end - intro.start > const Duration(minutes: 10)) continue;
      return intro;
    }
    return null;
  }

  Future<void> _loadIntroTimestampsBestEffort() async {
    if (!widget.appState.autoSkipIntro) return;
    final access = _serverAccess;
    if (access == null) return;

    final seq = _introSeq;

    try {
      final ts = await access.adapter.fetchIntroTimestamps(
        access.auth,
        itemId: widget.itemId,
      );
      if (!mounted || seq != _introSeq) return;
      if (ts != null && ts.isValid) {
        _introTimestamps = ts;
        _maybeUpdateSkipIntroPrompt(_position);
        return;
      }
    } catch (_) {
      // Ignore unsupported endpoints or transient errors.
    }

    try {
      final chapters = await access.adapter
          .fetchChapters(access.auth, itemId: widget.itemId);
      if (!mounted || seq != _introSeq) return;
      final ts = _introFromChapters(chapters);
      if (ts == null) return;
      _introTimestamps = ts;
      _maybeUpdateSkipIntroPrompt(_position);
    } catch (_) {
      // Ignore chapter failures.
    }
  }

  void _maybeUpdateSkipIntroPrompt(Duration pos) {
    if (_skipIntroHandled ||
        !_skipIntroPromptVisible && !widget.appState.autoSkipIntro) {
      return;
    }

    final ts = _introTimestamps;
    if (ts == null || !ts.isValid || !widget.appState.autoSkipIntro) {
      if (_skipIntroPromptVisible) {
        setState(() => _skipIntroPromptVisible = false);
      }
      return;
    }

    final start = ts.start;
    final end = ts.end;
    if (pos > end) {
      if (_skipIntroPromptVisible) {
        setState(() => _skipIntroPromptVisible = false);
      }
      _skipIntroHandled = true;
      return;
    }

    final inIntro = pos >= start && pos <= end;
    if (inIntro && !_skipIntroPromptVisible) {
      setState(() => _skipIntroPromptVisible = true);
    } else if (!inIntro && _skipIntroPromptVisible) {
      setState(() => _skipIntroPromptVisible = false);
    }
  }

  void _dismissSkipIntroPrompt() {
    if (_skipIntroHandled) return;
    _skipIntroHandled = true;
    if (_skipIntroPromptVisible) {
      setState(() => _skipIntroPromptVisible = false);
    }
  }

  Future<void> _skipIntro() async {
    final ts = _introTimestamps;
    final controller = _controller;
    if (ts == null || !ts.isValid || controller == null) return;

    _skipIntroHandled = true;
    if (mounted) setState(() => _skipIntroPromptVisible = false);

    final target = _safeSeekTarget(ts.end, controller.value.duration);
    await controller.seekTo(target);
  }

  Future<void> _preloadCurrentItemBestEffort({
    required Duration startPosition,
    required String triggerSource,
  }) async {
    if (!widget.appState.preloadEnabled) return;
    final resolvedSource = _resolvedPlaybackSource;
    if (resolvedSource == null) return;
    final effectiveStart =
        startPosition < Duration.zero ? Duration.zero : startPosition;

    final result = await PlaybackPreloadCoordinator.preloadPrepared(
      PlaybackPreloadCoordinator.prepareResolved(
        appState: widget.appState,
        targetKind: PlaybackPreloadTargetKind.currentItem,
        triggerSource: triggerSource,
        resolvedSource: resolvedSource,
        startPosition: effectiveStart,
        httpProxyUrl: _preloadHttpProxyUrl,
        ownerKey: _preloadOwnerKey,
        scopeKey: 'playback_current',
      ),
    );

    if (!mounted) return;
    if (result.disabledNow) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('预加载失败，当前源将暂时跳过')),
      );
    }
  }

  Future<void>? _startCurrentItemPreloadWarmup({
    required Duration startPosition,
    required String triggerSource,
  }) {
    if (!widget.appState.preloadEnabled) return null;
    return _preloadCurrentItemBestEffort(
      startPosition: startPosition,
      triggerSource: triggerSource,
    );
  }

  void _maybePreloadNextEpisode(Duration pos) {
    if (_nextEpisodePreloadTriggered) return;
    if (!widget.appState.preloadEnabled) return;

    final total = _duration;
    if (total <= Duration.zero) return;
    final remaining = total - pos;
    if (remaining > const Duration(seconds: 5)) return;

    _nextEpisodePreloadTriggered = true;
    final access = _serverAccess;
    if (access == null) return;
    unawaited(_preloadNextEpisodeBestEffort(access));
  }

  Future<void> _preloadNextEpisodeBestEffort(ServerAccess access) async {
    final nextId = await _resolveNextEpisodeIdBestEffort(access);
    if (nextId == null || nextId.trim().isEmpty) return;
    StreamPreloadResult result;
    try {
      result = await PlaybackPreloadCoordinator.preloadItem(
        PlaybackPreloadBuildRequest(
          access: access,
          appState: widget.appState,
          itemId: nextId.trim(),
          playerCore: PlaybackSourcePlayerCoreKind.exo,
          targetKind: PlaybackPreloadTargetKind.nextItem,
          triggerSource: 'playback_next',
          selectedMediaSourceId: _selectedMediaSourceId,
          preferredMediaSourceIndex: _preferredMediaSourceIndex(),
          audioStreamIndex: _selectedAudioStreamIndex,
          subtitleStreamIndex: _selectedSubtitleStreamIndex,
          preferredVideoVersion: widget.appState.preferredVideoVersion,
          ownerKey: _preloadOwnerKey,
          scopeKey: 'playback_next',
        ),
      );
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

  Future<String?> _resolveNextEpisodeIdBestEffort(ServerAccess access) async {
    try {
      final detail = await access.adapter
          .fetchItemDetail(access.auth, itemId: widget.itemId);
      final seriesId = (detail.seriesId ?? widget.seriesId ?? '').trim();
      final seasonId = (detail.parentId ?? '').trim();
      if (seriesId.isEmpty || seasonId.isEmpty) return null;

      final eps =
          await access.adapter.fetchEpisodes(access.auth, seasonId: seasonId);
      final items = List<MediaItem>.from(eps.items);
      items.sort((a, b) {
        final aNo = a.episodeNumber ?? 0;
        final bNo = b.episodeNumber ?? 0;
        return aNo.compareTo(bNo);
      });
      final idx = items.indexWhere((e) => e.id == widget.itemId);
      if (idx >= 0 && idx + 1 < items.length) {
        return items[idx + 1].id;
      }

      final seasons =
          await access.adapter.fetchSeasons(access.auth, seriesId: seriesId);
      final seasonItems =
          seasons.items.where((s) => s.type.toLowerCase() == 'season').toList();
      seasonItems.sort((a, b) {
        final aNo = a.seasonNumber ?? a.episodeNumber ?? 0;
        final bNo = b.seasonNumber ?? b.episodeNumber ?? 0;
        return aNo.compareTo(bNo);
      });
      if (seasonItems.isEmpty) return null;

      final curIdx = seasonItems.indexWhere((s) => s.id == seasonId);
      if (curIdx < 0 || curIdx + 1 >= seasonItems.length) return null;

      final nextSeasonId = seasonItems[curIdx + 1].id;
      final nextEps = await access.adapter
          .fetchEpisodes(access.auth, seasonId: nextSeasonId);
      final nextItems = List<MediaItem>.from(nextEps.items);
      nextItems.sort((a, b) {
        final aNo = a.episodeNumber ?? 0;
        final bNo = b.episodeNumber ?? 0;
        return aNo.compareTo(bNo);
      });
      if (nextItems.isEmpty) return null;
      return nextItems.first.id;
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadOnlineDanmakuForNetwork({bool showToast = true}) async {
    final appState = widget.appState;
    if (appState.danmakuApiUrls.isEmpty) {
      if (showToast && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请先在设置-弹幕中添加在线弹幕源')),
        );
      }
      return;
    }

    var fileName = widget.title;
    int fileSizeBytes = 0;
    int videoDurationSeconds = 0;
    try {
      final access = _serverAccess;
      if (access != null) {
        final item = await access.adapter.fetchItemDetail(
          access.auth,
          itemId: widget.itemId,
        );
        fileName = _buildDanmakuMatchName(item);
        fileSizeBytes = item.sizeBytes ?? 0;
        final ticks = item.runTimeTicks ?? 0;
        if (ticks > 0) {
          videoDurationSeconds = (ticks / 10000000).round().clamp(0, 1 << 31);
        }
      }
    } catch (_) {}

    if (videoDurationSeconds <= 0) {
      videoDurationSeconds = _duration.inSeconds;
    }

    try {
      final sources = await loadOnlineDanmakuSources(
        apiUrls: appState.danmakuApiUrls,
        fileName: fileName,
        fileHash: null,
        fileSizeBytes: fileSizeBytes,
        videoDurationSeconds: videoDurationSeconds,
        matchMode: appState.danmakuMatchMode,
        chConvert: appState.danmakuChConvert,
        mergeRelated: appState.danmakuMergeRelated,
        throwIfEmpty: showToast,
      );
      if (!mounted) return;
      final processed = processDanmakuSources(
        sources,
        blockWords: appState.danmakuBlockWords,
        mergeDuplicates: appState.danmakuMergeDuplicates,
      );
      if (processed.isEmpty) {
        if (showToast) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('未匹配到在线弹幕')),
          );
        }
        return;
      }
      setState(() {
        _danmakuSources.addAll(processed);
        final desiredName = appState.danmakuRememberSelectedSource
            ? appState.danmakuLastSelectedSourceName
            : '';
        final idx = desiredName.isEmpty
            ? -1
            : _danmakuSources.indexWhere((s) => s.name == desiredName);
        _danmakuSourceIndex = idx >= 0 ? idx : (_danmakuSources.length - 1);
        _danmakuEnabled = true;
        _rebuildDanmakuHeatmap();
        _syncDanmakuCursor(_position);
      });

      await _ensureDanmakuVisible();

      if (showToast && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已加载在线弹幕：${sources.length} 个来源')),
        );
      }
    } catch (e) {
      if (showToast && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('在线弹幕加载失败：$e')),
        );
      }
    }
  }

  Future<void> _manualMatchOnlineDanmakuForCurrent({
    bool showToast = true,
  }) async {
    final appState = widget.appState;
    if (appState.danmakuApiUrls.isEmpty) {
      if (showToast && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请先在设置-弹幕中添加在线弹幕源')),
        );
      }
      return;
    }

    var matchName = widget.title;
    try {
      final access = _serverAccess;
      if (access != null) {
        final item = await access.adapter.fetchItemDetail(
          access.auth,
          itemId: widget.itemId,
        );
        matchName = _buildDanmakuMatchName(item);
      }
    } catch (_) {}

    final fallbackKeyword = stripFileExtension(matchName);
    final hint = suggestDandanplaySearchInput(fallbackKeyword);
    if (!mounted) return;
    final candidate = await showDanmakuManualSearchDialog(
      context: context,
      apiUrls: appState.danmakuApiUrls,
      initialKeyword: hint.keyword.isEmpty ? fallbackKeyword : hint.keyword,
      initialEpisodeHint: null,
    );
    if (!mounted || candidate == null) return;

    try {
      final title = '${candidate.animeTitle} ${candidate.episodeTitle}'.trim();
      final source = await loadOnlineDanmakuByEpisodeId(
        apiUrl: candidate.inputBaseUrl,
        episodeId: candidate.episodeId,
        sourceHost: candidate.sourceHost,
        title: title,
        chConvert: appState.danmakuChConvert,
        mergeRelated: appState.danmakuMergeRelated,
      );
      if (!mounted) return;
      if (source == null) {
        if (showToast) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('该条目未返回可用弹幕')),
          );
        }
        return;
      }

      final processed = processDanmakuSources(
        [source],
        blockWords: appState.danmakuBlockWords,
        mergeDuplicates: appState.danmakuMergeDuplicates,
      );
      if (processed.isEmpty) {
        if (showToast) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('弹幕已加载但被过滤规则全部移除')),
          );
        }
        return;
      }

      setState(() {
        _danmakuSources.addAll(processed);
        _danmakuSourceIndex = _danmakuSources.length - 1;
        _danmakuEnabled = true;
        _rebuildDanmakuHeatmap();
        _syncDanmakuCursor(_position);
      });

      await _ensureDanmakuVisible();
      if (!mounted) return;

      if (showToast) {
        final displayTitle =
            title.isEmpty ? 'episodeId=${candidate.episodeId}' : title;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已手动匹配并加载弹幕：$displayTitle')),
        );
      }
    } catch (e) {
      if (showToast && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('手动匹配加载失败：$e')),
        );
      }
    }
  }

  void _syncDanmakuCursor(Duration position) {
    if (_danmakuSourceIndex < 0 ||
        _danmakuSourceIndex >= _danmakuSources.length) {
      _nextDanmakuIndex = 0;
      return;
    }
    final items = _danmakuSources[_danmakuSourceIndex].items;
    _nextDanmakuIndex = DanmakuParser.lowerBoundByTime(items, position);
    _danmakuKey.currentState?.clear();
  }

  void _rebuildDanmakuHeatmap() {
    if (!_danmakuShowHeatmap) {
      _danmakuHeatmap = const [];
      return;
    }
    if (_duration <= Duration.zero ||
        _danmakuSourceIndex < 0 ||
        _danmakuSourceIndex >= _danmakuSources.length) {
      _danmakuHeatmap = const [];
      return;
    }
    _danmakuHeatmap = buildDanmakuHeatmap(
      _danmakuSources[_danmakuSourceIndex].items,
      duration: _duration,
    );
  }

  void _drainDanmaku(Duration position) {
    if (!_danmakuEnabled) return;
    if (_danmakuSourceIndex < 0 ||
        _danmakuSourceIndex >= _danmakuSources.length) {
      return;
    }
    final stage = _danmakuKey.currentState;
    if (stage == null) return;

    final items = _danmakuSources[_danmakuSourceIndex].items;
    while (_nextDanmakuIndex < items.length &&
        items[_nextDanmakuIndex].time <= position) {
      stage.emit(items[_nextDanmakuIndex]);
      _nextDanmakuIndex++;
    }
  }

  Future<void> _pickDanmakuFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['xml'],
      withData: kIsWeb,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;

    String content = '';
    if (kIsWeb) {
      final bytes = file.bytes;
      if (bytes == null) return;
      content = DanmakuParser.decodeBytes(bytes);
    } else {
      final path = file.path;
      if (path == null || path.trim().isEmpty) return;
      final bytes = await File(path).readAsBytes();
      content = DanmakuParser.decodeBytes(bytes);
    }

    var items = DanmakuParser.parseBilibiliXml(content);
    items = processDanmakuItems(
      items,
      blockWords: widget.appState.danmakuBlockWords,
      mergeDuplicates: widget.appState.danmakuMergeDuplicates,
    );
    if (!mounted) return;
    setState(() {
      _danmakuSources.add(DanmakuSource(name: file.name, items: items));
      final desiredName = widget.appState.danmakuRememberSelectedSource
          ? widget.appState.danmakuLastSelectedSourceName
          : '';
      final idx = desiredName.isEmpty
          ? -1
          : _danmakuSources.indexWhere((s) => s.name == desiredName);
      _danmakuSourceIndex = idx >= 0 ? idx : (_danmakuSources.length - 1);
      _danmakuEnabled = true;
      _rebuildDanmakuHeatmap();
      _syncDanmakuCursor(_position);
    });

    await _ensureDanmakuVisible();
  }

  Map<String, String> _embyHeaders() {
    return _resolvedStreamHeaders;
  }

  Future<void> _ensureDanmakuVisible() async {
    if (!_isAndroid) return;
    if (_viewType == VideoViewType.textureView) return;
    if (_switchingViewType) return;

    final stream = _resolvedStream;
    if (stream == null || stream.trim().isEmpty) {
      setState(() => _viewType = VideoViewType.textureView);
      return;
    }

    _switchingViewType = true;
    try {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text('为显示弹幕已切换到纹理渲染（部分 HDR/DV 片源可能偏色）'),
              duration: Duration(milliseconds: 1200),
            ),
          );
      }
      await _reopenStreamWithViewType(VideoViewType.textureView);
    } finally {
      _switchingViewType = false;
    }
  }

  Future<void> _reopenStreamWithViewType(VideoViewType next) async {
    if (!_isAndroid) return;
    final stream = _resolvedStream;
    if (stream == null || stream.trim().isEmpty) return;
    if (_viewType == next && _controller != null) return;

    final wasPlaying = _isPlaying;
    final pos = _position;

    _uiTimer?.cancel();
    _uiTimer = null;

    final prev = _controller;
    _controller = null;
    if (prev != null) {
      await prev.dispose();
    }

    setState(() {
      _viewType = next;
      _buffering = false;
      _playError = null;
      _subtitleText = '';
      _subtitlePollInFlight = false;
    });

    final controller = VideoPlayerController.networkUrl(
      Uri.parse(stream),
      httpHeaders: _embyHeaders(),
      viewType: next,
    );
    _controller = controller;
    await controller.initialize();
    await _applyExoSubtitleOptions();
    await _maybeAutoSelectSubtitleTrack(controller);

    final target = _safeSeekTarget(pos, controller.value.duration);
    if (target > Duration.zero) {
      try {
        await controller.seekTo(target).timeout(const Duration(seconds: 3));
        _position = target;
        _syncDanmakuCursor(target);
      } catch (_) {}
    }

    if (wasPlaying) {
      await _ensurePlaybackAutoStarts(controller);
    } else {
      await controller.pause();
    }

    _uiTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      final c = _controller;
      if (!mounted || c == null) return;
      final v = c.value;
      _buffering = v.isBuffering;
      _position = v.position;
      _duration = v.duration;

      _applyDanmakuPauseState(_buffering || !_isPlaying);
      _drainDanmaku(_position);
      if (!_isAndroid || _viewType == VideoViewType.textureView) {
        // ignore: unawaited_futures
        _pollSubtitleText();
      }

      _maybeReportPlaybackProgress(_position);
      _maybePreloadNextEpisode(_position);

      if (!_reportedStop &&
          _duration > Duration.zero &&
          !_buffering &&
          !v.isPlaying &&
          _position >= _duration - const Duration(milliseconds: 200)) {
        // ignore: unawaited_futures
        _reportPlaybackStoppedBestEffort(completed: true);
      }

      final now = DateTime.now();
      final shouldRebuild = _lastUiTickAt == null ||
          now.difference(_lastUiTickAt!) >= const Duration(milliseconds: 250);
      if (shouldRebuild) {
        _lastUiTickAt = now;
        setState(() {});
      }
    });

    _scheduleControlsHide();
    if (mounted) setState(() {});
  }

  void _showControls({bool scheduleHide = true}) {
    if (!_controlsVisible) {
      setState(() => _controlsVisible = true);
    }
    // ignore: unawaited_futures
    _exitImmersiveMode();
    if (scheduleHide && (!_remoteEnabled || widget.isTv)) {
      _scheduleControlsHide();
    } else {
      _controlsHideTimer?.cancel();
      _controlsHideTimer = null;
    }
  }

  void _toggleControls() {
    if (!_controlsVisible) {
      _showControls();
      return;
    }
    _controlsHideTimer?.cancel();
    _controlsHideTimer = null;
    setState(() {
      _controlsVisible = false;
      _tvBottomPanelIndex = 0;
      _tvPendingBottomPanelFocus = null;
    });
    // ignore: unawaited_futures
    _enterImmersiveMode();
    if (_remoteEnabled) _focusTvSurface();
  }

  void _focusTvSurface() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      FocusScope.of(context).requestFocus(_tvSurfaceFocusNode);
    });
  }

  void _focusTvPlayPause() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!_controlsVisible) return;
      FocusScope.of(context).requestFocus(_tvPlayPauseFocusNode);
    });
  }

  static const int _tvBottomPanelCount = 5;

  void _setTvBottomPanel(int index) {
    final next = index.clamp(0, _tvBottomPanelCount - 1);
    if (_tvBottomPanelIndex == next) return;
    setState(() => _tvBottomPanelIndex = next);
    _tvPendingBottomPanelFocus = next;
    if (next == 0) {
      _focusTvPlayPause();
    }
    if (next == 1) {
      // ignore: unawaited_futures
      _ensureEpisodePickerLoaded();
      return;
    }
    if (next == 2) {
      // ignore: unawaited_futures
      _refreshTvSubtitleTracks();
      return;
    }
    if (next == 3) {
      // ignore: unawaited_futures
      _refreshTvAudioTracks();
      return;
    }
  }

  void _cycleTvBottomPanel({required bool forward}) {
    if (forward) {
      _setTvBottomPanel((_tvBottomPanelIndex + 1) % _tvBottomPanelCount);
      return;
    }
    // Don't wrap backwards: keep arrow-up behavior predictable.
    if (_tvBottomPanelIndex <= 0) return;
    _setTvBottomPanel(_tvBottomPanelIndex - 1);
  }

  void _requestTvBottomPanelFocusIfNeeded(int panelIndex, FocusNode node) {
    if (!widget.isTv) return;
    if (_tvPendingBottomPanelFocus != panelIndex) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_tvBottomPanelIndex != panelIndex) return;
      if (_tvPendingBottomPanelFocus != panelIndex) return;
      FocusScope.of(context).requestFocus(node);
      _tvPendingBottomPanelFocus = null;
    });
  }

  String _tvTitleText() {
    final detail = _episodePickerItem;
    final seriesId = (widget.seriesId ?? '').trim();
    final type = (detail?.type ?? '').trim().toLowerCase();
    final isEpisode =
        seriesId.isNotEmpty || type == 'episode' || type == 'tv episode';
    if (!isEpisode) return widget.title;

    final seasonNo = detail?.seasonNumber;
    final epNo = detail?.episodeNumber;
    if (seasonNo == null || seasonNo <= 0 || epNo == null || epNo <= 0) {
      return widget.title;
    }

    return '第$seasonNo季 第$epNo集 ${widget.title}'.trim();
  }

  static String _tvFmtTime(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(t.hour)}:${two(t.minute)}';
  }

  static String _tvFmtNetSpeedMb(double? bytesPerSecond) {
    final v = bytesPerSecond;
    if (v == null || !v.isFinite || v < 0) return '— MB/S';
    final mb = v / (1024.0 * 1024.0);
    return '${mb.toStringAsFixed(1)} MB/S';
  }

  String _mobileTopTitleText() {
    final item = _episodePickerItem;
    final title = (item?.name ?? '').trim().isNotEmpty
        ? item!.name.trim()
        : widget.title.trim();
    if (item == null) return title;
    if (item.type.trim().toLowerCase() != 'episode') return title;
    final season = item.seasonNumber ?? 0;
    final episode = item.episodeNumber ?? 0;
    if (season <= 0 || episode <= 0) return title;
    final mark =
        'S${season.toString().padLeft(2, '0')}E${episode.toString().padLeft(2, '0')}';
    if (title.isEmpty) return mark;
    return '$mark $title';
  }

  String _mobileNetSpeedLabel() {
    final speed = _netSpeedBytesPerSecond;
    if (speed != null && speed.isFinite && speed > 0) {
      return formatBytesPerSecond(speed);
    }
    return '--';
  }

  List<Widget> _buildMobileTopActions(
    BuildContext context, {
    required bool controlsEnabled,
  }) {
    return [
      MobilePlayerActionButton(
        icon: Icons.route_outlined,
        label: '线路',
        compact: true,
        onTap: controlsEnabled
            ? () => _openMobilePanel(_MobilePlayerPanel.route)
            : null,
      ),
      MobilePlayerActionButton(
        icon: Icons.video_file_outlined,
        label: '版本',
        compact: true,
        onTap: controlsEnabled
            ? () => _openMobilePanel(_MobilePlayerPanel.version)
            : null,
      ),
      MobilePlayerActionButton(
        icon: Icons.audiotrack_outlined,
        label: '音频',
        compact: true,
        onTap: controlsEnabled
            ? () => _openMobilePanel(_MobilePlayerPanel.audio)
            : null,
      ),
      MobilePlayerActionButton(
        icon: Icons.tune,
        label:
            widget.appState.playerCore == PlayerCore.exo ? '内核 Exo' : '内核 mpv',
        compact: true,
        onTap: controlsEnabled
            ? () => _openMobilePanel(_MobilePlayerPanel.core)
            : null,
      ),
      MobilePlayerActionButton(
        icon: Icons.auto_fix_high_outlined,
        label: '超分 关',
        compact: true,
        onTap: controlsEnabled
            ? () => _openMobilePanel(_MobilePlayerPanel.superResolution)
            : null,
      ),
    ];
  }

  Widget _buildMobileTopStatusBar(
    BuildContext context, {
    required bool controlsEnabled,
  }) {
    return MobilePlayerTopStatusBar(
      title: _mobileTopTitleText(),
      actions: _buildMobileTopActions(
        context,
        controlsEnabled: controlsEnabled,
      ),
    );
  }

  Widget _buildMobileBottomStatusBar(
    BuildContext context, {
    required bool controlsEnabled,
    required VideoPlayerController controller,
  }) {
    return MobilePlayerBottomStatusBar(
      position: _position,
      buffered: _lastBufferedEnd,
      duration: _duration,
      positionLabel: _fmtClock(_position),
      durationLabel: _fmtClock(_duration),
      leftContent: Text(
        '网速 ${_mobileNetSpeedLabel()}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      centerContent: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          MobilePlayerTransportButton(
            icon: Icons.fast_rewind_rounded,
            onTap: controlsEnabled
                ? () {
                    _showControls();
                    unawaited(
                      _seekRelative(
                        Duration(seconds: -_seekBackSeconds),
                        showOverlay: false,
                      ),
                    );
                  }
                : null,
          ),
          const SizedBox(width: 4),
          MobilePlayerTransportButton(
            icon: _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
            emphasized: true,
            onTap: controlsEnabled
                ? () {
                    _showControls();
                    unawaited(_togglePlayPause(showOverlay: false));
                  }
                : null,
          ),
          const SizedBox(width: 4),
          MobilePlayerTransportButton(
            icon: Icons.fast_forward_rounded,
            onTap: controlsEnabled
                ? () {
                    _showControls();
                    unawaited(
                      _seekRelative(
                        Duration(seconds: _seekForwardSeconds),
                        showOverlay: false,
                      ),
                    );
                  }
                : null,
          ),
        ],
      ),
      rightContent: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            MobilePlayerActionButton(
              icon: Icons.speed_rounded,
              label: '倍速',
              compact: true,
              onTap: controlsEnabled
                  ? () => _openMobilePanel(_MobilePlayerPanel.speed)
                  : null,
            ),
            MobilePlayerActionButton(
              icon: (_danmakuEnabled || _danmakuHeatmap.isNotEmpty)
                  ? Icons.comment
                  : Icons.comment_outlined,
              label: '弹幕',
              compact: true,
              onTap: controlsEnabled
                  ? () => _openMobilePanel(_MobilePlayerPanel.danmaku)
                  : null,
            ),
            MobilePlayerActionButton(
              icon: Icons.subtitles_outlined,
              label: '字幕',
              compact: true,
              onTap: controlsEnabled
                  ? () => _openMobilePanel(_MobilePlayerPanel.subtitle)
                  : null,
            ),
            MobilePlayerActionButton(
              icon: Icons.format_list_numbered,
              label: '选集',
              compact: true,
              onTap: controlsEnabled && _canShowEpisodePickerButton
                  ? () {
                      _showControls(scheduleHide: false);
                      unawaited(_toggleEpisodePicker());
                    }
                  : null,
            ),
          ],
        ),
      ),
      onScrubStart: controlsEnabled ? _onScrubStart : null,
      onSeekPreview: controlsEnabled
          ? (target) => setState(() => _position = target)
          : null,
      onSeekCommit: controlsEnabled
          ? (target) async {
              await controller.seekTo(target);
              _maybeReportPlaybackProgress(target, force: true);
              _syncDanmakuCursor(target);
              _onScrubEnd();
              if (mounted) setState(() {});
            }
          : null,
    );
  }

  String _mobilePanelTitle(_MobilePlayerPanel panel) {
    return switch (panel) {
      _MobilePlayerPanel.route => '线路',
      _MobilePlayerPanel.version => '版本',
      _MobilePlayerPanel.audio => '音频',
      _MobilePlayerPanel.core => '内核',
      _MobilePlayerPanel.superResolution => '超分',
      _MobilePlayerPanel.danmaku => '弹幕',
      _MobilePlayerPanel.subtitle => '字幕',
      _MobilePlayerPanel.speed => '倍速',
    };
  }

  Future<List<Map<String, dynamic>>> _loadMobileVersionSources({
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh && _availableMediaSources.isNotEmpty) {
      return List<Map<String, dynamic>>.from(_availableMediaSources);
    }
    final access = _serverAccess;
    if (access == null) return const <Map<String, dynamic>>[];
    final info = await access.adapter.fetchPlaybackInfo(
      access.auth,
      itemId: widget.itemId,
      exoPlayer: true,
    );
    final sources = List<Map<String, dynamic>>.from(
      info.mediaSources.cast<Map<String, dynamic>>(),
    );
    _availableMediaSources = List<Map<String, dynamic>>.from(sources);
    return sources;
  }

  Future<List<vp_platform.VideoAudioTrack>> _loadMobileAudioTracks() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const <vp_platform.VideoAudioTrack>[];
    }
    final platform = vp_platform.VideoPlayerPlatform.instance;
    if (!platform.isAudioTrackSupportAvailable()) {
      return const <vp_platform.VideoAudioTrack>[];
    }
    // ignore: invalid_use_of_visible_for_testing_member
    return platform.getAudioTracks(_videoPlayerId(controller));
  }

  int _videoPlayerId(VideoPlayerController controller) {
    // ignore: invalid_use_of_visible_for_testing_member
    return controller.playerId;
  }

  Future<List<vp_android.ExoPlayerSubtitleTrackData>>
      _loadMobileSubtitleTracks() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const <vp_android.ExoPlayerSubtitleTrackData>[];
    }
    // ignore: invalid_use_of_visible_for_testing_member
    final playerId = _videoPlayerId(controller);
    final api = vp_android.VideoPlayerInstanceApi(
      messageChannelSuffix: playerId.toString(),
    );
    final data = await api.getSubtitleTracks();
    return data.exoPlayerTracks ??
        const <vp_android.ExoPlayerSubtitleTrackData>[];
  }

  Widget _buildMobileSpeedOverlay({required bool controlsEnabled}) {
    final currentRate =
        (_controller?.value.playbackSpeed ?? 1.0).clamp(0.1, 10.0).toDouble();
    final visible = _mobilePanel == _MobilePlayerPanel.speed;
    return MobilePlayerSpeedOverlay(
      visible: visible,
      currentRate: currentRate,
      enabled: controlsEnabled,
      onDismiss: _closeMobilePanels,
      onIncrease: () => _stepMobilePlaybackRate(0.1),
      onDecrease: () => _stepMobilePlaybackRate(-0.1),
      onIncreaseHoldStart: () => _startMobilePlaybackRateAdjust(0.1),
      onIncreaseHoldEnd: _stopMobilePlaybackRateAdjust,
      onDecreaseHoldStart: () => _startMobilePlaybackRateAdjust(-0.1),
      onDecreaseHoldEnd: _stopMobilePlaybackRateAdjust,
    );
  }

  Widget _buildMobileCorePanel({required bool controlsEnabled}) {
    final current = widget.appState.playerCore;

    return ListView(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 12),
      children: [
        MobilePlayerOptionTile(
          title: 'Exo',
          subtitle: '当前使用 Android Exo 播放内核',
          selected: current == PlayerCore.exo,
          trailing: current == PlayerCore.exo
              ? const Icon(Icons.check_circle, color: Colors.white)
              : null,
        ),
        const SizedBox(height: 8),
        MobilePlayerOptionTile(
          title: 'mpv',
          subtitle: '切换到 media_kit/mpv 播放内核',
          selected: current == PlayerCore.mpv,
          trailing: current == PlayerCore.mpv
              ? const Icon(Icons.check_circle, color: Colors.white)
              : null,
          onTap: current == PlayerCore.mpv || !controlsEnabled
              ? null
              : () {
                  _closeMobilePanels(scheduleHide: false);
                  unawaited(_switchCore());
                },
        ),
      ],
    );
  }

  Widget _buildMobileRoutePanel({required bool controlsEnabled}) {
    return FutureBuilder<List<RouteEntry>>(
      future: _ensureMobileRouteEntriesLoaded(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  snapshot.error.toString(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: controlsEnabled
                      ? () {
                          setState(() {
                            _mobileRouteEntriesFuture =
                                _ensureMobileRouteEntriesLoaded(
                              forceRefresh: true,
                            );
                          });
                        }
                      : null,
                  icon: const Icon(Icons.refresh),
                  label: const Text('重试'),
                ),
              ],
            ),
          );
        }
        final entries = snapshot.data ?? const <RouteEntry>[];
        if (entries.isEmpty) {
          return const Center(
              child: Text('暂无可用线路', style: TextStyle(color: Colors.white70)));
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 12),
          itemCount: entries.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final entry = entries[index];
            final domain = entry.domain;
            final selected = (_baseUrl ?? '').trim() == domain.url;
            final remark = (_playbackDomainRemark(domain.url) ?? '').trim();
            final name = domain.name.trim();
            final displayName = name.isNotEmpty
                ? name
                : (remark.isNotEmpty ? remark : '线路 ${index + 1}');
            return MobilePlayerOptionTile(
              title: displayName,
              selected: selected,
              trailing: selected
                  ? const Icon(Icons.check_circle_rounded, color: Colors.white)
                  : null,
              onTap: !controlsEnabled || selected
                  ? null
                  : () {
                      _closeMobilePanels(scheduleHide: false);
                      unawaited(_switchPlaybackRoute(domain.url));
                    },
            );
          },
        );
      },
    );
  }

  Widget _buildMobileVersionPanel({required bool controlsEnabled}) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _ensureMobileVersionSourcesLoaded(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final sources = List<Map<String, dynamic>>.from(
          snapshot.data ?? const <Map<String, dynamic>>[],
        )..sort(_compareMediaSourcesByQuality);
        if (sources.isEmpty) {
          return const Center(
              child: Text('无法获取版本列表', style: TextStyle(color: Colors.white70)));
        }
        final current = (_mediaSourceId ?? _selectedMediaSourceId ?? '').trim();
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 12),
          itemCount: sources.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final ms = sources[index];
            final selected = (ms['Id']?.toString() ?? '').trim() == current;
            return MobilePlayerOptionTile(
              title: _mediaSourceTitle(ms),
              subtitle: _mediaSourceSubtitle(ms),
              selected: selected,
              trailing: selected
                  ? const Icon(Icons.check_circle_rounded, color: Colors.white)
                  : null,
              onTap: !controlsEnabled || selected
                  ? null
                  : () {
                      unawaited(() async {
                        final selectedId = (ms['Id']?.toString() ?? '').trim();
                        if (selectedId.isEmpty) return;
                        final sid = (widget.seriesId ?? '').trim();
                        final serverId =
                            widget.server?.id ?? widget.appState.activeServerId;
                        if (serverId != null &&
                            serverId.isNotEmpty &&
                            sid.isNotEmpty) {
                          final idx = sources.indexWhere(
                            (item) =>
                                (item['Id']?.toString() ?? '').trim() ==
                                selectedId,
                          );
                          if (idx >= 0) {
                            unawaited(
                              widget.appState.setSeriesMediaSourceIndex(
                                serverId: serverId,
                                seriesId: sid,
                                mediaSourceIndex: idx,
                              ),
                            );
                          }
                        }
                        _closeMobilePanels(scheduleHide: false);
                        setState(() {
                          _selectedMediaSourceId = selectedId;
                          _selectedAudioStreamIndex = null;
                          _selectedSubtitleStreamIndex = null;
                          _overrideStartPosition = _position;
                          _overrideResumeImmediately = true;
                        });
                        await _init();
                      }());
                    },
            );
          },
        );
      },
    );
  }

  Widget _buildMobileAudioPanel({required bool controlsEnabled}) {
    return FutureBuilder<List<vp_platform.VideoAudioTrack>>(
      future: _loadMobileAudioTracks(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final tracks = snapshot.data ?? const <vp_platform.VideoAudioTrack>[];
        if (tracks.isEmpty) {
          return const Center(
              child: Text('暂无音频可选', style: TextStyle(color: Colors.white70)));
        }
        final controller = _controller;
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 12),
          itemCount: tracks.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final track = tracks[index];
            return MobilePlayerOptionTile(
              title: _audioTrackTitle(track),
              subtitle: _audioTrackSubtitle(track),
              selected: track.isSelected,
              trailing: track.isSelected
                  ? const Icon(Icons.check_circle_rounded, color: Colors.white)
                  : null,
              onTap: !controlsEnabled || track.isSelected || controller == null
                  ? null
                  : () {
                      unawaited(() async {
                        final platform =
                            vp_platform.VideoPlayerPlatform.instance;
                        // ignore: invalid_use_of_visible_for_testing_member
                        await platform.selectAudioTrack(
                          _videoPlayerId(controller),
                          track.id,
                        );
                        if (!mounted) return;
                        setState(() {});
                      }());
                    },
            );
          },
        );
      },
    );
  }

  Widget _buildMobileSubtitlePanel({required bool controlsEnabled}) {
    return FutureBuilder<List<vp_android.ExoPlayerSubtitleTrackData>>(
      future: _loadMobileSubtitleTracks(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final tracks =
            snapshot.data ?? const <vp_android.ExoPlayerSubtitleTrackData>[];
        final controller = _controller;
        return ListView(
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 12),
          children: [
            MobilePlayerOptionTile(
              title: '关闭字幕',
              selected: !tracks.any((track) => track.isSelected),
              trailing: !tracks.any((track) => track.isSelected)
                  ? const Icon(Icons.check_circle_rounded, color: Colors.white)
                  : null,
              onTap: !controlsEnabled || controller == null
                  ? null
                  : () {
                      unawaited(() async {
                        // ignore: invalid_use_of_visible_for_testing_member
                        final api = vp_android.VideoPlayerInstanceApi(
                          messageChannelSuffix:
                              _videoPlayerId(controller).toString(),
                        );
                        await api.deselectSubtitleTrack();
                        if (!mounted) return;
                        setState(() {});
                      }());
                    },
            ),
            if (tracks.isNotEmpty) const SizedBox(height: 8),
            for (final track in tracks) ...[
              MobilePlayerOptionTile(
                title: _subtitleTrackTitle(track),
                subtitle: _subtitleTrackSubtitle(track),
                selected: track.isSelected,
                trailing: track.isSelected
                    ? const Icon(Icons.check_circle_rounded,
                        color: Colors.white)
                    : null,
                onTap: !controlsEnabled || controller == null
                    ? null
                    : () {
                        unawaited(() async {
                          // ignore: invalid_use_of_visible_for_testing_member
                          final api = vp_android.VideoPlayerInstanceApi(
                            messageChannelSuffix:
                                _videoPlayerId(controller).toString(),
                          );
                          await api.selectSubtitleTrack(
                            track.groupIndex,
                            track.trackIndex,
                          );
                          if (!mounted) return;
                          setState(() {});
                        }());
                      },
              ),
              const SizedBox(height: 8),
            ],
          ],
        );
      },
    );
  }

  Widget _buildMobileSuperResolutionPanel() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 12),
      children: const [
        MobilePlayerOptionTile(
          title: 'Exo 内核暂不支持超分',
          subtitle: '如需 Anime4K/超分，可在上方内核面板切换到 mpv',
        ),
      ],
    );
  }

  Widget _buildMobileDanmakuPanel({required bool controlsEnabled}) {
    final hasSources = _danmakuSources.isNotEmpty;
    final selectedName = (_danmakuSourceIndex >= 0 &&
            _danmakuSourceIndex < _danmakuSources.length)
        ? _danmakuSources[_danmakuSourceIndex].name
        : '未选择';

    return ListView(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 12),
      children: [
        MobilePlayerOptionTile(
          title: '启用弹幕',
          subtitle: hasSources ? selectedName : '尚未加载弹幕',
          trailing: Switch(
            value: _danmakuEnabled,
            onChanged: !controlsEnabled
                ? null
                : (value) {
                    setState(() => _danmakuEnabled = value);
                    if (!value) {
                      _danmakuKey.currentState?.clear();
                    }
                  },
          ),
        ),
        const SizedBox(height: 8),
        MobilePlayerOptionTile(
          title: '导入本地弹幕',
          leading: const Icon(Icons.upload_file_outlined, color: Colors.white),
          onTap: controlsEnabled
              ? () {
                  unawaited(_pickDanmakuFile());
                }
              : null,
        ),
        const SizedBox(height: 8),
        MobilePlayerOptionTile(
          title: '加载在线弹幕',
          leading:
              const Icon(Icons.cloud_download_outlined, color: Colors.white),
          onTap: controlsEnabled
              ? () {
                  unawaited(_loadOnlineDanmakuForNetwork(showToast: true));
                }
              : null,
        ),
        const SizedBox(height: 8),
        MobilePlayerOptionTile(
          title: '手动匹配弹幕',
          leading: const Icon(Icons.search, color: Colors.white),
          onTap: controlsEnabled
              ? () {
                  unawaited(
                      _manualMatchOnlineDanmakuForCurrent(showToast: true));
                }
              : null,
        ),
        const SizedBox(height: 12),
        Text(
          '透明度 ${(_danmakuOpacity * 100).round()}%',
          style: const TextStyle(color: Colors.white70),
        ),
        Slider(
          value: _danmakuOpacity.clamp(0.2, 1.0),
          min: 0.2,
          max: 1.0,
          onChanged: !controlsEnabled
              ? null
              : (value) {
                  setState(() => _danmakuOpacity = value);
                },
        ),
      ],
    );
  }

  Widget _buildMobileSidePanelOverlay({
    required BuildContext context,
    required bool controlsEnabled,
  }) {
    final panel = _mobilePanel;
    final visibleSidePanel = panel != null && panel != _MobilePlayerPanel.speed;
    final effectivePanel = visibleSidePanel ? panel : _MobilePlayerPanel.route;

    Widget? headerTrailing;
    Widget child = const SizedBox.shrink();
    if (visibleSidePanel) {
      switch (effectivePanel) {
        case _MobilePlayerPanel.route:
          child = _buildMobileRoutePanel(controlsEnabled: controlsEnabled);
          headerTrailing = IconButton(
            tooltip: '刷新线路',
            onPressed: controlsEnabled
                ? () {
                    setState(() {
                      _mobileRouteEntriesFuture =
                          _ensureMobileRouteEntriesLoaded(
                        forceRefresh: true,
                      );
                    });
                  }
                : null,
            icon: const Icon(Icons.refresh_rounded),
            color: Colors.white,
            splashRadius: 20,
          );
          break;
        case _MobilePlayerPanel.version:
          child = _buildMobileVersionPanel(controlsEnabled: controlsEnabled);
          break;
        case _MobilePlayerPanel.audio:
          child = _buildMobileAudioPanel(controlsEnabled: controlsEnabled);
          break;
        case _MobilePlayerPanel.core:
          child = _buildMobileCorePanel(controlsEnabled: controlsEnabled);
          break;
        case _MobilePlayerPanel.superResolution:
          child = _buildMobileSuperResolutionPanel();
          break;
        case _MobilePlayerPanel.danmaku:
          child = _buildMobileDanmakuPanel(controlsEnabled: controlsEnabled);
          break;
        case _MobilePlayerPanel.subtitle:
          child = _buildMobileSubtitlePanel(controlsEnabled: controlsEnabled);
          break;
        case _MobilePlayerPanel.speed:
          break;
      }
    }

    return Stack(
      children: [
        _buildMobileSpeedOverlay(controlsEnabled: controlsEnabled),
        MobilePlayerSidePanel(
          title: _mobilePanelTitle(effectivePanel),
          visible: visibleSidePanel,
          onDismiss: _closeMobilePanels,
          headerTrailing: headerTrailing,
          child: child,
        ),
      ],
    );
  }

  Future<void> _refreshTvSubtitleTracks() async {
    if (_tvSubtitleTracksLoading) return;
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (!_isAndroid) return;

    setState(() {
      _tvSubtitleTracksLoading = true;
      _tvSubtitleTracksError = null;
    });
    try {
      // ignore: invalid_use_of_visible_for_testing_member
      final playerId = controller.playerId;
      final api = vp_android.VideoPlayerInstanceApi(
        messageChannelSuffix: playerId.toString(),
      );
      final data = await api.getSubtitleTracks();
      if (!mounted) return;
      setState(() {
        _tvSubtitleTracks = data.exoPlayerTracks ??
            const <vp_android.ExoPlayerSubtitleTrackData>[];
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _tvSubtitleTracks = const <vp_android.ExoPlayerSubtitleTrackData>[];
        _tvSubtitleTracksError = '获取字幕失败';
      });
    } finally {
      if (mounted) {
        setState(() => _tvSubtitleTracksLoading = false);
      }
    }
  }

  Future<void> _tvSelectSubtitleTrack(
      vp_android.ExoPlayerSubtitleTrackData? track) async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (!_isAndroid) return;

    try {
      // ignore: invalid_use_of_visible_for_testing_member
      final playerId = controller.playerId;
      final api = vp_android.VideoPlayerInstanceApi(
        messageChannelSuffix: playerId.toString(),
      );
      if (track == null) {
        await api.deselectSubtitleTrack();
      } else {
        await api.selectSubtitleTrack(track.groupIndex, track.trackIndex);
      }
    } catch (_) {}

    if (!mounted) return;
    await _refreshTvSubtitleTracks();
  }

  Future<void> _refreshTvAudioTracks() async {
    if (_tvAudioTracksLoading) return;
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;

    final platform = vp_platform.VideoPlayerPlatform.instance;
    if (!platform.isAudioTrackSupportAvailable()) {
      setState(() {
        _tvAudioTracks = const <vp_platform.VideoAudioTrack>[];
        _tvAudioTracksError = '当前内核不支持音轨切换';
      });
      return;
    }

    setState(() {
      _tvAudioTracksLoading = true;
      _tvAudioTracksError = null;
    });
    try {
      // ignore: invalid_use_of_visible_for_testing_member
      final playerId = controller.playerId;
      final tracks = await platform.getAudioTracks(playerId);
      if (!mounted) return;
      setState(() => _tvAudioTracks = tracks);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _tvAudioTracks = const <vp_platform.VideoAudioTrack>[];
        _tvAudioTracksError = '获取音轨失败';
      });
    } finally {
      if (mounted) {
        setState(() => _tvAudioTracksLoading = false);
      }
    }
  }

  Future<void> _tvSelectAudioTrack(vp_platform.VideoAudioTrack track) async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;

    final platform = vp_platform.VideoPlayerPlatform.instance;
    if (!platform.isAudioTrackSupportAvailable()) return;

    try {
      // ignore: invalid_use_of_visible_for_testing_member
      final playerId = controller.playerId;
      await platform.selectAudioTrack(playerId, track.id);
    } catch (_) {}

    if (!mounted) return;
    await _refreshTvAudioTracks();
  }

  Future<void> _pickTvSeason() async {
    if (_episodePickerLoading) return;
    await _ensureEpisodePickerLoaded();
    if (!mounted) return;

    final seasons = _episodeSeasons;
    if (seasons.isEmpty) return;
    final currentId = (_episodeSelectedSeasonId ?? seasons.first.id).trim();
    if (currentId.isEmpty) return;

    final picked = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('选择季'),
          content: SizedBox(
            width: 520,
            height: 420,
            child: ListView.separated(
              itemCount: seasons.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final season = seasons[index];
                final selected = season.id == currentId;
                return TvFocusable(
                  autofocus: selected,
                  onPressed: () => Navigator.of(ctx).pop(season.id),
                  borderRadius: BorderRadius.circular(12),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _seasonLabel(season, index),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (selected) const Icon(Icons.check, size: 18),
                    ],
                  ),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('取消'),
            ),
          ],
        );
      },
    );

    if (!mounted) return;
    final nextId = (picked ?? '').trim();
    if (nextId.isEmpty || nextId == currentId) return;
    setState(() => _episodeSelectedSeasonId = nextId);
  }

  Color _tvHudBg(ColorScheme scheme) {
    final isDark = scheme.brightness == Brightness.dark;
    return isDark ? const Color(0xE6000000) : const Color(0xE6FFFFFF);
  }

  Color _tvHudFg(ColorScheme scheme) =>
      scheme.brightness == Brightness.dark ? Colors.white : Colors.black;

  Widget _buildTvTopStatusBar() {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final uiScale = context.uiScale;

    final pillBg = scheme.brightness == Brightness.dark
        ? Colors.black.withValues(alpha: 0.34)
        : Colors.white.withValues(alpha: 0.70);
    final fg = _tvHudFg(scheme);

    final radius = (18 * uiScale).clamp(14.0, 26.0);
    final padH = (14 * uiScale).clamp(10.0, 18.0);
    final padV = (10 * uiScale).clamp(8.0, 14.0);

    Widget pill(Widget child) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: pillBg,
          borderRadius: BorderRadius.circular(radius),
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: padH, vertical: padV),
          child: child,
        ),
      );
    }

    final now = DateTime.now();
    final title = _tvTitleText();
    final speed = _tvFmtNetSpeedMb(_netSpeedBytesPerSecond);
    final time = _tvFmtTime(now);

    final titleStyle = theme.textTheme.titleMedium?.copyWith(
      color: fg,
      fontWeight: FontWeight.w800,
    );
    final rightStyle = theme.textTheme.labelLarge?.copyWith(
      color: fg,
      fontWeight: FontWeight.w800,
    );

    return Row(
      children: [
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: pill(
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: titleStyle,
              ),
            ),
          ),
        ),
        SizedBox(width: (12 * uiScale).clamp(8.0, 16.0)),
        pill(Text(speed, style: rightStyle)),
        SizedBox(width: (10 * uiScale).clamp(8.0, 16.0)),
        pill(Text(time, style: rightStyle)),
      ],
    );
  }

  Widget _buildTvProgressBar({
    required double progress,
    required double buffered,
    required Color progressColor,
    required Color bufferedColor,
    required Color trackColor,
    double height = 10,
  }) {
    final p = progress.clamp(0.0, 1.0);
    final b = buffered.clamp(0.0, 1.0);

    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: SizedBox(
        height: height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: trackColor),
            FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: b,
              child: ColoredBox(color: bufferedColor),
            ),
            FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: p,
              child: ColoredBox(color: progressColor),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTvChip({
    required String label,
    required VoidCallback? onPressed,
    bool autofocus = false,
    bool selected = false,
    IconData? icon,
    FocusNode? focusNode,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final uiScale = context.uiScale;
    final isDark = scheme.brightness == Brightness.dark;

    final padH = (12 * uiScale).clamp(10.0, 16.0);
    final padV = (10 * uiScale).clamp(8.0, 14.0);

    final surface = selected
        ? scheme.primary.withValues(alpha: isDark ? 0.28 : 0.18)
        : (isDark
            ? Colors.white.withValues(alpha: 0.12)
            : Colors.black.withValues(alpha: 0.06));
    final focusedSurface =
        scheme.primary.withValues(alpha: isDark ? 0.38 : 0.22);

    final effectiveOnPressed = onPressed == null
        ? null
        : () {
            _showControls();
            onPressed();
          };

    return TvFocusable(
      focusNode: focusNode,
      autofocus: autofocus,
      enabled: effectiveOnPressed != null,
      onPressed: effectiveOnPressed,
      borderRadius: BorderRadius.circular(999),
      surfaceColor: surface,
      focusedSurfaceColor: focusedSurface,
      padding: EdgeInsets.symmetric(horizontal: padH, vertical: padV),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: (18 * uiScale).clamp(16.0, 22.0)),
            SizedBox(width: (8 * uiScale).clamp(6.0, 10.0)),
          ],
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 240),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTvEpisodesPanel({required bool enabled}) {
    if (_episodePickerLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    final err = (_episodePickerError ?? '').trim();
    if (err.isNotEmpty) {
      return Center(child: Text(err));
    }

    final seasons = _episodeSeasons;
    if (seasons.isEmpty) {
      return const Center(child: Text('暂无可选剧集'));
    }

    final selectedSeasonId =
        ((_episodeSelectedSeasonId ?? '').trim().isNotEmpty)
            ? _episodeSelectedSeasonId!.trim()
            : seasons.first.id;
    final selectedSeason = seasons.firstWhere(
      (s) => s.id == selectedSeasonId,
      orElse: () => seasons.first,
    );

    return Row(
      children: [
        if (seasons.length > 1) ...[
          _buildTvChip(
            label: _seasonLabel(
              selectedSeason,
              seasons.indexOf(selectedSeason),
            ),
            icon: Icons.layers_outlined,
            onPressed: enabled ? _pickTvSeason : null,
          ),
          const SizedBox(width: 10),
        ],
        Expanded(
          child: FutureBuilder<List<MediaItem>>(
            future: _episodesFutureForSeasonId(selectedSeason.id),
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return const Center(child: Text('加载剧集失败'));
              }
              final eps = snapshot.data ?? const <MediaItem>[];
              if (eps.isEmpty) {
                return const Center(child: Text('暂无剧集'));
              }

              final selectedIndex =
                  eps.indexWhere((e) => e.id == widget.itemId);
              final focusNode = selectedIndex >= 0
                  ? _tvEpisodeSelectedFocusNode
                  : _tvEpisodeFallbackFocusNode;
              final autofocusIndex = selectedIndex >= 0 ? selectedIndex : 0;
              _requestTvBottomPanelFocusIfNeeded(1, focusNode);

              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final entry in eps.asMap().entries) ...[
                      if (entry.key > 0) const SizedBox(width: 10),
                      _buildTvChip(
                        autofocus: entry.key == autofocusIndex,
                        focusNode:
                            entry.key == autofocusIndex ? focusNode : null,
                        selected: entry.value.id == widget.itemId,
                        label: (entry.value.episodeNumber ?? (entry.key + 1))
                            .toString(),
                        onPressed: !enabled
                            ? null
                            : () => _playEpisodeFromPicker(entry.value),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildTvSubtitlePanel({required bool enabled}) {
    if (_tvSubtitleTracksLoading && _tvSubtitleTracks.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    final err = (_tvSubtitleTracksError ?? '').trim();
    if (err.isNotEmpty && _tvSubtitleTracks.isEmpty) {
      return Center(child: Text(err));
    }

    final tracks = _tvSubtitleTracks;
    final selected = tracks.where((t) => t.isSelected).toList();
    final offSelected = selected.isEmpty;

    if (tracks.isEmpty) {
      _requestTvBottomPanelFocusIfNeeded(2, _tvSubtitleFallbackFocusNode);
      return Row(
        children: [
          _buildTvChip(
            autofocus: true,
            selected: offSelected,
            label: '关闭',
            icon: Icons.subtitles_off_outlined,
            focusNode: _tvSubtitleFallbackFocusNode,
            onPressed: enabled ? () => _tvSelectSubtitleTrack(null) : null,
          ),
          const SizedBox(width: 12),
          const Expanded(child: Text('暂无字幕')),
        ],
      );
    }

    final selectedIndex = tracks.indexWhere((t) => t.isSelected);
    final hasSelected = selectedIndex >= 0;
    _requestTvBottomPanelFocusIfNeeded(
      2,
      hasSelected ? _tvSubtitleSelectedFocusNode : _tvSubtitleFallbackFocusNode,
    );

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _buildTvChip(
            autofocus: !hasSelected,
            selected: offSelected,
            label: '关闭',
            icon: Icons.subtitles_off_outlined,
            focusNode: _tvSubtitleFallbackFocusNode,
            onPressed: enabled ? () => _tvSelectSubtitleTrack(null) : null,
          ),
          for (final entry in tracks.asMap().entries) ...[
            const SizedBox(width: 10),
            _buildTvChip(
              autofocus: hasSelected && entry.key == selectedIndex,
              selected: entry.value.isSelected,
              label: _subtitleTrackTitle(entry.value),
              icon: Icons.subtitles_outlined,
              focusNode: hasSelected && entry.key == selectedIndex
                  ? _tvSubtitleSelectedFocusNode
                  : null,
              onPressed:
                  !enabled ? null : () => _tvSelectSubtitleTrack(entry.value),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTvAudioPanel({required bool enabled}) {
    if (_tvAudioTracksLoading && _tvAudioTracks.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    final err = (_tvAudioTracksError ?? '').trim();
    if (err.isNotEmpty) {
      return Center(child: Text(err));
    }

    final tracks = _tvAudioTracks;
    if (tracks.isEmpty) {
      return const Center(child: Text('暂无音轨'));
    }

    final selectedIndex = tracks.indexWhere((t) => t.isSelected);
    final focusNode = selectedIndex >= 0
        ? _tvAudioSelectedFocusNode
        : _tvAudioFallbackFocusNode;
    final autofocusIndex = selectedIndex >= 0 ? selectedIndex : 0;
    _requestTvBottomPanelFocusIfNeeded(3, focusNode);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final entry in tracks.asMap().entries) ...[
            if (entry.key > 0) const SizedBox(width: 10),
            _buildTvChip(
              autofocus: entry.key == autofocusIndex,
              selected: entry.value.isSelected,
              label: _audioTrackTitle(entry.value),
              icon: Icons.audiotrack_outlined,
              focusNode: entry.key == autofocusIndex ? focusNode : null,
              onPressed:
                  enabled ? () => _tvSelectAudioTrack(entry.value) : null,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTvCorePanel({required bool enabled}) {
    final canUseExo =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

    final selectedCore = widget.appState.playerCore;
    final mpvSelected = selectedCore == PlayerCore.mpv || !canUseExo;
    final exoSelected = selectedCore == PlayerCore.exo && canUseExo;

    final focusNode = mpvSelected ? _tvCoreExoFocusNode : _tvCoreMpvFocusNode;
    _requestTvBottomPanelFocusIfNeeded(4, focusNode);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _buildTvChip(
            autofocus: !mpvSelected,
            selected: mpvSelected,
            label: 'mpv',
            icon: Icons.movie_outlined,
            focusNode: _tvCoreMpvFocusNode,
            onPressed:
                !enabled || mpvSelected ? null : () => unawaited(_switchCore()),
          ),
          const SizedBox(width: 10),
          _buildTvChip(
            autofocus: mpvSelected,
            selected: exoSelected,
            label: canUseExo ? 'Exo' : 'Exo（仅 Android）',
            icon: Icons.flash_on_outlined,
            focusNode: _tvCoreExoFocusNode,
            onPressed: !enabled || !canUseExo || exoSelected
                ? null
                : () {
                    unawaited(widget.appState.setPlayerCore(PlayerCore.exo));
                    setState(() {});
                  },
          ),
        ],
      ),
    );
  }

  Widget _buildTvBottomStatusBar({
    required bool enabled,
    required Duration position,
    required Duration buffered,
    required Duration duration,
    required bool isPlaying,
    required Future<void> Function() onPlay,
    required Future<void> Function() onPause,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final uiScale = context.uiScale;

    final bg = _tvHudBg(scheme);
    final fg = _tvHudFg(scheme);
    final radius = (18 * uiScale).clamp(14.0, 26.0);
    final padH = (14 * uiScale).clamp(10.0, 18.0);
    final padV = (12 * uiScale).clamp(10.0, 16.0);

    final durationMs = duration.inMilliseconds;
    final progress =
        durationMs <= 0 ? 0.0 : position.inMilliseconds / durationMs;
    final bufferedRatio =
        durationMs <= 0 ? 0.0 : buffered.inMilliseconds / durationMs;

    final progressColor = scheme.primary;
    final bufferedColor = scheme.brightness == Brightness.dark
        ? Colors.white.withValues(alpha: 0.28)
        : Colors.black.withValues(alpha: 0.14);
    final trackColor = scheme.brightness == Brightness.dark
        ? Colors.white.withValues(alpha: 0.18)
        : Colors.black.withValues(alpha: 0.10);
    final timeText =
        '当前观看时长（${_fmtClock(position)}） / 总时长（${_fmtClock(duration)}）';
    final timeStyle = theme.textTheme.labelLarge?.copyWith(
          color: fg,
          fontWeight: FontWeight.w800,
          fontFeatures: const [FontFeature.tabularFigures()],
        ) ??
        TextStyle(
          color: fg,
          fontWeight: FontWeight.w800,
          fontFeatures: const [FontFeature.tabularFigures()],
        );

    Widget panel = switch (_tvBottomPanelIndex) {
      0 => Row(
          children: [
            TvFocusable(
              focusNode: _tvPlayPauseFocusNode,
              autofocus: true,
              enabled: enabled,
              onPressed: !enabled
                  ? null
                  : () {
                      // ignore: unawaited_futures
                      isPlaying ? onPause() : onPlay();
                    },
              borderRadius: BorderRadius.circular(999),
              surfaceColor: scheme.brightness == Brightness.dark
                  ? Colors.white.withValues(alpha: 0.12)
                  : Colors.black.withValues(alpha: 0.06),
              focusedSurfaceColor: scheme.primary.withValues(
                  alpha: scheme.brightness == Brightness.dark ? 0.26 : 0.16),
              padding: EdgeInsets.symmetric(
                horizontal: (14 * uiScale).clamp(10.0, 18.0),
                vertical: (10 * uiScale).clamp(8.0, 14.0),
              ),
              child: Icon(
                isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                color: fg,
                size: (26 * uiScale).clamp(22.0, 34.0),
              ),
            ),
            const SizedBox(width: 14),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: (360 * uiScale).clamp(260.0, 520.0),
              ),
              child: Text(
                timeText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: timeStyle,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildTvProgressBar(
                progress: progress,
                buffered: bufferedRatio,
                progressColor: progressColor,
                bufferedColor: bufferedColor,
                trackColor: trackColor,
                height: (10 * uiScale).clamp(8.0, 12.0),
              ),
            ),
          ],
        ),
      1 => _buildTvEpisodesPanel(enabled: enabled),
      2 => _buildTvSubtitlePanel(enabled: enabled),
      3 => _buildTvAudioPanel(enabled: enabled),
      4 => _buildTvCorePanel(enabled: enabled),
      _ => _buildTvAudioPanel(enabled: enabled),
    };

    panel = KeyedSubtree(
      key: ValueKey<int>(_tvBottomPanelIndex),
      child: panel,
    );

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(radius),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: padH, vertical: padV),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) {
            final fade = CurvedAnimation(
              parent: animation,
              curve: Curves.easeOut,
            );
            final slide = Tween<Offset>(
              begin: const Offset(0, 0.10),
              end: Offset.zero,
            ).animate(animation);
            return FadeTransition(
              opacity: fade,
              child: SlideTransition(
                position: slide,
                child: child,
              ),
            );
          },
          child: panel,
        ),
      ),
    );
  }

  void _hideControlsForRemote() {
    _controlsHideTimer?.cancel();
    _controlsHideTimer = null;
    if (_controlsVisible) {
      setState(() {
        _controlsVisible = false;
        _tvBottomPanelIndex = 0;
        _tvPendingBottomPanelFocus = null;
      });
    }
    // ignore: unawaited_futures
    _enterImmersiveMode();
    _focusTvSurface();
  }

  void _scheduleControlsHide() {
    _controlsHideTimer?.cancel();
    _controlsHideTimer = null;
    if (_remoteEnabled && !widget.isTv) return;
    if (!_controlsVisible || _isScrubbing) return;
    _controlsHideTimer = Timer(_controlsAutoHideDelay, () {
      if (!mounted || _isScrubbing || (_remoteEnabled && !widget.isTv)) return;
      setState(() {
        _controlsVisible = false;
        _tvBottomPanelIndex = 0;
        _tvPendingBottomPanelFocus = null;
      });
      // ignore: unawaited_futures
      _enterImmersiveMode();
      if (widget.isTv) _focusTvSurface();
    });
  }

  void _onScrubStart() {
    _isScrubbing = true;
    _controlsHideTimer?.cancel();
    _controlsHideTimer = null;
    _showControls(scheduleHide: false);
  }

  void _onScrubEnd() {
    _isScrubbing = false;
    _scheduleControlsHide();
  }

  void _setGestureOverlay({required IconData icon, required String text}) {
    _gestureOverlayTimer?.cancel();
    _gestureOverlayTimer = null;
    if (!mounted) {
      _gestureOverlayIcon = icon;
      _gestureOverlayText = text;
      return;
    }
    setState(() {
      _gestureOverlayIcon = icon;
      _gestureOverlayText = text;
    });
  }

  void _hideGestureOverlay([Duration delay = _gestureOverlayAutoHideDelay]) {
    _gestureOverlayTimer?.cancel();
    _gestureOverlayTimer = Timer(delay, () {
      if (!mounted) return;
      setState(() {
        _gestureOverlayIcon = null;
        _gestureOverlayText = null;
      });
    });
  }

  bool get _gesturesEnabled {
    final controller = _controller;
    return controller != null &&
        controller.value.isInitialized &&
        !_loading &&
        _playError == null;
  }

  int get _seekBackSeconds => widget.appState.seekBackwardSeconds;
  int get _seekForwardSeconds => widget.appState.seekForwardSeconds;

  Future<void> _togglePlayPause({bool showOverlay = true}) async {
    if (!_gesturesEnabled) return;
    final controller = _controller!;
    _showControls();
    if (controller.value.isPlaying) {
      await controller.pause();
      _applyDanmakuPauseState(true);
      _maybeReportPlaybackProgress(controller.value.position, force: true);
      if (showOverlay) {
        _setGestureOverlay(icon: Icons.pause, text: '暂停');
        _hideGestureOverlay();
      }
      if (mounted) setState(() {});
      return;
    }
    await controller.play();
    _applyDanmakuPauseState(false);
    _maybeReportPlaybackProgress(controller.value.position, force: true);
    if (showOverlay) {
      _setGestureOverlay(icon: Icons.play_arrow, text: '播放');
      _hideGestureOverlay();
    }
    if (mounted) setState(() {});
  }

  Future<void> _seekRelative(Duration delta, {bool showOverlay = true}) async {
    if (!_gesturesEnabled) return;
    final controller = _controller!;
    final duration = controller.value.duration;
    final current = _position;
    var target = current + delta;
    if (target < Duration.zero) target = Duration.zero;
    if (duration > Duration.zero && target > duration) target = duration;

    await controller.seekTo(target);
    _position = target;
    _maybeReportPlaybackProgress(controller.value.position, force: true);
    _syncDanmakuCursor(target);
    if (mounted) setState(() {});

    if (showOverlay) {
      final absSeconds = delta.inSeconds.abs();
      _setGestureOverlay(
        icon: delta.isNegative ? Icons.fast_rewind : Icons.fast_forward,
        text: '${delta.isNegative ? '快退' : '快进'} ${absSeconds}s',
      );
      _hideGestureOverlay();
    }
  }

  Future<void> _handleDoubleTap(Offset localPos, double width) async {
    if (!_gesturesEnabled) return;

    final region = width <= 0
        ? 1
        : (localPos.dx < width / 3)
            ? 0
            : (localPos.dx < width * 2 / 3)
                ? 1
                : 2;

    final action = switch (region) {
      0 => widget.appState.doubleTapLeft,
      1 => widget.appState.doubleTapCenter,
      _ => widget.appState.doubleTapRight,
    };

    switch (action) {
      case DoubleTapAction.none:
        return;
      case DoubleTapAction.playPause:
        await _togglePlayPause();
        return;
      case DoubleTapAction.seekBackward:
        await _seekRelative(Duration(seconds: -_seekBackSeconds));
        return;
      case DoubleTapAction.seekForward:
        await _seekRelative(Duration(seconds: _seekForwardSeconds));
        return;
    }
  }

  void _onSeekDragStart(DragStartDetails details) {
    if (!_gesturesEnabled) return;
    if (!widget.appState.gestureSeek) return;
    _gestureMode = _GestureMode.seek;
    _gestureStartPos = details.localPosition;
    _seekGestureStartPosition = _position;
    _seekGesturePreviewPosition = _position;
    _showControls(scheduleHide: false);
    _setGestureOverlay(icon: Icons.swap_horiz, text: _fmtClock(_position));
  }

  void _onSeekDragUpdate(
    DragUpdateDetails details, {
    required double width,
    required Duration duration,
  }) {
    if (_gestureMode != _GestureMode.seek) return;
    if (_gestureStartPos == null) return;
    if (width <= 0) return;
    if (!_gesturesEnabled) return;

    final dx = details.localPosition.dx - _gestureStartPos!.dx;
    final d = duration;
    if (d <= Duration.zero) return;

    final maxSeekSeconds = math.min(d.inSeconds.toDouble(), 300.0);
    if (maxSeekSeconds <= 0) return;

    final deltaSeconds = (dx / width) * maxSeekSeconds;
    final delta = Duration(seconds: deltaSeconds.round());
    var target = _seekGestureStartPosition + delta;
    if (target < Duration.zero) target = Duration.zero;
    if (d > Duration.zero && target > d) target = d;
    _seekGesturePreviewPosition = target;

    _setGestureOverlay(
      icon: delta.isNegative ? Icons.fast_rewind : Icons.fast_forward,
      text:
          '${_fmtClock(target)}（${delta.isNegative ? '-' : '+'}${delta.inSeconds.abs()}s）',
    );

    if (mounted) setState(() {});
  }

  Future<void> _onSeekDragEnd(DragEndDetails details) async {
    if (_gestureMode != _GestureMode.seek) return;
    final target = _seekGesturePreviewPosition;
    _gestureMode = _GestureMode.none;
    _gestureStartPos = null;
    _seekGesturePreviewPosition = null;

    if (target != null && _gesturesEnabled) {
      final controller = _controller!;
      await controller.seekTo(target);
      _position = target;
      _maybeReportPlaybackProgress(controller.value.position, force: true);
      _syncDanmakuCursor(target);
      if (mounted) setState(() {});
    }

    _hideGestureOverlay();
    _scheduleControlsHide();
  }

  void _onSideDragStart(DragStartDetails details, {required double width}) {
    if (!_gesturesEnabled) return;
    _gestureStartPos = details.localPosition;
    final isLeft = width <= 0 ? true : details.localPosition.dx < width / 2;
    if (isLeft && widget.appState.gestureBrightness) {
      _gestureMode = _GestureMode.brightness;
      _gestureStartBrightness = _screenBrightness;
      _setGestureOverlay(
        icon: Icons.brightness_6_outlined,
        text: '亮度 ${(100 * _screenBrightness).round()}%',
      );
      return;
    }
    if (!isLeft && widget.appState.gestureVolume) {
      _gestureMode = _GestureMode.volume;
      _gestureStartVolume = _playerVolume;
      _setGestureOverlay(
        icon: Icons.volume_up,
        text: '音量 ${(100 * _playerVolume).round()}%',
      );
      return;
    }
    _gestureMode = _GestureMode.none;
  }

  void _onSideDragUpdate(
    DragUpdateDetails details, {
    required double height,
  }) {
    if (!_gesturesEnabled) return;
    if (_gestureStartPos == null) return;
    if (height <= 0) return;
    if (_gestureMode != _GestureMode.brightness &&
        _gestureMode != _GestureMode.volume) {
      return;
    }

    final dy = details.localPosition.dy - _gestureStartPos!.dy;
    final delta = (-dy / height).clamp(-1.0, 1.0);

    switch (_gestureMode) {
      case _GestureMode.brightness:
        final v = (_gestureStartBrightness + delta).clamp(0.2, 1.0).toDouble();
        if (v == _screenBrightness) return;
        setState(() => _screenBrightness = v);
        _setGestureOverlay(
          icon: Icons.brightness_6_outlined,
          text: '亮度 ${(100 * v).round()}%',
        );
        break;
      case _GestureMode.volume:
        final v = (_gestureStartVolume + delta).clamp(0.0, 1.0).toDouble();
        _playerVolume = v;
        final controller = _controller;
        if (controller != null) {
          // ignore: unawaited_futures
          controller.setVolume(v);
        }
        _setGestureOverlay(
          icon: v == 0 ? Icons.volume_off : Icons.volume_up,
          text: '音量 ${(100 * v).round()}%',
        );
        break;
      default:
        break;
    }
  }

  void _onSideDragEnd(DragEndDetails details) {
    if (_gestureMode == _GestureMode.brightness ||
        _gestureMode == _GestureMode.volume) {
      _hideGestureOverlay();
    }
    _gestureMode = _GestureMode.none;
    _gestureStartPos = null;
  }

  void _onLongPressStart(LongPressStartDetails details) {
    if (!_gesturesEnabled) return;
    if (!widget.appState.gestureLongPressSpeed) return;

    final controller = _controller;
    if (controller == null) return;
    _gestureMode = _GestureMode.speed;
    _longPressStartPos = details.localPosition;
    _longPressBaseRate = controller.value.playbackSpeed;
    final targetRate =
        (_longPressBaseRate! * widget.appState.longPressSpeedMultiplier)
            .clamp(0.25, 5.0)
            .toDouble();
    // ignore: unawaited_futures
    controller.setPlaybackSpeed(targetRate);
    _setGestureOverlay(
      icon: Icons.speed,
      text: '倍速 ×${(targetRate / _longPressBaseRate!).toStringAsFixed(2)}',
    );
  }

  void _onLongPressMoveUpdate(
    LongPressMoveUpdateDetails details, {
    required double height,
  }) {
    if (_gestureMode != _GestureMode.speed) return;
    if (!_gesturesEnabled) return;
    if (!widget.appState.longPressSlideSpeed) return;
    if (_longPressBaseRate == null || _longPressStartPos == null) return;
    if (height <= 0) return;

    final dy = details.localPosition.dy - _longPressStartPos!.dy;
    final delta = (-dy / height) * 2.0;
    final multiplier = (widget.appState.longPressSpeedMultiplier + delta)
        .clamp(0.25, 5.0)
        .toDouble();
    final targetRate =
        (_longPressBaseRate! * multiplier).clamp(0.25, 5.0).toDouble();
    final controller = _controller;
    if (controller != null) {
      // ignore: unawaited_futures
      controller.setPlaybackSpeed(targetRate);
    }
    _setGestureOverlay(
      icon: Icons.speed,
      text: '倍速 ×${multiplier.toStringAsFixed(2)}',
    );
  }

  void _onLongPressEnd(LongPressEndDetails details) {
    if (_gestureMode != _GestureMode.speed) return;
    final base = _longPressBaseRate;
    _gestureMode = _GestureMode.none;
    _longPressBaseRate = null;
    _longPressStartPos = null;
    final controller = _controller;
    if (base != null && controller != null) {
      // ignore: unawaited_futures
      controller.setPlaybackSpeed(base);
    }
    _hideGestureOverlay();
  }

  Future<void> _switchCore() async {
    final pos = _position;
    _maybeReportPlaybackProgress(pos, force: true);
    await widget.appState.setPlayerCore(PlayerCore.mpv);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => PlayNetworkPage(
          title: widget.title,
          itemId: widget.itemId,
          appState: widget.appState,
          server: widget.server,
          isTv: widget.isTv,
          seriesId: widget.seriesId,
          startPosition: pos,
          resumeImmediately: true,
          mediaSourceId:
              _selectedMediaSourceId ?? _mediaSourceId ?? widget.mediaSourceId,
          audioStreamIndex: _selectedAudioStreamIndex,
          subtitleStreamIndex: _selectedSubtitleStreamIndex,
        ),
      ),
    );
  }

  String? get _playbackServerId =>
      widget.server?.id ?? widget.appState.activeServerId;

  String? _playbackDomainRemark(String url) {
    final serverId = _playbackServerId;
    if (serverId == null || serverId.isEmpty) {
      return widget.appState.domainRemark(url);
    }
    return widget.appState.serverDomainRemark(serverId, url);
  }

  Future<List<RouteEntry>> _resolvePlaybackRouteEntries({
    bool forceRefresh = false,
  }) async {
    final serverId = _playbackServerId;
    final usingActiveServer = serverId == null ||
        serverId.isEmpty ||
        serverId == widget.appState.activeServerId;

    final customDomains = (serverId == null || serverId.isEmpty)
        ? widget.appState.customDomains
        : widget.appState.customDomainsOfServer(serverId);
    final customEntries = customDomains
        .map((d) => DomainInfo(name: d.name, url: d.url))
        .toList(growable: false);

    List<DomainInfo> pluginDomains = const [];
    if (usingActiveServer) {
      if (forceRefresh || widget.appState.domains.isEmpty) {
        await widget.appState.refreshDomains();
      }
      pluginDomains = List<DomainInfo>.from(widget.appState.domains);
    } else {
      final access = _serverAccess;
      if (access != null) {
        try {
          pluginDomains = List<DomainInfo>.from(
            await access.adapter.fetchDomains(access.auth, allowFailure: true),
          );
        } catch (_) {}
      }
    }

    final knownUrls = <String>{
      for (final d in customEntries) d.url,
      for (final d in pluginDomains) d.url,
      (_baseUrl ?? '').trim(),
    };
    final historyEntries = <DomainInfo>[];
    for (final raw in _playbackRouteHistory) {
      final url = raw.trim();
      if (url.isEmpty || knownUrls.contains(url)) continue;
      historyEntries.add(
        DomainInfo(name: '上次线路 ${historyEntries.length + 1}', url: url),
      );
      knownUrls.add(url);
      if (historyEntries.length >= _playbackRouteHistoryLimit) break;
    }

    return buildRouteEntries(
      currentUrl: _baseUrl,
      customEntries: [...historyEntries, ...customEntries],
      pluginDomains: pluginDomains,
    );
  }

  void _rememberPlaybackRouteHistory(String url) {
    final value = url.trim();
    if (value.isEmpty) return;
    _playbackRouteHistory.removeWhere((entry) => entry == value);
    _playbackRouteHistory.insert(0, value);
    if (_playbackRouteHistory.length > _playbackRouteHistoryLimit) {
      _playbackRouteHistory.removeRange(
        _playbackRouteHistoryLimit,
        _playbackRouteHistory.length,
      );
    }
  }

  Future<void> _switchPlaybackRoute(String url) async {
    final nextUrl = url.trim();
    final currentUrl = (_baseUrl ?? '').trim();
    final serverId = _playbackServerId;
    if (nextUrl.isEmpty ||
        currentUrl.isEmpty ||
        nextUrl == currentUrl ||
        serverId == null ||
        serverId.isEmpty ||
        _loading) {
      return;
    }

    final resumePos = _position;
    _maybeReportPlaybackProgress(resumePos, force: true);
    _rememberPlaybackRouteHistory(currentUrl);

    final previousSources =
        List<Map<String, dynamic>>.from(_availableMediaSources);
    final previousSelectedSourceId = _selectedMediaSourceId;
    final previousAudioIndex = _selectedAudioStreamIndex;
    final previousSubtitleIndex = _selectedSubtitleStreamIndex;
    var routeUpdated = false;

    Future<void> restorePreviousRoute({String? message}) async {
      try {
        await widget.appState.updateServerRoute(serverId, url: currentUrl);
      } catch (_) {}
      _serverAccess =
          resolveServerAccess(appState: widget.appState, server: widget.server);
      if (!mounted) return;
      setState(() {
        _availableMediaSources = previousSources;
        _selectedMediaSourceId = previousSelectedSourceId;
        _selectedAudioStreamIndex = previousAudioIndex;
        _selectedSubtitleStreamIndex = previousSubtitleIndex;
        _overrideStartPosition = resumePos;
        _overrideResumeImmediately = true;
        _loading = true;
        _playError = null;
      });
      await _init();
      if (!mounted || message == null || message.trim().isEmpty) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message.trim())),
      );
    }

    try {
      await widget.appState.updateServerRoute(serverId, url: nextUrl);
      routeUpdated = true;
      _serverAccess =
          resolveServerAccess(appState: widget.appState, server: widget.server);
      if (!mounted) return;
      setState(() {
        _availableMediaSources = const [];
        _selectedMediaSourceId = null;
        _selectedAudioStreamIndex = null;
        _selectedSubtitleStreamIndex = null;
        _overrideStartPosition = resumePos;
        _overrideResumeImmediately = true;
        _loading = true;
        _playError = null;
      });
      await _init();
      if (!mounted) return;
      if (_playError == null) return;
      await restorePreviousRoute(message: '新线路无画面，已恢复到原线路');
    } catch (e) {
      if (routeUpdated) {
        await restorePreviousRoute();
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('线路切换失败：$e')),
      );
    }
  }

  Future<void> _init() async {
    _allowRoutePop = false;
    _exitInProgress = false;
    _uiTimer?.cancel();
    _uiTimer = null;
    _serverProgressSync?.stop();
    _serverProgressSync?.reset();
    _playError = null;
    _loading = true;
    _buffering = false;
    _lastBufferedEnd = Duration.zero;
    _lastBufferedAt = null;
    _bufferSpeedSampleEnd = Duration.zero;
    _bufferSpeedX = null;
    _netSpeedBytesPerSecond = null;
    _lastAppRxBytes = null;
    _lastAppRxAt = null;
    _nextDanmakuIndex = 0;
    _danmakuKey.currentState?.clear();
    _danmakuSources.clear();
    _danmakuSourceIndex = -1;
    _danmakuEnabled = widget.appState.danmakuEnabled;
    _danmakuOpacity = widget.appState.danmakuOpacity;
    _danmakuScale = widget.appState.danmakuScale;
    _danmakuSpeed = widget.appState.danmakuSpeed;
    _danmakuBold = widget.appState.danmakuBold;
    _danmakuMaxLines = widget.appState.danmakuMaxLines;
    _danmakuTopMaxLines = widget.appState.danmakuTopMaxLines;
    _danmakuBottomMaxLines = widget.appState.danmakuBottomMaxLines;
    _danmakuPreventOverlap = widget.appState.danmakuPreventOverlap;
    _danmakuShowHeatmap = widget.appState.danmakuShowHeatmap;
    _danmakuHeatmap = const [];
    _danmakuPaused = false;

    _reportedStart = false;
    _reportedStop = false;
    _markPlayedThresholdReached = false;
    _autoMarkedPlayed = false;
    _lastLocalProgressSecond = -1;
    _pendingLocalProgressTicks = null;
    _localProgressWriteInFlight = false;
    _lastUiTickAt = null;

    _playSessionId = null;
    _mediaSourceId = null;
    _resolvedStream = null;
    _resolvedStreamHeaders = const <String, String>{};
    _resumeHintTimer?.cancel();
    _resumeHintTimer = null;
    _resumeHintPosition = null;
    _showResumeHint = false;
    _startOverHintTimer?.cancel();
    _startOverHintTimer = null;
    _startOverHintPosition = null;
    _showStartOverHint = false;
    _deferProgressReporting = false;
    _introSeq++;
    _introTimestamps = null;
    _skipIntroPromptVisible = false;
    _skipIntroHandled = false;
    _nextEpisodePreloadTriggered = false;
    _cancelActivePlaybackCacheFills();
    _resolvedPlaybackSource = null;
    _preloadHttpProxyUrl = null;
    _controlsVisible = true;
    _isScrubbing = false;
    _subtitleText = '';
    _subtitlePollInFlight = false;
    _controlsHideTimer?.cancel();
    _controlsHideTimer = null;
    _mobileRouteEntriesFuture = null;
    _mobileVersionSourcesFuture = null;
    _mobileSpeedAdjustTimer?.cancel();
    _mobileSpeedAdjustTimer = null;

    if (_preloadOwnerKey.isNotEmpty) {
      PlaybackPreloadCoordinator.cancelOwner(_preloadOwnerKey);
    }
    _preloadOwnerKey =
        PlaybackPreloadCoordinator.createOwnerToken('playback_exo');

    final prev = _controller;
    _controller = null;
    if (prev != null) {
      await prev.dispose();
    }

    if (!mounted) return;
    setState(() {});

    final remoteStartFuture =
        _serverProgressSync?.fetchServerProgressDurationBestEffort() ??
            Future<Duration?>.value(null);
    final localStartFuture = _readLocalProgressDuration();

    try {
      if (!_isAndroid) {
        throw Exception('Exo 内核仅支持 Android');
      }
      final resolvedPlayback = await _buildResolvedPlaybackSource();
      final resolvedSource = resolvedPlayback.resolvedSource;
      _playSessionId = resolvedPlayback.playbackInfo.playSessionId;
      _mediaSourceId = resolvedSource.mediaSourceId;
      _availableMediaSources = resolvedPlayback.mediaSources;
      _selectedMediaSourceId = resolvedPlayback.selectedMediaSourceId;
      _preloadHttpProxyUrl = PlaybackPreloadCoordinator.resolveHttpProxyUrl(
        appState: widget.appState,
        sourceUrl: resolvedSource.url,
        preferBuiltInProxy: false,
      );
      _resolvedPlaybackSource = resolvedSource.copyWith(
        proxyUrl: _preloadHttpProxyUrl,
      );
      final cloudStart = _overrideStartPosition ?? widget.startPosition;
      final remoteStart = await remoteStartFuture;
      final localStart = await localStartFuture;
      Duration? start = cloudStart;
      if (remoteStart != null && (start == null || remoteStart > start)) {
        start = remoteStart;
      }
      if (localStart != null && (start == null || localStart > start)) {
        start = localStart;
      }
      await _applyOrientationForMode(
        mediaSource: resolvedPlayback.selectedMediaSource,
      );
      final preloadStart = start ?? Duration.zero;
      final preloadWarmup = _startCurrentItemPreloadWarmup(
        startPosition: preloadStart,
        triggerSource:
            preloadStart > Duration.zero ? 'playback_resume' : 'playback_start',
      );
      if (preloadWarmup != null) {
        unawaited(preloadWarmup);
      }
      final playbackSource = await _buildPlaybackSource(resolvedSource);
      _resolvedStream = playbackSource.url;
      _resolvedStreamHeaders = playbackSource.httpHeaders;
      AppDiagnosticsLogger.instance.info(
        'player_network_exo',
        'Prepared network playback source',
        data: <String, Object?>{
          'itemId': widget.itemId,
          'resolved': AppDiagnosticsLogger.summarizeUrl(resolvedSource.url),
          'playback': AppDiagnosticsLogger.summarizeUrl(playbackSource.url),
          'resolvedHeaders': AppDiagnosticsLogger.summarizeHeaderKeys(
              resolvedSource.httpHeaders),
          'playbackHeaders': AppDiagnosticsLogger.summarizeHeaderKeys(
              playbackSource.httpHeaders),
          'mediaType': resolvedSource.mediaTypeHint.name,
          'preloadProxy': _preloadHttpProxyUrl ?? '',
          'usesLoopbackProxy':
              (Uri.tryParse(playbackSource.url)?.host ?? '') == '127.0.0.1',
        },
      );
      final controller = VideoPlayerController.networkUrl(
        Uri.parse(playbackSource.url),
        httpHeaders: _embyHeaders(),
        // Use platform view on Android to avoid color issues with some HDR/Dolby Vision sources.
        // (Texture-based rendering may show green/purple tint on certain P8 files.)
        viewType: _viewType,
      );
      _controller = controller;
      await controller.initialize();
      await _applyOrientationForMode();
      await _applyExoSubtitleOptions();
      await _maybeAutoSelectSubtitleTrack(controller);
      final resumeImmediately =
          _overrideResumeImmediately || widget.resumeImmediately;
      _overrideStartPosition = null;
      _overrideResumeImmediately = false;
      Duration? resumeTarget;
      if (start != null && start > Duration.zero) {
        final target = _safeSeekTarget(start, controller.value.duration);
        _deferProgressReporting = true;
        if (resumeImmediately) {
          resumeTarget = target;
        } else {
          _resumeHintPosition = target;
          _showResumeHint = true;
        }
      }
      await _ensurePlaybackAutoStarts(controller);
      if (resumeTarget != null) {
        // Avoid blocking startup on long/unsupported seeks; seek after playback starts.
        // ignore: unawaited_futures
        _resumeToPositionAfterStart(controller, resumeTarget);
      }

      _uiTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
        final c = _controller;
        if (!mounted || c == null) return;
        final v = c.value;
        final now = DateTime.now();
        _buffering = v.isBuffering;
        _position = v.position;
        _duration = v.duration;

        if (_orientationMode == _OrientationMode.auto &&
            _shouldControlSystemUi) {
          final last = _lastAutoOrientationApplyAt;
          if (last == null ||
              now.difference(last) >= const Duration(seconds: 1)) {
            _lastAutoOrientationApplyAt = now;
            // ignore: unawaited_futures
            _applyOrientationForMode();
          }
        }

        var bufferedEnd = Duration.zero;
        for (final r in v.buffered) {
          if (r.end > bufferedEnd) bufferedEnd = r.end;
        }
        _lastBufferedEnd = bufferedEnd;

        final wantBufferSpeed = widget.appState.showBufferSpeed;
        final wantNetSpeed = wantBufferSpeed || widget.isTv;

        if (wantBufferSpeed) {
          final refreshSeconds = widget.appState.bufferSpeedRefreshSeconds
              .clamp(0.2, 3.0)
              .toDouble();
          final refreshMs = (refreshSeconds * 1000).round();

          final prevAt = _lastBufferedAt;
          if (prevAt == null) {
            _bufferSpeedX = null;
            _netSpeedBytesPerSecond = null;
            _lastBufferedAt = now;
            _bufferSpeedSampleEnd = bufferedEnd;
            _pollAppNetSpeedOrFallback();
          } else {
            final dtMs = now.difference(prevAt).inMilliseconds;
            if (dtMs >= refreshMs) {
              final deltaMs =
                  (bufferedEnd - _bufferSpeedSampleEnd).inMilliseconds;
              _lastBufferedAt = now;
              _bufferSpeedSampleEnd = bufferedEnd;
              _bufferSpeedX =
                  (dtMs > 0 && deltaMs >= 0) ? (deltaMs / dtMs) : null;

              double? fallbackSpeed;
              final bitrate = _currentMediaSourceBitrateBitsPerSecond();
              final x = _bufferSpeedX;
              if (bitrate != null && bitrate > 0 && x != null) {
                fallbackSpeed = x * bitrate / 8.0;
              }
              _pollAppNetSpeedOrFallback(
                fallbackBytesPerSecond: fallbackSpeed,
              );
            }
          }
        } else {
          _bufferSpeedX = null;
          _lastBufferedAt = null;
          _bufferSpeedSampleEnd = bufferedEnd;

          if (wantNetSpeed) {
            final last = _tvNetSpeedLastPollAt;
            if (last == null ||
                now.difference(last) >= const Duration(seconds: 1)) {
              _tvNetSpeedLastPollAt = now;
              _pollAppNetSpeedOrFallback();
            }
          } else {
            _netSpeedBytesPerSecond = null;
            _lastAppRxBytes = null;
            _lastAppRxAt = null;
          }
        }

        _applyDanmakuPauseState(_buffering || !_isPlaying);
        _drainDanmaku(_position);
        if (!_isAndroid || _viewType == VideoViewType.textureView) {
          // ignore: unawaited_futures
          _pollSubtitleText();
        }

        _maybeReportPlaybackProgress(_position);
        _maybeUpdateSkipIntroPrompt(_position);
        _maybePreloadNextEpisode(_position);

        if (!_reportedStop &&
            _duration > Duration.zero &&
            !_buffering &&
            !v.isPlaying &&
            _position >= _duration - const Duration(milliseconds: 200)) {
          // ignore: unawaited_futures
          _reportPlaybackStoppedBestEffort(completed: true);
        }
        final shouldRebuild = _lastUiTickAt == null ||
            now.difference(_lastUiTickAt!) >= const Duration(milliseconds: 250);
        if (shouldRebuild) {
          _lastUiTickAt = now;
          setState(() {});
        }
      });

      _maybeAutoLoadOnlineDanmaku();
      // ignore: unawaited_futures
      _loadIntroTimestampsBestEffort();

      await _ensurePlaybackAutoStarts(controller);
      if (!_deferProgressReporting) {
        // ignore: unawaited_futures
        _reportPlaybackStartBestEffort();
      }
    } catch (e) {
      _playError = e.toString();
      _resumeHintPosition = null;
      _showResumeHint = false;
      _startOverHintPosition = null;
      _showStartOverHint = false;
      _deferProgressReporting = false;
    } finally {
      if (mounted) {
        setState(() => _loading = false);
        if (_showResumeHint && _resumeHintPosition != null) {
          _startResumeHintTimer();
        }
        if (_showStartOverHint && _startOverHintPosition != null) {
          _startStartOverHintTimer();
        }
        _scheduleControlsHide();
      }
    }
  }

  int? _preferredMediaSourceIndex() {
    final sid = (widget.seriesId ?? '').trim();
    final serverId = widget.server?.id ?? widget.appState.activeServerId;
    if (serverId == null || serverId.isEmpty || sid.isEmpty) return null;
    return widget.appState
        .seriesMediaSourceIndex(serverId: serverId, seriesId: sid);
  }

  Future<PlaybackSourceBuildResult> _buildResolvedPlaybackSource() async {
    final access = _serverAccess;
    if (access == null) throw StateError('No server access');
    return PlaybackSourceBuilder.build(
      PlaybackSourceBuildRequest(
        adapter: access.adapter,
        auth: access.auth,
        itemId: widget.itemId,
        playerCore: PlaybackSourcePlayerCoreKind.exo,
        selectedMediaSourceId: _selectedMediaSourceId,
        preferredMediaSourceIndex: _preferredMediaSourceIndex(),
        audioStreamIndex: _selectedAudioStreamIndex,
        subtitleStreamIndex: _selectedSubtitleStreamIndex,
        preferredVideoVersion: widget.appState.preferredVideoVersion,
      ),
    );
  }

  Future<PlayableSource> _buildPlaybackSource(
    ResolvedPlaybackSource resolvedSource,
  ) async {
    final cacheKey = buildResolvedPlaybackCacheKey(
      resolvedSource,
      proxyUrl: _preloadHttpProxyUrl,
    );
    final mediaType = switch (resolvedSource.mediaTypeHint) {
      ResolvedPlaybackMediaType.hls => StreamMediaType.hls,
      ResolvedPlaybackMediaType.dash => StreamMediaType.dash,
      ResolvedPlaybackMediaType.file => StreamMediaType.file,
      ResolvedPlaybackMediaType.unknown => StreamMediaType.unknown,
    };
    final candidate = PlayableSource(
      url: resolvedSource.url,
      httpHeaders: resolvedSource.httpHeaders,
      mediaTypeHint: mediaType,
      fromStrm: resolvedSource.fromStrm,
      redirectChain: resolvedSource.redirectChain,
      contentTypeHint: resolvedSource.contentTypeHint,
      supportsByteRange: resolvedSource.supportsByteRange,
      httpStatusHint: resolvedSource.httpStatusHint,
      bitrateHint: resolvedSource.bitrate,
    );
    final proxied = await LocalHttpStreamProxy.wrapPlaybackSource(
      candidate,
      cacheKey: cacheKey,
    );
    if (proxied != null) {
      _playbackCacheFingerprint = cacheKey?.fingerprint;
    }
    return proxied ?? candidate;
  }

  int _toTicks(Duration d) => d.inMicroseconds * 10;

  String get _localProgressKey {
    final serverId =
        (widget.server?.id ?? widget.appState.activeServerId ?? '').trim();
    final base = _baseUrl ?? '';
    final scope = serverId.isNotEmpty ? serverId : base;
    final normalized = scope.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return '$_kLocalPlaybackProgressPrefix$normalized:${widget.itemId}';
  }

  Future<Duration?> _readLocalProgressDuration() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ticks = prefs.getInt(_localProgressKey);
      if (ticks == null || ticks <= 0) return null;
      return Duration(microseconds: (ticks / 10).round());
    } catch (_) {
      return null;
    }
  }

  Future<void> _clearLocalProgress() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_localProgressKey);
    } catch (_) {}
    _lastLocalProgressSecond = -1;
    _pendingLocalProgressTicks = null;
  }

  void _persistLocalProgress(Duration position, {bool force = false}) {
    final safe = position < Duration.zero ? Duration.zero : position;
    final second = safe.inSeconds;
    if (!force && second == _lastLocalProgressSecond) return;
    _lastLocalProgressSecond = second;
    _pendingLocalProgressTicks = _toTicks(safe);
    // ignore: unawaited_futures
    _flushPendingLocalProgress();
  }

  Future<void> _flushPendingLocalProgress() async {
    if (_localProgressWriteInFlight) return;
    _localProgressWriteInFlight = true;
    try {
      while (_pendingLocalProgressTicks != null) {
        final ticks = _pendingLocalProgressTicks!;
        _pendingLocalProgressTicks = null;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt(_localProgressKey, ticks);
      }
    } finally {
      _localProgressWriteInFlight = false;
    }
  }

  static String _fmtClock(Duration d) {
    String two(int v) => v.toString().padLeft(2, '0');
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    return h > 0 ? '${two(h)}:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
  }

  static int? _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  int? _currentMediaSourceBitrateBitsPerSecond() {
    final sources = _availableMediaSources;
    if (sources.isEmpty) return null;

    final id = (_mediaSourceId ?? _selectedMediaSourceId ?? '').trim();
    final ms = id.isEmpty
        ? sources.first
        : sources.firstWhere(
            (s) => (s['Id']?.toString() ?? '').trim() == id,
            orElse: () => sources.first,
          );

    final bitrate = _asInt(ms['Bitrate']);
    if (bitrate == null || bitrate <= 0) return null;
    return bitrate;
  }

  void _pollAppNetSpeedOrFallback({double? fallbackBytesPerSecond}) {
    if (_systemNetSpeedPollInFlight) return;
    _systemNetSpeedPollInFlight = true;

    DeviceType.appRxBytes().then((appRx) {
      if (!mounted) return;
      final sampleAt = DateTime.now();

      final appRate = appRx == null
          ? null
          : computeTrafficRateBytesPerSecond(
              totalBytes: appRx,
              previousBytes: _lastAppRxBytes,
              sampleAt: sampleAt,
              previousAt: _lastAppRxAt,
            );
      _lastAppRxBytes = appRx;
      _lastAppRxAt = appRx == null ? null : sampleAt;

      final next = (appRate != null && appRate.isFinite && appRate >= 0)
          ? appRate
          : (fallbackBytesPerSecond != null && fallbackBytesPerSecond.isFinite
              ? fallbackBytesPerSecond
              : null);

      if (next == null) {
        if (_netSpeedBytesPerSecond != null) {
          setState(() => _netSpeedBytesPerSecond = null);
        }
        return;
      }

      final smoothed = smoothNetworkSpeedBytesPerSecond(
        next,
        previous: _netSpeedBytesPerSecond,
      );
      setState(() => _netSpeedBytesPerSecond = smoothed);
    }).catchError((_) {
      if (!mounted) return;
      _lastAppRxBytes = null;
      _lastAppRxAt = null;

      final next =
          (fallbackBytesPerSecond != null && fallbackBytesPerSecond.isFinite)
              ? fallbackBytesPerSecond
              : null;
      if (next == null) {
        if (_netSpeedBytesPerSecond != null) {
          setState(() => _netSpeedBytesPerSecond = null);
        }
        return;
      }

      final smoothed = smoothNetworkSpeedBytesPerSecond(
        next,
        previous: _netSpeedBytesPerSecond,
      );
      setState(() => _netSpeedBytesPerSecond = smoothed);
    }).whenComplete(() {
      _systemNetSpeedPollInFlight = false;
    });
  }

  static List<Map<String, dynamic>> _streamsOfType(
      Map<String, dynamic> ms, String type) {
    final streams = (ms['MediaStreams'] as List?) ?? const [];
    return streams
        .where((e) => (e as Map)['Type'] == type)
        .map((e) => e as Map<String, dynamic>)
        .toList();
  }

  static String _mediaSourceTitle(Map<String, dynamic> ms) {
    return (ms['Name'] as String?) ?? (ms['Container'] as String?) ?? '默认版本';
  }

  static int _compareMediaSourcesByQuality(
    Map<String, dynamic> a,
    Map<String, dynamic> b,
  ) {
    int heightOf(Map<String, dynamic> ms) {
      final videos = _streamsOfType(ms, 'Video');
      final video = videos.isNotEmpty ? videos.first : null;
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

  static String _mediaSourceSubtitle(Map<String, dynamic> ms) {
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

  Duration _safeSeekTarget(Duration target, Duration total) {
    if (target <= Duration.zero) return Duration.zero;
    if (total <= Duration.zero) return target;
    if (target < total) return target;
    final rewind = total - const Duration(seconds: 5);
    return rewind > Duration.zero ? rewind : Duration.zero;
  }

  static const Duration _kResumeSeekTolerance = Duration(seconds: 1);

  bool _seekCloseEnough(Duration position, Duration target) {
    return (position - target).inMilliseconds.abs() <=
        _kResumeSeekTolerance.inMilliseconds;
  }

  Future<bool> _seekToPositionBestEffort(
      VideoPlayerController controller, Duration target) async {
    if (!controller.value.isInitialized) return false;
    if (target <= Duration.zero) return true;

    Future<void> attemptSeek() async {
      try {
        final seekFuture = controller.seekTo(target);
        await seekFuture.timeout(const Duration(seconds: 3));
      } catch (_) {}
    }

    await attemptSeek();
    await Future<void>.delayed(const Duration(milliseconds: 80));
    if (_seekCloseEnough(controller.value.position, target)) return true;

    // Some streams (e.g., certain HLS transcodes) only allow seeking after playback starts.
    if (!controller.value.isPlaying) {
      try {
        await controller.play();
      } catch (_) {}
    }

    for (var attempt = 0; attempt < 3; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      await attemptSeek();
      await Future<void>.delayed(const Duration(milliseconds: 80));
      if (_seekCloseEnough(controller.value.position, target)) return true;
    }

    return _seekCloseEnough(controller.value.position, target);
  }

  Future<void> _resumeToPositionAfterStart(
    VideoPlayerController controller,
    Duration target,
  ) async {
    final ok = await _seekToPositionBestEffort(controller, target);
    if (!mounted) return;
    if (_controller != controller) return;

    final applied = controller.value.position;
    _position = applied;
    _syncDanmakuCursor(applied);

    if (ok) {
      final shouldStartReporting = _deferProgressReporting;
      _deferProgressReporting = false;
      if (applied > Duration.zero) {
        _startOverHintPosition = applied;
        _showStartOverHint = true;
        _startStartOverHintTimer();
      }
      if (shouldStartReporting) {
        // ignore: unawaited_futures
        _reportPlaybackStartBestEffort();
        _maybeReportPlaybackProgress(_position, force: true);
      }
      setState(() {});
      return;
    }

    _resumeHintPosition = target;
    _showResumeHint = true;
    _startResumeHintTimer();
    setState(() {});
  }

  void _startResumeHintTimer() {
    _resumeHintTimer?.cancel();
    _resumeHintTimer = Timer(const Duration(seconds: 5), () {
      if (!mounted) return;
      if (!_showResumeHint) return;
      _showResumeHint = false;
      final shouldStartReporting = _deferProgressReporting;
      _deferProgressReporting = false;
      if (shouldStartReporting) {
        // ignore: unawaited_futures
        _reportPlaybackStartBestEffort();
        _maybeReportPlaybackProgress(_position, force: true);
      }
      setState(() {});
    });
  }

  void _startStartOverHintTimer() {
    _startOverHintTimer?.cancel();
    _startOverHintTimer = Timer(const Duration(seconds: 5), () {
      if (!mounted) return;
      if (!_showStartOverHint) return;
      _showStartOverHint = false;
      setState(() {});
    });
  }

  Future<void> _restartFromBeginning() async {
    final controller = _controller;
    if (controller == null) return;
    if (!controller.value.isInitialized) return;
    _showControls(scheduleHide: false);

    try {
      final seekFuture = controller.seekTo(Duration.zero);
      await seekFuture.timeout(const Duration(seconds: 3));
    } catch (_) {}

    _position = Duration.zero;
    _syncDanmakuCursor(Duration.zero);
    _maybeReportPlaybackProgress(_position, force: true);

    _startOverHintTimer?.cancel();
    _startOverHintTimer = null;
    _showStartOverHint = false;
    if (mounted) setState(() {});
  }

  Future<void> _resumeToHistoryPosition() async {
    final controller = _controller;
    final target = _resumeHintPosition;
    if (controller == null) return;
    if (target == null || target <= Duration.zero) return;
    if (!controller.value.isInitialized) return;

    final safeTarget = _safeSeekTarget(target, controller.value.duration);
    try {
      final seekFuture = controller.seekTo(safeTarget);
      await seekFuture.timeout(const Duration(seconds: 3));
      _position = safeTarget;
      _syncDanmakuCursor(safeTarget);
    } catch (_) {}

    _resumeHintTimer?.cancel();
    _resumeHintTimer = null;
    _showResumeHint = false;
    final shouldStartReporting = _deferProgressReporting;
    _deferProgressReporting = false;
    if (shouldStartReporting) {
      // ignore: unawaited_futures
      _reportPlaybackStartBestEffort();
      _maybeReportPlaybackProgress(_position, force: true);
    }
    if (mounted) setState(() {});
  }

  Future<void> _reportPlaybackStartBestEffort() async {
    if (_reportedStart || _reportedStop) return;
    final access = _serverAccess;
    if (access == null) return;

    _reportedStart = true;
    _serverProgressSync?.start();
    final posTicks = _toTicks(_position);
    final paused = !_isPlaying;
    try {
      final ps = _playSessionId;
      final ms = _mediaSourceId;
      if (ps != null && ps.isNotEmpty && ms != null && ms.isNotEmpty) {
        await access.adapter.reportPlaybackStart(
          access.auth,
          itemId: widget.itemId,
          mediaSourceId: ms,
          playSessionId: ps,
          positionTicks: posTicks,
          isPaused: paused,
        );
      }
    } catch (_) {}
  }

  void _maybeReportPlaybackProgress(Duration position, {bool force = false}) {
    if (_reportedStop) return;
    if (_deferProgressReporting) return;
    _persistLocalProgress(position, force: force);
    _maybeAutoMarkPlayed(position);
  }

  bool _isPlayedByThreshold(Duration position, Duration duration) {
    if (duration <= Duration.zero) return false;
    final durUs = duration.inMicroseconds;
    if (durUs <= 0) return false;
    final threshold = widget.appState.markPlayedThresholdPercent.clamp(75, 100);
    final posUs = position.inMicroseconds;
    return posUs * 100 >= durUs * threshold;
  }

  void _maybeAutoMarkPlayed(Duration position) {
    if (_reportedStop) return;
    if (_autoMarkedPlayed) return;

    final duration = _duration;
    if (!_isPlayedByThreshold(position, duration)) return;

    _markPlayedThresholdReached = true;
    _autoMarkedPlayed = true;
    // ignore: unawaited_futures
    _autoMarkPlayedBestEffort(position);
  }

  Future<void> _autoMarkPlayedBestEffort(Duration position) async {
    final access = _serverAccess;
    if (access == null) return;

    try {
      await access.adapter.updatePlaybackPosition(
        access.auth,
        itemId: widget.itemId,
        positionTicks: _toTicks(position),
        played: true,
      );
    } catch (_) {}
  }

  Future<void> _reportPlaybackStoppedBestEffort(
      {bool completed = false}) async {
    if (_reportedStop) return;
    _reportedStop = true;
    _serverProgressSync?.stop();

    final controller = _controller;
    final pos = (controller != null && controller.value.isInitialized)
        ? controller.value.position
        : _position;
    final dur = (controller != null && controller.value.isInitialized)
        ? controller.value.duration
        : _duration;
    final played = completed ||
        _markPlayedThresholdReached ||
        _isPlayedByThreshold(pos, dur);
    final ticks = _toTicks(pos);
    _persistLocalProgress(pos, force: true);
    await _flushPendingLocalProgress();

    final access = _serverAccess;
    if (access == null) {
      if (played) {
        await _clearLocalProgress();
      }
      return;
    }

    try {
      final ps = _playSessionId;
      final ms = _mediaSourceId;
      if (ps != null && ps.isNotEmpty && ms != null && ms.isNotEmpty) {
        await access.adapter.reportPlaybackStopped(
          access.auth,
          itemId: widget.itemId,
          mediaSourceId: ms,
          playSessionId: ps,
          positionTicks: ticks,
        );
      }
    } catch (_) {}

    try {
      await access.adapter.updatePlaybackPosition(
        access.auth,
        itemId: widget.itemId,
        positionTicks: ticks,
        played: played,
      );
    } catch (_) {}

    if (played) {
      await _clearLocalProgress();
    }
  }

  bool get _shouldControlSystemUi {
    if (kIsWeb) return false;
    if (widget.isTv) return false;
    return Platform.isAndroid || Platform.isIOS;
  }

  bool get _shouldIgnoreLifecyclePause {
    final until = _suppressLifecyclePauseUntil;
    return until != null && DateTime.now().isBefore(until);
  }

  void _suppressLifecyclePauseTemporarily() {
    _suppressLifecyclePauseUntil = DateTime.now().add(
      const Duration(milliseconds: 1200),
    );
  }

  Future<void> _enterImmersiveMode() async {
    if (!_shouldControlSystemUi) return;
    try {
      await SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.immersiveSticky,
        overlays: const [],
      );
    } catch (_) {}
  }

  Future<void> _exitImmersiveMode({bool resetOrientations = false}) async {
    if (!_shouldControlSystemUi) return;
    try {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    } catch (_) {}
    if (!resetOrientations) return;
    _lastOrientationKey = null;
    try {
      await SystemChrome.setPreferredOrientations(const []);
    } catch (_) {}
  }

  Future<void> _applyOrientationForMode({
    Map<String, dynamic>? mediaSource,
  }) async {
    if (!_shouldControlSystemUi) return;

    List<DeviceOrientation>? orientations;
    switch (_orientationMode) {
      case _OrientationMode.landscape:
        orientations = const [
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ];
        break;
      case _OrientationMode.portrait:
        orientations = const [DeviceOrientation.portraitUp];
        break;
      case _OrientationMode.auto:
        var aspect = playbackDisplayAspectForMediaSource(mediaSource);
        if (aspect == null) {
          final controller = _controller;
          if (controller == null || !controller.value.isInitialized) return;
          aspect = controller.value.aspectRatio;
          if (aspect <= 0) {
            final size = controller.value.size;
            if (size.width > 0 && size.height > 0) {
              aspect = size.width / size.height;
            }
          }
          if (aspect <= 0) return;

          final rotation = controller.value.rotationCorrection;
          if (rotation == 90 || rotation == 270) {
            aspect = 1.0 / aspect;
          }
        }
        orientations = preferredOrientationsForDisplayAspect(aspect);
        break;
    }

    final key = orientations.map((o) => o.name).join(',');
    if (_lastOrientationKey == key) return;
    _lastOrientationKey = key;
    _suppressLifecyclePauseTemporarily();
    try {
      await SystemChrome.setPreferredOrientations(orientations);
    } catch (_) {}
  }

  Future<void> _ensurePlaybackAutoStarts(
    VideoPlayerController controller,
  ) async {
    if (_controller != controller) return;
    if (!controller.value.isInitialized) return;
    if (controller.value.isPlaying) return;

    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        await controller.play();
      } catch (_) {}
      await Future<void>.delayed(
        Duration(milliseconds: attempt == 0 ? 120 : 220),
      );
      if (!mounted || _controller != controller) return;
      if (!controller.value.isInitialized) return;
      if (controller.value.isPlaying) return;
    }
  }

  String _audioTrackTitle(vp_platform.VideoAudioTrack t) {
    final label = (t.label ?? '').trim();
    if (label.isNotEmpty) return label;
    final lang = (t.language ?? '').trim();
    if (lang.isNotEmpty) return lang;
    return '音轨 ${t.id}';
  }

  String _audioTrackSubtitle(vp_platform.VideoAudioTrack t) {
    final parts = <String>[];
    final codec = (t.codec ?? '').trim();
    if (codec.isNotEmpty) parts.add(codec);
    if (t.channelCount != null && t.channelCount! > 0) {
      parts.add('${t.channelCount}ch');
    }
    if (t.sampleRate != null && t.sampleRate! > 0) {
      parts.add('${t.sampleRate}Hz');
    }
    if (t.bitrate != null && t.bitrate! > 0) {
      parts.add('${(t.bitrate! / 1000).round()} kbps');
    }
    return parts.join('  ');
  }

  String _subtitleTrackTitle(vp_android.ExoPlayerSubtitleTrackData t) {
    final label = (t.label ?? '').trim();
    if (label.isNotEmpty) return label;
    final lang = (t.language ?? '').trim();
    if (lang.isNotEmpty) return lang;
    return '字幕 ${t.groupIndex}_${t.trackIndex}';
  }

  String _subtitleTrackSubtitle(vp_android.ExoPlayerSubtitleTrackData t) {
    final parts = <String>[];
    final codec = (t.codec ?? '').trim();
    final mime = (t.mimeType ?? '').trim();
    if (codec.isNotEmpty) parts.add(codec);
    if (mime.isNotEmpty) parts.add(mime);
    return parts.join('  ');
  }

  double get _subtitleBottomPadding =>
      (_subtitlePositionStep.clamp(0, 20) * 5.0).clamp(0.0, 200.0).toDouble();

  Future<void> _applyExoSubtitleOptions() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;

    // ignore: invalid_use_of_visible_for_testing_member
    final playerId = controller.playerId;

    final api = vp_android.VideoPlayerInstanceApi(
      messageChannelSuffix: playerId.toString(),
    );

    try {
      await api.setSubtitleDelay((_subtitleDelaySeconds * 1000).round());
    } catch (_) {}

    try {
      await api.setSubtitleStyle(
        vp_android.SubtitleStyleMessage(
          fontSize: _subtitleFontSize.clamp(8.0, 96.0),
          bottomPadding: _subtitleBottomPadding,
          bold: _subtitleBold,
        ),
      );
    } catch (_) {}
  }

  Future<void> _maybeAutoSelectSubtitleTrack(
      VideoPlayerController controller) async {
    if (!_isAndroid) return;

    final prefRaw = widget.appState.preferredSubtitleLang.trim();
    final shouldOff =
        _selectedSubtitleStreamIndex == -1 || isSubtitleOffPreference(prefRaw);

    // ignore: invalid_use_of_visible_for_testing_member
    final playerId = controller.playerId;
    final api = vp_android.VideoPlayerInstanceApi(
      messageChannelSuffix: playerId.toString(),
    );

    if (shouldOff) {
      try {
        await api.deselectSubtitleTrack();
      } catch (_) {}
      return;
    }

    late final List<vp_android.ExoPlayerSubtitleTrackData> tracks;
    try {
      final data = await api.getSubtitleTracks();
      tracks = data.exoPlayerTracks ??
          const <vp_android.ExoPlayerSubtitleTrackData>[];
    } catch (_) {
      return;
    }

    if (tracks.isEmpty) return;
    if (tracks.any((t) => t.isSelected)) return;

    final isDefaultPref = prefRaw.isEmpty || prefRaw.toLowerCase() == 'default';
    final primaryPref = isDefaultPref ? 'zhs' : prefRaw;

    vp_android.ExoPlayerSubtitleTrackData? picked;
    if (primaryPref.isNotEmpty) {
      for (final t in tracks) {
        if (matchesPreferredLanguage(
          preference: primaryPref,
          language: t.language,
          title: t.label,
        )) {
          picked = t;
          break;
        }
      }
    }

    // Default fallback: any Chinese subtitle if Simplified isn't available.
    if (picked == null && isDefaultPref) {
      for (final t in tracks) {
        if (matchesPreferredLanguage(
          preference: 'chi',
          language: t.language,
          title: t.label,
        )) {
          picked = t;
          break;
        }
      }
    }

    if (picked == null) return;
    try {
      await api.selectSubtitleTrack(picked.groupIndex, picked.trackIndex);
    } catch (_) {}
  }

  Future<void> _pollSubtitleText() async {
    if (_subtitlePollInFlight) return;
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (_isAndroid && _viewType != VideoViewType.textureView) return;

    _subtitlePollInFlight = true;
    try {
      // ignore: invalid_use_of_visible_for_testing_member
      final playerId = controller.playerId;
      final api = vp_android.VideoPlayerInstanceApi(
        messageChannelSuffix: playerId.toString(),
      );
      final text = await api.getSubtitleText();
      if (!mounted) return;
      if (text != _subtitleText) {
        setState(() => _subtitleText = text);
      }
    } catch (_) {
      // ignore
    } finally {
      _subtitlePollInFlight = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final isReady = controller != null && controller.value.isInitialized;
    final controlsEnabled = isReady && !_loading && _playError == null;
    final enableBlur = !widget.isTv && widget.appState.enableBlurEffects;

    final remoteEnabled = widget.isTv || widget.appState.forceRemoteControlKeys;
    _remoteEnabled = remoteEnabled;
    final canPopRoute = Navigator.of(context).canPop();
    final needsSafeExit =
        canPopRoute && !_allowRoutePop && (_loading || controller != null);

    return PopScope(
      canPop: !needsSafeExit,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop || !needsSafeExit) return;
        unawaited(_requestExitThenPop());
      },
      child: Focus(
        focusNode: _tvSurfaceFocusNode,
        autofocus: remoteEnabled,
        canRequestFocus: remoteEnabled,
        skipTraversal: true,
        onKeyEvent: (node, event) {
          if (!remoteEnabled) return KeyEventResult.ignored;
          final key = event.logicalKey;

          if (widget.isTv && event is KeyDownEvent) {
            if (key == LogicalKeyboardKey.arrowLeft ||
                key == LogicalKeyboardKey.arrowRight) {
              _showControls();
            }

            final isBackKey = key == LogicalKeyboardKey.goBack ||
                key == LogicalKeyboardKey.escape ||
                key == LogicalKeyboardKey.browserBack;
            if (isBackKey) {
              if (_tvBottomPanelIndex != 0) {
                _showControls();
                _setTvBottomPanel(0);
                _focusTvPlayPause();
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            }

            if (key == LogicalKeyboardKey.arrowDown) {
              _showControls();
              final before = _tvBottomPanelIndex;
              _cycleTvBottomPanel(forward: true);
              if (before == _tvBottomPanelCount - 1) {
                _focusTvPlayPause();
              }
              return KeyEventResult.handled;
            }
            if (key == LogicalKeyboardKey.arrowUp) {
              _showControls();
              final before = _tvBottomPanelIndex;
              _cycleTvBottomPanel(forward: false);
              if (before == 1) {
                _focusTvPlayPause();
              }
              return KeyEventResult.handled;
            }

            if (controlsEnabled && _tvBottomPanelIndex == 0) {
              if (key == LogicalKeyboardKey.arrowLeft) {
                _showControls();
                // ignore: unawaited_futures
                _seekRelative(Duration(seconds: -_seekBackSeconds));
                return KeyEventResult.handled;
              }
              if (key == LogicalKeyboardKey.arrowRight) {
                _showControls();
                // ignore: unawaited_futures
                _seekRelative(Duration(seconds: _seekForwardSeconds));
                return KeyEventResult.handled;
              }
            }
          }

          if (!node.hasPrimaryFocus) return KeyEventResult.ignored;

          if (event is KeyDownEvent) {
            if (key == LogicalKeyboardKey.arrowUp) {
              _showControls(scheduleHide: false);
              _focusTvPlayPause();
              return KeyEventResult.handled;
            }
            if (key == LogicalKeyboardKey.arrowDown) {
              if (_controlsVisible) {
                _hideControlsForRemote();
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            }
          }

          if (!controlsEnabled) return KeyEventResult.ignored;

          final isOkKey = key == LogicalKeyboardKey.space ||
              key == LogicalKeyboardKey.enter ||
              key == LogicalKeyboardKey.select;
          if (isOkKey) {
            // If long-press speed is disabled, keep original behavior (toggle on key-down).
            if (!widget.appState.gestureLongPressSpeed) {
              if (event is KeyDownEvent) {
                // ignore: unawaited_futures
                _togglePlayPause();
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            }

            if (event is KeyDownEvent) {
              if (_tvOkLongPressTimer != null) return KeyEventResult.handled;
              final controller = _controller;
              if (controller == null || !controller.value.isInitialized) {
                return KeyEventResult.ignored;
              }

              _tvOkLongPressTriggered = false;
              _tvOkLongPressBaseRate = controller.value.playbackSpeed;
              _tvOkLongPressTimer = Timer(_tvOkLongPressDelay, () {
                if (!mounted) return;
                final controller = _controller;
                if (controller == null || !controller.value.isInitialized) {
                  return;
                }

                final base =
                    _tvOkLongPressBaseRate ?? controller.value.playbackSpeed;
                final targetRate =
                    (base * widget.appState.longPressSpeedMultiplier)
                        .clamp(0.25, 5.0)
                        .toDouble();
                _tvOkLongPressTriggered = true;
                // ignore: unawaited_futures
                controller.setPlaybackSpeed(targetRate);
                _setGestureOverlay(
                  icon: Icons.speed,
                  text: '倍速 ×${(targetRate / base).toStringAsFixed(2)}',
                );
              });
              return KeyEventResult.handled;
            }

            if (event is KeyUpEvent) {
              final t = _tvOkLongPressTimer;
              _tvOkLongPressTimer = null;
              t?.cancel();

              final controller = _controller;
              if (controller == null || !controller.value.isInitialized) {
                _tvOkLongPressBaseRate = null;
                _tvOkLongPressTriggered = false;
                return KeyEventResult.ignored;
              }

              if (_tvOkLongPressTriggered) {
                final base = _tvOkLongPressBaseRate;
                _tvOkLongPressTriggered = false;
                _tvOkLongPressBaseRate = null;
                if (base != null) {
                  // ignore: unawaited_futures
                  controller.setPlaybackSpeed(base);
                }
                _hideGestureOverlay();
                return KeyEventResult.handled;
              }

              _tvOkLongPressBaseRate = null;
              // ignore: unawaited_futures
              _togglePlayPause();
              return KeyEventResult.handled;
            }

            return KeyEventResult.ignored;
          }

          if (event is! KeyDownEvent) return KeyEventResult.ignored;

          final allowSeek = !widget.isTv || _tvBottomPanelIndex == 0;

          if (allowSeek && key == LogicalKeyboardKey.arrowLeft) {
            // ignore: unawaited_futures
            _seekRelative(Duration(seconds: -_seekBackSeconds));
            return KeyEventResult.handled;
          }
          if (allowSeek && key == LogicalKeyboardKey.arrowRight) {
            // ignore: unawaited_futures
            _seekRelative(Duration(seconds: _seekForwardSeconds));
            return KeyEventResult.handled;
          }

          return KeyEventResult.ignored;
        },
        child: Scaffold(
          backgroundColor: Colors.black,
          extendBodyBehindAppBar: true,
          appBar: null,
          body: Column(
            children: [
              Expanded(
                child: Container(
                  color: Colors.black,
                  child: isReady
                      ? Stack(
                          fit: StackFit.expand,
                          children: [
                            Center(
                              child: AspectRatio(
                                aspectRatio: controller.value.aspectRatio == 0
                                    ? 16 / 9
                                    : controller.value.aspectRatio,
                                child: VideoPlayer(controller),
                              ),
                            ),
                            Positioned.fill(
                              child: DanmakuStage(
                                key: _danmakuKey,
                                enabled: _danmakuEnabled,
                                opacity: _danmakuOpacity,
                                scale: _danmakuScale,
                                speed: _danmakuSpeed,
                                timeScale: controller.value.playbackSpeed,
                                bold: _danmakuBold,
                                scrollMaxLines: _danmakuMaxLines,
                                topMaxLines: _danmakuTopMaxLines,
                                bottomMaxLines: _danmakuBottomMaxLines,
                                preventOverlap: _danmakuPreventOverlap,
                              ),
                            ),
                            if ((!_isAndroid ||
                                    _viewType == VideoViewType.textureView) &&
                                _subtitleText.trim().isNotEmpty)
                              Positioned.fill(
                                child: IgnorePointer(
                                  child: Align(
                                    alignment: Alignment.bottomCenter,
                                    child: Padding(
                                      padding: EdgeInsets.fromLTRB(
                                        16,
                                        0,
                                        16,
                                        _subtitleBottomPadding,
                                      ),
                                      child: DecoratedBox(
                                        decoration: BoxDecoration(
                                          color: Colors.black.withValues(
                                            alpha: 0.55,
                                          ),
                                          borderRadius:
                                              BorderRadius.circular(6),
                                        ),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 4,
                                          ),
                                          child: Text(
                                            _subtitleText.trim(),
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              height: 1.4,
                                              fontSize: _subtitleFontSize.clamp(
                                                12.0,
                                                60.0,
                                              ),
                                              fontWeight: _subtitleBold
                                                  ? FontWeight.w600
                                                  : FontWeight.normal,
                                              color: Colors.white,
                                              shadows: const [
                                                Shadow(
                                                  blurRadius: 6,
                                                  offset: Offset(2, 2),
                                                  color: Colors.black,
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            if (_screenBrightness < 0.999)
                              Positioned.fill(
                                child: IgnorePointer(
                                  child: ColoredBox(
                                    color: Colors.black.withValues(
                                      alpha: (1.0 - _screenBrightness)
                                          .clamp(0.0, 0.8)
                                          .toDouble(),
                                    ),
                                  ),
                                ),
                              ),
                            if (_buffering)
                              Positioned.fill(
                                child: IgnorePointer(
                                  child: ColoredBox(
                                    color: Colors.black26,
                                    child: Center(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const CircularProgressIndicator(),
                                          if (widget.appState.showBufferSpeed)
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                  top: 12),
                                              child: Text(
                                                '网速：${_netSpeedBytesPerSecond == null ? '—' : formatBytesPerSecond(_netSpeedBytesPerSecond!)}',
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            Positioned.fill(
                              child: LayoutBuilder(
                                builder: (ctx, constraints) {
                                  final w = constraints.maxWidth;
                                  final h = constraints.maxHeight;
                                  final sideDragEnabled =
                                      widget.appState.gestureBrightness ||
                                          widget.appState.gestureVolume;
                                  return GestureDetector(
                                    behavior: HitTestBehavior.translucent,
                                    onTap: _toggleControls,
                                    onDoubleTapDown: controlsEnabled
                                        ? (d) => _doubleTapDownPosition =
                                            d.localPosition
                                        : null,
                                    onDoubleTap: controlsEnabled
                                        ? () {
                                            final pos =
                                                _doubleTapDownPosition ??
                                                    Offset(w / 2, 0);
                                            // ignore: unawaited_futures
                                            _handleDoubleTap(pos, w);
                                          }
                                        : null,
                                    onHorizontalDragStart: (controlsEnabled &&
                                            widget.appState.gestureSeek)
                                        ? _onSeekDragStart
                                        : null,
                                    onHorizontalDragUpdate: (controlsEnabled &&
                                            widget.appState.gestureSeek)
                                        ? (d) => _onSeekDragUpdate(
                                              d,
                                              width: w,
                                              duration:
                                                  controller.value.duration,
                                            )
                                        : null,
                                    onHorizontalDragEnd: (controlsEnabled &&
                                            widget.appState.gestureSeek)
                                        ? _onSeekDragEnd
                                        : null,
                                    onVerticalDragStart: (controlsEnabled &&
                                            sideDragEnabled)
                                        ? (d) => _onSideDragStart(d, width: w)
                                        : null,
                                    onVerticalDragUpdate: (controlsEnabled &&
                                            sideDragEnabled)
                                        ? (d) => _onSideDragUpdate(d, height: h)
                                        : null,
                                    onVerticalDragEnd:
                                        (controlsEnabled && sideDragEnabled)
                                            ? _onSideDragEnd
                                            : null,
                                    onLongPressStart: (controlsEnabled &&
                                            widget
                                                .appState.gestureLongPressSpeed)
                                        ? _onLongPressStart
                                        : null,
                                    onLongPressMoveUpdate: (controlsEnabled &&
                                            widget.appState
                                                .gestureLongPressSpeed &&
                                            widget.appState.longPressSlideSpeed)
                                        ? (d) => _onLongPressMoveUpdate(
                                              d,
                                              height: h,
                                            )
                                        : null,
                                    onLongPressEnd: (controlsEnabled &&
                                            widget
                                                .appState.gestureLongPressSpeed)
                                        ? _onLongPressEnd
                                        : null,
                                    child: const SizedBox.expand(),
                                  );
                                },
                              ),
                            ),
                            if (_gestureOverlayText != null)
                              Center(
                                child: IgnorePointer(
                                  child: Material(
                                    color: Colors.black54,
                                    borderRadius: BorderRadius.circular(12),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 10,
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            _gestureOverlayIcon ??
                                                Icons.info_outline,
                                            size: 20,
                                            color: Colors.white,
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            _gestureOverlayText!,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 13,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            if (!widget.isTv && !_mobileSidePanelVisible)
                              Align(
                                alignment: Alignment.topCenter,
                                child: SafeArea(
                                  bottom: false,
                                  minimum:
                                      const EdgeInsets.fromLTRB(12, 12, 12, 0),
                                  child: AnimatedSlide(
                                    offset: _controlsVisible
                                        ? Offset.zero
                                        : const Offset(0, -0.18),
                                    duration: const Duration(milliseconds: 200),
                                    curve: Curves.easeOutCubic,
                                    child: AnimatedOpacity(
                                      opacity: _controlsVisible ? 1 : 0,
                                      duration:
                                          const Duration(milliseconds: 160),
                                      curve: Curves.easeOut,
                                      child: IgnorePointer(
                                        ignoring: !_controlsVisible,
                                        child: Listener(
                                          onPointerDown: (_) => _showControls(),
                                          child: _buildMobileTopStatusBar(
                                            context,
                                            controlsEnabled: controlsEnabled,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            if (_skipIntroPromptVisible)
                              Align(
                                alignment: Alignment.topRight,
                                child: SafeArea(
                                  bottom: false,
                                  child: Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                        12, 12, 12, 0),
                                    child: Material(
                                      color: Colors.black54,
                                      borderRadius: BorderRadius.circular(999),
                                      clipBehavior: Clip.antiAlias,
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 10,
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(
                                              Icons.skip_next,
                                              size: 18,
                                              color: Colors.white,
                                            ),
                                            const SizedBox(width: 6),
                                            Builder(builder: (context) {
                                              final end = _introTimestamps?.end;
                                              final endText = (end != null &&
                                                      end > Duration.zero)
                                                  ? '（至 ${_fmtClock(end)}）'
                                                  : '';
                                              return Text(
                                                '检测到片头$endText',
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 13,
                                                ),
                                              );
                                            }),
                                            const SizedBox(width: 10),
                                            InkWell(
                                              onTap: _skipIntro,
                                              borderRadius:
                                                  BorderRadius.circular(999),
                                              child: Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 10,
                                                  vertical: 6,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: Colors.white
                                                      .withValues(alpha: 0.18),
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                          999),
                                                ),
                                                child: const Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    Icon(
                                                      Icons.fast_forward,
                                                      size: 18,
                                                      color: Colors.white,
                                                    ),
                                                    SizedBox(width: 4),
                                                    Text(
                                                      '跳过',
                                                      style: TextStyle(
                                                        color: Colors.white,
                                                        fontSize: 13,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            InkWell(
                                              onTap: _dismissSkipIntroPrompt,
                                              borderRadius:
                                                  BorderRadius.circular(999),
                                              child: Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 10,
                                                  vertical: 6,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: Colors.white
                                                      .withValues(alpha: 0.12),
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                          999),
                                                ),
                                                child: const Text(
                                                  '不跳过',
                                                  style: TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 13,
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
                              ),
                            if (controlsEnabled &&
                                _showResumeHint &&
                                _resumeHintPosition != null)
                              Align(
                                alignment: Alignment.topCenter,
                                child: SafeArea(
                                  bottom: false,
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 12),
                                    child: Material(
                                      color: Colors.black54,
                                      borderRadius: BorderRadius.circular(999),
                                      clipBehavior: Clip.antiAlias,
                                      child: InkWell(
                                        onTap: _resumeToHistoryPosition,
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 10,
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const Icon(
                                                Icons.history,
                                                size: 18,
                                                color: Colors.white,
                                              ),
                                              const SizedBox(width: 6),
                                              Text(
                                                '跳转到 ${_fmtClock(_resumeHintPosition!)} 继续观看',
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 13,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            if (controlsEnabled &&
                                _showStartOverHint &&
                                _startOverHintPosition != null)
                              Align(
                                alignment: Alignment.topCenter,
                                child: SafeArea(
                                  bottom: false,
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 12),
                                    child: Material(
                                      color: Colors.black54,
                                      borderRadius: BorderRadius.circular(999),
                                      clipBehavior: Clip.antiAlias,
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 10,
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(
                                              Icons.history,
                                              size: 18,
                                              color: Colors.white,
                                            ),
                                            const SizedBox(width: 6),
                                            Text(
                                              '已从 ${_fmtClock(_startOverHintPosition!)} 继续播放',
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 13,
                                              ),
                                            ),
                                            const SizedBox(width: 10),
                                            InkWell(
                                              onTap: _restartFromBeginning,
                                              borderRadius:
                                                  BorderRadius.circular(999),
                                              child: Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 10,
                                                  vertical: 6,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: Colors.white
                                                      .withValues(alpha: 0.18),
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                          999),
                                                ),
                                                child: const Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    Icon(
                                                      Icons.replay,
                                                      size: 18,
                                                      color: Colors.white,
                                                    ),
                                                    SizedBox(width: 4),
                                                    Text(
                                                      '从头开始',
                                                      style: TextStyle(
                                                        color: Colors.white,
                                                        fontSize: 13,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            if (widget.isTv)
                              Align(
                                alignment: Alignment.topCenter,
                                child: Padding(
                                  padding:
                                      const EdgeInsets.fromLTRB(12, 12, 12, 0),
                                  child: AnimatedSlide(
                                    offset: _controlsVisible
                                        ? Offset.zero
                                        : const Offset(0, -0.20),
                                    duration: const Duration(milliseconds: 200),
                                    curve: Curves.easeOutCubic,
                                    child: AnimatedOpacity(
                                      opacity: _controlsVisible ? 1 : 0,
                                      duration:
                                          const Duration(milliseconds: 160),
                                      curve: Curves.easeOut,
                                      child: IgnorePointer(
                                        ignoring: !_controlsVisible,
                                        child: _buildTvTopStatusBar(),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            if (widget.isTv)
                              Align(
                                alignment: Alignment.bottomCenter,
                                child: Padding(
                                  padding:
                                      const EdgeInsets.fromLTRB(12, 0, 12, 12),
                                  child: AnimatedSlide(
                                    offset: _controlsVisible
                                        ? Offset.zero
                                        : const Offset(0, 0.20),
                                    duration: const Duration(milliseconds: 200),
                                    curve: Curves.easeOutCubic,
                                    child: AnimatedOpacity(
                                      opacity: _controlsVisible ? 1 : 0,
                                      duration:
                                          const Duration(milliseconds: 160),
                                      curve: Curves.easeOut,
                                      child: IgnorePointer(
                                        ignoring: !_controlsVisible,
                                        child: _buildTvBottomStatusBar(
                                          enabled: controlsEnabled,
                                          position: _position,
                                          buffered: _lastBufferedEnd,
                                          duration: _duration,
                                          isPlaying: _isPlaying,
                                          onPlay: () async {
                                            _showControls();
                                            await controller.play();
                                            _maybeReportPlaybackProgress(
                                              controller.value.position,
                                              force: true,
                                            );
                                            _applyDanmakuPauseState(false);
                                            if (mounted) setState(() {});
                                          },
                                          onPause: () async {
                                            _showControls();
                                            await controller.pause();
                                            _maybeReportPlaybackProgress(
                                              controller.value.position,
                                              force: true,
                                            );
                                            _applyDanmakuPauseState(true);
                                            if (mounted) setState(() {});
                                          },
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            if (!widget.isTv && !_mobileSidePanelVisible)
                              Align(
                                alignment: Alignment.bottomCenter,
                                child: SafeArea(
                                  top: false,
                                  minimum:
                                      const EdgeInsets.fromLTRB(12, 0, 12, 12),
                                  child: AnimatedSlide(
                                    offset: _controlsVisible
                                        ? Offset.zero
                                        : const Offset(0, 0.18),
                                    duration: const Duration(milliseconds: 200),
                                    curve: Curves.easeOutCubic,
                                    child: AnimatedOpacity(
                                      opacity: _controlsVisible ? 1 : 0,
                                      duration:
                                          const Duration(milliseconds: 160),
                                      curve: Curves.easeOut,
                                      child: IgnorePointer(
                                        ignoring: !_controlsVisible,
                                        child: Listener(
                                          onPointerDown: (_) => _showControls(),
                                          child: Focus(
                                            canRequestFocus: false,
                                            onKeyEvent: (node, event) {
                                              if (!_remoteEnabled) {
                                                return KeyEventResult.ignored;
                                              }
                                              if (event is! KeyDownEvent) {
                                                return KeyEventResult.ignored;
                                              }
                                              if (event.logicalKey ==
                                                  LogicalKeyboardKey
                                                      .arrowDown) {
                                                final moved =
                                                    FocusScope.of(context)
                                                        .focusInDirection(
                                                  TraversalDirection.down,
                                                );
                                                if (moved) {
                                                  return KeyEventResult.handled;
                                                }
                                                _hideControlsForRemote();
                                                return KeyEventResult.handled;
                                              }
                                              return KeyEventResult.ignored;
                                            },
                                            child: _buildMobileBottomStatusBar(
                                              context,
                                              controlsEnabled: controlsEnabled,
                                              controller: controller,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            if (!widget.isTv)
                              _buildEpisodePickerOverlay(
                                  enableBlur: enableBlur),
                            if (!widget.isTv)
                              _buildMobileSidePanelOverlay(
                                context: context,
                                controlsEnabled: controlsEnabled,
                              ),
                          ],
                        )
                      : _playError != null
                          ? Center(
                              child: Text(
                                _playError!,
                                style: const TextStyle(color: Colors.redAccent),
                                textAlign: TextAlign.center,
                              ),
                            )
                          : const Center(child: CircularProgressIndicator()),
                ),
              ),
              if (_loading) const LinearProgressIndicator(),
            ],
          ),
        ),
      ),
    );
  }
}

enum _MobilePlayerPanel {
  route,
  version,
  audio,
  core,
  superResolution,
  danmaku,
  subtitle,
  speed,
}

enum _OrientationMode { auto, landscape, portrait }

enum _GestureMode { none, brightness, volume, seek, speed }
