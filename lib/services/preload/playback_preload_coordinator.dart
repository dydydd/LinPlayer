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
  const PreparedPlaybackPreload({
    required this.targetKind,
    required this.triggerSource,
    required this.resolvedSource,
    required this.startPosition,
    this.httpProxyUrl,
    this.ownerKey,
    this.scopeKey,
  });

  final PlaybackPreloadTargetKind targetKind;
  final String triggerSource;
  final ResolvedPlaybackSource resolvedSource;
  final Duration startPosition;
  final String? httpProxyUrl;
  final String? ownerKey;
  final String? scopeKey;

  PreloadRequest toPreloadRequest() {
    return PreloadRequest(
      resolvedSource: resolvedSource,
      triggerSource: triggerSource,
      startPosition: startPosition,
      dedupeFingerprint: _dedupeFingerprintForTargetKind(targetKind),
      httpProxyUrl: httpProxyUrl,
      ownerKey: ownerKey,
      scopeKey: scopeKey,
    );
  }

  static String _dedupeFingerprintForTargetKind(
    PlaybackPreloadTargetKind kind,
  ) {
    return switch (kind) {
      PlaybackPreloadTargetKind.currentItem => 'target:current',
      PlaybackPreloadTargetKind.nextItem => 'target:next',
    };
  }
}

class PlaybackPreloadCoordinator {
  const PlaybackPreloadCoordinator._();

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
    return prepareResolved(
      appState: request.appState,
      targetKind: request.targetKind,
      triggerSource: request.triggerSource,
      resolvedSource: buildResult.resolvedSource,
      startPosition: request.startPosition,
      preferBuiltInProxy: request.preferBuiltInProxy,
      ownerKey: request.ownerKey,
      scopeKey: request.scopeKey,
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
    String? ownerKey,
    String? scopeKey,
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
      httpProxyUrl: normalizedProxy,
      ownerKey: normalizedOwner,
      scopeKey: normalizedScope,
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
}
