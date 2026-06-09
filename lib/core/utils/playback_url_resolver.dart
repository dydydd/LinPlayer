import '../api/api_interfaces.dart';

class PlaybackUrlRequest {
  final String itemId;
  final String? mediaSourceId;
  final String? container;
  final String? playSessionId;
  final bool staticStream;
  final bool allowDirectPlay;
  final bool allowDirectStream;
  final bool allowTranscoding;
  final bool enableAutoStreamCopy;
  final bool enableAutoStreamCopyAudio;
  final bool enableAutoStreamCopyVideo;

  const PlaybackUrlRequest({
    required this.itemId,
    this.mediaSourceId,
    this.container,
    this.playSessionId,
    this.staticStream = true,
    this.allowDirectPlay = true,
    this.allowDirectStream = true,
    this.allowTranscoding = false,
    this.enableAutoStreamCopy = true,
    this.enableAutoStreamCopyAudio = true,
    this.enableAutoStreamCopyVideo = true,
  });

  PlaybackUrlRequest copyWith({
    String? itemId,
    String? mediaSourceId,
    String? container,
    String? playSessionId,
    bool? staticStream,
    bool? allowDirectPlay,
    bool? allowDirectStream,
    bool? allowTranscoding,
    bool? enableAutoStreamCopy,
    bool? enableAutoStreamCopyAudio,
    bool? enableAutoStreamCopyVideo,
  }) {
    return PlaybackUrlRequest(
      itemId: itemId ?? this.itemId,
      mediaSourceId: mediaSourceId ?? this.mediaSourceId,
      container: container ?? this.container,
      playSessionId: playSessionId ?? this.playSessionId,
      staticStream: staticStream ?? this.staticStream,
      allowDirectPlay: allowDirectPlay ?? this.allowDirectPlay,
      allowDirectStream: allowDirectStream ?? this.allowDirectStream,
      allowTranscoding: allowTranscoding ?? this.allowTranscoding,
      enableAutoStreamCopy: enableAutoStreamCopy ?? this.enableAutoStreamCopy,
      enableAutoStreamCopyAudio:
          enableAutoStreamCopyAudio ?? this.enableAutoStreamCopyAudio,
      enableAutoStreamCopyVideo:
          enableAutoStreamCopyVideo ?? this.enableAutoStreamCopyVideo,
    );
  }
}

class PlaybackSelection {
  final MediaSource? mediaSource;
  final PlaybackUrlRequest primaryRequest;
  final PlaybackUrlRequest? fallbackRequest;
  final bool startsWithSoftwareDecoding;
  final String? fallbackReason;

  const PlaybackSelection({
    required this.mediaSource,
    required this.primaryRequest,
    this.fallbackRequest,
    this.startsWithSoftwareDecoding = false,
    this.fallbackReason,
  });
}

MediaSource? resolvePreferredMediaSource(
  PlaybackInfo playbackInfo, {
  String? preferredMediaSourceId,
}) {
  final mediaSources = playbackInfo.mediaSources;
  if (mediaSources.isEmpty) {
    return null;
  }
  if (preferredMediaSourceId == null || preferredMediaSourceId.isEmpty) {
    return mediaSources.firstOrNull;
  }
  return mediaSources
          .where((source) => source.id == preferredMediaSourceId)
          .firstOrNull ??
      mediaSources.firstOrNull;
}

PlaybackSelection buildPlaybackSelection({
  required PlaybackInfo playbackInfo,
  required String itemId,
  String? preferredMediaSourceId,
  String? playSessionId,
}) {
  final mediaSource = resolvePreferredMediaSource(
    playbackInfo,
    preferredMediaSourceId: preferredMediaSourceId,
  );
  final normalizedContainer = _preferredContainer(mediaSource);
  final primaryRequest = PlaybackUrlRequest(
    itemId: itemId,
    mediaSourceId: mediaSource?.id,
    container: normalizedContainer,
    playSessionId: playSessionId,
  );

  final audioStreams = mediaSource?.mediaStreams.where((s) => s.isAudio).toList() ??
      const <MediaStream>[];
  final riskyAudioTrack = _selectRiskiestAudio(audioStreams);
  final riskyCodec = riskyAudioTrack?.codec?.toLowerCase();

  if (riskyCodec == null) {
    return PlaybackSelection(mediaSource: mediaSource, primaryRequest: primaryRequest);
  }

  if (_needsTranscodeFallback(riskyCodec)) {
    return PlaybackSelection(
      mediaSource: mediaSource,
      primaryRequest: primaryRequest.copyWith(
        allowDirectPlay: false,
        allowDirectStream: false,
        allowTranscoding: true,
        enableAutoStreamCopy: false,
        enableAutoStreamCopyAudio: false,
      ),
      fallbackRequest: primaryRequest.copyWith(
        allowDirectPlay: false,
        allowDirectStream: false,
        allowTranscoding: true,
        enableAutoStreamCopy: false,
        enableAutoStreamCopyAudio: false,
        enableAutoStreamCopyVideo: false,
      ),
      startsWithSoftwareDecoding: true,
      fallbackReason: '检测到高风险音频编码 ${riskyCodec.toUpperCase()}，优先请求服务器转码以避免解码失败。',
    );
  }

  if (_shouldDisableHardwareDecoding(riskyCodec)) {
    return PlaybackSelection(
      mediaSource: mediaSource,
      primaryRequest: primaryRequest,
      fallbackRequest: primaryRequest.copyWith(
        allowDirectPlay: false,
        allowDirectStream: false,
        allowTranscoding: true,
        enableAutoStreamCopy: false,
        enableAutoStreamCopyAudio: false,
      ),
      startsWithSoftwareDecoding: true,
      fallbackReason: '检测到兼容性较差的音频编码 ${riskyCodec.toUpperCase()}，先关闭硬件解码并准备转码兜底。',
    );
  }

  return PlaybackSelection(
    mediaSource: mediaSource,
    primaryRequest: primaryRequest,
    fallbackRequest: primaryRequest.copyWith(
      allowDirectPlay: false,
      allowDirectStream: false,
      allowTranscoding: true,
      enableAutoStreamCopy: false,
      enableAutoStreamCopyAudio: false,
    ),
  );
}

String _preferredContainer(MediaSource? mediaSource) {
  final container = mediaSource?.container?.trim().toLowerCase();
  if (container != null && container.isNotEmpty) {
    return container;
  }
  final videoStream =
      mediaSource?.mediaStreams.where((stream) => stream.isVideo).firstOrNull;
  final codec = videoStream?.codec?.trim().toLowerCase();
  if (codec == 'hevc' || codec == 'h265') {
    return 'mkv';
  }
  return 'mp4';
}

MediaStream? _selectRiskiestAudio(List<MediaStream> audioStreams) {
  MediaStream? risky;
  for (final stream in audioStreams) {
    final codec = stream.codec?.toLowerCase() ?? '';
    if (_needsTranscodeFallback(codec)) {
      return stream;
    }
    if (_shouldDisableHardwareDecoding(codec)) {
      risky ??= stream;
    }
  }
  return risky;
}

bool _needsTranscodeFallback(String codec) {
  return codec.contains('truehd') ||
      codec.contains('mlp') ||
      codec.contains('dts-hd') ||
      codec.contains('dtshd');
}

bool _shouldDisableHardwareDecoding(String codec) {
  return codec.contains('dts') ||
      codec.contains('eac3') ||
      codec.contains('flac');
}
