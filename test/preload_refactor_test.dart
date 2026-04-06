import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lin_player/services/preload/playback_preload_coordinator.dart';
import 'package:lin_player/services/stream_proxy/local_hls_stream_proxy.dart';
import 'package:lin_player/services/stream_proxy/local_http_stream_proxy.dart';
import 'package:lin_player/services/stream_resolver/stream_resolver.dart';
import 'package:lin_player_core/state/media_server_type.dart';
import 'package:lin_player_player/lin_player_player.dart';
import 'package:lin_player_prefs/lin_player_prefs.dart';
import 'package:lin_player_server_adapters/lin_player_server_adapters.dart';
import 'package:lin_player_server_api/services/http_stream_proxy.dart';
import 'package:lin_player_state/lin_player_state.dart';

void main() {
  const auth = ServerAuthSession(
    token: 'token-123',
    baseUrl: 'https://media.example.com',
    userId: 'user-1',
    apiPrefix: 'emby',
    preferredScheme: 'https',
  );

  setUp(() async {
    StreamPreloadService.instance.debugResetForTest();
    await HttpStreamProxyServer.instance.debugResetForTest();
    await LocalHlsStreamProxy.instance.debugResetForTest();
  });

  test('PlaybackPreloadCoordinator keeps proxy metadata on prepared requests',
      () {
    const proxyUrl = 'http://127.0.0.1:8900';
    final prepared = PlaybackPreloadCoordinator.prepareResolved(
      appState: AppState(),
      targetKind: PlaybackPreloadTargetKind.currentItem,
      triggerSource: 'detail_current',
      resolvedSource: const ResolvedPlaybackSource(
        itemId: 'item-proxy',
        playSessionId: 'ps-proxy',
        mediaSourceId: 'ms-proxy',
        url: 'https://media.example.com/videos/item-proxy/stream.mp4',
        httpHeaders: <String, String>{},
        isExternal: false,
        mediaTypeHint: ResolvedPlaybackMediaType.file,
        fromStrm: false,
        redirectChain: <String>[
          'https://media.example.com/videos/item-proxy/stream.mp4',
        ],
      ),
      httpProxyUrl: proxyUrl,
    );

    expect(prepared.httpProxyUrl, proxyUrl);
    expect(prepared.resolvedSource.proxyUrl, proxyUrl);

    final request = prepared.toPreloadRequest();
    expect(request.httpProxyUrl, proxyUrl);
    expect(request.resolvedSource.proxyUrl, proxyUrl);
    expect(request.dedupeFingerprint, 'target:current');
  });

  test(
    'PlaybackPreloadCoordinator separates current and next dedupe space but shares hits across trigger sources',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() async {
        await server.close(force: true);
      });

      var requestCount = 0;
      server.listen((HttpRequest request) async {
        requestCount++;
        request.response.statusCode = 206;
        request.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
        request.response.headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes 0-7/8',
        );
        request.response.headers.contentType = ContentType('video', 'mp4');
        request.response.contentLength = 8;
        request.response.add(const <int>[0, 1, 2, 3, 4, 5, 6, 7]);
        await request.response.close();
      });

      final url = 'http://127.0.0.1:${server.port}/shared-target.mp4';
      final appState = AppState();
      final resolvedSource = ResolvedPlaybackSource(
        itemId: 'episode-dedupe',
        playSessionId: 'ps-dedupe',
        mediaSourceId: 'ms-dedupe',
        url: url,
        httpHeaders: const <String, String>{'User-Agent': 'SourceUA/1.0'},
        isExternal: false,
        mediaTypeHint: ResolvedPlaybackMediaType.file,
        fromStrm: false,
        redirectChain: <String>[url],
        bitrate: 8000000,
        sizeBytes: 8000000,
      );

      final detailCurrent = PlaybackPreloadCoordinator.prepareResolved(
        appState: appState,
        targetKind: PlaybackPreloadTargetKind.currentItem,
        triggerSource: 'detail_current',
        resolvedSource: resolvedSource,
      );
      final playbackCurrent = PlaybackPreloadCoordinator.prepareResolved(
        appState: appState,
        targetKind: PlaybackPreloadTargetKind.currentItem,
        triggerSource: 'playback_resume',
        resolvedSource: resolvedSource,
      );
      final playbackNext = PlaybackPreloadCoordinator.prepareResolved(
        appState: appState,
        targetKind: PlaybackPreloadTargetKind.nextItem,
        triggerSource: 'playback_next',
        resolvedSource: resolvedSource,
      );

      final first = await PlaybackPreloadCoordinator.preloadPrepared(
        detailCurrent,
      );
      final second = await PlaybackPreloadCoordinator.preloadPrepared(
        playbackCurrent,
      );
      final third = await PlaybackPreloadCoordinator.preloadPrepared(
        playbackNext,
      );

      expect(first.status, StreamPreloadStatus.success);
      expect(second.status, StreamPreloadStatus.skippedAlreadyDone);
      expect(third.status, StreamPreloadStatus.success);
      expect(requestCount, 2);
    },
  );

  test('buildResolvedPlaybackCacheKey is stable and tracks proxy semantics',
      () {
    final sourceA = ResolvedPlaybackSource(
      itemId: 'item-cache-key',
      playSessionId: 'ps-cache-key',
      mediaSourceId: 'ms-cache-key',
      url:
          'https://media.example.com/Videos/item-cache-key/stream.mp4?AudioStreamIndex=2&SubtitleStreamIndex=5',
      httpHeaders: const <String, String>{
        'X-Auth': 'token',
        'User-Agent': 'SourceUA/1.0',
      },
      isExternal: false,
      mediaTypeHint: ResolvedPlaybackMediaType.file,
      fromStrm: false,
      redirectChain: const <String>[
        'https://media.example.com/Videos/item-cache-key/stream.mp4',
      ],
    );
    final sourceB = ResolvedPlaybackSource(
      itemId: 'item-cache-key',
      playSessionId: 'ps-cache-key-2',
      mediaSourceId: 'ms-cache-key',
      url:
          'https://media.example.com/Videos/item-cache-key/stream.mp4?SubtitleStreamIndex=5&AudioStreamIndex=2',
      httpHeaders: const <String, String>{
        'User-Agent': 'SourceUA/1.0',
        'X-Auth': 'token',
      },
      isExternal: false,
      mediaTypeHint: ResolvedPlaybackMediaType.file,
      fromStrm: false,
      redirectChain: const <String>[
        'https://media.example.com/Videos/item-cache-key/stream.mp4',
      ],
    );

    final keyA = buildResolvedPlaybackCacheKey(
      sourceA,
      proxyUrl: 'http://127.0.0.1:7890',
    );
    final keyB = buildResolvedPlaybackCacheKey(
      sourceB,
      proxyUrl: 'http://127.0.0.1:7890',
    );
    final keyDifferentProxy = buildResolvedPlaybackCacheKey(
      sourceB,
      proxyUrl: 'http://127.0.0.1:7891',
    );
    final keyDifferentMedia = buildResolvedPlaybackCacheKey(
      sourceB.copyWith(mediaSourceId: 'ms-other'),
      proxyUrl: 'http://127.0.0.1:7890',
    );

    expect(keyA, isNotNull);
    expect(keyB, isNotNull);
    expect(keyA!.fingerprint, keyB!.fingerprint);
    expect(keyA.audioStreamIndex, 2);
    expect(keyA.subtitleStreamIndex, 5);
    expect(keyA.proxyUrl, 'http://127.0.0.1:7890');
    expect(keyDifferentProxy, isNotNull);
    expect(keyDifferentMedia, isNotNull);
    expect(keyDifferentProxy!.fingerprint, isNot(keyA.fingerprint));
    expect(keyDifferentMedia!.fingerprint, isNot(keyA.fingerprint));
  });

  test(
      'StreamCacheDownloadRequest keeps original cache semantics when re-pointed to a redirect-final URI',
      () {
    const proxyUrl = 'http://127.0.0.1:7890';
    final request = StreamCacheDownloadRequest(
      resolvedSource: const ResolvedPlaybackSource(
        itemId: 'item-cache-download',
        playSessionId: 'ps-cache-download',
        mediaSourceId: 'ms-cache-download',
        url:
            'https://media.example.com/Videos/item-cache-download/stream.mp4?AudioStreamIndex=2',
        httpHeaders: <String, String>{'User-Agent': 'SourceUA/1.0'},
        isExternal: false,
        mediaTypeHint: ResolvedPlaybackMediaType.file,
        fromStrm: false,
        redirectChain: <String>[
          'https://media.example.com/Videos/item-cache-download/stream.mp4',
        ],
        proxyUrl: proxyUrl,
      ),
    );

    final redirected = request.withRemoteUri(
      Uri.parse('https://cdn.example.net/final.mp4'),
    );

    expect(request.remoteUri?.toString(), contains('media.example.com'));
    expect(
        redirected.remoteUri?.toString(), 'https://cdn.example.net/final.mp4');
    expect(request.effectiveProxyUrl, proxyUrl);
    expect(redirected.effectiveProxyUrl, proxyUrl);
    expect(request.cacheKey, isNotNull);
    expect(redirected.cacheKey, isNotNull);
    expect(redirected.cacheKey!.fingerprint, request.cacheKey!.fingerprint);
    expect(redirected.effectiveFileName, 'final.mp4');
  });

  test(
      'StreamCacheDownloadService warms resolved source ranges for later playback reuse',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() async {
      await server.close(force: true);
    });

    var prefixHits = 0;
    var tailHits = 0;
    final observedRanges = <String?>[];
    server.listen((HttpRequest request) async {
      final range = request.headers.value(HttpHeaders.rangeHeader);
      observedRanges.add(range);
      final bytes = <int>[0, 1, 2, 3, 4, 5, 6, 7];
      if ((range ?? '').startsWith('bytes=4-')) {
        tailHits++;
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

      prefixHits++;
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
    });

    final url = 'http://127.0.0.1:${server.port}/download-service.mp4';
    final request = StreamCacheDownloadRequest(
      resolvedSource: ResolvedPlaybackSource(
        itemId: 'episode-download-service',
        playSessionId: 'ps-download-service',
        mediaSourceId: 'ms-download-service',
        url: url,
        httpHeaders: const <String, String>{'User-Agent': 'SourceUA/1.0'},
        isExternal: false,
        mediaTypeHint: ResolvedPlaybackMediaType.file,
        fromStrm: false,
        redirectChain: <String>[url],
        bitrate: 8000000,
        sizeBytes: 8,
      ),
    );

    final warmup = await StreamCacheDownloadService.instance.warmRangeToCache(
      request: request,
      startByte: 0,
      lengthBytes: 4,
    );
    final snapshot =
        await StreamCacheDownloadService.instance.describe(request);

    expect(warmup, isNotNull);
    expect(warmup!.requestedBytes, 4);
    expect(snapshot, isNotNull);
    expect(snapshot!.state, HttpStreamCacheState.playable);
    expect(snapshot.cachedBytes, 4);
    expect(snapshot.ranges, hasLength(1));
    expect(snapshot.ranges.single.startByte, 0);
    expect(snapshot.ranges.single.lengthBytes, 4);

    final proxyUri =
        await StreamCacheDownloadService.instance.registerStream(request);
    expect(proxyUri, isNotNull);

    final client = HttpClient();
    addTearDown(() {
      client.close(force: true);
    });

    final response = await (await client.getUrl(proxyUri!)).close();
    final body = await response.fold<List<int>>(
      <int>[],
      (acc, chunk) => <int>[...acc, ...chunk],
    );

    expect(response.statusCode, HttpStatus.ok);
    expect(body, <int>[0, 1, 2, 3, 4, 5, 6, 7]);
    expect(prefixHits, 1);
    expect(tailHits, 1);
    expect(
      observedRanges.whereType<String>(),
      contains(predicate<String>((value) => value.startsWith('bytes=0-'))),
    );
    expect(observedRanges, contains('bytes=4-'));
  });

  group('PlaybackSourceBuilder', () {
    test(
      'preferred media source index wins and inherits query parameters',
      () async {
        final adapter = _FakeAdapter(
          playbackInfo: PlaybackInfoResult(
            playSessionId: 'play-1',
            mediaSourceId: 'ms-hi',
            mediaSources: <Map<String, dynamic>>[
              <String, dynamic>{
                'Id': 'ms-hi',
                'DirectStreamUrl': '/emby/Videos/item-1/high.mkv',
                'Bitrate': 9000000,
                'Size': 9000,
                'MediaStreams': const <Map<String, dynamic>>[
                  <String, dynamic>{'Type': 'Video', 'Height': 2160},
                ],
              },
              <String, dynamic>{
                'Id': 'ms-lo',
                'DirectStreamUrl': '/emby/Videos/item-1/low.mkv',
                'Bitrate': 3000000,
                'Size': 3000,
                'MediaStreams': const <Map<String, dynamic>>[
                  <String, dynamic>{'Type': 'Video', 'Height': 1080},
                ],
              },
            ],
          ),
          streamHeaders: const <String, String>{'X-Test': 'stream'},
        );

        final result = await PlaybackSourceBuilder.build(
          PlaybackSourceBuildRequest(
            adapter: adapter,
            auth: auth,
            itemId: 'item-1',
            playerCore: PlaybackSourcePlayerCoreKind.mpv,
            preferredMediaSourceIndex: 1,
            audioStreamIndex: 2,
            subtitleStreamIndex: 5,
            preferredVideoVersion: VideoVersionPreference.highestResolution,
            resolveExternalSource: false,
          ),
        );

        final uri = Uri.parse(result.resolvedSource.url);
        expect(result.selectedMediaSourceId, 'ms-lo');
        expect(uri.path, '/emby/Videos/item-1/low.mkv');
        expect(uri.queryParameters['api_key'], 'token-123');
        expect(uri.queryParameters['AudioStreamIndex'], '2');
        expect(uri.queryParameters['SubtitleStreamIndex'], '5');
        expect(
          result.resolvedSource.httpHeaders,
          const <String, String>{'X-Test': 'stream'},
        );
        expect(result.resolvedSource.isExternal, isFalse);
      },
    );

    test('cross-origin path stays external without server auth decoration',
        () async {
      final adapter = _FakeAdapter(
        playbackInfo: PlaybackInfoResult(
          playSessionId: 'play-2',
          mediaSourceId: 'ms-ext',
          mediaSources: const <Map<String, dynamic>>[
            <String, dynamic>{
              'Id': 'ms-ext',
              'Path': 'https://cdn.example.net/video/master.m3u8',
              'Bitrate': 4000000,
              'MediaStreams': <Map<String, dynamic>>[
                <String, dynamic>{'Type': 'Video', 'Height': 1080},
              ],
            },
          ],
        ),
      );

      final result = await PlaybackSourceBuilder.build(
        PlaybackSourceBuildRequest(
          adapter: adapter,
          auth: auth,
          itemId: 'item-2',
          playerCore: PlaybackSourcePlayerCoreKind.mpv,
          resolveExternalSource: false,
        ),
      );

      final uri = Uri.parse(result.resolvedSource.url);
      expect(result.selectedMediaSourceId, 'ms-ext');
      expect(uri.host, 'cdn.example.net');
      expect(uri.queryParameters.containsKey('api_key'), isFalse);
      expect(result.resolvedSource.isExternal, isTrue);
      expect(result.resolvedSource.httpHeaders, isEmpty);
      expect(
        result.resolvedSource.mediaTypeHint,
        ResolvedPlaybackMediaType.hls,
      );
    });

    test('body-link resolution strips sensitive headers on cross-origin target',
        () async {
      final linkServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() async {
        await linkServer.close(force: true);
      });
      final mediaServer =
          await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() async {
        await mediaServer.close(force: true);
      });

      var mediaRequests = 0;
      mediaServer.listen((HttpRequest request) async {
        mediaRequests++;
        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType('video', 'mp4');
        request.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
        await request.response.close();
      });

      linkServer.listen((HttpRequest request) async {
        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType('text', 'plain');
        if (request.method != 'HEAD') {
          final link = 'http://127.0.0.1:${mediaServer.port}/final.mp4'
              '|Referer=${Uri.encodeQueryComponent('https://ref.example/path')}'
              '&Cookie=${Uri.encodeQueryComponent('session=abc')}'
              '&Authorization=${Uri.encodeQueryComponent('Bearer secret')}';
          request.response.write(link);
        }
        await request.response.close();
      });

      final adapter = _FakeAdapter(
        playbackInfo: PlaybackInfoResult(
          playSessionId: 'play-3',
          mediaSourceId: 'ms-strm',
          mediaSources: <Map<String, dynamic>>[
            <String, dynamic>{
              'Id': 'ms-strm',
              'Path': 'http://127.0.0.1:${linkServer.port}/source.strm',
            },
          ],
        ),
      );

      final result = await PlaybackSourceBuilder.build(
        PlaybackSourceBuildRequest(
          adapter: adapter,
          auth: auth,
          itemId: 'item-3',
          playerCore: PlaybackSourcePlayerCoreKind.mpv,
        ),
      );

      expect(
        result.resolvedSource.url,
        'http://127.0.0.1:${mediaServer.port}/final.mp4',
      );
      expect(result.resolvedSource.fromStrm, isTrue);
      expect(
        result.resolvedSource.httpHeaders['Referer'],
        'https://ref.example/path',
      );
      final lowerHeaderKeys = result.resolvedSource.httpHeaders.keys
          .map((key) => key.toLowerCase())
          .toSet();
      expect(lowerHeaderKeys.contains('cookie'), isFalse);
      expect(lowerHeaderKeys.contains('authorization'), isFalse);
      expect(
        result.resolvedSource.redirectChain,
        contains('http://127.0.0.1:${linkServer.port}/source.strm'),
      );
      expect(
        result.resolvedSource.redirectChain,
        contains('http://127.0.0.1:${mediaServer.port}/final.mp4'),
      );
      expect(mediaRequests, greaterThanOrEqualTo(1));
    });

    test(
      'shared builder and stream resolver agree on STRM redirect/body-link target',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() async {
          await server.close(force: true);
        });

        server.listen((HttpRequest request) async {
          switch (request.uri.path) {
            case '/start.strm':
              request.response.statusCode = 302;
              request.response.headers.set(HttpHeaders.locationHeader, '/api');
              await request.response.close();
              return;
            case '/api':
              request.response.statusCode = 200;
              request.response.headers.contentType = ContentType.text;
              if (request.method != 'HEAD') {
                request.response.write(
                  'http://127.0.0.1:${server.port}/final.mp4'
                  '|Referer=${Uri.encodeQueryComponent('https://ref.example/path')}'
                  '&Cookie=${Uri.encodeQueryComponent('session=abc')}',
                );
              }
              await request.response.close();
              return;
            case '/final.mp4':
              request.response.statusCode = 200;
              request.response.headers.contentType =
                  ContentType('video', 'mp4');
              request.response.headers
                  .set(HttpHeaders.acceptRangesHeader, 'bytes');
              await request.response.close();
              return;
          }

          request.response.statusCode = 404;
          await request.response.close();
        });

        final strmUrl = 'http://127.0.0.1:${server.port}/start.strm';
        final adapter = _FakeAdapter(
          playbackInfo: PlaybackInfoResult(
            playSessionId: 'play-shared',
            mediaSourceId: 'ms-shared',
            mediaSources: <Map<String, dynamic>>[
              <String, dynamic>{
                'Id': 'ms-shared',
                'Path': strmUrl,
              },
            ],
          ),
        );

        final buildResult = await PlaybackSourceBuilder.build(
          PlaybackSourceBuildRequest(
            adapter: adapter,
            auth: auth,
            itemId: 'item-shared',
            playerCore: PlaybackSourcePlayerCoreKind.mpv,
          ),
        );

        final resolved = await StreamResolver.resolve(
          StreamResolveRequest(
            sourcePathOrUrl: '',
            fileName: 'shared.strm',
            bytes: utf8.encode('$strmUrl\n'),
          ),
          options: const StreamResolveOptions(
            preferBrowserUserAgentForStrm: false,
            cacheRedirectResolution: false,
          ),
        );

        expect(resolved.isSuccess, isTrue);
        final candidate = resolved.candidates.first;
        expect(buildResult.resolvedSource.url, candidate.url);
        expect(
          _headerValue(buildResult.resolvedSource.httpHeaders, 'Referer'),
          _headerValue(candidate.httpHeaders, 'Referer'),
        );
        expect(
          _headerValue(buildResult.resolvedSource.httpHeaders, 'Cookie'),
          _headerValue(candidate.httpHeaders, 'Cookie'),
        );
        expect(
          buildResult.resolvedSource.mediaTypeHint,
          ResolvedPlaybackMediaType.file,
        );
        expect(candidate.mediaTypeHint, StreamMediaType.file);
      },
    );
  });

  test(
      'StreamPreloadService preserves upstream UA and dedupes repeated requests',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() async {
      await server.close(force: true);
    });

    var requestCount = 0;
    final userAgents = <String?>[];
    server.listen((HttpRequest request) async {
      requestCount++;
      userAgents.add(request.headers.value(HttpHeaders.userAgentHeader));
      request.response.statusCode = 206;
      request.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
      request.response.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes 0-7/8',
      );
      request.response.headers.contentType = ContentType('video', 'mp4');
      request.response.contentLength = 8;
      request.response.add(const <int>[0, 1, 2, 3, 4, 5, 6, 7]);
      await request.response.close();
    });

    final url = 'http://127.0.0.1:${server.port}/media.mp4';
    final source = ResolvedPlaybackSource(
      itemId: 'preload-item-${server.port}',
      playSessionId: 'ps-${server.port}',
      mediaSourceId: 'ms-${server.port}',
      url: url,
      httpHeaders: const <String, String>{'User-Agent': 'SourceUA/1.0'},
      isExternal: false,
      mediaTypeHint: ResolvedPlaybackMediaType.file,
      fromStrm: false,
      redirectChain: <String>[url],
      bitrate: 8000000,
      sizeBytes: 8000000,
    );
    final request = PreloadRequest(
      resolvedSource: source,
      triggerSource: 'detail_current',
    );

    final first = await StreamPreloadService.instance.preloadResolvedSource(
      request,
    );
    final second = await StreamPreloadService.instance.preloadResolvedSource(
      request,
    );

    expect(first.status, StreamPreloadStatus.success);
    expect(second.status, StreamPreloadStatus.skippedAlreadyDone);
    expect(requestCount, 1);
    expect(userAgents, contains('SourceUA/1.0'));

    final diagnostics = StreamPreloadService.instance.buildDiagnosticsText(
      maxEntries: 2,
    );
    final summary = StreamPreloadService.instance.buildStatusSummaryText();
    expect(diagnostics, contains('trigger=detail_current'));
    expect(diagnostics, contains('status=success'));
    expect(diagnostics, contains('status=skippedAlreadyDone'));
    expect(summary, contains('observedAttempts: 2'));
    expect(summary, contains('success=1'));
    expect(summary, contains('skippedAlreadyDone=1'));
  });

  test('StreamPreloadService preloads direct links near the resume offset',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() async {
      await server.close(force: true);
    });

    final ranges = <String?>[];
    server.listen((HttpRequest request) async {
      ranges.add(request.headers.value(HttpHeaders.rangeHeader));
      request.response.statusCode = 206;
      request.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
      request.response.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes 0-7/80000000',
      );
      request.response.headers.contentType = ContentType('video', 'mp4');
      request.response.contentLength = 8;
      request.response.add(const <int>[0, 1, 2, 3, 4, 5, 6, 7]);
      await request.response.close();
    });

    final url = 'http://127.0.0.1:${server.port}/resume.mp4';
    final result = await StreamPreloadService.instance.preloadResolvedSource(
      PreloadRequest(
        resolvedSource: ResolvedPlaybackSource(
          itemId: 'episode-resume',
          playSessionId: 'ps-resume',
          mediaSourceId: 'ms-resume',
          url: url,
          httpHeaders: const <String, String>{'User-Agent': 'SourceUA/1.0'},
          isExternal: false,
          mediaTypeHint: ResolvedPlaybackMediaType.file,
          fromStrm: false,
          redirectChain: <String>[url],
          bitrate: 8000000,
          sizeBytes: 80000000,
        ),
        triggerSource: 'playback_resume',
        startPosition: const Duration(seconds: 10),
      ),
    );

    expect(result.status, StreamPreloadStatus.success);
    expect(ranges, hasLength(2));
    expect(ranges.first, 'bytes=0-524287');
    expect(ranges.last, startsWith('bytes=10000000-'));
  });

  test(
    'StreamPreloadService honors per-request preload duration when estimating range',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() async {
        await server.close(force: true);
      });

      final ranges = <String?>[];
      server.listen((HttpRequest request) async {
        ranges.add(request.headers.value(HttpHeaders.rangeHeader));
        request.response.statusCode = 206;
        request.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
        request.response.headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes 0-7/80000000',
        );
        request.response.headers.contentType = ContentType('video', 'mp4');
        request.response.contentLength = 8;
        request.response.add(const <int>[0, 1, 2, 3, 4, 5, 6, 7]);
        await request.response.close();
      });

      final url = 'http://127.0.0.1:${server.port}/resume-5s.mp4';
      final result = await StreamPreloadService.instance.preloadResolvedSource(
        PreloadRequest(
          resolvedSource: ResolvedPlaybackSource(
            itemId: 'episode-resume-5s',
            playSessionId: 'ps-resume-5s',
            mediaSourceId: 'ms-resume-5s',
            url: url,
            httpHeaders: const <String, String>{'User-Agent': 'SourceUA/1.0'},
            isExternal: false,
            mediaTypeHint: ResolvedPlaybackMediaType.file,
            fromStrm: false,
            redirectChain: <String>[url],
            bitrate: 8000000,
            sizeBytes: 80000000,
          ),
          triggerSource: 'playback_resume',
          startPosition: const Duration(seconds: 10),
          preloadDuration: const Duration(seconds: 5),
        ),
      );

      expect(result.status, StreamPreloadStatus.success);
      expect(ranges, hasLength(2));
      expect(ranges.first, 'bytes=0-524287');
      expect(ranges.last, 'bytes=10000000-14999999');
    },
  );

  test('StreamPreloadService dedupe key distinguishes different media sources',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() async {
      await server.close(force: true);
    });

    var requestCount = 0;
    server.listen((HttpRequest request) async {
      requestCount++;
      request.response.statusCode = 206;
      request.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
      request.response.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes 0-7/8',
      );
      request.response.headers.contentType = ContentType('video', 'mp4');
      request.response.contentLength = 8;
      request.response.add(const <int>[0, 1, 2, 3, 4, 5, 6, 7]);
      await request.response.close();
    });

    final url = 'http://127.0.0.1:${server.port}/shared.mp4';

    ResolvedPlaybackSource buildSource(String mediaSourceId) {
      return ResolvedPlaybackSource(
        itemId: 'episode-1',
        playSessionId: 'ps-$mediaSourceId',
        mediaSourceId: mediaSourceId,
        url: url,
        httpHeaders: const <String, String>{'User-Agent': 'SourceUA/1.0'},
        isExternal: false,
        mediaTypeHint: ResolvedPlaybackMediaType.file,
        fromStrm: false,
        redirectChain: <String>[url],
        bitrate: 8000000,
        sizeBytes: 8000000,
      );
    }

    final first = await StreamPreloadService.instance.preloadResolvedSource(
      PreloadRequest(
        resolvedSource: buildSource('ms-a'),
        triggerSource: 'detail_current',
      ),
    );
    final second = await StreamPreloadService.instance.preloadResolvedSource(
      PreloadRequest(
        resolvedSource: buildSource('ms-b'),
        triggerSource: 'detail_current',
      ),
    );

    expect(first.status, StreamPreloadStatus.success);
    expect(second.status, StreamPreloadStatus.success);
    expect(requestCount, 2);
  });

  test('StreamPreloadService routes requests through the configured HTTP proxy',
      () async {
    final proxyServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() async {
      await proxyServer.close(force: true);
    });

    var requestCount = 0;
    proxyServer.listen((HttpRequest request) async {
      requestCount++;
      request.response.statusCode = 206;
      request.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
      request.response.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes 0-7/8',
      );
      request.response.headers.contentType = ContentType('video', 'mp4');
      request.response.contentLength = 8;
      request.response.add(const <int>[0, 1, 2, 3, 4, 5, 6, 7]);
      await request.response.close();
    });

    final result = await StreamPreloadService.instance.preloadResolvedSource(
      PreloadRequest(
        resolvedSource: const ResolvedPlaybackSource(
          itemId: 'episode-proxy',
          playSessionId: 'ps-proxy',
          mediaSourceId: 'ms-proxy',
          url: 'http://example.invalid/media.mp4',
          httpHeaders: <String, String>{'User-Agent': 'SourceUA/1.0'},
          isExternal: true,
          mediaTypeHint: ResolvedPlaybackMediaType.file,
          fromStrm: false,
          redirectChain: <String>['http://example.invalid/media.mp4'],
          bitrate: 8000000,
          sizeBytes: 8000000,
        ),
        triggerSource: 'detail_current',
        httpProxyUrl: 'http://127.0.0.1:${proxyServer.port}',
      ),
    );

    expect(result.status, StreamPreloadStatus.success);
    expect(requestCount, 1);
    expect(
      StreamPreloadService.instance.buildDiagnosticsText(),
      contains('proxy=true'),
    );
  });

  test(
      'StreamPreloadService seeds loopback proxy cache for later playback reuse',
      () async {
    final preloadProxy = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() async {
      await preloadProxy.close(force: true);
    });

    var preloadProxyRequests = 0;
    preloadProxy.listen((HttpRequest request) async {
      preloadProxyRequests++;
      request.response.statusCode = 206;
      request.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
      request.response.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes 0-7/8',
      );
      request.response.headers.contentType = ContentType('video', 'mp4');
      request.response.contentLength = 8;
      request.response.add(const <int>[0, 1, 2, 3, 4, 5, 6, 7]);
      await request.response.close();
    });

    const remoteUrl = 'http://media.example.invalid/reused.mp4';
    final resolvedSource = ResolvedPlaybackSource(
      itemId: 'episode-cache-reuse',
      playSessionId: 'ps-cache-reuse',
      mediaSourceId: 'ms-cache-reuse',
      url: remoteUrl,
      httpHeaders: const <String, String>{},
      isExternal: true,
      mediaTypeHint: ResolvedPlaybackMediaType.file,
      fromStrm: false,
      redirectChain: const <String>[remoteUrl],
      bitrate: 8000000,
      sizeBytes: 8,
    );
    final cacheKey = buildResolvedPlaybackCacheKey(
      resolvedSource,
      proxyUrl: 'http://127.0.0.1:${preloadProxy.port}',
    );
    final preloadResult =
        await StreamPreloadService.instance.preloadResolvedSource(
      PreloadRequest(
        resolvedSource: resolvedSource,
        triggerSource: 'detail_current',
        httpProxyUrl: 'http://127.0.0.1:${preloadProxy.port}',
      ),
    );

    expect(preloadResult.status, StreamPreloadStatus.success);
    expect(preloadProxyRequests, 1);

    final proxyUri = await HttpStreamProxyServer.instance.registerStream(
      remoteUri: Uri.parse(remoteUrl),
      httpHeaders: const <String, String>{},
      fileName: 'reused.mp4',
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
    expect(response.headers.contentLength, 8);
    expect(body, <int>[0, 1, 2, 3, 4, 5, 6, 7]);
    expect(preloadProxyRequests, 1);
  });

  test(
      'Preload + proxy playback reuses cached prefix and only fills the missing tail',
      () async {
    final upstreamProxy =
        await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() async {
      await upstreamProxy.close(force: true);
    });

    var prefixHits = 0;
    var tailHits = 0;
    final observedRanges = <String?>[];

    upstreamProxy.listen((HttpRequest request) async {
      final range = request.headers.value(HttpHeaders.rangeHeader);
      observedRanges.add(range);
      final bytes = <int>[0, 1, 2, 3, 4, 5, 6, 7];
      if ((range ?? '').startsWith('bytes=4-')) {
        tailHits++;
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

      prefixHits++;
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
    });

    final proxyUrl = 'http://127.0.0.1:${upstreamProxy.port}';
    const remoteUrl = 'http://media.example.invalid/preload-tail.mp4';
    final resolvedSource = ResolvedPlaybackSource(
      itemId: 'episode-preload-tail',
      playSessionId: 'ps-preload-tail',
      mediaSourceId: 'ms-preload-tail',
      url: remoteUrl,
      httpHeaders: const <String, String>{},
      isExternal: true,
      mediaTypeHint: ResolvedPlaybackMediaType.file,
      fromStrm: false,
      redirectChain: const <String>[remoteUrl],
      bitrate: 8000000,
      sizeBytes: 8,
    );

    final preloadResult =
        await StreamPreloadService.instance.preloadResolvedSource(
      PreloadRequest(
        resolvedSource: resolvedSource,
        triggerSource: 'detail_current',
        httpProxyUrl: proxyUrl,
      ),
    );

    expect(preloadResult.status, StreamPreloadStatus.success);
    expect(prefixHits, 1);
    expect(tailHits, 0);

    final cacheKey = buildResolvedPlaybackCacheKey(
      resolvedSource,
      proxyUrl: proxyUrl,
    );
    final proxyUri = await HttpStreamProxyServer.instance.registerStream(
      remoteUri: Uri.parse(remoteUrl),
      httpHeaders: const <String, String>{},
      fileName: 'preload-tail.mp4',
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
    expect(prefixHits, 1);
    expect(tailHits, 1);
    expect(
      observedRanges
          .whereType<String>()
          .where((value) => value.startsWith('bytes=0-'))
          .length,
      1,
    );
    expect(observedRanges, contains('bytes=4-'));
    expect(
      HttpStreamProxyServer.instance.buildDiagnosticsText(),
      contains('reuse=cache+remote-tail'),
    );
  });

  test(
      'Playback waits for in-flight preload warmup instead of duplicating upstream prefix download',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() async {
      await server.close(force: true);
    });

    var upstreamHits = 0;
    final firstRequestStarted = Completer<void>();
    server.listen((HttpRequest request) async {
      upstreamHits++;
      if (!firstRequestStarted.isCompleted) {
        firstRequestStarted.complete();
      }
      await Future<void>.delayed(const Duration(milliseconds: 180));
      request.response.statusCode = HttpStatus.partialContent;
      request.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
      request.response.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes 0-7/8',
      );
      request.response.headers.contentType = ContentType('video', 'mp4');
      request.response.contentLength = 8;
      request.response.add(const <int>[0, 1, 2, 3, 4, 5, 6, 7]);
      await request.response.close();
    });

    final url = 'http://127.0.0.1:${server.port}/warming.mp4';
    final resolvedSource = ResolvedPlaybackSource(
      itemId: 'episode-warmup-wait',
      playSessionId: 'ps-warmup-wait',
      mediaSourceId: 'ms-warmup-wait',
      url: url,
      httpHeaders: const <String, String>{'User-Agent': 'SourceUA/1.0'},
      isExternal: false,
      mediaTypeHint: ResolvedPlaybackMediaType.file,
      fromStrm: false,
      redirectChain: <String>[url],
      bitrate: 8000000,
      sizeBytes: 8,
    );

    final preloadFuture = StreamPreloadService.instance.preloadResolvedSource(
      PreloadRequest(
        resolvedSource: resolvedSource,
        triggerSource: 'detail_current',
      ),
    );

    await firstRequestStarted.future.timeout(const Duration(seconds: 2));

    final cacheKey = buildResolvedPlaybackCacheKey(resolvedSource);
    final proxyUri = await HttpStreamProxyServer.instance.registerStream(
      remoteUri: Uri.parse(url),
      httpHeaders: resolvedSource.httpHeaders,
      fileName: 'warming.mp4',
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
    final preloadResult = await preloadFuture;

    expect(preloadResult.status, StreamPreloadStatus.success);
    expect(response.statusCode, HttpStatus.ok);
    expect(body, <int>[0, 1, 2, 3, 4, 5, 6, 7]);
    expect(upstreamHits, 1);
    expect(
      HttpStreamProxyServer.instance.buildDiagnosticsText(),
      contains('warmupWait=true'),
    );
    expect(
      HttpStreamProxyServer.instance.buildDiagnosticsText(),
      contains('reuse=cache-only'),
    );
  });

  test(
      'StreamPreloadService records redirect-final URL so playback tail fetch skips the redirect hop',
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
    final resolvedSource = ResolvedPlaybackSource(
      itemId: 'episode-redirect-final-url',
      playSessionId: 'ps-redirect-final-url',
      mediaSourceId: 'ms-redirect-final-url',
      url: remoteUrl,
      httpHeaders: const <String, String>{},
      isExternal: true,
      mediaTypeHint: ResolvedPlaybackMediaType.file,
      fromStrm: false,
      redirectChain: const <String>[remoteUrl],
      bitrate: 8000000,
      sizeBytes: 8,
    );

    final preloadResult =
        await StreamPreloadService.instance.preloadResolvedSource(
      PreloadRequest(
        resolvedSource: resolvedSource,
        triggerSource: 'detail_current',
        httpProxyUrl: proxyUrl,
      ),
    );

    expect(preloadResult.status, StreamPreloadStatus.success);
    expect(startHits, 1);
    expect(finalHits, 1);

    final cacheKey = buildResolvedPlaybackCacheKey(
      resolvedSource,
      proxyUrl: proxyUrl,
    );
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
      contains(predicate<String>((value) => value.startsWith('bytes=0-'))),
    );
    expect(observedRanges, contains('bytes=4-'));
    expect(
      observedTargets.where((value) => value.contains('start.mp4')).length,
      1,
    );
  });

  test('StreamPreloadService merges concurrent in-flight requests', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() async {
      await server.close(force: true);
    });

    var requestCount = 0;
    server.listen((HttpRequest request) async {
      requestCount++;
      await Future<void>.delayed(const Duration(milliseconds: 120));
      request.response.statusCode = 206;
      request.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
      request.response.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes 0-7/8',
      );
      request.response.headers.contentType = ContentType('video', 'mp4');
      request.response.contentLength = 8;
      request.response.add(const <int>[0, 1, 2, 3, 4, 5, 6, 7]);
      await request.response.close();
    });

    final url = 'http://127.0.0.1:${server.port}/shared.mp4';
    final request = PreloadRequest(
      resolvedSource: ResolvedPlaybackSource(
        itemId: 'episode-concurrent',
        playSessionId: 'ps-concurrent',
        mediaSourceId: 'ms-concurrent',
        url: url,
        httpHeaders: const <String, String>{'User-Agent': 'SourceUA/1.0'},
        isExternal: false,
        mediaTypeHint: ResolvedPlaybackMediaType.file,
        fromStrm: false,
        redirectChain: <String>[url],
        bitrate: 8000000,
        sizeBytes: 8000000,
      ),
      triggerSource: 'detail_current',
    );

    final results = await Future.wait<StreamPreloadResult>([
      StreamPreloadService.instance.preloadResolvedSource(request),
      StreamPreloadService.instance.preloadResolvedSource(request),
    ]);

    expect(results.map((entry) => entry.status).toList(), <StreamPreloadStatus>[
      StreamPreloadStatus.success,
      StreamPreloadStatus.success,
    ]);
    expect(requestCount, 1);
  });

  test(
      'StreamPreloadService preloads HLS master playlist with init and first segments',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() async {
      await server.close(force: true);
    });

    final hits = <String, int>{};
    server.listen((HttpRequest request) async {
      final path = request.uri.path;
      hits[path] = (hits[path] ?? 0) + 1;

      switch (path) {
        case '/master.m3u8':
          request.response.statusCode = 200;
          request.response.headers.contentType =
              ContentType('application', 'vnd.apple.mpegurl');
          request.response.write(
            '#EXTM3U\n'
            '#EXT-X-STREAM-INF:BANDWIDTH=2000000\n'
            'variant.m3u8\n',
          );
          break;
        case '/variant.m3u8':
          request.response.statusCode = 200;
          request.response.headers.contentType =
              ContentType('application', 'vnd.apple.mpegurl');
          request.response.write(
            '#EXTM3U\n'
            '#EXT-X-MAP:URI="init.mp4"\n'
            '#EXTINF:1.5,\n'
            'seg1.ts\n'
            '#EXTINF:1.5,\n'
            'seg2.ts\n'
            '#EXTINF:1.5,\n'
            'seg3.ts\n',
          );
          break;
        case '/init.mp4':
          request.response.statusCode = 200;
          request.response.headers.contentType = ContentType('video', 'mp4');
          request.response.add(const <int>[0, 1, 2, 3]);
          break;
        case '/seg1.ts':
        case '/seg2.ts':
        case '/seg3.ts':
          request.response.statusCode = 200;
          request.response.headers.contentType = ContentType('video', 'mp2t');
          request.response.add(const <int>[0, 1, 2, 3, 4, 5, 6, 7]);
          break;
        default:
          request.response.statusCode = 404;
      }

      await request.response.close();
    });

    final url = 'http://127.0.0.1:${server.port}/master.m3u8';
    final result = await StreamPreloadService.instance.preloadResolvedSource(
      PreloadRequest(
        resolvedSource: ResolvedPlaybackSource(
          itemId: 'episode-hls',
          playSessionId: 'ps-hls',
          mediaSourceId: 'ms-hls',
          url: url,
          httpHeaders: const <String, String>{'User-Agent': 'SourceUA/1.0'},
          isExternal: false,
          mediaTypeHint: ResolvedPlaybackMediaType.hls,
          fromStrm: false,
          redirectChain: <String>[url],
          bitrate: 4000000,
          sizeBytes: 4000000,
        ),
        triggerSource: 'detail_current',
      ),
    );

    expect(result.status, StreamPreloadStatus.success);
    expect(hits['/master.m3u8'], 1);
    expect(hits['/variant.m3u8'], 1);
    expect(hits['/init.mp4'], 1);
    expect(hits['/seg1.ts'], 1);
    expect(hits['/seg2.ts'], 1);
    expect(hits.containsKey('/seg3.ts'), isFalse);
  });

  test('StreamPreloadService picks the HLS variant closest to source bitrate',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() async {
      await server.close(force: true);
    });

    final hits = <String, int>{};
    server.listen((HttpRequest request) async {
      final path = request.uri.path;
      hits[path] = (hits[path] ?? 0) + 1;

      switch (path) {
        case '/master.m3u8':
          request.response.statusCode = HttpStatus.ok;
          request.response.headers.contentType =
              ContentType('application', 'vnd.apple.mpegurl');
          request.response.write(
            '#EXTM3U\n'
            '#EXT-X-STREAM-INF:BANDWIDTH=1200000\n'
            'low.m3u8\n'
            '#EXT-X-STREAM-INF:BANDWIDTH=5000000\n'
            'high.m3u8\n',
          );
          break;
        case '/low.m3u8':
          request.response.statusCode = HttpStatus.ok;
          request.response.headers.contentType =
              ContentType('application', 'vnd.apple.mpegurl');
          request.response.write(
            '#EXTM3U\n'
            '#EXTINF:2.0,\n'
            'low1.ts\n',
          );
          break;
        case '/high.m3u8':
          request.response.statusCode = HttpStatus.ok;
          request.response.headers.contentType =
              ContentType('application', 'vnd.apple.mpegurl');
          request.response.write(
            '#EXTM3U\n'
            '#EXTINF:2.0,\n'
            'high1.ts\n',
          );
          break;
        case '/low1.ts':
        case '/high1.ts':
          request.response.statusCode = HttpStatus.ok;
          request.response.headers.contentType = ContentType('video', 'mp2t');
          request.response.add(const <int>[0, 1, 2, 3]);
          break;
        default:
          request.response.statusCode = HttpStatus.notFound;
      }

      await request.response.close();
    });

    final url = 'http://127.0.0.1:${server.port}/master.m3u8';
    final result = await StreamPreloadService.instance.preloadResolvedSource(
      PreloadRequest(
        resolvedSource: ResolvedPlaybackSource(
          itemId: 'episode-hls-closest',
          playSessionId: 'ps-hls-closest',
          mediaSourceId: 'ms-hls-closest',
          url: url,
          httpHeaders: const <String, String>{'User-Agent': 'SourceUA/1.0'},
          isExternal: false,
          mediaTypeHint: ResolvedPlaybackMediaType.hls,
          fromStrm: false,
          redirectChain: <String>[url],
          bitrate: 1500000,
          sizeBytes: 4000000,
        ),
        triggerSource: 'detail_current',
      ),
    );

    expect(result.status, StreamPreloadStatus.success);
    expect(hits['/master.m3u8'], 1);
    expect(hits['/low.m3u8'], 1);
    expect(hits.containsKey('/high.m3u8'), isFalse);
    expect(hits['/low1.ts'], 1);
    expect(hits.containsKey('/high1.ts'), isFalse);
  });

  test(
    'StreamPreloadService preloads HLS media playlist from the resume-aligned segment',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() async {
        await server.close(force: true);
      });

      final hits = <String, int>{};
      server.listen((HttpRequest request) async {
        final path = request.uri.path;
        hits[path] = (hits[path] ?? 0) + 1;

        switch (path) {
          case '/media.m3u8':
            request.response.statusCode = 200;
            request.response.headers.contentType =
                ContentType('application', 'vnd.apple.mpegurl');
            request.response.write(
              '#EXTM3U\n'
              '#EXTINF:2.0,\n'
              'seg1.ts\n'
              '#EXTINF:2.0,\n'
              'seg2.ts\n'
              '#EXTINF:2.0,\n'
              'seg3.ts\n',
            );
            break;
          case '/seg1.ts':
          case '/seg2.ts':
          case '/seg3.ts':
            request.response.statusCode = 200;
            request.response.headers.contentType = ContentType('video', 'mp2t');
            request.response.add(const <int>[0, 1, 2, 3, 4, 5, 6, 7]);
            break;
          default:
            request.response.statusCode = 404;
        }

        await request.response.close();
      });

      final url = 'http://127.0.0.1:${server.port}/media.m3u8';
      final result = await StreamPreloadService.instance.preloadResolvedSource(
        PreloadRequest(
          resolvedSource: ResolvedPlaybackSource(
            itemId: 'episode-hls-media',
            playSessionId: 'ps-hls-media',
            mediaSourceId: 'ms-hls-media',
            url: url,
            httpHeaders: const <String, String>{'User-Agent': 'SourceUA/1.0'},
            isExternal: false,
            mediaTypeHint: ResolvedPlaybackMediaType.hls,
            fromStrm: false,
            redirectChain: <String>[url],
            bitrate: 4000000,
            sizeBytes: 4000000,
          ),
          triggerSource: 'playback_resume',
          startPosition: const Duration(seconds: 3),
        ),
      );

      expect(result.status, StreamPreloadStatus.success);
      expect(hits['/media.m3u8'], 1);
      expect(hits.containsKey('/seg1.ts'), isFalse);
      expect(hits['/seg2.ts'], 1);
      expect(hits['/seg3.ts'], 1);
    },
  );

  test(
    'Preloaded HLS assets are reused by the local playback HLS proxy',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() async {
        await server.close(force: true);
      });

      final hits = <String, int>{};
      server.listen((HttpRequest request) async {
        final path = request.uri.path;
        hits[path] = (hits[path] ?? 0) + 1;

        switch (path) {
          case '/media.m3u8':
            request.response.statusCode = HttpStatus.ok;
            request.response.headers.contentType =
                ContentType('application', 'vnd.apple.mpegurl');
            request.response.write(
              '#EXTM3U\n'
              '#EXT-X-MAP:URI="init.mp4"\n'
              '#EXTINF:2.0,\n'
              'seg1.ts\n'
              '#EXTINF:2.0,\n'
              'seg2.ts\n',
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
          case '/seg2.ts':
            request.response.statusCode = HttpStatus.ok;
            request.response.headers.contentType = ContentType('video', 'mp2t');
            request.response.add(const <int>[8, 9, 10, 11]);
            break;
          default:
            request.response.statusCode = HttpStatus.notFound;
        }

        await request.response.close();
      });

      final url = 'http://127.0.0.1:${server.port}/media.m3u8';
      final resolvedSource = ResolvedPlaybackSource(
        itemId: 'episode-hls-reuse',
        playSessionId: 'ps-hls-reuse',
        mediaSourceId: 'ms-hls-reuse',
        url: url,
        httpHeaders: const <String, String>{'User-Agent': 'SourceUA/1.0'},
        isExternal: false,
        mediaTypeHint: ResolvedPlaybackMediaType.hls,
        fromStrm: false,
        redirectChain: <String>[url],
        bitrate: 4000000,
        sizeBytes: 4000000,
      );

      final preload = await StreamPreloadService.instance.preloadResolvedSource(
        PreloadRequest(
          resolvedSource: resolvedSource,
          triggerSource: 'detail_current',
        ),
      );

      expect(preload.status, StreamPreloadStatus.success);
      expect(hits['/init.mp4'], 1);
      expect(hits['/seg1.ts'], 1);

      final proxied = await LocalHttpStreamProxy.wrapPlaybackSource(
        PlayableSource(
          url: resolvedSource.url,
          httpHeaders: resolvedSource.httpHeaders,
          mediaTypeHint: StreamMediaType.hls,
          fromStrm: false,
          redirectChain: resolvedSource.redirectChain,
        ),
        cacheKey: buildResolvedPlaybackCacheKey(resolvedSource),
      );
      expect(proxied, isNotNull);

      final client = HttpClient();
      addTearDown(() {
        client.close(force: true);
      });

      final playlistResponse =
          await (await client.getUrl(Uri.parse(proxied!.url))).close();
      final playlistText = utf8.decode(
        await playlistResponse.fold<List<int>>(
          <int>[],
          (acc, chunk) => <int>[...acc, ...chunk],
        ),
        allowMalformed: true,
      );
      final streamUrls = RegExp(r'http://127\.0\.0\.1:\d+/stream/[^\s]+')
          .allMatches(playlistText)
          .map((match) => match.group(0)!)
          .toList(growable: false);

      expect(streamUrls.length, greaterThanOrEqualTo(2));

      final initResponse =
          await (await client.getUrl(Uri.parse(streamUrls[0]))).close();
      final initBytes = await initResponse.fold<List<int>>(
        <int>[],
        (acc, chunk) => <int>[...acc, ...chunk],
      );
      final seg1Response =
          await (await client.getUrl(Uri.parse(streamUrls[1]))).close();
      final seg1Bytes = await seg1Response.fold<List<int>>(
        <int>[],
        (acc, chunk) => <int>[...acc, ...chunk],
      );

      expect(initResponse.statusCode, HttpStatus.ok);
      expect(initBytes, <int>[0, 1, 2, 3]);
      expect(seg1Response.statusCode, HttpStatus.ok);
      expect(seg1Bytes, <int>[4, 5, 6, 7]);
      expect(hits['/init.mp4'], 1);
      expect(hits['/seg1.ts'], 1);
    },
  );

  test('StreamPreloadService opens scoped circuit and recovers after TTL',
      () async {
    final service = StreamPreloadService.instance;
    var now = DateTime.utc(2026, 4, 1, 0, 0, 0);
    service.debugResetForTest(nowProvider: () => now);

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() async {
      await server.close(force: true);
    });

    var requestCount = 0;
    var failMode = true;
    server.listen((HttpRequest request) async {
      requestCount++;
      if (failMode) {
        request.response.statusCode = 503;
        await request.response.close();
        return;
      }
      request.response.statusCode = 206;
      request.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
      request.response.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes 0-7/8',
      );
      request.response.headers.contentType = ContentType('video', 'mp4');
      request.response.contentLength = 8;
      request.response.add(const <int>[0, 1, 2, 3, 4, 5, 6, 7]);
      await request.response.close();
    });

    final url = 'http://127.0.0.1:${server.port}/unstable.mp4';
    final request = PreloadRequest(
      resolvedSource: ResolvedPlaybackSource(
        itemId: 'episode-2',
        playSessionId: 'ps-unstable',
        mediaSourceId: 'ms-unstable',
        url: url,
        httpHeaders: const <String, String>{'User-Agent': 'SourceUA/1.0'},
        isExternal: false,
        mediaTypeHint: ResolvedPlaybackMediaType.file,
        fromStrm: false,
        redirectChain: <String>[url],
        bitrate: 8000000,
        sizeBytes: 8000000,
      ),
      triggerSource: 'playback_next',
    );

    final first = await service.preloadResolvedSource(request);
    final second = await service.preloadResolvedSource(request);
    final skipped = await service.preloadResolvedSource(request);

    expect(first.status, StreamPreloadStatus.failed);
    expect(second.status, StreamPreloadStatus.failedDisabled);
    expect(skipped.status, StreamPreloadStatus.skippedDisabled);
    expect(requestCount, 6);
    expect(service.buildDiagnosticsText(), contains('activeCircuits: 1'));

    failMode = false;
    now = now.add(const Duration(minutes: 3));

    final recovered = await service.preloadResolvedSource(request);
    expect(recovered.status, StreamPreloadStatus.success);
    expect(requestCount, 7);
    expect(service.buildDiagnosticsText(), contains('activeCircuits: 0'));
  });
}

class _FakeAdapter extends Fake implements MediaServerAdapter {
  _FakeAdapter({
    required this.playbackInfo,
    this.streamHeaders = const <String, String>{},
  });

  final PlaybackInfoResult playbackInfo;
  final Map<String, String> streamHeaders;

  @override
  MediaServerType get serverType => MediaServerType.emby;

  @override
  String get deviceId => 'device-test';

  @override
  Map<String, String> buildStreamHeaders(ServerAuthSession auth) =>
      streamHeaders;

  @override
  Future<PlaybackInfoResult> fetchPlaybackInfo(
    ServerAuthSession auth, {
    required String itemId,
    bool exoPlayer = false,
  }) async {
    return playbackInfo;
  }
}

String? _headerValue(Map<String, String> headers, String name) {
  final lower = name.trim().toLowerCase();
  for (final entry in headers.entries) {
    if (entry.key.trim().toLowerCase() == lower) return entry.value;
  }
  return null;
}
