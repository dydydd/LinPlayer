import 'package:flutter/foundation.dart';
import 'package:lin_player_player/lin_player_player.dart';
import 'package:lin_player_prefs/lin_player_prefs.dart';
import 'package:lin_player_state/lin_player_state.dart';

import '../../server_adapters/server_access.dart';
import '../built_in_proxy/built_in_proxy_service.dart';
import '../playback_proxy/playback_proxy.dart';

enum PlaybackPreloadTargetKind {
  currentItem,
  nextItem,
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
}

@immutable
class PreparedPlaybackPreload {
  const PreparedPlaybackPreload({
    required this.targetKind,
    required this.triggerSource,
    required this.resolvedSource,
    required this.startPosition,
    this.httpProxyUrl,
  });

  final PlaybackPreloadTargetKind targetKind;
  final String triggerSource;
  final ResolvedPlaybackSource resolvedSource;
  final Duration startPosition;
  final String? httpProxyUrl;

  PreloadRequest toPreloadRequest() {
    return PreloadRequest(
      resolvedSource: resolvedSource,
      triggerSource: triggerSource,
      startPosition: startPosition,
      httpProxyUrl: httpProxyUrl,
    );
  }
}

class PlaybackPreloadCoordinator {
  const PlaybackPreloadCoordinator._();

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
    return prepareResolved(
      appState: request.appState,
      targetKind: request.targetKind,
      triggerSource: request.triggerSource,
      resolvedSource: buildResult.resolvedSource,
      startPosition: request.startPosition,
      preferBuiltInProxy: request.preferBuiltInProxy,
    );
  }

  static PreparedPlaybackPreload prepareResolved({
    required AppState appState,
    required PlaybackPreloadTargetKind targetKind,
    required String triggerSource,
    required ResolvedPlaybackSource resolvedSource,
    Duration startPosition = Duration.zero,
    String? httpProxyUrl,
    bool preferBuiltInProxy = false,
  }) {
    final normalizedStart =
        startPosition < Duration.zero ? Duration.zero : startPosition;
    final normalizedTrigger = triggerSource.trim().isEmpty
        ? 'unknown'
        : triggerSource.trim();
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
      httpProxyUrl: normalizedProxy,
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
}
