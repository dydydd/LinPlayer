import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:lin_player/services/emby_http_client_factory_io.dart';

void main() {
  test('closing one shared Emby client lease does not close the delegate', () async {
    final delegate = _RecordingClient();
    final first = debugWrapSharedEmbyClient(delegate);
    final second = debugWrapSharedEmbyClient(delegate);

    first.close();

    final response = await second.get(Uri.parse('https://example.com/ok'));

    expect(response.statusCode, 200);
    expect(delegate.sendCount, 1);
    expect(delegate.closeCount, 0);
  });

  test('closed shared Emby client lease rejects further requests', () async {
    final delegate = _RecordingClient();
    final lease = debugWrapSharedEmbyClient(delegate);

    lease.close();

    await expectLater(
      lease.get(Uri.parse('https://example.com/closed')),
      throwsA(isA<http.ClientException>()),
    );
    expect(delegate.sendCount, 0);
    expect(delegate.closeCount, 0);
  });
}

class _RecordingClient extends http.BaseClient {
  int sendCount = 0;
  int closeCount = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    sendCount += 1;
    return http.StreamedResponse(
      Stream<List<int>>.value(const <int>[]),
      200,
      request: request,
      contentLength: 0,
      headers: const <String, String>{'content-type': 'application/json'},
    );
  }

  @override
  void close() {
    closeCount += 1;
  }
}
