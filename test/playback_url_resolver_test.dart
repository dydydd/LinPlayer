import 'package:flutter_test/flutter_test.dart';
import 'package:linplayer_mobile/core/api/api_interfaces.dart';
import 'package:linplayer_mobile/core/utils/playback_url_resolver.dart';

void main() {
  group('buildPlaybackSelection', () {
    test('keeps a single direct-play request for desktop playback', () {
      final playbackInfo = PlaybackInfo(
        itemId: 'item-1',
        mediaSources: [
          MediaSource(
            id: 'source-1',
            container: 'mkv',
            mediaStreams: [
              MediaStream(
                index: 0,
                type: 'Video',
                codec: 'hevc',
              ),
            ],
          ),
        ],
      );

      final selection = buildPlaybackSelection(
        playbackInfo: playbackInfo,
        itemId: 'item-1',
        playSessionId: 'session-1',
      );

      expect(selection.mediaSource?.id, 'source-1');
      expect(selection.primaryRequest.mediaSourceId, 'source-1');
      expect(selection.primaryRequest.container, 'mkv');
      expect(selection.primaryRequest.allowDirectPlay, isTrue);
      expect(selection.primaryRequest.allowDirectStream, isTrue);
      expect(selection.primaryRequest.allowTranscoding, isFalse);
      expect(selection.fallbackRequest, isNull);
      expect(selection.fallbackReason, isNull);
    });
  });
}
