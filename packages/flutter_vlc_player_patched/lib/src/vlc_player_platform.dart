import 'package:flutter_vlc_player/src/linplayer_method_channel_vlc_player.dart';
import 'package:flutter_vlc_player_platform_interface/flutter_vlc_player_platform_interface.dart';

VlcPlayerPlatform _installDefaultVlcPlayerPlatform() {
  final platform = LinPlayerMethodChannelVlcPlayer();
  VlcPlayerPlatform.instance = platform;
  return platform;
}

final VlcPlayerPlatform _defaultVlcPlayerPlatform =
    _installDefaultVlcPlayerPlatform();

VlcPlayerPlatform get vlcPlayerPlatform {
  final current = VlcPlayerPlatform.instance;
  if (identical(current, _defaultVlcPlayerPlatform)) {
    return _defaultVlcPlayerPlatform;
  }
  return current;
}
