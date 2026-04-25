import 'package:flutter/foundation.dart';
import 'package:lin_player_player/lin_player_player.dart';
import 'package:lin_player_prefs/lin_player_prefs.dart';
import 'package:lin_player_state/lin_player_state.dart';

import '../../server_adapters/server_access.dart';
import '../built_in_proxy/built_in_proxy_service.dart';
import '../playback_proxy/playback_proxy.dart';
import '../stream_proxy/local_http_stream_proxy.dart';
import '../stream_resolver/stream_models.dart';

const Object _preparedPlaybackSourceUnset = Object();

enum PlaybackPreloadTargetKind {
  currentItem,
  nextItem,
}

enum StartupPlaybackWarmupTiming {
  notRequested,
  immediate,
  afterPlayerInitialize,
}

@immutable
class PlaybackPreloadBuildRequest {
  const PlaybackPreloadBuildRequest({
    required this.access,
    required this.appState,
    required this.itemId,
    required this.playerCore,
    required this.targetKind,
    required this.triggerSource,
    this.startPosition = Duration.zero,
    this.selectedMediaSourceId,
    this.preferredMediaSourceIndex,
    this.audioStreamIndex,
    this.subtitleStreamIndex,
    this.preferredVideoVersion = VideoVersionPreference.defaultVersion,
    this.preferBuiltInProxy = false,
    this.ownerKey,
    this.scopeKey,
  });

  final ServerAccess access;
  final AppState appState;
  final String itemId;
  final PlaybackSourcePlayerCoreKind playerCore;
  final PlaybackPreloadTargetKind targetKind;
  final String triggerSource;
  final Duration startPosition;
  final String? selectedMediaSourceId;
  final int? preferredMediaSourceIndex;
  final int? audioStreamIndex;
  final int? subtitleStreamIndex;
  final VideoVersionPreference preferredVideoVersion;
  final bool preferBuiltInProxy;
  final String? ownerKey;
  final String? scopeKey;
}

@immutable
class PreparedPlaybackPreload {
  static const Duration _mpvDirectFilePreloadDuration = Duration(seconds: 8);

  PreparedPlaybackPreload({
    required this.targetKind,
    required this.triggerSource,
    required this.resolvedSource,
    required this.startPosition,
    this.playerCore = PlaybackSourcePlayerCoreKind.mpv,
    this.httpProxyUrl,
    this.ownerKey,
    this.scopeKey,
    this.playSessionId,
    List<Map<String, dynamic>> mediaSources = const <Map<String, dynamic>>[],
    Map<String, dynamic>? selectedMediaSource,
    this.selectedMediaSourceId,
    this.audioStreamIndex,
    this.subtitleStreamIndex,
    this.playbackSource,
  })  : mediaSources = List<Map<String, dynamic>>.unmodifiable(
          mediaSources
              .map((entry) => Map<String, dynamic>.unmodifiable(entry))
              .toList(growable: false),
        ),
        selectedMediaSource = selectedMediaSource == null
            ? null
            : Map<String, dynamic>.unmodifiable(selectedMediaSource);

  final PlaybackPreloadTargetKind targetKind;
  final String triggerSource;
  final ResolvedPlaybackSource resolvedSource;
  final Duration startPosition;
  final PlaybackSourcePlayerCoreKind playerCore;
  final String? httpProxyUrl;
  final String? ownerKey;
  final String? scopeKey;
  final String? playSessionId;
  final List<Map<String, dynamic>> mediaSources;
  final Map<String, dynamic>? selectedMediaSource;
  final String? selectedMediaSourceId;
  final int? audioStreamIndex;
  final int? subtitleStreamIndex;
  final PlayableSource? playbackSource;

  String? get effectivePlaySessionId {
    final prepared = (playSessionId ?? '').trim();
    if (prepared.isNotEmpty) return prepared;
    final resolved = resolvedSource.playSessionId.trim();
    return resolved.isEmpty ? null : resolved;
  }

  bool matchesPlayback({
    required String itemId,
    required PlaybackSourcePlayerCoreKind playerCore,
    String? selectedMediaSourceId,
    int? audioStreamIndex,
    int? subtitleStreamIndex,
  }) {
    if (this.playerCore != playerCore) return false;
    if (resolvedSource.itemId.trim() != itemId.trim()) return false;

    final expectedMediaSource = (selectedMediaSourceId ?? '').trim();
    final preparedMediaSource =
        ((this.selectedMediaSourceId ?? resolvedSource.mediaSourceId)).trim();
    if (expectedMediaSource.isNotEmpty &&
        preparedMediaSource.isNotEmpty &&
        expectedMediaSource != preparedMediaSource) {
      return false;
    }

    if (this.audioStreamIndex != audioStreamIndex) return false;
    if (this.subtitleStreamIndex != subtitleStreamIndex) return false;
    return true;
  }

  bool matchesHttpProxyUrl(String? proxyUrl) {
    return _normalizeProxyUrl(proxyUrl) == _normalizeProxyUrl(httpProxyUrl);
  }

  PreparedPlaybackPreload copyWith({
    Object? playbackSource = _preparedPlaybackSourceUnset,
  }) {
    return PreparedPlaybackPreload(
      targetKind: targetKind,
      triggerSource: triggerSource,
      resolvedSource: resolvedSource,
      startPosition: startPosition,
      playerCore: playerCore,
      httpProxyUrl: httpProxyUrl,
      ownerKey: ownerKey,
      scopeKey: scopeKey,
      playSessionId: playSessionId,
      mediaSources: mediaSources,
      selectedMediaSource: selectedMediaSource,
      selectedMediaSourceId: selectedMediaSourceId,
      audioStreamIndex: audioStreamIndex,
      subtitleStreamIndex: subtitleStreamIndex,
      playbackSource: identical(playbackSource, _preparedPlaybackSourceUnset)
          ? this.playbackSource
          : playbackSource as PlayableSource?,
    );
  }

  PreloadRequest toPreloadRequest() {
    return PreloadRequest(
      resolvedSource: resolvedSource,
      triggerSource: triggerSource,
      startPosition: startPosition,
      preloadDuration: _preloadDurationForPreparedSource(),
      dedupeFingerprint: _dedupeFingerprintForTargetKind(targetKind),
      httpProxyUrl: httpProxyUrl,
      ownerKey: ownerKey,
      scopeKey: scopeKey,
    );
  }

  Duration _preloadDurationForPreparedSource() {
    if (playerCore != PlaybackSourcePlayerCoreKind.mpv) {
      return PreloadRequest.defaultPreloadDuration;
    }
    return switch (resolvedSource.mediaTypeHint) {
      // MPV still tends to ask for a larger contiguous prefix before the first
      // frame, so widen prepared direct-file warmups instead of only relying
      // on the default 3s preload window.
      ResolvedPlaybackMediaType.file ||
      ResolvedPlaybackMediaType.unknown =>
        _mpvDirectFilePreloadDuration,
      ResolvedPlaybackMediaType.hls ||
      ResolvedPlaybackMediaType.dash =>
        PreloadRequest.defaultPreloadDuration,
    };
  }

  static String _dedupeFingerprintForTargetKind(
    PlaybackPreloadTargetKind kind,
  ) {
    return switch (kind) {
      PlaybackPreloadTargetKind.currentItem => 'target:current',
      PlaybackPreloadTargetKind.nextItem => 'target:next',
    };
  }

  static String? _normalizeProxyUrl(String? raw) {
    final value = (raw ?? '').trim();
    return value.isEmpty ? null : value;
  }
}

@immutable
class StartupPlaybackWarmupPlan {
  const StartupPlaybackWarmupPlan({
    required this.timing,
    required this.startPosition,
    required this.triggerSource,
    required this.reason,
  });

  final StartupPlaybackWarmupTiming timing;
  final Duration startPosition;
  final String triggerSource;
  final String reason;

  bool get shouldRequest => timing != StartupPlaybackWarmupTiming.notRequested;
}

class PlaybackPreloadCoordinator {
  const PlaybackPreloadCoordinator._();

  static const Duration _startupWarmupPreparedAlignmentTolerance =
      Duration(seconds: 2);

  static int _nextOwnerTokenId = 0;

  static Future<PreparedPlaybackPreload> prepareItem(
    PlaybackPreloadBuildRequest request,
  ) async {
    final buildResult = await PlaybackSourceBuilder.build(
      PlaybackSourceBuildRequest(
        adapter: request.access.adapter,
        auth: request.access.auth,
        itemId: request.itemId,
        playerCore: request.playerCore,
        selectedMediaSourceId: request.selectedMediaSourceId,
        preferredMediaSourceIndex: request.preferredMediaSourceIndex,
        audioStreamIndex: request.audioStreamIndex,
        subtitleStreamIndex: request.subtitleStreamIndex,
        preferredVideoVersion: request.preferredVideoVersion,
      ),
    );
    final prepared = prepareResolved(
      appState: request.appState,
      targetKind: request.targetKind,
      triggerSource: request.triggerSource,
      resolvedSource: buildResult.resolvedSource,
      startPosition: request.startPosition,
      playerCore: request.playerCore,
      preferBuiltInProxy: request.preferBuiltInProxy,
      ownerKey: request.ownerKey,
      scopeKey: request.scopeKey,
      playSessionId: buildResult.playbackInfo.playSessionId,
      mediaSources: buildResult.mediaSources,
      selectedMediaSource: buildResult.selectedMediaSource,
      selectedMediaSourceId: buildResult.selectedMediaSourceId,
      audioStreamIndex: request.audioStreamIndex,
      subtitleStreamIndex: request.subtitleStreamIndex,
    );
    try {
      return await attachPlaybackSource(prepared);
    } catch (_) {
      return prepared;
    }
  }

  static PreparedPlaybackPreload prepareResolved({
    required AppState appState,
    required PlaybackPreloadTargetKind targetKind,
    required String triggerSource,
    required ResolvedPlaybackSource resolvedSource,
    Duration startPosition = Duration.zero,
    PlaybackSourcePlayerCoreKind playerCore = PlaybackSourcePlayerCoreKind.mpv,
    String? httpProxyUrl,
    bool preferBuiltInProxy = false,
    String? ownerKey,
    String? scopeKey,
    String? playSessionId,
    List<Map<String, dynamic>> mediaSources = const <Map<String, dynamic>>[],
    Map<String, dynamic>? selectedMediaSource,
    String? selectedMediaSourceId,
    int? audioStreamIndex,
    int? subtitleStreamIndex,
  }) {
    final normalizedStart =
        startPosition < Duration.zero ? Duration.zero : startPosition;
    final normalizedTrigger =
        triggerSource.trim().isEmpty ? 'unknown' : triggerSource.trim();
    final normalizedOwner = _normalizeScopeToken(ownerKey);
    final normalizedScope = _normalizeScopeToken(scopeKey);
    final normalizedProxy = (httpProxyUrl ?? '').trim().isNotEmpty
        ? httpProxyUrl!.trim()
        : resolveHttpProxyUrl(
            appState: appState,
            sourceUrl: resolvedSource.url,
            preferBuiltInProxy: preferBuiltInProxy,
          );
    return PreparedPlaybackPreload(
      targetKind: targetKind,
      triggerSource: normalizedTrigger,
      resolvedSource: resolvedSource.copyWith(proxyUrl: normalizedProxy),
      startPosition: normalizedStart,
      playerCore: playerCore,
      httpProxyUrl: normalizedProxy,
      ownerKey: normalizedOwner,
      scopeKey: normalizedScope,
      playSessionId:
          (playSessionId ?? '').trim().isEmpty ? null : playSessionId!.trim(),
      mediaSources: mediaSources,
      selectedMediaSource: selectedMediaSource,
      selectedMediaSourceId: (() {
        final value =
            ((selectedMediaSourceId ?? resolvedSource.mediaSourceId)).trim();
        return value.isEmpty ? null : value;
      })(),
      audioStreamIndex: audioStreamIndex,
      subtitleStreamIndex: subtitleStreamIndex,
    );
  }

  static Future<StreamPreloadResult> preloadItem(
    PlaybackPreloadBuildRequest request,
  ) async {
    final prepared = await prepareItem(request);
    return preloadPrepared(prepared);
  }

  static Future<StreamPreloadResult> preloadPrepared(
    PreparedPlaybackPreload request,
  ) {
    return StreamPreloadService.instance.preloadResolvedSource(
      request.toPreloadRequest(),
    );
  }

  static Future<PreparedPlaybackPreload> attachPlaybackSource(
    PreparedPlaybackPreload prepared,
  ) async {
    final playbackSource = await buildPlaybackSource(
      resolvedSource: prepared.resolvedSource,
      httpProxyUrl: prepared.httpProxyUrl,
      playerCore: prepared.playerCore,
    );
    return prepared.copyWith(playbackSource: playbackSource);
  }

  static Future<PlayableSource> buildPlaybackSource({
    required ResolvedPlaybackSource resolvedSource,
    String? httpProxyUrl,
    PlaybackSourcePlayerCoreKind playerCore = PlaybackSourcePlayerCoreKind.mpv,
  }) async {
    final cacheKey = buildResolvedPlaybackCacheKey(
      resolvedSource,
      proxyUrl: _normalizeProxyUrl(httpProxyUrl ?? resolvedSource.proxyUrl),
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
    if (!playbackSourceCoreUsesLoopbackPlaybackPackaging(playerCore)) {
      return candidate;
    }
    final proxied = await LocalHttpStreamProxy.wrapPlaybackSource(
      candidate,
      cacheKey: cacheKey,
    );
    return proxied ?? candidate;
  }

  static StartupPlaybackWarmupPlan buildStartupWarmupPlan({
    required bool preloadEnabled,
    required Duration startPosition,
    PreparedPlaybackPreload? preparedPreload,
  }) {
    final normalizedStart =
        startPosition < Duration.zero ? Duration.zero : startPosition;
    final triggerSource =
        normalizedStart > Duration.zero ? 'playback_resume' : 'playback_start';
    if (!preloadEnabled) {
      return StartupPlaybackWarmupPlan(
        timing: StartupPlaybackWarmupTiming.notRequested,
        startPosition: normalizedStart,
        triggerSource: triggerSource,
        reason: 'disabled',
      );
    }

    final prepared = preparedPreload;
    if (prepared == null) {
      return StartupPlaybackWarmupPlan(
        timing: normalizedStart > Duration.zero
            ? StartupPlaybackWarmupTiming.immediate
            : StartupPlaybackWarmupTiming.afterPlayerInitialize,
        startPosition: normalizedStart,
        triggerSource: triggerSource,
        reason: normalizedStart > Duration.zero
            ? 'resume-without-handoff'
            : 'avoid-startup-contention',
      );
    }

    final preparedStart = prepared.startPosition < Duration.zero
        ? Duration.zero
        : prepared.startPosition;
    if (_startupWarmupPreparedAligned(
      preparedStart: preparedStart,
      playbackStart: normalizedStart,
    )) {
      return StartupPlaybackWarmupPlan(
        timing: StartupPlaybackWarmupTiming.afterPlayerInitialize,
        startPosition: normalizedStart,
        triggerSource: triggerSource,
        reason: normalizedStart > Duration.zero
            ? 'resume-already-prepared'
            : 'prepared-handoff',
      );
    }

    return StartupPlaybackWarmupPlan(
      timing: StartupPlaybackWarmupTiming.immediate,
      startPosition: normalizedStart,
      triggerSource: triggerSource,
      reason: 'resume-window-shifted',
    );
  }

  static String createOwnerToken(String namespace) {
    final normalized = _normalizeScopeToken(namespace) ?? 'preload';
    _nextOwnerTokenId += 1;
    return '$normalized-${_nextOwnerTokenId.toString().padLeft(4, '0')}';
  }

  static void cancelOwner(String ownerKey) {
    StreamPreloadService.instance.cancelOwner(ownerKey);
  }

  static void cancelOwnerScope({
    required String ownerKey,
    required String scopeKey,
  }) {
    StreamPreloadService.instance.cancelOwnerScope(
      ownerKey: ownerKey,
      scopeKey: scopeKey,
    );
  }

  static String? resolveHttpProxyUrl({
    required AppState appState,
    required String sourceUrl,
    required bool preferBuiltInProxy,
  }) {
    final uri = Uri.tryParse(sourceUrl);
    if (uri == null) return null;
    if (preferBuiltInProxy) {
      return BuiltInProxyService.proxyUrlForUri(uri);
    }
    return resolvePlaybackHttpProxyForUri(appState: appState, uri: uri);
  }

  static String? _normalizeScopeToken(String? raw) {
    final value = (raw ?? '').trim();
    if (value.isEmpty) return null;
    return value.replaceAll(RegExp(r'\s+'), '_');
  }

  static String? _normalizeProxyUrl(String? raw) {
    final value = (raw ?? '').trim();
    return value.isEmpty ? null : value;
  }

  static bool _startupWarmupPreparedAligned({
    required Duration preparedStart,
    required Duration playbackStart,
  }) {
    final delta = preparedStart - playbackStart;
    return delta.abs() <= _startupWarmupPreparedAlignmentTolerance;
  }
}
