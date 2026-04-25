import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:lin_player_server_api/services/emby_api.dart';

void main() {
  test('fetchPlaybackInfo uses AVPlayer device profile when requested',
      () async {
    Map<String, dynamic>? postedProfile;

    final client = MockClient((req) async {
      final url = req.url.toString();
      if (url == 'https://example.com/emby/Items/i1/PlaybackInfo') {
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        postedProfile = body['DeviceProfile'] as Map<String, dynamic>?;
        return http.Response(
          jsonEncode({
            'PlaySessionId': 's1',
            'MediaSources': [
              {'Id': 'ms1'}
            ],
          }),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }
      return http.Response('no', 500);
    });

    final api = EmbyApi(
      hostOrUrl: 'https://example.com',
      preferredScheme: 'https',
      client: client,
    );

    await api.fetchPlaybackInfo(
      token: 't1',
      baseUrl: 'https://example.com',
      userId: 'u1',
      deviceId: 'd1',
      itemId: 'i1',
      profile: PlaybackInfoProfileKind.avplayer,
    );

    expect(postedProfile, isNotNull);
    expect(postedProfile!['Name'], 'LinPlayer-AVPlayer');
    final transcode = postedProfile!['TranscodingProfiles'] as List?;
    expect(transcode, isNotNull);
    expect(transcode, isEmpty);

    final direct = postedProfile!['DirectPlayProfiles'] as List?;
    expect(direct, isNotNull);
    final video = direct!
        .cast<Map>()
        .firstWhere((e) => (e['Type'] as String?) == 'Video');
    expect((video['Container'] as String?)?.contains('mkv'), isTrue);
    expect((video['Container'] as String?)?.contains('mp4'), isTrue);
    expect(video.containsKey('VideoCodec'), isFalse);
  });

  test('fetchPlaybackInfo uses Exo device profile when requested', () async {
    Map<String, dynamic>? postedProfile;

    final client = MockClient((req) async {
      final url = req.url.toString();
      if (url ==
          'https://example.com/emby/Items/i1/PlaybackInfo?UserId=u1&DeviceId=d1') {
        return http.Response('no', 404);
      }
      if (url == 'https://example.com/emby/Items/i1/PlaybackInfo') {
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        postedProfile = body['DeviceProfile'] as Map<String, dynamic>?;
        return http.Response(
          jsonEncode({
            'PlaySessionId': 's1',
            'MediaSources': [
              {'Id': 'ms1'}
            ],
          }),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }
      return http.Response('no', 500);
    });

    final api = EmbyApi(
      hostOrUrl: 'https://example.com',
      preferredScheme: 'https',
      client: client,
    );

    await api.fetchPlaybackInfo(
      token: 't1',
      baseUrl: 'https://example.com',
      userId: 'u1',
      deviceId: 'd1',
      itemId: 'i1',
      profile: PlaybackInfoProfileKind.exo,
    );

    expect(postedProfile, isNotNull);
    expect(postedProfile!['Name'], 'LinPlayer-Exo');
    final transcode = postedProfile!['TranscodingProfiles'] as List?;
    expect(transcode, isNotNull);
    expect(transcode, isEmpty);

    final direct = postedProfile!['DirectPlayProfiles'] as List?;
    expect(direct, isNotNull);
    final video = direct!
        .cast<Map>()
        .firstWhere((e) => (e['Type'] as String?) == 'Video');
    expect((video['Container'] as String?)?.contains('mkv'), isTrue);
    expect(video.containsKey('AudioCodec'), isFalse);
  });

  test('fetchPlaybackInfo uses dedicated VLC device profile and POSTs first',
      () async {
    final methods = <String>[];
    Map<String, dynamic>? postedBody;
    Map<String, dynamic>? postedProfile;

    final client = MockClient((req) async {
      methods.add(req.method);
      final url = req.url.toString();
      if (url == 'https://example.com/emby/Items/i1/PlaybackInfo') {
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        postedBody = body;
        postedProfile = body['DeviceProfile'] as Map<String, dynamic>?;
        return http.Response(
          jsonEncode({
            'PlaySessionId': 's1',
            'MediaSources': [
              {'Id': 'ms1'}
            ],
          }),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }
      return http.Response('no', 500);
    });

    final api = EmbyApi(
      hostOrUrl: 'https://example.com',
      preferredScheme: 'https',
      client: client,
    );

    await api.fetchPlaybackInfo(
      token: 't1',
      baseUrl: 'https://example.com',
      userId: 'u1',
      deviceId: 'd1',
      itemId: 'i1',
      profile: PlaybackInfoProfileKind.vlc,
    );

    expect(methods, isNotEmpty);
    expect(methods.first, 'POST');
    expect(postedBody, isNotNull);
    expect(postedBody!['EnableDirectPlay'], isTrue);
    expect(postedBody!['EnableDirectStream'], isTrue);
    expect(postedBody!['EnableTranscoding'], isFalse);
    expect(postedProfile, isNotNull);
    expect(postedProfile!['Name'], 'LinPlayer-VLC');
    expect(postedProfile!['SupportsDirectPlay'], isTrue);
    expect(postedProfile!['SupportsDirectStream'], isTrue);
    expect(postedProfile!['SupportsTranscoding'], isFalse);
    final transcode = postedProfile!['TranscodingProfiles'] as List?;
    expect(transcode, isNotNull);
    expect(transcode, isEmpty);

    final direct = postedProfile!['DirectPlayProfiles'] as List?;
    expect(direct, isNotNull);
    final video = direct!
        .cast<Map>()
        .firstWhere((e) => (e['Type'] as String?) == 'Video');
    expect(
      (video['Container'] as String?)?.contains('m2ts'),
      isTrue,
    );
    final audio =
        direct.cast<Map>().firstWhere((e) => (e['Type'] as String?) == 'Audio');
    expect((audio['Container'] as String?)?.contains('ac3'), isTrue);
    expect((audio['Container'] as String?)?.contains('eac3'), isTrue);
  });
}
