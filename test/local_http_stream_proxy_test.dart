import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lin_player/services/stream_proxy/local_hls_stream_proxy.dart';
import 'package:lin_player/services/stream_proxy/local_http_stream_proxy.dart';
import 'package:lin_player/services/stream_resolver/stream_models.dart';
import 'package:lin_player_server_api/services/http_stream_proxy.dart';

Future<String> _waitForProxyDiagnostics(
  bool Function(String text) predicate, {
  Duration timeout = const Duration(seconds: 2),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (true) {
    final text = HttpStreamProxyServer.instance.buildDiagnosticsText();
    if (predicate(text)) return text;
    if (!DateTime.now().isBefore(deadline)) return text;
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
}

void main() {
  setUp(() async {
    await HttpStreamProxyServer.instance.debugResetForTest();
    await LocalHlsStreamProxy.instance.debugResetForTest();
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

  test('HttpStreamProxyServer serves HEAD from cached metadata', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() async {
      await server.close(force: true);
    });

    var upstreamHits = 0;
    server.listen((HttpRequest req) async {
      upstreamHits++;
      req.response.statusCode = HttpStatus.ok;
      req.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
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
      bytes: const <int>[0, 1, 2, 3],
      contentTypeMime: 'video/mp4',
      totalBytes: 8,
      acceptRanges: true,
    );

    final client = HttpClient();
    addTearDown(() {
      client.close(force: true);
    });

    final response = await (await client.headUrl(proxyUri)).close();
    await response.drain<void>();
    final diagnostics = await _waitForProxyDiagnostics(
      (text) =>
          text.contains('reason=head-metadata') &&
          text.contains('reuse=cache-only'),
    );

    expect(response.statusCode, HttpStatus.ok);
    expect(response.headers.contentLength, 8);
    expect(response.headers.value(HttpHeaders.acceptRangesHeader), 'bytes');
    expect(upstreamHits, 0);
    expect(diagnostics, contains('reason=head-metadata'));
    expect(diagnostics, contains('reuse=cache-only'));
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

  test('HttpStreamProxyServer isolates cache entries by proxy semantics',
      () async {
    final remote = Uri.parse('http://example.com/media/video.mp4');
    final keyA = HttpStreamCacheKey.fromNetworkSource(
      remoteUri: remote,
      httpHeaders: const <String, String>{'User-Agent': 'BrowserUA'},
      mediaSourceId: 'ms-1',
      proxyUrl: 'http://127.0.0.1:7890',
    );
    final keyB = HttpStreamCacheKey.fromNetworkSource(
      remoteUri: remote,
      httpHeaders: const <String, String>{'User-Agent': 'BrowserUA'},
      mediaSourceId: 'ms-1',
      proxyUrl: 'http://127.0.0.1:7891',
    );

    final first = await HttpStreamProxyServer.instance.registerStream(
      remoteUri: remote,
      httpHeaders: const <String, String>{'User-Agent': 'BrowserUA'},
      fileName: 'video.mp4',
      cacheKey: keyA,
    );
    final second = await HttpStreamProxyServer.instance.registerStream(
      remoteUri: remote,
      httpHeaders: const <String, String>{'User-Agent': 'BrowserUA'},
      fileName: 'video.mp4',
      cacheKey: keyB,
    );

    expect(second, isNot(first));
  });

  test('HttpStreamProxyServer reports cache state lifecycle', () async {
    final remote = Uri.parse('http://example.com/media/video.mp4');
    final key = HttpStreamCacheKey.fromNetworkSource(
      remoteUri: remote,
      httpHeaders: const <String, String>{'User-Agent': 'BrowserUA'},
      mediaSourceId: 'ms-state',
      audioStreamIndex: 2,
      subtitleStreamIndex: 5,
      proxyUrl: 'http://127.0.0.1:7890',
    );

    HttpStreamProxyServer.instance.beginStreamWarmup(
      remoteUri: remote,
      httpHeaders: const <String, String>{'User-Agent': 'BrowserUA'},
      cacheKey: key,
    );
    final warming = await HttpStreamProxyServer.instance.debugDescribeStream(
      remoteUri: remote,
      httpHeaders: const <String, String>{'User-Agent': 'BrowserUA'},
      cacheKey: key,
    );

    await HttpStreamProxyServer.instance.seedStreamCache(
      remoteUri: remote,
      httpHeaders: const <String, String>{'User-Agent': 'BrowserUA'},
      fileName: 'video.mp4',
      cacheKey: key,
      startByte: 0,
      bytes: const <int>[0, 1, 2, 3],
      contentTypeMime: 'video/mp4',
      totalBytes: 8,
      acceptRanges: true,
    );
    final playable = await HttpStreamProxyServer.instance.debugDescribeStream(
      remoteUri: remote,
      httpHeaders: const <String, String>{'User-Agent': 'BrowserUA'},
      cacheKey: key,
    );

    await HttpStreamProxyServer.instance.seedStreamCache(
      remoteUri: remote,
      httpHeaders: const <String, String>{'User-Agent': 'BrowserUA'},
      fileName: 'video.mp4',
      cacheKey: key,
      startByte: 4,
      bytes: const <int>[4, 5, 6, 7],
      contentTypeMime: 'video/mp4',
      totalBytes: 8,
      acceptRanges: true,
    );
    HttpStreamProxyServer.instance.endStreamWarmup(
      remoteUri: remote,
      httpHeaders: const <String, String>{'User-Agent': 'BrowserUA'},
      cacheKey: key,
    );
    final completed = await HttpStreamProxyServer.instance.debugDescribeStream(
      remoteUri: remote,
      httpHeaders: const <String, String>{'User-Agent': 'BrowserUA'},
      cacheKey: key,
    );

    final failedKey = HttpStreamCacheKey.fromNetworkSource(
      remoteUri: remote,
      httpHeaders: const <String, String>{'User-Agent': 'BrowserUA'},
      mediaSourceId: 'ms-failed',
    );
    await HttpStreamProxyServer.instance.markStreamFailure(
      remoteUri: remote,
      httpHeaders: const <String, String>{'User-Agent': 'BrowserUA'},
      cacheKey: failedKey,
      error: StateError('warmup failed'),
    );
    final failed = await HttpStreamProxyServer.instance.debugDescribeStream(
      remoteUri: remote,
      httpHeaders: const <String, String>{'User-Agent': 'BrowserUA'},
      cacheKey: failedKey,
    );
    final stale = await HttpStreamProxyServer.instance.debugDescribeStream(
      remoteUri: remote,
      httpHeaders: const <String, String>{'User-Agent': 'BrowserUA'},
      cacheKey: key,
      now: DateTime.now().add(const Duration(hours: 7)),
    );

    expect(warming.state, HttpStreamCacheState.warming);
    expect(playable.state, HttpStreamCacheState.playable);
    expect(playable.contiguousBytesFromStart, 4);
    expect(completed.state, HttpStreamCacheState.completed);
    expect(completed.cachedBytes, 8);
    expect(completed.key.proxyUrl, 'http://127.0.0.1:7890');
    expect(failed.state, HttpStreamCacheState.failed);
    expect(failed.lastFailureMessage, contains('warmup failed'));
    expect(stale.state, HttpStreamCacheState.stale);
  });

  test('HttpStreamProxyServer emits warmup download progress snapshots',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() async {
      await server.close(force: true);
    });

    server.listen((HttpRequest req) async {
      req.response.statusCode = HttpStatus.partialContent;
      req.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
      req.response.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes 0-7/8',
      );
      req.response.headers.contentType = ContentType('video', 'mp4');
      req.response.contentLength = 8;
      req.response.add(const <int>[0, 1, 2, 3]);
      await req.response.flush();
      await Future<void>.delayed(const Duration(milliseconds: 80));
      req.response.add(const <int>[4, 5, 6, 7]);
      await req.response.close();
    });

    final activeProgress = Completer<HttpStreamCacheDownloadProgressSnapshot>();
    final completed = Completer<void>();
    final sub = HttpStreamProxyServer.instance.downloadProgressStream.listen((
      snapshots,
    ) {
      if (!activeProgress.isCompleted) {
        final current = snapshots.where((entry) {
          return entry.kind == HttpStreamCacheDownloadKind.warmup &&
              entry.bytesWritten > 0;
        });
        if (current.isNotEmpty) {
          activeProgress.complete(current.last);
        }
      }
      if (activeProgress.isCompleted &&
          !completed.isCompleted &&
          snapshots.isEmpty) {
        completed.complete();
      }
    });
    addTearDown(() async {
      await sub.cancel();
    });

    final warmup = HttpStreamProxyServer.instance.warmRangeToCache(
      remoteUri: Uri.parse('http://127.0.0.1:${server.port}/media'),
      httpHeaders: const <String, String>{'User-Agent': 'BrowserUA'},
      fileName: 'video.mp4',
      startByte: 0,
      lengthBytes: 8,
    );

    final snapshot = await activeProgress.future.timeout(
      const Duration(seconds: 2),
      onTimeout: () => throw TimeoutException('waiting for active warmup'),
    );
    expect(snapshot.kind, HttpStreamCacheDownloadKind.warmup);
    expect(snapshot.startByte, 0);
    expect(snapshot.requestedBytes, 8);
    expect(snapshot.bytesWritten, greaterThan(0));
    expect(snapshot.progress, isNotNull);
    expect(snapshot.progress!, greaterThan(0));

    final result = await warmup;
    expect(result.bytesWritten, 8);

    await completed.future.timeout(const Duration(seconds: 2));
    expect(
      HttpStreamProxyServer.instance.currentDownloadProgressSnapshots(),
      isEmpty,
    );
  });

  test('HttpStreamProxyServer cancels active playback fill without draining',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() async {
      await server.close(force: true);
    });

    var upstreamChunks = 0;
    server.listen((HttpRequest req) async {
      req.response.statusCode = HttpStatus.ok;
      req.response.headers.contentType = ContentType('video', 'mp4');
      req.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
      try {
        for (var i = 0; i < 200; i++) {
          upstreamChunks++;
          req.response.add(List<int>.filled(32 * 1024, i % 256));
          await req.response.flush();
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      } catch (_) {
        // Expected when the proxy cancels the upstream request.
      } finally {
        try {
          await req.response.close();
        } catch (_) {}
      }
    });

    final activeProgress = Completer<HttpStreamCacheDownloadProgressSnapshot>();
    final completed = Completer<void>();
    final sub = HttpStreamProxyServer.instance.downloadProgressStream.listen((
      snapshots,
    ) {
      if (!activeProgress.isCompleted) {
        final current = snapshots.where((entry) {
          return entry.kind == HttpStreamCacheDownloadKind.playbackFill &&
              entry.bytesWritten > 0;
        });
        if (current.isNotEmpty) {
          activeProgress.complete(current.last);
        }
      }
      if (activeProgress.isCompleted &&
          !completed.isCompleted &&
          snapshots.isEmpty) {
        completed.complete();
      }
    });
    addTearDown(() async {
      await sub.cancel();
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
    final response = await (await client.getUrl(proxyUri)).close();
    final responseSub = response.listen(
      (_) {},
      onError: (_) {},
    );
    addTearDown(() async {
      await responseSub.cancel();
    });

    final snapshot = await activeProgress.future.timeout(
      const Duration(seconds: 2),
    );
    expect(snapshot.kind, HttpStreamCacheDownloadKind.playbackFill);

    final cancelled = HttpStreamProxyServer.instance
        .cancelActivePlaybackDownloads(
            cacheFingerprint: snapshot.key.fingerprint);
    expect(cancelled, 1);

    await completed.future.timeout(
      const Duration(seconds: 2),
      onTimeout: () => throw TimeoutException('waiting for playbackFill clear'),
    );
    await responseSub.cancel();
    client.close(force: true);
    await Future<void>.delayed(const Duration(milliseconds: 250));
    expect(upstreamChunks, lessThan(200));
    expect(
      HttpStreamProxyServer.instance.currentDownloadProgressSnapshots(),
      isEmpty,
    );
    expect(
      HttpStreamProxyServer.instance.buildDiagnosticsText(),
      isNot(contains('proxy-error')),
    );
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

  test('LocalHttpStreamProxy exposes first playback observation by fingerprint',
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
    const headers = <String, String>{'User-Agent': 'BrowserUA'};
    final cacheKey = HttpStreamCacheKey.fromNetworkSource(
      remoteUri: remoteUri,
      httpHeaders: headers,
    );
    final proxyUri = await HttpStreamProxyServer.instance.registerStream(
      remoteUri: remoteUri,
      httpHeaders: headers,
      fileName: 'video.mp4',
      cacheKey: cacheKey,
    );

    final observationFuture =
        LocalHttpStreamProxy.waitForFirstPlaybackObservation(
      cacheFingerprint: cacheKey.fingerprint,
    );

    final client = HttpClient();
    addTearDown(() {
      client.close(force: true);
    });

    final request = await client.getUrl(proxyUri);
    request.headers.set(HttpHeaders.rangeHeader, 'bytes=0-3');
    final response = await request.close();
    await response.drain<void>();

    final observation = await observationFuture;
    expect(observation, isNotNull);
    expect(observation!.firstPlaybackRequest, isTrue);
    expect(observation.cacheFingerprint, cacheKey.fingerprint);
    expect(observation.cacheStatus, 'miss');
    expect(observation.reuseOutcome, 'direct-upstream');
    expect(observation.rangeHeader, 'bytes=0-3');
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

  test('HttpStreamProxyServer warmRangeToCache resumes partially cached ranges',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() async {
      await server.close(force: true);
    });

    final observedRanges = <String?>[];
    server.listen((HttpRequest req) async {
      observedRanges.add(req.headers.value(HttpHeaders.rangeHeader));
      final range = req.headers.value(HttpHeaders.rangeHeader);
      req.response.statusCode = HttpStatus.partialContent;
      req.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
      req.response.headers.contentType = ContentType('video', 'mp4');
      if (range == 'bytes=4-7') {
        req.response.headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes 4-7/8',
        );
        req.response.contentLength = 4;
        req.response.add(const <int>[4, 5, 6, 7]);
      } else {
        req.response.headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes 0-3/8',
        );
        req.response.contentLength = 4;
        req.response.add(const <int>[0, 1, 2, 3]);
      }
      await req.response.close();
    });

    final remoteUri = Uri.parse('http://127.0.0.1:${server.port}/media');
    const headers = <String, String>{'User-Agent': 'BrowserUA'};
    await HttpStreamProxyServer.instance.seedStreamCache(
      remoteUri: remoteUri,
      httpHeaders: headers,
      fileName: 'video.mp4',
      startByte: 0,
      bytes: const <int>[0, 1, 2, 3],
      contentTypeMime: 'video/mp4',
      totalBytes: 8,
      acceptRanges: true,
    );

    final first = await HttpStreamProxyServer.instance.warmRangeToCache(
      remoteUri: remoteUri,
      httpHeaders: headers,
      fileName: 'video.mp4',
      startByte: 0,
      lengthBytes: 8,
    );
    final second = await HttpStreamProxyServer.instance.warmRangeToCache(
      remoteUri: remoteUri,
      httpHeaders: headers,
      fileName: 'video.mp4',
      startByte: 0,
      lengthBytes: 8,
    );

    expect(first.bytesWritten, 4);
    expect(first.satisfiedFromCache, isFalse);
    expect(second.bytesWritten, 0);
    expect(second.satisfiedFromCache, isTrue);
    expect(observedRanges, <String?>['bytes=4-7']);

    final proxyUri = await HttpStreamProxyServer.instance.registerStream(
      remoteUri: remoteUri,
      httpHeaders: headers,
      fileName: 'video.mp4',
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

    expect(response.statusCode, HttpStatus.ok);
    expect(body, <int>[0, 1, 2, 3, 4, 5, 6, 7]);
  });

  test(
      'HttpStreamProxyServer warmRangeToCache records redirect-final URL for later tail fetch',
      () async {
    final upstreamProxy =
        await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() async {
      await upstreamProxy.close(force: true);
    });

    var startHits = 0;
    var finalHits = 0;
    final observedTargets = <String>[];
    final observedRanges = <String?>[];

    upstreamProxy.listen((HttpRequest request) async {
      final target =
          '${request.headers.value(HttpHeaders.hostHeader) ?? ''} ${request.uri}';
      observedTargets.add(target);

      if (target.contains('start.mp4')) {
        startHits++;
        request.response.statusCode = HttpStatus.found;
        request.response.headers.set(
          HttpHeaders.locationHeader,
          'http://cdn.example.invalid/final.mp4',
        );
        await request.response.close();
        return;
      }

      if (target.contains('final.mp4')) {
        finalHits++;
        final range = request.headers.value(HttpHeaders.rangeHeader);
        observedRanges.add(range);
        final bytes = <int>[0, 1, 2, 3, 4, 5, 6, 7];
        if ((range ?? '').startsWith('bytes=4-')) {
          request.response.statusCode = HttpStatus.partialContent;
          request.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
          request.response.headers.set(
            HttpHeaders.contentRangeHeader,
            'bytes 4-7/8',
          );
          request.response.headers.contentType = ContentType('video', 'mp4');
          request.response.contentLength = 4;
          request.response.add(bytes.sublist(4));
          await request.response.close();
          return;
        }

        request.response.statusCode = HttpStatus.partialContent;
        request.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
        request.response.headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes 0-3/8',
        );
        request.response.headers.contentType = ContentType('video', 'mp4');
        request.response.contentLength = 4;
        request.response.add(bytes.sublist(0, 4));
        await request.response.close();
        return;
      }

      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
    });

    final proxyUrl = 'http://127.0.0.1:${upstreamProxy.port}';
    const remoteUrl = 'http://media.example.invalid/start.mp4';
    final cacheKey = HttpStreamCacheKey.fromNetworkSource(
      remoteUri: Uri.parse(remoteUrl),
      httpHeaders: const <String, String>{},
      mediaSourceId: 'ms-redirect-direct',
      proxyUrl: proxyUrl,
    );

    final warmup = await HttpStreamProxyServer.instance.warmRangeToCache(
      remoteUri: Uri.parse(remoteUrl),
      httpHeaders: const <String, String>{},
      fileName: 'start.mp4',
      cacheKey: cacheKey,
      startByte: 0,
      lengthBytes: 4,
    );

    expect(warmup.effectiveRemoteUri.toString(),
        'http://cdn.example.invalid/final.mp4');
    expect(startHits, 1);
    expect(finalHits, 1);

    final proxyUri = await HttpStreamProxyServer.instance.registerStream(
      remoteUri: Uri.parse(remoteUrl),
      httpHeaders: const <String, String>{},
      fileName: 'start.mp4',
      cacheKey: cacheKey,
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

    expect(response.statusCode, HttpStatus.ok);
    expect(body, <int>[0, 1, 2, 3, 4, 5, 6, 7]);
    expect(startHits, 1);
    expect(finalHits, 2);
    expect(
      observedRanges.whereType<String>(),
      contains(predicate<String>((value) => value.startsWith('bytes=4-'))),
    );
    expect(
      observedTargets.where((value) => value.contains('start.mp4')).length,
      1,
    );
  });

  test('HttpStreamProxyServer routes cache misses through the entry proxy',
      () async {
    final upstreamProxy =
        await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() async {
      await upstreamProxy.close(force: true);
    });

    var proxyHits = 0;
    upstreamProxy.listen((HttpRequest req) async {
      proxyHits++;
      req.response.statusCode = 200;
      req.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
      req.response.headers.contentType = ContentType('video', 'mp4');
      req.response.contentLength = 4;
      req.response.add(const <int>[0, 1, 2, 3]);
      await req.response.close();
    });

    const remoteUrl = 'http://media.example.invalid/proxy-media.mp4';
    final cacheKey = HttpStreamCacheKey.fromNetworkSource(
      remoteUri: Uri.parse(remoteUrl),
      httpHeaders: const <String, String>{'User-Agent': 'BrowserUA'},
      mediaSourceId: 'ms-proxy-route',
      proxyUrl: 'http://127.0.0.1:${upstreamProxy.port}',
    );
    final proxyUri = await HttpStreamProxyServer.instance.registerStream(
      remoteUri: Uri.parse(remoteUrl),
      httpHeaders: const <String, String>{'User-Agent': 'BrowserUA'},
      fileName: 'proxy-media.mp4',
      cacheKey: cacheKey,
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

    expect(response.statusCode, HttpStatus.ok);
    expect(body, <int>[0, 1, 2, 3]);
    expect(proxyHits, 1);
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
    final diagnostics = await _waitForProxyDiagnostics(
      (text) => text.contains('miss=header-mismatch'),
    );

    expect(
      diagnostics,
      contains('miss=header-mismatch'),
    );
  });

  test('LocalHttpStreamProxy wraps direct-file and HLS playback sources',
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
    expect(proxiedHls, isNotNull);
    expect(Uri.parse(proxiedHls!.url).host, '127.0.0.1');
  });

  test(
      'LocalHttpStreamProxy rewrites HLS playlist entries through local proxies',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() async {
      await server.close(force: true);
    });

    server.listen((HttpRequest request) async {
      switch (request.uri.path) {
        case '/master.m3u8':
          request.response.statusCode = HttpStatus.ok;
          request.response.headers.contentType =
              ContentType('application', 'vnd.apple.mpegurl');
          request.response.write(
            '#EXTM3U\n'
            '#EXT-X-STREAM-INF:BANDWIDTH=2000000\n'
            'media.m3u8\n',
          );
          break;
        case '/media.m3u8':
          request.response.statusCode = HttpStatus.ok;
          request.response.headers.contentType =
              ContentType('application', 'vnd.apple.mpegurl');
          request.response.write(
            '#EXTM3U\n'
            '#EXT-X-MAP:URI="init.mp4"\n'
            '#EXTINF:2.0,\n'
            'seg1.ts\n',
          );
          break;
        case '/init.mp4':
          request.response.statusCode = HttpStatus.ok;
          request.response.headers.contentType = ContentType('video', 'mp4');
          request.response.add(const <int>[0, 1, 2, 3]);
          break;
        case '/seg1.ts':
          request.response.statusCode = HttpStatus.ok;
          request.response.headers.contentType = ContentType('video', 'mp2t');
          request.response.add(const <int>[4, 5, 6, 7]);
          break;
        default:
          request.response.statusCode = HttpStatus.notFound;
      }
      await request.response.close();
    });

    final source = PlayableSource(
      url: 'http://127.0.0.1:${server.port}/master.m3u8',
      mediaTypeHint: StreamMediaType.hls,
      httpHeaders: const <String, String>{'User-Agent': 'BrowserUA'},
    );
    final proxied = await LocalHttpStreamProxy.wrapPlaybackSource(source);
    expect(proxied, isNotNull);

    final client = HttpClient();
    addTearDown(() {
      client.close(force: true);
    });

    final playlistResponse =
        await (await client.getUrl(Uri.parse(proxied!.url))).close();
    final playlistBody = utf8.decode(
      await playlistResponse.fold<List<int>>(
        <int>[],
        (acc, chunk) => <int>[...acc, ...chunk],
      ),
      allowMalformed: true,
    );
    final nestedPlaylistUrl = RegExp(r'http://127\.0\.0\.1:\d+/hls/[^\s]+')
        .firstMatch(playlistBody)
        ?.group(0);

    expect(playlistResponse.statusCode, HttpStatus.ok);
    expect(playlistBody, contains('http://127.0.0.1:'));
    expect(playlistBody, contains('/hls/'));
    expect(nestedPlaylistUrl, isNotNull);

    final nestedResponse =
        await (await client.getUrl(Uri.parse(nestedPlaylistUrl!))).close();
    final nestedBody = utf8.decode(
      await nestedResponse.fold<List<int>>(
        <int>[],
        (acc, chunk) => <int>[...acc, ...chunk],
      ),
      allowMalformed: true,
    );

    expect(nestedResponse.statusCode, HttpStatus.ok);
    expect(nestedBody, contains('/stream/'));
  });

  test(
      'LocalHttpStreamProxy pins master playlist to the closest bitrate variant',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() async {
      await server.close(force: true);
    });

    server.listen((HttpRequest request) async {
      switch (request.uri.path) {
        case '/master.m3u8':
          request.response.statusCode = HttpStatus.ok;
          request.response.headers.contentType =
              ContentType('application', 'vnd.apple.mpegurl');
          request.response.write(
            '#EXTM3U\n'
            '#EXT-X-STREAM-INF:BANDWIDTH=1000000\n'
            'low.m3u8\n'
            '#EXT-X-STREAM-INF:BANDWIDTH=4000000\n'
            'high.m3u8\n',
          );
          break;
        case '/low.m3u8':
        case '/high.m3u8':
          request.response.statusCode = HttpStatus.ok;
          request.response.headers.contentType =
              ContentType('application', 'vnd.apple.mpegurl');
          request.response.write('#EXTM3U\n');
          break;
        default:
          request.response.statusCode = HttpStatus.notFound;
      }
      await request.response.close();
    });

    final source = PlayableSource(
      url: 'http://127.0.0.1:${server.port}/master.m3u8',
      mediaTypeHint: StreamMediaType.hls,
      httpHeaders: const <String, String>{'User-Agent': 'BrowserUA'},
      bitrateHint: 1200000,
    );
    final proxied = await LocalHttpStreamProxy.wrapPlaybackSource(source);
    expect(proxied, isNotNull);

    final client = HttpClient();
    addTearDown(() {
      client.close(force: true);
    });

    final playlistResponse =
        await (await client.getUrl(Uri.parse(proxied!.url))).close();
    final playlistBody = utf8.decode(
      await playlistResponse.fold<List<int>>(
        <int>[],
        (acc, chunk) => <int>[...acc, ...chunk],
      ),
      allowMalformed: true,
    );

    expect(playlistResponse.statusCode, HttpStatus.ok);
    expect(RegExp(r'/hls/').allMatches(playlistBody).length, 1);
    expect(playlistBody, isNot(contains('high.m3u8')));
  });
}
