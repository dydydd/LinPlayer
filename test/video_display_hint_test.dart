import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lin_player/services/playback/video_display_hint.dart';

void main() {
  group('playbackDisplayAspectForMediaSource', () {
    test('uses explicit aspect ratio strings', () {
      final mediaSource = <String, dynamic>{
        'MediaStreams': <Map<String, dynamic>>[
          <String, dynamic>{
            'Type': 'Video',
            'AspectRatio': '9:16',
          },
        ],
      };

      expect(
        playbackDisplayAspectForMediaSource(mediaSource),
        closeTo(9 / 16, 0.0001),
      );
      expect(
        playbackOrientationsForMediaSource(mediaSource),
        const <DeviceOrientation>[DeviceOrientation.portraitUp],
      );
    });

    test('falls back to stream dimensions', () {
      final mediaSource = <String, dynamic>{
        'MediaStreams': <Map<String, dynamic>>[
          <String, dynamic>{
            'Type': 'Video',
            'Width': 1920,
            'Height': 1080,
          },
        ],
      };

      expect(
        playbackDisplayAspectForMediaSource(mediaSource),
        closeTo(16 / 9, 0.0001),
      );
      expect(
        playbackOrientationsForMediaSource(mediaSource),
        const <DeviceOrientation>[
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ],
      );
    });

    test('applies rotation metadata to inferred aspect', () {
      final mediaSource = <String, dynamic>{
        'MediaStreams': <Map<String, dynamic>>[
          <String, dynamic>{
            'Type': 'Video',
            'Width': 1920,
            'Height': 1080,
            'Rotation': 90,
          },
        ],
      };

      expect(
        playbackDisplayAspectForMediaSource(mediaSource),
        closeTo(9 / 16, 0.0001),
      );
      expect(
        playbackOrientationsForMediaSource(mediaSource),
        const <DeviceOrientation>[DeviceOrientation.portraitUp],
      );
    });
  });
}
