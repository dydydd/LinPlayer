import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lin_player_prefs/lin_player_prefs.dart';

void main() {
  group('player core platform rules', () {
    test('iOS defaults to AVPlayer and exposes AVPlayer, MPV, VLC', () {
      expect(
        playerCoresForPlatform(platform: TargetPlatform.iOS, isWeb: false),
        const <PlayerCore>[
          PlayerCore.avplayer,
          PlayerCore.mpv,
          PlayerCore.vlc,
        ],
      );
      expect(
        defaultPlayerCoreForPlatform(
          platform: TargetPlatform.iOS,
          isWeb: false,
        ),
        PlayerCore.avplayer,
      );
    });

    test('iOS normalizes unsupported EXO back to AVPlayer', () {
      expect(
        normalizePlayerCoreForPlatform(
          PlayerCore.exo,
          platform: TargetPlatform.iOS,
          isWeb: false,
        ),
        PlayerCore.avplayer,
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
