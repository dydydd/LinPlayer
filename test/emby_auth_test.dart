import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:lin_player_core/state/media_server_type.dart';
import 'package:lin_player_server_api/services/emby_api.dart';

void main() {
  test('buildAuthorizationHeaders uses configured default device name', () {
    final previous = EmbyApi.defaultDeviceName;
    try {
      EmbyApi.setDefaultDeviceName('Google Pixel 8');
      final headers = EmbyApi.buildAuthorizationHeaders(
        serverType: MediaServerType.emby,
        deviceId: 'device-1',
      );
      expect(
        headers['Authorization'],
        contains('Device="Google Pixel 8"'),
      );
      expect(
        headers['X-Emby-Authorization'],
        contains('Device="Google Pixel 8"'),
      );
    } finally {
      EmbyApi.setDefaultDeviceName(previous);
    }
  });

  test('authenticate prefers root base when user input ends with /emby',
      () async {
    final requested = <String>[];
    final client = MockClient((req) async {
      requested.add(req.url.toString());
      if (req.url.toString() ==
          'https://example.com/emby/Users/AuthenticateByName') {
        return http.Response(
          jsonEncode({
            'AccessToken': 't1',
            'User': {'Id': 'u1'},
          }),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }
      return http.Response('no', 405);
    });

    final api = EmbyApi(
      hostOrUrl: 'https://example.com/emby',
      preferredScheme: 'https',
      client: client,
    );

    final auth = await api.authenticate(
      username: 'demo',
      password: 'pw',
      deviceId: 'device-1',
    );

    expect(auth.baseUrlUsed, 'https://example.com');
    expect(auth.token, 't1');
    expect(auth.userId, 'u1');
    expect(requested, ['https://example.com/emby/Users/AuthenticateByName']);
  });

  test(
      'authenticate falls back to base with /emby when server requires double prefix',
      () async {
    final requested = <String>[];
    final client = MockClient((req) async {
      requested.add(req.url.toString());
      if (req.url.toString() ==
          'https://example.com/emby/emby/Users/AuthenticateByName') {
        return http.Response(
          jsonEncode({
            'AccessToken': 't2',
            'User': {'Id': 'u2'},
          }),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }
      return http.Response('method not allowed', 405);
    });

    final api = EmbyApi(
      hostOrUrl: 'https://example.com',
      preferredScheme: 'https',
      client: client,
    );

    final auth = await api.authenticate(
      username: 'demo',
      password: 'pw',
      deviceId: 'device-1',
    );

    expect(auth.baseUrlUsed, 'https://example.com/emby');
    expect(auth.token, 't2');
    expect(auth.userId, 'u2');
    expect(
      requested.take(5).toList(),
      [
        'https://example.com/emby/Users/AuthenticateByName',
        'https://example.com:8920/emby/Users/AuthenticateByName',
        'http://example.com/emby/Users/AuthenticateByName',
        'http://example.com:8096/emby/Users/AuthenticateByName',
        'https://example.com/emby/emby/Users/AuthenticateByName',
      ],
    );
  });

  test('authenticate strips /web/index.html from pasted url', () async {
    final requested = <String>[];
    final client = MockClient((req) async {
      requested.add(req.url.toString());
      if (req.url.toString() ==
          'https://example.com/emby/Users/AuthenticateByName') {
        return http.Response(
          jsonEncode({
            'AccessToken': 't3',
            'User': {'Id': 'u3'},
          }),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }
      return http.Response('no', 404);
    });

    final api = EmbyApi(
      hostOrUrl: 'https://example.com/web/index.html',
      preferredScheme: 'https',
      client: client,
    );

    final auth = await api.authenticate(
      username: 'demo',
      password: 'pw',
      deviceId: 'device-1',
    );

    expect(auth.baseUrlUsed, 'https://example.com');
    expect(requested, ['https://example.com/emby/Users/AuthenticateByName']);
  });

  test('authenticate tries common direct Emby ports when port is omitted',
      () async {
    final requested = <String>[];
    final client = MockClient((req) async {
      requested.add(req.url.toString());
      if (req.url.toString() ==
          'http://example.com:8096/emby/Users/AuthenticateByName') {
        return http.Response(
          jsonEncode({
            'AccessToken': 't4',
            'User': {'Id': 'u4'},
          }),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }
      return http.Response('no', 404);
    });

    final api = EmbyApi(
      hostOrUrl: 'example.com',
      preferredScheme: 'https',
      client: client,
    );

    final auth = await api.authenticate(
      username: 'demo',
      password: 'pw',
      deviceId: 'device-1',
    );

    expect(auth.baseUrlUsed, 'http://example.com:8096');
    expect(
      requested.take(4).toList(),
      [
        'https://example.com/emby/Users/AuthenticateByName',
        'https://example.com:8920/emby/Users/AuthenticateByName',
        'http://example.com/emby/Users/AuthenticateByName',
        'http://example.com:8096/emby/Users/AuthenticateByName',
      ],
    );
  });

  test('authenticate surfaces connection refused without mislabeling DNS',
      () async {
    final client = MockClient((_) async {
      throw const SocketException('Connection refused');
    });

    final api = EmbyApi(
      hostOrUrl: 'example.com',
      preferredScheme: 'https',
      client: client,
    );

    await expectLater(
      () => api.authenticate(
        username: 'demo',
        password: 'pw',
        deviceId: 'device-1',
      ),
      throwsA(
        predicate(
          (error) {
            final text = error.toString();
            return text.contains('Connection refused') &&
                !text.contains('DNS/');
          },
        ),
      ),
    );
  });
}
