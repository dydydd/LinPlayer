import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lin_player/services/stream_resolver/stream_resolver.dart';

void main() {
  test('resolves STRM target that returns a direct URL in plain text body', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() async {
      await server.close(force: true);
    });

    server.listen((HttpRequest req) async {
      if (req.uri.path == '/api') {
        final body = 'http://127.0.0.1:${server.port}/media.mp4\n';
        req.response.statusCode = 200;
        req.response.headers.contentType = ContentType.text;
        req.response.contentLength = utf8.encode(body).length;
        req.response.write(body);
        await req.response.close();
        return;
      }

      req.response.statusCode = 404;
      await req.response.close();
    });

    final bytes = utf8.encode('http://127.0.0.1:${server.port}/api\n');
    final res = await StreamResolver.resolve(
      StreamResolveRequest(
        sourcePathOrUrl: '',
        fileName: 'a.strm',
        bytes: bytes,
      ),
      options: const StreamResolveOptions(
        cacheRedirectResolution: false,
        redirectResolveTimeout: Duration(seconds: 2),
        bodyLinkResolveTimeout: Duration(seconds: 2),
      ),
    );

    expect(res.isSuccess, isTrue);
    expect(res.inputWasStrm, isTrue);
    expect(res.candidates.length, 2);
    expect(res.candidates.first.url, contains('/media.mp4'));
    expect(res.candidates.last.url, contains('/api'));
  });

  test('resolves STRM target that returns a direct URL in JSON body', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() async {
      await server.close(force: true);
    });

    server.listen((HttpRequest req) async {
      if (req.uri.path == '/api') {
        final body = jsonEncode(<String, dynamic>{
          'url': 'http://127.0.0.1:${server.port}/media.mp4',
        });
        req.response.statusCode = 200;
        req.response.headers.contentType = ContentType.json;
        req.response.contentLength = utf8.encode(body).length;
        req.response.write(body);
        await req.response.close();
        return;
      }

      req.response.statusCode = 404;
      await req.response.close();
    });

    final bytes = utf8.encode('http://127.0.0.1:${server.port}/api\n');
    final res = await StreamResolver.resolve(
      StreamResolveRequest(
        sourcePathOrUrl: '',
        fileName: 'a.strm',
        bytes: bytes,
      ),
      options: const StreamResolveOptions(
        cacheRedirectResolution: false,
        redirectResolveTimeout: Duration(seconds: 2),
        bodyLinkResolveTimeout: Duration(seconds: 2),
      ),
    );

    expect(res.isSuccess, isTrue);
    expect(res.candidates.first.url, contains('/media.mp4'));
  });
}

