import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lin_player_prefs/lin_player_prefs.dart';

void main() {
  group('player core platform rules', () {
    test('iOS keeps MPV only', () {
      expect(
        playerCoresForPlatform(platform: TargetPlatform.iOS, isWeb: false),
        const <PlayerCore>[PlayerCore.mpv],
      );
      expect(
        defaultPlayerCoreForPlatform(
          platform: TargetPlatform.iOS,
          isWeb: false,
        ),
        PlayerCore.mpv,
      );
    });

    test('iOS normalizes removed native cores back to MPV', () {
      expect(
        normalizePlayerCoreForPlatform(
          PlayerCore.exo,
          platform: TargetPlatform.iOS,
          isWeb: false,
        ),
        PlayerCore.mpv,
      );
      expect(
        normalizePlayerCoreForPlatform(
          PlayerCore.avplayer,
          platform: TargetPlatform.iOS,
          isWeb: false,
        ),
        PlayerCore.mpv,
      );
      expect(
        normalizePlayerCoreForPlatform(
          PlayerCore.vlc,
          platform: TargetPlatform.iOS,
          isWeb: false,
        ),
        PlayerCore.mpv,
      );
    });

    test('Android keeps MPV and EXO only', () {
      expect(
        playerCoresForPlatform(platform: TargetPlatform.android, isWeb: false),
        const <PlayerCore>[PlayerCore.mpv, PlayerCore.exo],
      );
      expect(
        playerCoreIsSupportedOnPlatform(
          PlayerCore.vlc,
          platform: TargetPlatform.android,
          isWeb: false,
        ),
        isFalse,
      );
    });

    test('web falls back to MPV only', () {
      expect(
        playerCoresForPlatform(platform: TargetPlatform.iOS, isWeb: true),
        const <PlayerCore>[PlayerCore.mpv],
      );
      expect(
        normalizePlayerCoreForPlatform(
          PlayerCore.avplayer,
          platform: TargetPlatform.iOS,
          isWeb: true,
        ),
        PlayerCore.mpv,
      );
    });
  });
}
