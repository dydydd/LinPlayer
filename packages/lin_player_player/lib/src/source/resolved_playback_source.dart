import 'package:flutter/foundation.dart';
import 'package:lin_player_prefs/lin_player_prefs.dart';
import 'package:lin_player_server_adapters/lin_player_server_adapters.dart';

enum PlaybackSourcePlayerCoreKind {
  mpv,
  exo,
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
    this.selectedMediaSourceId,
    this.preferredMediaSourceIndex,
    this.audioStreamIndex,
    this.subtitleStreamIndex,
    this.preferredVideoVersion = VideoVersionPreference.defaultVersion,
    this.resolveExternalSource = true,
  });

  final MediaServerAdapter adapter;
  final ServerAuthSession auth;
  final String itemId;
  final PlaybackSourcePlayerCoreKind playerCore;
  final String? selectedMediaSourceId;
  final int? preferredMediaSourceIndex;
  final int? audioStreamIndex;
  final int? subtitleStreamIndex;
  final VideoVersionPreference preferredVideoVersion;
  final bool resolveExternalSource;
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

  bool get isHls => mediaTypeHint == ResolvedPlaybackMediaType.hls;
}

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
