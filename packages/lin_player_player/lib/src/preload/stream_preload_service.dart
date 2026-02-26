import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:lin_player_prefs/lin_player_prefs.dart';
import 'package:lin_player_server_adapters/lin_player_server_adapters.dart';

enum StreamPreloadStatus {
  skippedDisabled,
  skippedAlreadyDone,
  success,
  failedDisabled,
}

@immutable
class StreamPreloadResult {
  const StreamPreloadResult(this.status, {this.error});

  final StreamPreloadStatus status;
  final Object? error;

  bool get disabledNow => status == StreamPreloadStatus.failedDisabled;
}

class StreamPreloadService {
  StreamPreloadService._();

  static final StreamPreloadService instance = StreamPreloadService._();

  static const String preloadUserAgent = 'preload-linplayer';
  static const Duration preloadDuration = Duration(seconds: 3);
  static const int maxAttempts = 3;

  static const int _minBytes = 256 * 1024;
  static const int _maxBytes = 24 * 1024 * 1024;

  bool _permanentlyDisabled = false;
  bool get permanentlyDisabled => _permanentlyDisabled;

  final Set<String> _doneKeys = <String>{};
  final Map<String, Future<StreamPreloadResult>> _inFlight =
      <String, Future<StreamPreloadResult>>{};

  String _keyFor(ServerAuthSession auth, String itemId) {
    final base = auth.baseUrl.trim().toLowerCase();
    final id = itemId.trim();
    return '$base|$id';
  }

  Future<StreamPreloadResult> preloadFirst3Seconds({
    required MediaServerAdapter adapter,
    required ServerAuthSession auth,
    required String itemId,
    bool exoPlayer = false,
    String? selectedMediaSourceId,
    int? audioStreamIndex,
    int? subtitleStreamIndex,
    VideoVersionPreference preferredVideoVersion =
        VideoVersionPreference.defaultVersion,
    String? httpProxyUrl,
  }) async {
    final key = _keyFor(auth, itemId);
    if (_permanentlyDisabled) {
      return const StreamPreloadResult(StreamPreloadStatus.skippedDisabled);
    }
    if (_doneKeys.contains(key)) {
      return const StreamPreloadResult(StreamPreloadStatus.skippedAlreadyDone);
    }

    final inFlight = _inFlight[key];
    if (inFlight != null) return inFlight;

    final run = () async {
      Object? lastError;

      for (var attempt = 0; attempt < maxAttempts; attempt++) {
        try {
          final info = await adapter.fetchPlaybackInfo(
            auth,
            itemId: itemId,
            exoPlayer: exoPlayer,
          );
          final sources = info.mediaSources.cast<Map<String, dynamic>>();
          final chosenMediaSourceId = _resolveMediaSourceId(
            sources: sources,
            selectedMediaSourceId: selectedMediaSourceId,
            preferred: preferredVideoVersion,
          );
          final ms = _findMediaSource(
            sources,
            chosenMediaSourceId,
          );
          final streamUrl = _buildStreamUrl(
            auth: auth,
            adapterDeviceId: adapter.deviceId,
            itemId: itemId,
            info: info,
            mediaSource: ms,
            exoPlayer: exoPlayer,
            audioStreamIndex: audioStreamIndex,
            subtitleStreamIndex: subtitleStreamIndex,
          );
          final bitrate = _asInt(ms?['Bitrate']);
          final bytesToFetch = _estimateBytesToFetch(bitrate);
          final headers = <String, String>{
            ...adapter.buildStreamHeaders(auth),
            'User-Agent': preloadUserAgent,
          };
          final ok = await _prefetch(
            url: streamUrl,
            headers: headers,
            bytesToFetch: bytesToFetch,
            httpProxyUrl: httpProxyUrl,
          );
          if (ok) {
            _doneKeys.add(key);
            return const StreamPreloadResult(StreamPreloadStatus.success);
          }
        } catch (e) {
          lastError = e;
        }

        if (attempt < maxAttempts - 1) {
          await Future<void>.delayed(
            Duration(milliseconds: attempt == 0 ? 180 : 320),
          );
        }
      }

      _permanentlyDisabled = true;
      return StreamPreloadResult(
        StreamPreloadStatus.failedDisabled,
        error: lastError,
      );
    }();

    _inFlight[key] = run;
    try {
      return await run;
    } finally {
      _inFlight.remove(key);
    }
  }

  int _estimateBytesToFetch(int? bitrateBitsPerSecond) {
    final bps = bitrateBitsPerSecond ?? 0;
    if (bps <= 0) return _minBytes;
    final bytesPerSecond = bps / 8.0;
    final estimated = (bytesPerSecond * preloadDuration.inSeconds).round();
    return estimated.clamp(_minBytes, _maxBytes);
  }

  Future<bool> _prefetch({
    required String url,
    required Map<String, String> headers,
    required int bytesToFetch,
    String? httpProxyUrl,
  }) async {
    if (kIsWeb) return false;
    final uri = Uri.tryParse(url);
    if (uri == null) return false;

    final client = LinHttpClientFactory.createHttpClient(
      _overrideConfig(httpProxyUrl),
    );
    try {
      return await _prefetchUri(
        client: client,
        uri: uri,
        headers: headers,
        bytesToFetch: bytesToFetch,
      );
    } finally {
      try {
        client.close(force: true);
      } catch (_) {}
    }
  }

  LinHttpClientConfig _overrideConfig(String? httpProxyUrl) {
    final base = LinHttpClientFactory.config;
    final proxy = (httpProxyUrl ?? '').trim();
    final proxyUri = proxy.isEmpty ? null : Uri.tryParse(proxy);
    final hasProxy = proxyUri != null &&
        proxyUri.host.trim().isNotEmpty &&
        proxyUri.port > 0 &&
        proxyUri.port <= 65535;

    LinProxyResolver? proxyResolver;
    if (hasProxy) {
      final host = proxyUri.host;
      final port = proxyUri.port;
      proxyResolver = (_) => 'PROXY $host:$port';
    }

    return base.copyWith(
      userAgent: preloadUserAgent,
      connectionTimeout: const Duration(seconds: 8),
      idleTimeout: const Duration(seconds: 8),
      maxConnectionsPerHost: 4,
      proxyResolver: proxyResolver,
    );
  }

  Future<bool> _prefetchUri({
    required HttpClient client,
    required Uri uri,
    required Map<String, String> headers,
    required int bytesToFetch,
  }) async {
    final first = await _get(
      client: client,
      uri: uri,
      headers: headers,
      rangeBytes: bytesToFetch,
      captureLimitBytes: 512 * 1024,
    );
    if (!first.ok) return false;

    final playlistText = _asHlsPlaylistText(first);
    if (playlistText == null) {
      return first.bytesRead > 0;
    }

    final playlistUri = first.effectiveUri;
    return _prefetchHls(
      client: client,
      playlistUri: playlistUri,
      playlistText: playlistText,
      headers: headers,
    );
  }

  Future<bool> _prefetchHls({
    required HttpClient client,
    required Uri playlistUri,
    required String playlistText,
    required Map<String, String> headers,
  }) async {
    var parsed = _parseHls(playlistText, base: playlistUri);
    if (parsed == null) return false;

    if (parsed.variantPlaylistUri != null) {
      final variant = await _get(
        client: client,
        uri: parsed.variantPlaylistUri!,
        headers: headers,
        rangeBytes: 512 * 1024,
        captureLimitBytes: 1024 * 1024,
      );
      if (!variant.ok) return false;
      final text = _asHlsPlaylistText(variant);
      if (text == null) return false;
      parsed = _parseHls(text, base: variant.effectiveUri);
      if (parsed == null) return false;
    }

    if (parsed.initSegmentUri != null) {
      final init = await _get(
        client: client,
        uri: parsed.initSegmentUri!,
        headers: headers,
        rangeBytes: null,
        captureLimitBytes: 0,
      );
      if (!init.ok) return false;
    }

    var remainingMs = preloadDuration.inMilliseconds;
    var fetchedAny = false;
    var segmentCount = 0;
    for (final seg in parsed.segments) {
      if (remainingMs <= 0) break;
      if (segmentCount >= 3) break;

      final r = await _get(
        client: client,
        uri: seg.uri,
        headers: headers,
        rangeBytes: null,
        captureLimitBytes: 0,
      );
      if (!r.ok) return false;
      fetchedAny = true;
      segmentCount++;

      final durMs = seg.durationMs > 0 ? seg.durationMs : preloadDuration.inMilliseconds;
      remainingMs -= durMs;
    }

    return fetchedAny;
  }

  String? _asHlsPlaylistText(StreamPreloadGetResult result) {
    final mime = (result.contentTypeMime ?? '').toLowerCase();
    final looksLikeMime = mime.contains('mpegurl') || mime.contains('m3u8');
    final text = utf8.decode(result.capturedBytes, allowMalformed: true);
    final prefix = text.trimLeft();
    final looksLikeText = prefix.startsWith('#EXTM3U');
    if (!looksLikeMime && !looksLikeText) return null;
    return text;
  }

  Future<StreamPreloadGetResult> _get({
    required HttpClient client,
    required Uri uri,
    required Map<String, String> headers,
    required int? rangeBytes,
    required int captureLimitBytes,
  }) async {
    final request = await client.getUrl(uri).timeout(const Duration(seconds: 8));
    request.followRedirects = true;
    request.maxRedirects = 5;
    headers.forEach((k, v) {
      request.headers.set(k, v);
    });
    if (rangeBytes != null && rangeBytes > 0) {
      request.headers.set(HttpHeaders.rangeHeader, 'bytes=0-${rangeBytes - 1}');
    }

    final response = await request.close().timeout(const Duration(seconds: 10));
    final status = response.statusCode;
    final ok = status == 200 || status == 206;
    final mime = response.headers.contentType?.mimeType;

    var bytesRead = 0;
    final captured = <int>[];

    try {
      await for (final chunk in response.timeout(const Duration(seconds: 10))) {
        bytesRead += chunk.length;
        if (captureLimitBytes > 0 && captured.length < captureLimitBytes) {
          final take =
              (captureLimitBytes - captured.length).clamp(0, chunk.length);
          if (take > 0) {
            captured.addAll(chunk.take(take));
          }
        }
        if (rangeBytes != null &&
            rangeBytes > 0 &&
            status != 206 &&
            bytesRead >= rangeBytes) {
          break;
        }
      }
    } catch (_) {
      // best-effort
    }

    var effective = uri;
    try {
      for (final r in response.redirects) {
        effective = effective.resolveUri(r.location);
      }
    } catch (_) {}

    return StreamPreloadGetResult(
      ok: ok,
      statusCode: status,
      bytesRead: bytesRead,
      capturedBytes: captured,
      contentTypeMime: mime,
      effectiveUri: effective,
    );
  }

  static int? _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  static List<Map<String, dynamic>> _streamsOfType(
    Map<String, dynamic> ms,
    String type,
  ) {
    final streams = (ms['MediaStreams'] as List?) ?? const [];
    return streams
        .where((e) => (e as Map)['Type'] == type)
        .map((e) => e as Map<String, dynamic>)
        .toList();
  }

  static String? _resolveMediaSourceId({
    required List<Map<String, dynamic>> sources,
    required String? selectedMediaSourceId,
    required VideoVersionPreference preferred,
  }) {
    final selected = (selectedMediaSourceId ?? '').trim();
    if (selected.isNotEmpty) return selected;

    if (preferred == VideoVersionPreference.defaultVersion) return null;
    if (sources.isEmpty) return null;

    int heightOf(Map<String, dynamic> ms) {
      final videos = _streamsOfType(ms, 'Video');
      final video = videos.isNotEmpty ? videos.first : null;
      return _asInt(video?['Height']) ?? 0;
    }

    int bitrateOf(Map<String, dynamic> ms) => _asInt(ms['Bitrate']) ?? 0;

    String videoCodecOf(Map<String, dynamic> ms) {
      final msCodec = (ms['VideoCodec'] as String?)?.trim();
      if (msCodec != null && msCodec.isNotEmpty) return msCodec.toLowerCase();
      final videos = _streamsOfType(ms, 'Video');
      final v = videos.isNotEmpty ? videos.first : null;
      final codec = (v?['Codec'] as String?)?.trim() ?? '';
      return codec.toLowerCase();
    }

    bool isHevc(Map<String, dynamic> ms) {
      final c = videoCodecOf(ms);
      return c.contains('hevc') ||
          c.contains('h265') ||
          c.contains('h.265') ||
          c.contains('x265');
    }

    bool isAvc(Map<String, dynamic> ms) {
      final c = videoCodecOf(ms);
      return c.contains('avc') ||
          c.contains('h264') ||
          c.contains('h.264') ||
          c.contains('x264');
    }

    Map<String, dynamic>? pickBest(
      List<Map<String, dynamic>> list, {
      required int Function(Map<String, dynamic> ms) primary,
      required int Function(Map<String, dynamic> ms) secondary,
      required bool higherIsBetter,
    }) {
      if (list.isEmpty) return null;
      Map<String, dynamic> chosen = list.first;
      var bestPrimary = primary(chosen);
      var bestSecondary = secondary(chosen);
      for (final ms in list.skip(1)) {
        final p = primary(ms);
        final s = secondary(ms);
        final better = higherIsBetter
            ? (p > bestPrimary || (p == bestPrimary && s > bestSecondary))
            : (p < bestPrimary || (p == bestPrimary && s < bestSecondary));
        if (better) {
          chosen = ms;
          bestPrimary = p;
          bestSecondary = s;
        }
      }
      return chosen;
    }

    Map<String, dynamic>? chosen;
    switch (preferred) {
      case VideoVersionPreference.highestResolution:
        chosen = pickBest(
          sources,
          primary: heightOf,
          secondary: bitrateOf,
          higherIsBetter: true,
        );
        break;
      case VideoVersionPreference.lowestBitrate:
        chosen = pickBest(
          sources,
          primary: (ms) => bitrateOf(ms) == 0 ? 1 << 30 : bitrateOf(ms),
          secondary: heightOf,
          higherIsBetter: false,
        );
        break;
      case VideoVersionPreference.preferHevc:
        final hevc = sources.where(isHevc).toList();
        chosen = pickBest(
          hevc.isNotEmpty ? hevc : sources,
          primary: heightOf,
          secondary: bitrateOf,
          higherIsBetter: true,
        );
        break;
      case VideoVersionPreference.preferAvc:
        final avc = sources.where(isAvc).toList();
        chosen = pickBest(
          avc.isNotEmpty ? avc : sources,
          primary: heightOf,
          secondary: bitrateOf,
          higherIsBetter: true,
        );
        break;
      case VideoVersionPreference.defaultVersion:
        break;
    }

    final id = chosen?['Id']?.toString().trim();
    return (id == null || id.isEmpty) ? null : id;
  }

  static Map<String, dynamic>? _findMediaSource(
    List<Map<String, dynamic>> sources,
    String? mediaSourceId,
  ) {
    if (sources.isEmpty) return null;
    final id = (mediaSourceId ?? '').trim();
    if (id.isEmpty) return sources.first;
    return sources.firstWhere(
      (s) => (s['Id']?.toString() ?? '').trim() == id,
      orElse: () => sources.first,
    );
  }

  static String _normalizeApiPrefix(String raw) {
    var v = raw.trim();
    while (v.startsWith('/')) {
      v = v.substring(1);
    }
    while (v.endsWith('/')) {
      v = v.substring(0, v.length - 1);
    }
    return v;
  }

  static String _apiUrlWithPrefix(String baseUrl, String apiPrefix, String path) {
    var base = baseUrl.trim();
    while (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }

    final fixedPrefix = _normalizeApiPrefix(apiPrefix);
    final prefixPart = fixedPrefix.isEmpty ? '' : '/$fixedPrefix';

    final fixedPath =
        path.trim().startsWith('/') ? path.trim() : '/${path.trim()}';
    return '$base$prefixPart$fixedPath';
  }

  static String _buildStreamUrl({
    required ServerAuthSession auth,
    required String adapterDeviceId,
    required String itemId,
    required PlaybackInfoResult info,
    required Map<String, dynamic>? mediaSource,
    required bool exoPlayer,
    required int? audioStreamIndex,
    required int? subtitleStreamIndex,
  }) {
    final base = auth.baseUrl;
    final token = auth.token;
    final userId = auth.userId;

    String applyQueryPrefs(String url) {
      final uri = Uri.parse(url);
      final params = Map<String, String>.from(uri.queryParameters);
      if (!params.containsKey('api_key') && token.trim().isNotEmpty) {
        params['api_key'] = token.trim();
      }
      if (audioStreamIndex != null) {
        params['AudioStreamIndex'] = audioStreamIndex.toString();
      }
      if (subtitleStreamIndex != null && subtitleStreamIndex >= 0) {
        params['SubtitleStreamIndex'] = subtitleStreamIndex.toString();
      }
      return uri.replace(queryParameters: params).toString();
    }

    String resolve(String candidate) {
      final resolved = Uri.parse(base).resolve(candidate).toString();
      return applyQueryPrefs(resolved);
    }

    final directStreamUrl = (mediaSource?['DirectStreamUrl'] as String?)?.trim();
    final transcodingUrl = (mediaSource?['TranscodingUrl'] as String?)?.trim();
    if (directStreamUrl != null && directStreamUrl.isNotEmpty) {
      return resolve(directStreamUrl);
    }
    if (exoPlayer && transcodingUrl != null && transcodingUrl.isNotEmpty) {
      return resolve(transcodingUrl);
    }

    final mediaSourceId =
        (mediaSource?['Id'] as String?)?.trim().isNotEmpty == true
            ? (mediaSource!['Id'] as String).trim()
            : info.mediaSourceId.trim();
    final path =
        'Videos/$itemId/stream?static=true&MediaSourceId=$mediaSourceId'
        '&PlaySessionId=${Uri.encodeQueryComponent(info.playSessionId)}'
        '&UserId=${Uri.encodeQueryComponent(userId)}'
        '&DeviceId=${Uri.encodeQueryComponent(adapterDeviceId)}'
        '${token.trim().isEmpty ? '' : '&api_key=${Uri.encodeQueryComponent(token.trim())}'}';
    return applyQueryPrefs(_apiUrlWithPrefix(base, auth.apiPrefix, path));
  }
}

@immutable
class StreamPreloadGetResult {
  const StreamPreloadGetResult({
    required this.ok,
    required this.statusCode,
    required this.bytesRead,
    required this.capturedBytes,
    required this.contentTypeMime,
    required this.effectiveUri,
  });

  final bool ok;
  final int statusCode;
  final int bytesRead;
  final List<int> capturedBytes;
  final String? contentTypeMime;
  final Uri effectiveUri;
}

@immutable
class _HlsSegment {
  const _HlsSegment({
    required this.uri,
    required this.durationMs,
  });

  final Uri uri;
  final int durationMs;
}

@immutable
class _HlsParseResult {
  const _HlsParseResult({
    required this.variantPlaylistUri,
    required this.initSegmentUri,
    required this.segments,
  });

  final Uri? variantPlaylistUri;
  final Uri? initSegmentUri;
  final List<_HlsSegment> segments;
}

_HlsParseResult? _parseHls(String text, {required Uri base}) {
  final normalized = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  final lines = normalized.split('\n');
  if (lines.isEmpty) return null;

  Uri? initUri;
  final variants = <({Uri uri, int bandwidth})>[];
  final segments = <_HlsSegment>[];

  var expectingVariantUri = false;
  var variantBandwidth = 0;
  double? pendingDurationSeconds;

  for (final raw in lines) {
    final line = raw.trim();
    if (line.isEmpty) continue;

    if (expectingVariantUri) {
      if (!line.startsWith('#')) {
        variants.add((
          uri: base.resolve(line),
          bandwidth: variantBandwidth,
        ));
        expectingVariantUri = false;
        variantBandwidth = 0;
        continue;
      }
      expectingVariantUri = false;
      variantBandwidth = 0;
    }

    if (line.startsWith('#EXT-X-STREAM-INF')) {
      expectingVariantUri = true;
      final m = RegExp(r'BANDWIDTH=(\d+)').firstMatch(line);
      variantBandwidth = int.tryParse(m?.group(1) ?? '') ?? 0;
      continue;
    }

    if (line.startsWith('#EXT-X-MAP')) {
      final m = RegExp(r'URI=\"([^\"]+)\"').firstMatch(line);
      final uri = (m?.group(1) ?? '').trim();
      if (uri.isNotEmpty) {
        initUri = base.resolve(uri);
      }
      continue;
    }

    if (line.startsWith('#EXTINF')) {
      final m = RegExp(r'#EXTINF:([0-9.]+)').firstMatch(line);
      pendingDurationSeconds = double.tryParse(m?.group(1) ?? '');
      continue;
    }

    if (line.startsWith('#')) continue;

    final segUri = base.resolve(line);
    final durMs =
        ((pendingDurationSeconds ?? 0) * 1000).round().clamp(0, 1 << 30);
    segments.add(_HlsSegment(uri: segUri, durationMs: durMs));
    pendingDurationSeconds = null;
  }

  Uri? variantUri;
  if (variants.isNotEmpty) {
    variants.sort((a, b) => b.bandwidth.compareTo(a.bandwidth));
    variantUri = variants.first.uri;
  }

  return _HlsParseResult(
    variantPlaylistUri: variantUri,
    initSegmentUri: initUri,
    segments: segments,
  );
}
