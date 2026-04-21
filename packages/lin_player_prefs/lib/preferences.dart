import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, immutable, kIsWeb;

enum TvBackgroundMode {
  none,
  solidColor,
  image,
  randomApi,
}

TvBackgroundMode tvBackgroundModeFromId(String? id) {
  switch ((id ?? '').trim().toLowerCase()) {
    case 'solid':
      return TvBackgroundMode.solidColor;
    case 'image':
      return TvBackgroundMode.image;
    case 'random':
      return TvBackgroundMode.randomApi;
    default:
      return TvBackgroundMode.none;
  }
}

extension TvBackgroundModeX on TvBackgroundMode {
  String get id {
    switch (this) {
      case TvBackgroundMode.none:
        return 'none';
      case TvBackgroundMode.solidColor:
        return 'solid';
      case TvBackgroundMode.image:
        return 'image';
      case TvBackgroundMode.randomApi:
        return 'random';
    }
  }

  String get label {
    switch (this) {
      case TvBackgroundMode.none:
        return '\u65e0';
      case TvBackgroundMode.solidColor:
        return '\u7eaf\u8272';
      case TvBackgroundMode.image:
        return '\u56fe\u7247';
      case TvBackgroundMode.randomApi:
        return '\u968f\u673a API';
    }
  }
}

enum VideoVersionPreference {
  defaultVersion,
  highestResolution,
  lowestBitrate,
  preferHevc,
  preferAvc,
}

enum PlayerCore {
  avplayer,
  mpv,
  vlc,
  exo,
}

enum PlaybackBufferPreset {
  seekFast,
  balanced,
  stable,
  custom,
}

enum PlaybackProxyMode {
  system,
  custom,
}

PlayerCore playerCoreFromId(String? id) {
  switch ((id ?? '').trim().toLowerCase()) {
    case 'avplayer':
      return PlayerCore.avplayer;
    case 'vlc':
      return PlayerCore.vlc;
    case 'exo':
      return PlayerCore.exo;
    case 'mpv':
    default:
      return PlayerCore.mpv;
  }
}

bool playerCoreUsesNativeVideoPlayer(PlayerCore core) {
  return core == PlayerCore.exo || core == PlayerCore.avplayer;
}

bool playerCoreIsSupportedOnPlatform(
  PlayerCore core, {
  TargetPlatform? platform,
  bool? isWeb,
}) {
  final resolvedIsWeb = isWeb ?? kIsWeb;
  if (resolvedIsWeb) {
    return core == PlayerCore.mpv;
  }

  switch (platform ?? defaultTargetPlatform) {
    case TargetPlatform.android:
      return core == PlayerCore.mpv || core == PlayerCore.exo;
    case TargetPlatform.iOS:
      return core == PlayerCore.avplayer ||
          core == PlayerCore.mpv ||
          core == PlayerCore.vlc;
    case TargetPlatform.macOS:
    case TargetPlatform.windows:
    case TargetPlatform.linux:
    case TargetPlatform.fuchsia:
      return core == PlayerCore.mpv;
  }
}

List<PlayerCore> playerCoresForPlatform({
  TargetPlatform? platform,
  bool? isWeb,
}) {
  final resolvedIsWeb = isWeb ?? kIsWeb;
  if (resolvedIsWeb) {
    return const <PlayerCore>[PlayerCore.mpv];
  }

  switch (platform ?? defaultTargetPlatform) {
    case TargetPlatform.android:
      return const <PlayerCore>[PlayerCore.mpv, PlayerCore.exo];
    case TargetPlatform.iOS:
      return const <PlayerCore>[
        PlayerCore.avplayer,
        PlayerCore.mpv,
        PlayerCore.vlc,
      ];
    case TargetPlatform.macOS:
    case TargetPlatform.windows:
    case TargetPlatform.linux:
    case TargetPlatform.fuchsia:
      return const <PlayerCore>[PlayerCore.mpv];
  }
}

PlayerCore defaultPlayerCoreForPlatform({
  TargetPlatform? platform,
  bool? isWeb,
}) {
  return playerCoresForPlatform(platform: platform, isWeb: isWeb).first;
}

PlayerCore normalizePlayerCoreForPlatform(
  PlayerCore core, {
  TargetPlatform? platform,
  bool? isWeb,
}) {
  if (playerCoreIsSupportedOnPlatform(core, platform: platform, isWeb: isWeb)) {
    return core;
  }
  return defaultPlayerCoreForPlatform(platform: platform, isWeb: isWeb);
}

PlaybackProxyMode playbackProxyModeFromId(String? id) {
  switch ((id ?? '').trim()) {
    case 'custom':
      return PlaybackProxyMode.custom;
    case 'system':
    default:
      return PlaybackProxyMode.system;
  }
}

PlaybackBufferPreset playbackBufferPresetFromId(String? id) {
  switch ((id ?? '').trim()) {
    case 'seekFast':
      return PlaybackBufferPreset.seekFast;
    case 'balanced':
      return PlaybackBufferPreset.balanced;
    case 'stable':
      return PlaybackBufferPreset.stable;
    case 'custom':
      return PlaybackBufferPreset.custom;
    default:
      return PlaybackBufferPreset.seekFast;
  }
}

extension PlayerCoreX on PlayerCore {
  String get id {
    switch (this) {
      case PlayerCore.avplayer:
        return 'avplayer';
      case PlayerCore.mpv:
        return 'mpv';
      case PlayerCore.vlc:
        return 'vlc';
      case PlayerCore.exo:
        return 'exo';
    }
  }

  String get label {
    switch (this) {
      case PlayerCore.avplayer:
        return 'AVPlayer';
      case PlayerCore.mpv:
        return 'MPV';
      case PlayerCore.vlc:
        return 'VLC';
      case PlayerCore.exo:
        return 'Exo';
    }
  }
}

extension PlaybackBufferPresetX on PlaybackBufferPreset {
  String get id {
    switch (this) {
      case PlaybackBufferPreset.seekFast:
        return 'seekFast';
      case PlaybackBufferPreset.balanced:
        return 'balanced';
      case PlaybackBufferPreset.stable:
        return 'stable';
      case PlaybackBufferPreset.custom:
        return 'custom';
    }
  }

  String get label {
    switch (this) {
      case PlaybackBufferPreset.seekFast:
        return '\u62d6\u52a8\u79d2\u5f00';
      case PlaybackBufferPreset.balanced:
        return '\u5747\u8861';
      case PlaybackBufferPreset.stable:
        return '\u7a33\u5b9a\u4f18\u5148';
      case PlaybackBufferPreset.custom:
        return '\u81ea\u5b9a\u4e49';
    }
  }

  double? get suggestedBackRatio {
    switch (this) {
      case PlaybackBufferPreset.seekFast:
        return 0.05;
      case PlaybackBufferPreset.balanced:
        return 0.15;
      case PlaybackBufferPreset.stable:
        return 0.25;
      case PlaybackBufferPreset.custom:
        return null;
    }
  }
}

extension PlaybackProxyModeX on PlaybackProxyMode {
  String get id {
    switch (this) {
      case PlaybackProxyMode.system:
        return 'system';
      case PlaybackProxyMode.custom:
        return 'custom';
    }
  }

  String get label {
    switch (this) {
      case PlaybackProxyMode.system:
        return '\u7cfb\u7edf\u4ee3\u7406';
      case PlaybackProxyMode.custom:
        return '\u81ea\u5b9a\u4e49';
    }
  }
}

@immutable
class PlaybackBufferSplit {
  final int totalBytes;
  final int backBytes;
  final int forwardBytes;
  final double backRatio;

  const PlaybackBufferSplit._({
    required this.totalBytes,
    required this.backBytes,
    required this.forwardBytes,
    required this.backRatio,
  });

  static const int _mb = 1024 * 1024;

  int get totalMb => (totalBytes / _mb).round();
  int get backMb => (backBytes / _mb).round();
  int get forwardMb => (forwardBytes / _mb).round();

  static PlaybackBufferSplit from({
    required int totalMb,
    required double backRatio,
    double maxBackRatio = 0.30,
  }) {
    final tMb = totalMb.clamp(200, 2048);
    final r = backRatio.clamp(0.0, maxBackRatio).toDouble();
    final backMb = (tMb * r).round().clamp(0, tMb);
    final totalBytes = tMb * _mb;
    final backBytes = backMb * _mb;
    final forwardBytes = totalBytes - backBytes;
    return PlaybackBufferSplit._(
      totalBytes: totalBytes,
      backBytes: backBytes,
      forwardBytes: forwardBytes,
      backRatio: r,
    );
  }
}

enum ServerListLayout {
  grid,
  list,
}

ServerListLayout serverListLayoutFromId(String? id) {
  switch (id) {
    case 'list':
      return ServerListLayout.list;
    default:
      return ServerListLayout.grid;
  }
}

extension ServerListLayoutX on ServerListLayout {
  String get id {
    switch (this) {
      case ServerListLayout.grid:
        return 'grid';
      case ServerListLayout.list:
        return 'list';
    }
  }
}

VideoVersionPreference videoVersionPreferenceFromId(String? id) {
  switch (id) {
    case 'highestResolution':
      return VideoVersionPreference.highestResolution;
    case 'lowestBitrate':
      return VideoVersionPreference.lowestBitrate;
    case 'preferHevc':
      return VideoVersionPreference.preferHevc;
    case 'preferAvc':
      return VideoVersionPreference.preferAvc;
    default:
      return VideoVersionPreference.defaultVersion;
  }
}

extension VideoVersionPreferenceX on VideoVersionPreference {
  String get id {
    switch (this) {
      case VideoVersionPreference.defaultVersion:
        return 'default';
      case VideoVersionPreference.highestResolution:
        return 'highestResolution';
      case VideoVersionPreference.lowestBitrate:
        return 'lowestBitrate';
      case VideoVersionPreference.preferHevc:
        return 'preferHevc';
      case VideoVersionPreference.preferAvc:
        return 'preferAvc';
    }
  }

  String get label {
    switch (this) {
      case VideoVersionPreference.defaultVersion:
        return '\u9ed8\u8ba4';
      case VideoVersionPreference.highestResolution:
        return '\u6700\u9ad8\u5206\u8fa8\u7387';
      case VideoVersionPreference.lowestBitrate:
        return '\u6700\u4f4e\u7801\u7387';
      case VideoVersionPreference.preferHevc:
        return '\u4f18\u5148 HEVC';
      case VideoVersionPreference.preferAvc:
        return '\u4f18\u5148 AVC';
    }
  }
}
