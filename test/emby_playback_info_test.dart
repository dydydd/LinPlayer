import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:lin_player_server_api/services/emby_api.dart';

void main() {
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
    expect(transcode, isNotEmpty);

    final direct = postedProfile!['DirectPlayProfiles'] as List?;
    expect(direct, isNotNull);
    final video = direct!
        .cast<Map>()
        .firstWhere((e) => (e['Type'] as String?) == 'Video');
    expect(video['AudioCodec'], 'aac,mp3');
  });

  test('fetchPlaybackInfo uses dedicated VLC device profile and POSTs first',
      () async {
    final methods = <String>[];
    Map<String, dynamic>? postedProfile;

    final client = MockClient((req) async {
      methods.add(req.method);
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
      profile: PlaybackInfoProfileKind.vlc,
    );

    expect(methods, isNotEmpty);
    expect(methods.first, 'POST');
    expect(postedProfile, isNotNull);
    expect(postedProfile!['Name'], 'LinPlayer-VLC');
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
  });
}
