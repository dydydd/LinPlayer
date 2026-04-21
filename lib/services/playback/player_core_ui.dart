import 'package:flutter/material.dart';
import 'package:lin_player_prefs/lin_player_prefs.dart';

String playerCoreOverlayLabel(PlayerCore core) {
  return '内核 ${core.label}';
}

IconData playerCoreIcon(PlayerCore core) {
  switch (core) {
    case PlayerCore.avplayer:
      return Icons.phone_iphone_rounded;
    case PlayerCore.mpv:
      return Icons.movie_outlined;
    case PlayerCore.vlc:
      return Icons.play_circle_outline_rounded;
    case PlayerCore.exo:
      return Icons.flash_on_outlined;
  }
}

String playerCorePanelSubtitle(
  PlayerCore core, {
  required bool active,
  required bool localPlayback,
}) {
  final prefix = active ? '当前使用' : '切换到';
  final scene = localPlayback ? '本地播放' : '播放内核';
  switch (core) {
    case PlayerCore.avplayer:
      return '$prefix iOS AVPlayer $scene';
    case PlayerCore.mpv:
      return '$prefix media_kit / MPV $scene';
    case PlayerCore.vlc:
      return '$prefix VLC $scene';
    case PlayerCore.exo:
      return '$prefix Android Exo $scene';
  }
}
