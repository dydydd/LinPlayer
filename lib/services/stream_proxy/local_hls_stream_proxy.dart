import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:lin_player_player/lin_player_player.dart';
import 'package:lin_player_server_api/services/http_stream_proxy.dart';

class LocalHlsStreamProxy {
  LocalHlsStreamProxy._();

  static final LocalHlsStreamProxy instance = LocalHlsStreamProxy._();

  HttpServer? _server;
  Uri? _baseUri;
  final Map<String, _LocalHlsPlaylistEntry> _entries =
      <String, _LocalHlsPlaylistEntry>{};

  Future<Uri> registerPlaylist({
    required Uri remoteUri,
    required Map<String, String> httpHeaders,
    HttpStreamCacheKey? rootCacheKey,
    int? preferredVariantBitrate,
  }) async {
    final baseKey = _playlistCacheKeyFor(
      remoteUri: remoteUri,
      httpHeaders: httpHeaders,
      rootCacheKey: rootCacheKey,
    ).fingerprint;
    final normalizedPreferredBitrate =
        preferredVariantBitrate != null && preferredVariantBitrate > 0
            ? preferredVariantBitrate
            : null;
    final key = normalizedPreferredBitrate == null
        ? baseKey
        : '$baseKey-bw$normalizedPreferredBitrate';
    _entries.putIfAbsent(
      key,
      () => _LocalHlsPlaylistEntry(
        id: key,
        remoteUri: remoteUri,
        httpHeaders: Map<String, String>.unmodifiable(httpHeaders),
        rootCacheKey: rootCacheKey,
        preferredVariantBitrate: normalizedPreferredBitrate,
      ),
    );
    final baseUri = await _ensureStarted();
    return baseUri.resolve('hls/$key/index.m3u8');
  }

  Future<void> debugResetForTest() async {
    _entries.clear();
    final server = _server;
    _server = null;
    _baseUri = null;
    if (server != null) {
      await server.close(force: true);
    }
  }

  Future<Uri> _ensureStarted() async {
    final existing = _baseUri;
    if (existing != null && _server != null) return existing;
    final server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
      shared: true,
    );
    _server = server;
    _baseUri = Uri.parse('http://${server.address.address}:${server.port}/');
    unawaited(_serve(server));
    return _baseUri!;
  }

  Future<void> _serve(HttpServer server) async {
    await for (final request in server) {
      unawaited(_handleRequest(request));
    }
  }

  Future<void> _handleRequest(HttpRequest request) async {
    try {
      final segments = request.uri.pathSegments;
      if (segments.length < 3 || segments[0] != 'hls') {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        return;
      }
      if (request.method != 'GET' && request.method != 'HEAD') {
        request.response.statusCode = HttpStatus.methodNotAllowed;
        await request.response.close();
        return;
      }

      final entry = _entries[segments[1]];
      if (entry == null) {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        return;
      }

      final fetched = await _fetchPlaylist(entry);
      if (fetched == null) {
        request.response.statusCode = HttpStatus.badGateway;
        await request.response.close();
        return;
      }

      final rewritten = await _rewritePlaylist(
        fetched.text,
        baseUri: fetched.effectiveUri,
        entry: entry,
      );
      request.response.statusCode = HttpStatus.ok;
      request.response.headers.contentType =
          ContentType('application', 'vnd.apple.mpegurl');
      request.response.headers.set(
        HttpHeaders.cacheControlHeader,
        'no-cache, no-store, must-revalidate',
      );
      if (request.method == 'GET') {
        request.response.write(rewritten);
      }
      await request.response.close();
    } catch (_) {
      try {
        request.response.statusCode = HttpStatus.internalServerError;
        await request.response.close();
      } catch (_) {}
    }
  }

  Future<_FetchedHlsPlaylist?> _fetchPlaylist(
    _LocalHlsPlaylistEntry entry,
  ) async {
    try {
      final proxyUri = await HttpStreamProxyServer.instance.registerStream(
        remoteUri: entry.remoteUri,
        httpHeaders: entry.httpHeaders,
        fileName: _suggestFileName(
          entry.remoteUri,
          fallback: 'playlist.m3u8',
        ),
        cacheKey: _playlistCacheKeyFor(
          remoteUri: entry.remoteUri,
          httpHeaders: entry.httpHeaders,
          rootCacheKey: entry.rootCacheKey,
        ),
      );
      final client = HttpClient()..findProxy = (_) => 'DIRECT';
      try {
        final request = await client.getUrl(proxyUri);
        final response = await request.close();
        if (response.statusCode < 200 || response.statusCode >= 300) {
          return null;
        }
        final bytes = await response.fold<List<int>>(
          <int>[],
          (acc, chunk) => <int>[...acc, ...chunk],
        );
        final rawEffectiveUri = response.headers
            .value(HttpStreamProxyServer.effectiveRemoteUrlHeader);
        final effectiveUri =
            Uri.tryParse((rawEffectiveUri ?? '').trim()) ?? entry.remoteUri;
        return _FetchedHlsPlaylist(
          effectiveUri: effectiveUri,
          text: utf8.decode(bytes, allowMalformed: true),
        );
      } finally {
        client.close(force: true);
      }
    } catch (_) {
      return null;
    }
  }

  Future<String> _rewritePlaylist(
    String text, {
    required Uri baseUri,
    required _LocalHlsPlaylistEntry entry,
  }) async {
    final normalized = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final lines = normalized.split('\n');
    final isMediaPlaylist = _looksLikeMediaPlaylist(lines);
    if (!isMediaPlaylist) {
      final pinned = await _rewritePinnedVariantMasterPlaylist(
        lines,
        baseUri: baseUri,
        entry: entry,
      );
      if (pinned != null) return pinned;
    }
    final output = <String>[];
    var expectingVariantUri = false;

    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty) {
        output.add(rawLine);
        continue;
      }

      if (expectingVariantUri && !line.startsWith('#')) {
        final variantUri = baseUri.resolve(line);
        output.add(await _proxyPlaylistUri(variantUri, entry));
        expectingVariantUri = false;
        continue;
      }

      if (line.startsWith('#EXT-X-STREAM-INF')) {
        output.add(rawLine);
        expectingVariantUri = true;
        continue;
      }

      if (isMediaPlaylist) {
        if (!line.startsWith('#')) {
          output.add(await _proxyBinaryUri(baseUri.resolve(line), entry));
          continue;
        }
        output.add(
          await _rewriteUriAttribute(
            rawLine,
            baseUri: baseUri,
            entry: entry,
            asPlaylist: false,
          ),
        );
        continue;
      }

      if (!line.startsWith('#')) {
        output.add(await _proxyPlaylistUri(baseUri.resolve(line), entry));
        continue;
      }

      final asPlaylist = line.startsWith('#EXT-X-MEDIA') ||
          line.startsWith('#EXT-X-I-FRAME-STREAM-INF');
      output.add(
        await _rewriteUriAttribute(
          rawLine,
          baseUri: baseUri,
          entry: entry,
          asPlaylist: asPlaylist,
        ),
      );
    }

    return output.join('\n');
  }

  Future<String?> _rewritePinnedVariantMasterPlaylist(
    List<String> lines, {
    required Uri baseUri,
    required _LocalHlsPlaylistEntry entry,
  }) async {
    final preferred = entry.preferredVariantBitrate;
    if (preferred == null || preferred <= 0) return null;

    final variants = <_HlsVariantLine>[];
    for (var i = 0; i < lines.length - 1; i++) {
      final line = lines[i].trim();
      if (!line.startsWith('#EXT-X-STREAM-INF')) continue;
      final nextLine = lines[i + 1].trim();
      if (nextLine.isEmpty || nextLine.startsWith('#')) continue;
      final bandwidthMatch = RegExp(r'BANDWIDTH=(\d+)').firstMatch(line);
      variants.add(
        _HlsVariantLine(
          tagLineIndex: i,
          uriLineIndex: i + 1,
          bandwidth: int.tryParse(bandwidthMatch?.group(1) ?? '') ?? 0,
          uri: baseUri.resolve(nextLine),
        ),
      );
    }
    if (variants.isEmpty) return null;

    variants.sort((a, b) {
      final aDistance = (a.bandwidth - preferred).abs();
      final bDistance = (b.bandwidth - preferred).abs();
      if (aDistance != bDistance) return aDistance.compareTo(bDistance);
      if (a.bandwidth != b.bandwidth) return a.bandwidth.compareTo(b.bandwidth);
      return a.tagLineIndex.compareTo(b.tagLineIndex);
    });
    final chosen = variants.first;

    final output = <String>[];
    for (var i = 0; i < lines.length; i++) {
      final rawLine = lines[i];
      final line = rawLine.trim();
      if (line.isEmpty) {
        output.add(rawLine);
        continue;
      }
      if (line.startsWith('#EXT-X-STREAM-INF')) {
        if (i == chosen.tagLineIndex) {
          output.add(rawLine);
          output.add(await _proxyPlaylistUri(chosen.uri, entry));
        }
        i += 1;
        continue;
      }
      if (i == chosen.uriLineIndex) continue;
      if (!line.startsWith('#')) continue;

      final asPlaylist = line.startsWith('#EXT-X-MEDIA') ||
          line.startsWith('#EXT-X-I-FRAME-STREAM-INF');
      output.add(
        await _rewriteUriAttribute(
          rawLine,
          baseUri: baseUri,
          entry: entry,
          asPlaylist: asPlaylist,
        ),
      );
    }
    return output.join('\n');
  }

  bool _looksLikeMediaPlaylist(List<String> lines) {
    for (final raw in lines) {
      final line = raw.trim();
      if (line.startsWith('#EXTINF') ||
          line.startsWith('#EXT-X-TARGETDURATION') ||
          line.startsWith('#EXT-X-MEDIA-SEQUENCE') ||
          line.startsWith('#EXT-X-MAP') ||
          line.startsWith('#EXT-X-PART') ||
          line.startsWith('#EXT-X-ENDLIST')) {
        return true;
      }
    }
    return false;
  }

  Future<String> _rewriteUriAttribute(
    String rawLine, {
    required Uri baseUri,
    required _LocalHlsPlaylistEntry entry,
    required bool asPlaylist,
  }) async {
    final match = RegExp(r'URI=\"([^\"]+)\"').firstMatch(rawLine);
    if (match == null) return rawLine;
    final rawUri = (match.group(1) ?? '').trim();
    if (rawUri.isEmpty) return rawLine;
    final resolved = baseUri.resolve(rawUri);
    final replacement = asPlaylist
        ? await _proxyPlaylistUri(resolved, entry)
        : await _proxyBinaryUri(resolved, entry);
    return rawLine.replaceRange(match.start + 5, match.end - 1, replacement);
  }

  Future<String> _proxyPlaylistUri(
    Uri remoteUri,
    _LocalHlsPlaylistEntry entry,
  ) async {
    final proxied = await registerPlaylist(
      remoteUri: remoteUri,
      httpHeaders: entry.httpHeaders,
      rootCacheKey: entry.rootCacheKey,
      preferredVariantBitrate: entry.preferredVariantBitrate,
    );
    return proxied.toString();
  }

  Future<String> _proxyBinaryUri(
    Uri remoteUri,
    _LocalHlsPlaylistEntry entry,
  ) async {
    final cacheKey = buildNetworkPlaybackCacheKey(
      remoteUri: remoteUri,
      httpHeaders: entry.httpHeaders,
      mediaSourceId: entry.rootCacheKey?.mediaSourceId,
      proxyUrl: entry.rootCacheKey?.proxyUrl,
    );
    final proxied = await HttpStreamProxyServer.instance.registerStream(
      remoteUri: remoteUri,
      httpHeaders: entry.httpHeaders,
      fileName: _suggestFileName(remoteUri),
      cacheKey: cacheKey,
    );
    return proxied.toString();
  }

  HttpStreamCacheKey _playlistCacheKeyFor({
    required Uri remoteUri,
    required Map<String, String> httpHeaders,
    required HttpStreamCacheKey? rootCacheKey,
  }) {
    return buildNetworkPlaybackCacheKey(
      remoteUri: remoteUri,
      httpHeaders: httpHeaders,
      mediaSourceId: rootCacheKey?.mediaSourceId,
      proxyUrl: rootCacheKey?.proxyUrl,
    );
  }

  String _suggestFileName(Uri uri, {String fallback = 'segment.bin'}) {
    if (uri.pathSegments.isNotEmpty) {
      final last = uri.pathSegments.last.trim();
      if (last.isNotEmpty) return last;
    }
    return fallback;
  }
}

class _LocalHlsPlaylistEntry {
  const _LocalHlsPlaylistEntry({
    required this.id,
    required this.remoteUri,
    required this.httpHeaders,
    required this.rootCacheKey,
    required this.preferredVariantBitrate,
  });

  final String id;
  final Uri remoteUri;
  final Map<String, String> httpHeaders;
  final HttpStreamCacheKey? rootCacheKey;
  final int? preferredVariantBitrate;
}

class _FetchedHlsPlaylist {
  const _FetchedHlsPlaylist({
    required this.effectiveUri,
    required this.text,
  });

  final Uri effectiveUri;
  final String text;
}

class _HlsVariantLine {
  const _HlsVariantLine({
    required this.tagLineIndex,
    required this.uriLineIndex,
    required this.bandwidth,
    required this.uri,
  });

  final int tagLineIndex;
  final int uriLineIndex;
  final int bandwidth;
  final Uri uri;
}
