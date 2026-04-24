import 'package:flutter_test/flutter_test.dart';

import 'package:lin_player/services/playback/vlc_video_player_adapter.dart';

void main() {
  group('VLC video player adapter', () {
    test('maps HTTP headers into VLC options', () {
      final options = buildVlcPlayerOptionsFromHttpHeaders(
        <String, String>{
          'User-Agent': 'LinPlayer/1.0',
          'Referer': 'https://ref.example/',
          'Cookie': 'sid=abc; theme=dark',
        },
      );

      expect(options, isNotNull);
      expect(
        options!.get(),
        containsAll(<String>[
          ':http-user-agent=LinPlayer/1.0',
          '--http-referrer=https://ref.example/',
          '--http-forward-cookies',
          ':http-cookie=sid=abc; theme=dark',
        ]),
      );
    });

    test('injects api key from token header case-insensitively', () {
      final controller = VideoPlayerController.networkUrl(
        Uri.parse('https://media.example/items/1/master.m3u8'),
        httpHeaders: <String, String>{
          'x-emby-token': 'secret-token',
        },
      );

      expect(
        controller.debugSource,
        'https://media.example/items/1/master.m3u8?api_key=secret-token',
      );
    });

    test('keeps existing api_key query untouched', () {
      final controller = VideoPlayerController.networkUrl(
        Uri.parse(
          'https://media.example/items/1/master.m3u8?api_key=existing-token',
        ),
        httpHeaders: <String, String>{
          'X-Emby-Token': 'new-token',
        },
      );

      expect(
        controller.debugSource,
        'https://media.example/items/1/master.m3u8?api_key=existing-token',
      );
    });
  });
}
