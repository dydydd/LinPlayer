import 'package:flutter/foundation.dart';
import 'package:lin_player_prefs/lin_player_prefs.dart';
import 'package:lin_player_server_adapters/lin_player_server_adapters.dart';

enum PlaybackSourcePlayerCoreKind {
  mpv,
  vlc,
  avplayer,
  exo,
}

PlaybackSourcePlayerCoreKind playbackSourcePlayerCoreKindForPlayerCore(
  PlayerCore core,
) {
  return switch (core) {
    PlayerCore.vlc => PlaybackSourcePlayerCoreKind.vlc,
    PlayerCore.avplayer => PlaybackSourcePlayerCoreKind.avplayer,
    PlayerCore.exo => PlaybackSourcePlayerCoreKind.exo,
    PlayerCore.mpv => PlaybackSourcePlayerCoreKind.mpv,
  };
}

PlaybackInfoProfileKind playbackInfoProfileKindForPlaybackSourceCore(
  PlaybackSourcePlayerCoreKind core,
) {
  return switch (core) {
    PlaybackSourcePlayerCoreKind.vlc => PlaybackInfoProfileKind.vlc,
    PlaybackSourcePlayerCoreKind.avplayer => PlaybackInfoProfileKind.avplayer,
    PlaybackSourcePlayerCoreKind.exo => PlaybackInfoProfileKind.exo,
    PlaybackSourcePlayerCoreKind.mpv => PlaybackInfoProfileKind.defaultProfile,
  };
}

String? playbackPipelineForPlaybackSourceCore(
  PlaybackSourcePlayerCoreKind core,
) {
  return switch (core) {
    PlaybackSourcePlayerCoreKind.avplayer => 'avplayer',
    PlaybackSourcePlayerCoreKind.exo ||
    PlaybackSourcePlayerCoreKind.mpv ||
    PlaybackSourcePlayerCoreKind.vlc =>
      null,
  };
}

PlaybackInfoProfileKind playbackInfoProfileKindForPlayerCore(PlayerCore core) {
  return playbackInfoProfileKindForPlaybackSourceCore(
    playbackSourcePlayerCoreKindForPlayerCore(core),
  );
}

bool playbackSourceCoreUsesLoopbackPlaybackPackaging(
  PlaybackSourcePlayerCoreKind core,
) {
  return core != PlaybackSourcePlayerCoreKind.vlc;
}

enum ResolvedPlaybackMediaType {
  unknown,
  file,
  hls,
  dash,
}

@immutable
class PlaybackSourceBuildRequest {
  const PlaybackSourceBuildRequest({
    required this.adapter,
    required this.auth,
    required this.itemId,
    required this.playerCore,
    this.startPosition = Duration.zero,
    this.selectedMediaSourceId,
    this.preferredMediaSourceIndex,
    this.audioStreamIndex,
    this.subtitleStreamIndex,
    this.preferredVideoVersion = VideoVersionPreference.defaultVersion,
    this.resolveExternalSource = true,
    this.seriesId,
    this.serverId,
    bool? allowTranscoding,
  }) : allowTranscoding = allowTranscoding ?? false;

  final MediaServerAdapter adapter;
  final ServerAuthSession auth;
  final String itemId;
  final PlaybackSourcePlayerCoreKind playerCore;
  final Duration startPosition;
  final String? selectedMediaSourceId;
  final int? preferredMediaSourceIndex;
  final int? audioStreamIndex;
  final int? subtitleStreamIndex;
  final VideoVersionPreference preferredVideoVersion;
  final bool resolveExternalSource;
  final String? seriesId;
  final String? serverId;
  final bool allowTranscoding;
}

@immutable
class ResolvedPlaybackSource {
  const ResolvedPlaybackSource({
    required this.itemId,
    required this.playSessionId,
    required this.mediaSourceId,
    required this.url,
    required this.httpHeaders,
    required this.isExternal,
    required this.mediaTypeHint,
    required this.fromStrm,
    required this.redirectChain,
    this.contentTypeHint,
    this.supportsByteRange,
    this.httpStatusHint,
    this.bitrate,
    this.sizeBytes,
    this.sourcePath,
    this.proxyUrl,
    this.playbackPipeline,
  });

  final String itemId;
  final String playSessionId;
  final String mediaSourceId;
  final String url;
  final Map<String, String> httpHeaders;
  final bool isExternal;
  final ResolvedPlaybackMediaType mediaTypeHint;
  final bool fromStrm;
  final List<String> redirectChain;
  final String? contentTypeHint;
  final bool? supportsByteRange;
  final int? httpStatusHint;
  final int? bitrate;
  final int? sizeBytes;
  final String? sourcePath;
  final String? proxyUrl;
  final String? playbackPipeline;

  bool get isHls => mediaTypeHint == ResolvedPlaybackMediaType.hls;

  ResolvedPlaybackSource copyWith({
    String? itemId,
    String? playSessionId,
    String? mediaSourceId,
    String? url,
    Map<String, String>? httpHeaders,
    bool? isExternal,
    ResolvedPlaybackMediaType? mediaTypeHint,
    bool? fromStrm,
    List<String>? redirectChain,
    Object? contentTypeHint = _unset,
    Object? supportsByteRange = _unset,
    Object? httpStatusHint = _unset,
    Object? bitrate = _unset,
    Object? sizeBytes = _unset,
    Object? sourcePath = _unset,
    Object? proxyUrl = _unset,
    Object? playbackPipeline = _unset,
  }) {
    return ResolvedPlaybackSource(
      itemId: itemId ?? this.itemId,
      playSessionId: playSessionId ?? this.playSessionId,
      mediaSourceId: mediaSourceId ?? this.mediaSourceId,
      url: url ?? this.url,
      httpHeaders: httpHeaders ?? this.httpHeaders,
      isExternal: isExternal ?? this.isExternal,
      mediaTypeHint: mediaTypeHint ?? this.mediaTypeHint,
      fromStrm: fromStrm ?? this.fromStrm,
      redirectChain: redirectChain ?? this.redirectChain,
      contentTypeHint: identical(contentTypeHint, _unset)
          ? this.contentTypeHint
          : contentTypeHint as String?,
      supportsByteRange: identical(supportsByteRange, _unset)
          ? this.supportsByteRange
          : supportsByteRange as bool?,
      httpStatusHint: identical(httpStatusHint, _unset)
          ? this.httpStatusHint
          : httpStatusHint as int?,
      bitrate: identical(bitrate, _unset) ? this.bitrate : bitrate as int?,
      sizeBytes:
          identical(sizeBytes, _unset) ? this.sizeBytes : sizeBytes as int?,
      sourcePath: identical(sourcePath, _unset)
          ? this.sourcePath
          : sourcePath as String?,
      proxyUrl:
          identical(proxyUrl, _unset) ? this.proxyUrl : proxyUrl as String?,
      playbackPipeline: identical(playbackPipeline, _unset)
          ? this.playbackPipeline
          : playbackPipeline as String?,
    );
  }
}

const Object _unset = Object();

@immutable
class PlaybackSourceBuildResult {
  PlaybackSourceBuildResult({
    required this.playbackInfo,
    required List<Map<String, dynamic>> mediaSources,
    required Map<String, dynamic>? selectedMediaSource,
    required this.selectedMediaSourceId,
    required this.resolvedSource,
  })  : mediaSources = List<Map<String, dynamic>>.unmodifiable(
          mediaSources
              .map((entry) => Map<String, dynamic>.unmodifiable(entry))
              .toList(growable: false),
        ),
        selectedMediaSource = selectedMediaSource == null
            ? null
            : Map<String, dynamic>.unmodifiable(selectedMediaSource);

  final PlaybackInfoResult playbackInfo;
  final List<Map<String, dynamic>> mediaSources;
  final Map<String, dynamic>? selectedMediaSource;
  final String? selectedMediaSourceId;
  final ResolvedPlaybackSource resolvedSource;
}
