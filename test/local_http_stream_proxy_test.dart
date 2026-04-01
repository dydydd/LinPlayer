import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lin_player/services/stream_proxy/local_http_stream_proxy.dart';
import 'package:lin_player/services/stream_resolver/stream_models.dart';
import 'package:lin_player_server_api/services/http_stream_proxy.dart';

void main() {
  setUp(() async {
    await HttpStreamProxyServer.instance.debugResetForTest();
  });

  test('HttpStreamProxyServer forwards Range and browser UA', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() async {
      await server.close(force: true);
    });

    String? upstreamRange;
    String? upstreamUa;

    server.listen((HttpRequest req) async {
      if (req.uri.path != '/media') {
        req.response.statusCode = 404;
        await req.response.close();
        return;
      }

      upstreamRange = req.headers.value(HttpHeaders.rangeHeader);
      upstreamUa = req.headers.value(HttpHeaders.userAgentHeader);

      req.response.statusCode = 206;
      req.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
      req.response.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes 1-3/6',
      );
      req.response.headers.contentType = ContentType('video', 'mp4');
      req.response.contentLength = 3;
      req.response.add(const <int>[1, 2, 3]);
      await req.response.close();
    });

    final proxyUri = await HttpStreamProxyServer.instance.registerStream(
      remoteUri: Uri.parse('http://127.0.0.1:${server.port}/media'),
      httpHeaders: const <String, String>{'User-Agent': 'BrowserUA'},
      fileName: 'video.mp4',
    );

    final client = HttpClient();
    addTearDown(() {
      client.close(force: true);
    });

    final request = await client.getUrl(proxyUri);
    request.headers.set(HttpHeaders.rangeHeader, 'bytes=1-3');
    final response = await request.close();
    final body = await response.fold<List<int>>(
      <int>[],
      (acc, chunk) => <int>[...acc, ...chunk],
    );

    expect(response.statusCode, 206);
    expect(response.headers.value(HttpHeaders.acceptRangesHeader), 'bytes');
    expect(
        response.headers.value(HttpHeaders.contentRangeHeader), 'bytes 1-3/6');
    expect(body, <int>[1, 2, 3]);
    expect(upstreamRange, 'bytes=1-3');
    expect(upstreamUa, 'BrowserUA');
  });

  test('HttpStreamProxyServer falls back to GET for HEAD requests', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() async {
      await server.close();
    });

    String? getRange;

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

        if (uri.path != '/media') {
          socket.write(
            'HTTP/1.1 404 Not Found\r\n'
            'Content-Length: 0\r\n'
            'Connection: close\r\n'
            '\r\n',
          );
          await socket.flush();
          await socket.close();
          return;
        }

        if (method == 'HEAD') {
          socket.destroy();
          return;
        }

        final rangeMatch = RegExp(
          r'^Range:\s*(.+)$',
          caseSensitive: false,
          multiLine: true,
        ).firstMatch(raw.substring(0, headerEnd));
        getRange = rangeMatch?.group(1)?.trim();

        socket.write(
          'HTTP/1.1 206 Partial Content\r\n'
          'Accept-Ranges: bytes\r\n'
          'Content-Range: bytes 0-0/6\r\n'
          'Content-Type: video/mp4\r\n'
          'Content-Length: 1\r\n'
          'Connection: close\r\n'
          '\r\n',
        );
        socket.add(const <int>[1]);
        await socket.flush();
        await socket.close();
      });
    });

    final proxyUri = await HttpStreamProxyServer.instance.registerStream(
      remoteUri: Uri.parse('http://127.0.0.1:${server.port}/media'),
      httpHeaders: const <String, String>{'User-Agent': 'BrowserUA'},
      fileName: 'video.mp4',
    );

    final client = HttpClient();
    addTearDown(() {
      client.close(force: true);
    });

    final response = await (await client.headUrl(proxyUri)).close();

    expect(response.statusCode, anyOf(200, 206));
    expect(getRange, 'bytes=0-0');
  });

  test('LocalHttpStreamProxy adds proxied STRM candidate first', () async {
    final source = PlayableSource(
      url: 'https://example.com/videoPlayUrl?id=1',
      httpHeaders: const <String, String>{'User-Agent': 'BrowserUA'},
      mediaTypeHint: StreamMediaType.unknown,
      fromStrm: true,
    );

    final wrapped = await LocalHttpStreamProxy.wrapCandidates(<PlayableSource>[
      source,
    ]);

    expect(wrapped, hasLength(2));
    expect(Uri.parse(wrapped.first.url).host, '127.0.0.1');
    expect(wrapped.first.httpHeaders, isEmpty);
    expect(wrapped.last.url, source.url);
    expect(wrapped.last.httpHeaders['User-Agent'], 'BrowserUA');
  });

  test('HttpStreamProxyServer reuses the same proxy URL for the same source',
      () async {
    final remote = Uri.parse('http://example.com/media/video.mp4');

    final first = await HttpStreamProxyServer.instance.registerStream(
      remoteUri: remote,
      httpHeaders: const <String, String>{'User-Agent': 'BrowserUA'},
      fileName: 'video.mp4',
    );
    final second = await HttpStreamProxyServer.instance.registerStream(
      remoteUri: remote,
      httpHeaders: const <String, String>{'User-Agent': 'BrowserUA'},
      fileName: 'video.mp4',
    );

    expect(second, first);
  });

  test('HttpStreamProxyServer summarizes first playback request details',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() async {
      await server.close(force: true);
    });

    server.listen((HttpRequest req) async {
      req.response.statusCode = 206;
      req.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
      req.response.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes 0-3/8',
      );
      req.response.headers.contentType = ContentType('video', 'mp4');
      req.response.contentLength = 4;
      req.response.add(const <int>[0, 1, 2, 3]);
      await req.response.close();
    });

    final proxyUri = await HttpStreamProxyServer.instance.registerStream(
      remoteUri: Uri.parse('http://127.0.0.1:${server.port}/media'),
      httpHeaders: const <String, String>{'User-Agent': 'BrowserUA'},
      fileName: 'video.mp4',
    );

    final client = HttpClient();
    addTearDown(() {
      client.close(force: true);
    });

    final request = await client.getUrl(proxyUri);
    request.headers.set(HttpHeaders.rangeHeader, 'bytes=0-3');
    final response = await request.close();
    await response.drain<void>();

    final summary = HttpStreamProxyServer.instance.buildReuseSummaryText();
    expect(summary, contains('observedRequests: 1'));
    expect(summary, contains('firstPlaybackRequests: 1'));
    expect(summary, contains('reuseOutcomes: direct-upstream=1'));
    expect(summary, contains('cache=miss'));
    expect(summary, contains('range=bytes=0-3'));
  });

  test(
      'HttpStreamProxyServer serves seeded cache before fetching upstream tail',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() async {
      await server.close(force: true);
    });

    String? upstreamRange;
    String? upstreamUa;
    server.listen((HttpRequest req) async {
      upstreamRange = req.headers.value(HttpHeaders.rangeHeader);
      upstreamUa = req.headers.value(HttpHeaders.userAgentHeader);
      req.response.statusCode = 206;
      req.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
      req.response.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes 4-7/8',
      );
      req.response.headers.contentType = ContentType('video', 'mp4');
      req.response.contentLength = 4;
      req.response.add(const <int>[4, 5, 6, 7]);
      await req.response.close();
    });

    final proxyUri = await HttpStreamProxyServer.instance.seedStreamCache(
      remoteUri: Uri.parse('http://127.0.0.1:${server.port}/media'),
      httpHeaders: const <String, String>{'User-Agent': 'BrowserUA'},
      fileName: 'video.mp4',
      startByte: 0,
      bytes: const <int>[0, 1, 2, 3],
      contentTypeMime: 'video/mp4',
      totalBytes: 8,
      acceptRanges: true,
    );

    final client = HttpClient();
    addTearDown(() {
      client.close(force: true);
    });

    final response = await (await client.getUrl(proxyUri)).close();
    final body = await response.fold<List<int>>(
      <int>[],
      (acc, chunk) => <int>[...acc, ...chunk],
    );

    expect(response.statusCode, 200);
    expect(response.headers.contentLength, 8);
    expect(body, <int>[0, 1, 2, 3, 4, 5, 6, 7]);
    expect(upstreamRange, 'bytes=4-');
    expect(upstreamUa, 'BrowserUA');
  });

  test(
      'HttpStreamProxyServer waits for in-flight warmup before falling back upstream',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() async {
      await server.close(force: true);
    });

    var upstreamHits = 0;
    server.listen((HttpRequest req) async {
      upstreamHits++;
      req.response.statusCode = 200;
      req.response.headers.contentType = ContentType('video', 'mp4');
      req.response.contentLength = 8;
      req.response.add(const <int>[9, 9, 9, 9, 9, 9, 9, 9]);
      await req.response.close();
    });

    final remoteUri = Uri.parse('http://127.0.0.1:${server.port}/media');
    const headers = <String, String>{'User-Agent': 'BrowserUA'};
    final proxyUri = await HttpStreamProxyServer.instance.registerStream(
      remoteUri: remoteUri,
      httpHeaders: headers,
      fileName: 'video.mp4',
    );

    HttpStreamProxyServer.instance.beginStreamWarmup(
      remoteUri: remoteUri,
      httpHeaders: headers,
    );
    unawaited(
      Future<void>(() async {
        await Future<void>.delayed(const Duration(milliseconds: 180));
        await HttpStreamProxyServer.instance.seedStreamCache(
          remoteUri: remoteUri,
          httpHeaders: headers,
          fileName: 'video.mp4',
          startByte: 0,
          bytes: const <int>[0, 1, 2, 3, 4, 5, 6, 7],
          contentTypeMime: 'video/mp4',
          totalBytes: 8,
          acceptRanges: true,
        );
        HttpStreamProxyServer.instance.endStreamWarmup(
          remoteUri: remoteUri,
          httpHeaders: headers,
        );
      }),
    );

    final client = HttpClient();
    addTearDown(() {
      client.close(force: true);
    });

    final response = await (await client.getUrl(proxyUri)).close();
    final body = await response.fold<List<int>>(
      <int>[],
      (acc, chunk) => <int>[...acc, ...chunk],
    );

    expect(response.statusCode, 200);
    expect(body, <int>[0, 1, 2, 3, 4, 5, 6, 7]);
    expect(upstreamHits, 0);
    expect(
      HttpStreamProxyServer.instance.buildDiagnosticsText(),
      contains('reuse=cache-only'),
    );
  });

  test(
      'HttpStreamProxyServer serves covered sub-range directly from seeded cache',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() async {
      await server.close(force: true);
    });

    var upstreamHits = 0;
    server.listen((HttpRequest req) async {
      upstreamHits++;
      req.response.statusCode = 200;
      req.response.headers.contentType = ContentType('video', 'mp4');
      req.response.contentLength = 8;
      req.response.add(const <int>[9, 9, 9, 9, 9, 9, 9, 9]);
      await req.response.close();
    });

    final proxyUri = await HttpStreamProxyServer.instance.seedStreamCache(
      remoteUri: Uri.parse('http://127.0.0.1:${server.port}/media'),
      httpHeaders: const <String, String>{'User-Agent': 'BrowserUA'},
      fileName: 'video.mp4',
      startByte: 0,
      bytes: const <int>[0, 1, 2, 3, 4, 5, 6, 7],
      contentTypeMime: 'video/mp4',
      totalBytes: 8,
      acceptRanges: true,
    );

    final client = HttpClient();
    addTearDown(() {
      client.close(force: true);
    });

    final request = await client.getUrl(proxyUri);
    request.headers.set(HttpHeaders.rangeHeader, 'bytes=2-5');
    final response = await request.close();
    final body = await response.fold<List<int>>(
      <int>[],
      (acc, chunk) => <int>[...acc, ...chunk],
    );

    expect(response.statusCode, 206);
    expect(
        response.headers.value(HttpHeaders.contentRangeHeader), 'bytes 2-5/8');
    expect(body, <int>[2, 3, 4, 5]);
    expect(upstreamHits, 0);
  });

  test('HttpStreamProxyServer caches remote GET response for later reuse',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() async {
      await server.close(force: true);
    });

    var upstreamHits = 0;
    server.listen((HttpRequest req) async {
      upstreamHits++;
      req.response.statusCode = 200;
      req.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
      req.response.headers.contentType = ContentType('video', 'mp4');
      req.response.contentLength = 8;
      req.response.add(const <int>[0, 1, 2, 3, 4, 5, 6, 7]);
      await req.response.close();
    });

    final proxyUri = await HttpStreamProxyServer.instance.registerStream(
      remoteUri: Uri.parse('http://127.0.0.1:${server.port}/media'),
      httpHeaders: const <String, String>{'User-Agent': 'BrowserUA'},
      fileName: 'video.mp4',
    );

    final client = HttpClient();
    addTearDown(() {
      client.close(force: true);
    });

    Future<List<int>> fetchOnce() async {
      final response = await (await client.getUrl(proxyUri)).close();
      expect(response.statusCode, 200);
      return response.fold<List<int>>(
        <int>[],
        (acc, chunk) => <int>[...acc, ...chunk],
      );
    }

    final first = await fetchOnce();
    final second = await fetchOnce();

    expect(first, <int>[0, 1, 2, 3, 4, 5, 6, 7]);
    expect(second, <int>[0, 1, 2, 3, 4, 5, 6, 7]);
    expect(upstreamHits, 1);
    expect(
      HttpStreamProxyServer.instance.buildDiagnosticsText(),
      contains('cache=hit'),
    );
  });

  test('HttpStreamProxyServer reuses in-flight cache fill for concurrent GETs',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() async {
      await server.close(force: true);
    });

    var upstreamHits = 0;
    server.listen((HttpRequest req) async {
      upstreamHits++;
      await Future<void>.delayed(const Duration(milliseconds: 160));
      req.response.statusCode = 200;
      req.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
      req.response.headers.contentType = ContentType('video', 'mp4');
      req.response.contentLength = 8;
      req.response.add(const <int>[0, 1, 2, 3, 4, 5, 6, 7]);
      await req.response.close();
    });

    final proxyUri = await HttpStreamProxyServer.instance.registerStream(
      remoteUri: Uri.parse('http://127.0.0.1:${server.port}/media'),
      httpHeaders: const <String, String>{'User-Agent': 'BrowserUA'},
      fileName: 'video.mp4',
    );

    final client = HttpClient();
    addTearDown(() {
      client.close(force: true);
    });

    Future<List<int>> fetchOnce() async {
      final response = await (await client.getUrl(proxyUri)).close();
      expect(response.statusCode, 200);
      return response.fold<List<int>>(
        <int>[],
        (acc, chunk) => <int>[...acc, ...chunk],
      );
    }

    final results = await Future.wait<List<int>>([
      fetchOnce(),
      fetchOnce(),
    ]);

    expect(results, <List<int>>[
      <int>[0, 1, 2, 3, 4, 5, 6, 7],
      <int>[0, 1, 2, 3, 4, 5, 6, 7],
    ]);
    expect(upstreamHits, 1);

    final diagnostics = HttpStreamProxyServer.instance.buildDiagnosticsText();
    expect(diagnostics, contains('cacheFillWait=true'));
    expect(diagnostics, contains('reuse=cache-only'));
    expect(diagnostics, contains('cache=hit'));
  });

  test(
      'HttpStreamProxyServer records miss reason when requested range is not covered',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() async {
      await server.close(force: true);
    });

    server.listen((HttpRequest req) async {
      req.response.statusCode = 206;
      req.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
      req.response.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes 6-7/8',
      );
      req.response.headers.contentType = ContentType('video', 'mp4');
      req.response.contentLength = 2;
      req.response.add(const <int>[6, 7]);
      await req.response.close();
    });

    final proxyUri = await HttpStreamProxyServer.instance.seedStreamCache(
      remoteUri: Uri.parse('http://127.0.0.1:${server.port}/media'),
      httpHeaders: const <String, String>{'User-Agent': 'BrowserUA'},
      fileName: 'video.mp4',
      startByte: 0,
      bytes: const <int>[0, 1, 2, 3],
      contentTypeMime: 'video/mp4',
      totalBytes: 8,
      acceptRanges: true,
    );

    final client = HttpClient();
    addTearDown(() {
      client.close(force: true);
    });

    final request = await client.getUrl(proxyUri);
    request.headers.set(HttpHeaders.rangeHeader, 'bytes=6-7');
    final response = await request.close();
    final body = await response.fold<List<int>>(
      <int>[],
      (acc, chunk) => <int>[...acc, ...chunk],
    );

    expect(response.statusCode, 206);
    expect(body, <int>[6, 7]);
    expect(
      HttpStreamProxyServer.instance.buildDiagnosticsText(),
      contains('reuse=direct-upstream'),
    );
    expect(
      HttpStreamProxyServer.instance.buildDiagnosticsText(),
      contains('miss=range-not-covered'),
    );
  });

  test(
      'HttpStreamProxyServer records header-mismatch when same remote cache exists under different headers',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() async {
      await server.close(force: true);
    });

    server.listen((HttpRequest req) async {
      req.response.statusCode = 206;
      req.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
      req.response.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes 0-3/8',
      );
      req.response.headers.contentType = ContentType('video', 'mp4');
      req.response.contentLength = 4;
      req.response.add(const <int>[0, 1, 2, 3]);
      await req.response.close();
    });

    final remoteUri = Uri.parse('http://127.0.0.1:${server.port}/media');
    await HttpStreamProxyServer.instance.seedStreamCache(
      remoteUri: remoteUri,
      httpHeaders: const <String, String>{'User-Agent': 'BrowserUA-A'},
      fileName: 'video.mp4',
      startByte: 0,
      bytes: const <int>[0, 1, 2, 3],
      contentTypeMime: 'video/mp4',
      totalBytes: 8,
      acceptRanges: true,
    );
    final proxyUri = await HttpStreamProxyServer.instance.registerStream(
      remoteUri: remoteUri,
      httpHeaders: const <String, String>{'User-Agent': 'BrowserUA-B'},
      fileName: 'video.mp4',
    );

    final client = HttpClient();
    addTearDown(() {
      client.close(force: true);
    });

    final request = await client.getUrl(proxyUri);
    request.headers.set(HttpHeaders.rangeHeader, 'bytes=0-3');
    final response = await request.close();
    await response.drain<void>();

    expect(
      HttpStreamProxyServer.instance.buildDiagnosticsText(),
      contains('miss=header-mismatch'),
    );
  });

  test('LocalHttpStreamProxy only wraps direct-file playback sources',
      () async {
    final fileSource = PlayableSource(
      url: 'https://example.com/video.mp4',
      mediaTypeHint: StreamMediaType.file,
      httpHeaders: const <String, String>{'User-Agent': 'BrowserUA'},
    );
    final hlsSource = PlayableSource(
      url: 'https://example.com/master.m3u8',
      mediaTypeHint: StreamMediaType.hls,
      httpHeaders: const <String, String>{'User-Agent': 'BrowserUA'},
    );

    final proxiedFile =
        await LocalHttpStreamProxy.wrapPlaybackSource(fileSource);
    final proxiedHls = await LocalHttpStreamProxy.wrapPlaybackSource(hlsSource);

    expect(proxiedFile, isNotNull);
    expect(Uri.parse(proxiedFile!.url).host, '127.0.0.1');
    expect(proxiedHls, isNull);
  });
}
