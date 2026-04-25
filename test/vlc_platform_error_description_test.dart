import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_vlc_player/src/vlc_player_controller.dart';

void main() {
  group('describeVlcPlatformError', () {
    test('prefers platform exception message and key diagnostics', () {
      final error = PlatformException(
        code: 'vlc_startup_black_screen',
        message: 'iOS VLC started but did not produce video output.',
        details: <String, Object?>{
          'reason': 'native-rebind',
          'state': 'playing',
          'positionMs': 1200,
          'durationMs': 42000,
          'videoWidth': 0,
          'videoHeight': 0,
          'viewReady': true,
          'drawableBound': true,
        },
      );

      expect(
        describeVlcPlatformError(error),
        'iOS VLC started but did not produce video output. | '
        'reason=native-rebind, state=playing, positionMs=1200, '
        'durationMs=42000, videoWidth=0, videoHeight=0, '
        'viewReady=true, drawableBound=true',
      );
    });

    test('falls back to exception code when message is empty', () {
      final error = PlatformException(
        code: 'vlc_state_error',
        message: '',
        details: const <String, Object?>{'state': 'error'},
      );

      expect(
        describeVlcPlatformError(error),
        'vlc_state_error | state=error',
      );
    });
  });
}
