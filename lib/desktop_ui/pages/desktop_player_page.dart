import 'package:flutter/material.dart';
import 'package:lin_player_state/lin_player_state.dart';

import '../../services/playback/player_core_pages.dart';
import '../theme/desktop_theme_scope.dart';

class DesktopPlayerPage extends StatelessWidget {
  const DesktopPlayerPage.local({
    super.key,
    required this.appState,
    this.startFullScreen = false,
  })  : title = null,
        itemId = null,
        server = null,
        isLocal = true,
        seriesId = null,
        startPosition = null,
        resumeImmediately = true,
        mediaSourceId = null,
        audioStreamIndex = null,
        subtitleStreamIndex = null;

  const DesktopPlayerPage.network({
    super.key,
    required this.title,
    required this.itemId,
    required this.appState,
    this.server,
    this.startFullScreen = false,
    this.seriesId,
    this.startPosition,
    this.resumeImmediately = true,
    this.mediaSourceId,
    this.audioStreamIndex,
    this.subtitleStreamIndex,
  }) : isLocal = false;

  final AppState appState;
  final bool startFullScreen;
  final bool isLocal;
  final String? title;
  final String? itemId;
  final ServerProfile? server;
  final String? seriesId;
  final Duration? startPosition;
  final bool resumeImmediately;
  final String? mediaSourceId;
  final int? audioStreamIndex;
  final int? subtitleStreamIndex;

  @override
  Widget build(BuildContext context) {
    final child = isLocal
        ? buildLocalPlayerScreen(
            appState: appState,
            startFullScreen: startFullScreen,
          )
        : buildNetworkPlayerPage(
            title: title ?? '',
            itemId: itemId ?? '',
            appState: appState,
            server: server,
            seriesId: seriesId,
            startPosition: startPosition,
            resumeImmediately: resumeImmediately,
            mediaSourceId: mediaSourceId,
            audioStreamIndex: audioStreamIndex,
            subtitleStreamIndex: subtitleStreamIndex,
          );

    return DesktopThemeScope(child: child);
  }
}
