import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lin_player/services/stream_resolver/src/stream_redirect_resolver.dart';
import 'package:lin_player/services/stream_resolver/stream_resolver.dart';

void main() {
  test('StreamRedirectResolver follows redirects and merges cookies', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() async {
      await server.close(force: true);
    });

    final requests = <String, String?>{};

    server.listen((HttpRequest req) async {
      final path = req.uri.path;
      final cookie = req.headers.value(HttpHeaders.cookieHeader);
      requests[path] = cookie;

      if (path == '/start') {
        req.response.statusCode = 302;
        req.response.headers.set(HttpHeaders.locationHeader, '/final');
        req.response.headers.add(
          HttpHeaders.setCookieHeader,
          'a=1; Path=/',
        );
        await req.response.close();
        return;
      }

      if (path == '/final') {
        req.response.statusCode = 200;
        req.response.headers.set('accept-ranges', 'bytes');
        req.response.headers.contentType = ContentType('video', 'mp4');
        await req.response.close();
        return;
      }

      req.response.statusCode = 404;
      await req.response.close();
    });

    final startUri = Uri.parse('http://127.0.0.1:${server.port}/start');
    final result = await StreamRedirectResolver.resolve(
      startUri,
      requestHeaders: const <String, String>{
        'User-Agent': 'UA',
        'Cookie': 'b=2',
      },
      timeout: const Duration(seconds: 2),
      maxRedirects: 5,
      useCache: false,
    );

    expect(result, isNotNull);
    expect(result!.effectiveUri.path, '/final');
    expect(result.statusCode, 200);
    expect(result.contentTypeMime, 'video/mp4');
    expect(result.acceptRanges, contains('bytes'));

    final finalCookie =
        result.effectiveRequestHeaders[HttpHeaders.cookieHeader];
    expect(finalCookie, isNotNull);
    expect(finalCookie, contains('a=1'));
    expect(finalCookie, contains('b=2'));

    expect(requests['/final'], isNotNull);
    expect(requests['/final'], contains('a=1'));
    expect(requests['/final'], contains('b=2'));
  });

  test('StreamRedirectResolver caches redirect resolutions', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() async {
      await server.close(force: true);
    });

    var requestCount = 0;

    server.listen((HttpRequest req) async {
      requestCount++;
      if (req.uri.path == '/start') {
        req.response.statusCode = 302;
        req.response.headers.set(HttpHeaders.locationHeader, '/final');
        await req.response.close();
        return;
      }
      if (req.uri.path == '/final') {
        req.response.statusCode = 200;
        await req.response.close();
        return;
      }
      req.response.statusCode = 404;
      await req.response.close();
    });

    final startUri = Uri.parse('http://127.0.0.1:${server.port}/start');

    final first = await StreamRedirectResolver.resolve(
      startUri,
      requestHeaders: const <String, String>{'User-Agent': 'UA'},
      timeout: const Duration(seconds: 2),
      cacheTtl: const Duration(minutes: 10),
      cacheMaxEntries: 128,
    );
    expect(first, isNotNull);
    expect(requestCount, 2);

    final second = await StreamRedirectResolver.resolve(
      startUri,
      requestHeaders: const <String, String>{'User-Agent': 'UA'},
      timeout: const Duration(seconds: 2),
      cacheTtl: const Duration(minutes: 10),
      cacheMaxEntries: 128,
    );
    expect(second, isNotNull);
    expect(requestCount, 2);
  });

  test('StreamRedirectResolver falls back to GET when HEAD fails', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() async {
      await server.close();
    });

    var startHeadCount = 0;
    var startGetCount = 0;

    server.listen((Socket socket) {
      final buffer = StringBuffer();
      late final StreamSubscription<List<int>> sub;
      sub = socket.listen((chunk) async {
        buffer.write(String.fromCharCodes(chunk));
        final raw = buffer.toString();
        final headerEnd = raw.indexOf('\r\n\r\n');
        if (headerEnd < 0) return;
        await sub.cancel();

        final requestLine = raw.substring(0, headerEnd).split('\r\n').first;
        final parts = requestLine.split(' ');
        final method = parts.isNotEmpty ? parts[0].trim().toUpperCase() : '';
        final target = parts.length > 1 ? parts[1].trim() : '/';
        final uri = Uri.parse(target);

        if (uri.path == '/start' && method == 'HEAD') {
          startHeadCount++;
          socket.destroy();
          return;
        }

        if (uri.path == '/start' && method == 'GET') {
          startGetCount++;
          socket.write(
            'HTTP/1.1 302 Found\r\n'
            'Location: /final\r\n'
            'Content-Length: 0\r\n'
            'Connection: close\r\n'
            '\r\n',
          );
          await socket.flush();
          await socket.close();
          return;
        }

        if (uri.path == '/final') {
          socket.write(
            'HTTP/1.1 206 Partial Content\r\n'
            'Accept-Ranges: bytes\r\n'
            'Content-Range: bytes 0-0/10\r\n'
            'Content-Type: video/mp4\r\n'
            'Content-Length: 1\r\n'
            'Connection: close\r\n'
            '\r\n',
          );
          if (method != 'HEAD') {
            socket.add(const <int>[0]);
          }
          await socket.flush();
          await socket.close();
          return;
        }

        socket.write(
          'HTTP/1.1 404 Not Found\r\n'
          'Content-Length: 0\r\n'
          'Connection: close\r\n'
          '\r\n',
        );
        await socket.flush();
        await socket.close();
      });
    });

    final startUri = Uri.parse('http://127.0.0.1:${server.port}/start');
    final result = await StreamRedirectResolver.resolve(
      startUri,
      requestHeaders: const <String, String>{'User-Agent': 'BrowserUA'},
      timeout: const Duration(seconds: 2),
      maxRedirects: 5,
      useCache: false,
    );

    expect(result, isNotNull);
    expect(result!.effectiveUri.path, '/final');
    expect(result.statusCode, 206);
    expect(result.acceptRanges, contains('bytes'));
    expect(startHeadCount, 1);
    expect(startGetCount, 1);
  });

  test('StreamResolver returns resolved + original candidates on redirect',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() async {
      await server.close(force: true);
    });

    server.listen((HttpRequest req) async {
      if (req.uri.path == '/start') {
        req.response.statusCode = 302;
        req.response.headers.set(HttpHeaders.locationHeader, '/final');
        req.response.headers.add(
          HttpHeaders.setCookieHeader,
          'a=1; Path=/',
        );
        await req.response.close();
        return;
      }
      if (req.uri.path == '/final') {
        req.response.statusCode = 200;
        req.response.headers.set('accept-ranges', 'bytes');
        req.response.headers.contentType = ContentType('video', 'mp4');
        await req.response.close();
        return;
      }
      req.response.statusCode = 404;
      await req.response.close();
    });

    final bytes = utf8.encode('http://127.0.0.1:${server.port}/start\n');

    final res = await StreamResolver.resolve(
      StreamResolveRequest(
        sourcePathOrUrl: '',
        fileName: 'a.strm',
        bytes: bytes,
      ),
      options: const StreamResolveOptions(
        redirectResolveTimeout: Duration(seconds: 2),
      ),
    );

    expect(res.isSuccess, isTrue);
    expect(res.inputWasStrm, isTrue);
    expect(res.candidates, hasLength(2));

    final resolved = res.candidates.first;
    expect(resolved.url, contains('/final'));
    expect(resolved.redirectChain.any((e) => e.contains('/start')), isTrue);
    expect(resolved.redirectChain.any((e) => e.contains('/final')), isTrue);
    expect(resolved.httpHeaders['User-Agent'], isNotEmpty);
    expect(resolved.httpHeaders[HttpHeaders.cookieHeader], contains('a=1'));
    expect(resolved.contentTypeHint, 'video/mp4');
    expect(resolved.supportsByteRange, isTrue);
    expect(resolved.httpStatusHint, 200);

    final original = res.candidates.last;
    expect(original.url, contains('/start'));
    expect(original.httpHeaders['User-Agent'], isNotEmpty);
    expect(original.httpHeaders[HttpHeaders.cookieHeader], isNull);
  });
}
