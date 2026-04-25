import 'package:flutter/material.dart';
import 'package:lin_player_prefs/lin_player_prefs.dart';
import 'package:lin_player_state/lin_player_state.dart';

import '../../play_network_page.dart';
import '../../play_network_page_native.dart';
import '../../play_network_page_vlc.dart';
import '../../player_screen.dart';
import '../../player_screen_native.dart';
import '../../player_screen_vlc.dart';
import '../preload/playback_preload_coordinator.dart';

Widget buildLocalPlayerScreen({
  required AppState appState,
  bool startFullScreen = false,
}) {
  switch (normalizePlayerCoreForPlatform(appState.playerCore)) {
    case PlayerCore.avplayer:
    case PlayerCore.exo:
      return NativePlayerScreen(
        appState: appState,
        startFullScreen: startFullScreen,
      );
    case PlayerCore.vlc:
      return VlcPlayerScreen(
        appState: appState,
        startFullScreen: startFullScreen,
      );
    case PlayerCore.mpv:
      return PlayerScreen(
        appState: appState,
        startFullScreen: startFullScreen,
      );
  }
}

Widget buildNetworkPlayerPage({
  required String title,
  required String itemId,
  required AppState appState,
  ServerProfile? server,
  bool isTv = false,
  String? seriesId,
  Duration? startPosition,
  bool resumeImmediately = true,
  String? mediaSourceId,
  int? audioStreamIndex,
  int? subtitleStreamIndex,
  PreparedPlaybackPreload? preparedPreload,
}) {
  switch (normalizePlayerCoreForPlatform(appState.playerCore)) {
    case PlayerCore.avplayer:
    case PlayerCore.exo:
      return NativePlayNetworkPage(
        title: title,
        itemId: itemId,
        appState: appState,
        server: server,
        isTv: isTv,
        seriesId: seriesId,
        startPosition: startPosition,
        resumeImmediately: resumeImmediately,
        mediaSourceId: mediaSourceId,
        audioStreamIndex: audioStreamIndex,
        subtitleStreamIndex: subtitleStreamIndex,
        preparedPreload: preparedPreload,
      );
    case PlayerCore.vlc:
      return VlcPlayNetworkPage(
        title: title,
        itemId: itemId,
        appState: appState,
        server: server,
        isTv: isTv,
        seriesId: seriesId,
        startPosition: startPosition,
        resumeImmediately: resumeImmediately,
        mediaSourceId: mediaSourceId,
        audioStreamIndex: audioStreamIndex,
        subtitleStreamIndex: subtitleStreamIndex,
        preparedPreload: preparedPreload,
      );
    case PlayerCore.mpv:
      return PlayNetworkPage(
        title: title,
        itemId: itemId,
        appState: appState,
        server: server,
        isTv: isTv,
        seriesId: seriesId,
        startPosition: startPosition,
        resumeImmediately: resumeImmediately,
        mediaSourceId: mediaSourceId,
        audioStreamIndex: audioStreamIndex,
        subtitleStreamIndex: subtitleStreamIndex,
        preparedPreload: preparedPreload,
      );
  }
}
