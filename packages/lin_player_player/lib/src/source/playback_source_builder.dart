import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:lin_player_prefs/lin_player_prefs.dart';
import 'package:lin_player_server_adapters/lin_player_server_adapters.dart';

import 'resolved_playback_source.dart';

bool _isHttpUrl(Uri uri) {
  final scheme = uri.scheme.toLowerCase();
  return (scheme == 'http' || scheme == 'https') && uri.host.trim().isNotEmpty;
}

class PlaybackSourceBuilder {
  const PlaybackSourceBuilder._();

  static Future<PlaybackSourceBuildResult> build(
    PlaybackSourceBuildRequest request,
  ) async {
    final info = await request.adapter.fetchPlaybackInfo(
      request.auth,
      itemId: request.itemId,
      exoPlayer: request.playerCore == PlaybackSourcePlayerCoreKind.exo,
    );
    final sources = info.mediaSources
        .cast<Map<String, dynamic>>()
        .map((entry) => Map<String, dynamic>.from(entry))
        .toList(growable: false);
    final selectedMediaSourceId = _resolveMediaSourceId(
      sources: sources,
      selectedMediaSourceId: request.selectedMediaSourceId,
      preferredMediaSourceIndex: request.preferredMediaSourceIndex,
      preferred: request.preferredVideoVersion,
    );
    final selectedMediaSource = _findMediaSource(sources, selectedMediaSourceId);
    final baseSource = _buildInitialResolvedSource(
      request: request,
      info: info,
      mediaSource: selectedMediaSource,
    );
    final resolvedSource = request.resolveExternalSource
        ? await _maybeResolveExternalSource(baseSource)
        : baseSource;
    return PlaybackSourceBuildResult(
      playbackInfo: info,
      mediaSources: sources,
      selectedMediaSource: selectedMediaSource,
      selectedMediaSourceId: selectedMediaSourceId,
      resolvedSource: resolvedSource,
    );
  }

  static int? asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  static List<Map<String, dynamic>> streamsOfType(
    Map<String, dynamic> mediaSource,
    String type,
  ) {
    final streams = (mediaSource['MediaStreams'] as List?) ?? const [];
    return streams
        .where((entry) => (entry as Map)['Type'] == type)
        .map((entry) => Map<String, dynamic>.from(entry as Map))
        .toList(growable: false);
  }

  static String? pickPreferredMediaSourceId(
    List<Map<String, dynamic>> sources,
    VideoVersionPreference preferred,
  ) {
    return _resolveMediaSourceId(
      sources: sources,
      selectedMediaSourceId: null,
      preferredMediaSourceIndex: null,
      preferred: preferred,
    );
  }

  static ResolvedPlaybackSource _buildInitialResolvedSource({
    required PlaybackSourceBuildRequest request,
    required PlaybackInfoResult info,
    required Map<String, dynamic>? mediaSource,
  }) {
    final auth = request.auth;
    final base = auth.baseUrl;
    final token = auth.token.trim();
    final userId = auth.userId.trim();
    final baseUri = Uri.tryParse(base);
    final sourcePath = (mediaSource?['Path'] as String?)?.trim();

    int effectivePort(Uri uri) {
      if (uri.hasPort) return uri.port;
      return uri.scheme.toLowerCase() == 'https' ? 443 : 80;
    }

    bool isSameOrigin(Uri a, Uri b) {
      return a.scheme.toLowerCase() == b.scheme.toLowerCase() &&
          a.host.toLowerCase() == b.host.toLowerCase() &&
          effectivePort(a) == effectivePort(b);
    }

    bool shouldApplyServerParams(Uri uri) {
      if (baseUri == null || baseUri.host.isEmpty) return true;
      if (uri.host.isEmpty) return true;
      return isSameOrigin(uri, baseUri);
    }

    String applyQueryPrefs(String url) {
      final uri = Uri.parse(url);
      if (!shouldApplyServerParams(uri)) return uri.toString();
      final params = Map<String, String>.from(uri.queryParameters);
      if (!params.containsKey('api_key') && token.isNotEmpty) {
        params['api_key'] = token;
      }
      if (request.audioStreamIndex != null) {
        params['AudioStreamIndex'] = request.audioStreamIndex.toString();
      }
      if (request.subtitleStreamIndex != null &&
          request.subtitleStreamIndex! >= 0) {
        params['SubtitleStreamIndex'] = request.subtitleStreamIndex.toString();
      }
      return uri.replace(queryParameters: params).toString();
    }

    String resolve(String candidate) {
      final resolved = Uri.parse(base).resolve(candidate).toString();
      return applyQueryPrefs(resolved);
    }

    final directStreamUrl = (mediaSource?['DirectStreamUrl'] as String?)?.trim();
    final transcodingUrl = (mediaSource?['TranscodingUrl'] as String?)?.trim();

    String url;
    if (directStreamUrl != null && directStreamUrl.isNotEmpty) {
      url = resolve(directStreamUrl);
    } else if (request.playerCore == PlaybackSourcePlayerCoreKind.exo &&
        transcodingUrl != null &&
        transcodingUrl.isNotEmpty) {
      url = resolve(transcodingUrl);
    } else {
      final pathUri =
          (sourcePath == null || sourcePath.isEmpty) ? null : Uri.tryParse(sourcePath);
      if (pathUri != null && pathUri.scheme.isNotEmpty) {
        if (pathUri.host.isNotEmpty &&
            (pathUri.scheme == 'http' || pathUri.scheme == 'https')) {
          url = shouldApplyServerParams(pathUri)
              ? applyQueryPrefs(pathUri.toString())
              : pathUri.toString();
        } else {
          url = pathUri.toString();
        }
      } else {
        final mediaSourceId =
            (mediaSource?['Id']?.toString() ?? info.mediaSourceId).trim();
        final path =
            'Videos/${request.itemId}/stream?static=true&MediaSourceId=$mediaSourceId'
            '&PlaySessionId=${Uri.encodeQueryComponent(info.playSessionId)}'
            '&UserId=${Uri.encodeQueryComponent(userId)}'
            '&DeviceId=${Uri.encodeQueryComponent(request.adapter.deviceId)}'
            '${token.isEmpty ? '' : '&api_key=${Uri.encodeQueryComponent(token)}'}';
        url = applyQueryPrefs(_apiUrlWithPrefix(base, auth.apiPrefix, path));
      }
    }

    final resolvedUri = Uri.tryParse(url);
    final isExternal = resolvedUri != null &&
        baseUri != null &&
        resolvedUri.host.isNotEmpty &&
        baseUri.host.isNotEmpty &&
        !shouldApplyServerParams(resolvedUri);
    final headers =
        isExternal ? const <String, String>{} : request.adapter.buildStreamHeaders(auth);
    final mediaSourceId =
        ((mediaSource?['Id']?.toString() ?? info.mediaSourceId).trim());
    return ResolvedPlaybackSource(
      itemId: request.itemId.trim(),
      playSessionId: info.playSessionId.trim(),
      mediaSourceId: mediaSourceId,
      url: url,
      httpHeaders: Map<String, String>.unmodifiable(headers),
      isExternal: isExternal,
      mediaTypeHint: _mediaTypeHintForUrl(url),
      fromStrm: _looksLikeStrmPathOrUrl(sourcePath ?? url),
      redirectChain: List<String>.unmodifiable(
        url.trim().isEmpty ? const <String>[] : <String>[url.trim()],
      ),
      bitrate: _estimateBitrateBitsPerSecond(mediaSource),
      sizeBytes: asInt(mediaSource?['Size']),
      sourcePath: sourcePath,
    );
  }

  static Future<ResolvedPlaybackSource> _maybeResolveExternalSource(
    ResolvedPlaybackSource source,
  ) async {
    if (kIsWeb || !source.isExternal) return source;
    final uri = Uri.tryParse(source.url);
    if (uri == null || !_isHttpUrl(uri)) return source;

    var resolved = source;
    final first = await _RedirectResolver.resolve(
      uri,
      requestHeaders: source.httpHeaders,
    );
    if (first == null) return resolved;

    resolved = _applyRedirectResult(
      resolved,
      originalUrl: source.url,
      result: first,
    );

    final bodyLink = await _BodyLinkResolver.resolve(
      first.effectiveUri,
      requestHeaders: first.effectiveRequestHeaders,
      contentTypeHint: first.contentTypeMime,
    );
    if (bodyLink == null || bodyLink.url.trim().isEmpty) {
      return resolved;
    }

    final bodyUri = Uri.tryParse(bodyLink.url.trim());
    final mergedHeaders = <String, String>{
      ...first.effectiveRequestHeaders,
      ...bodyLink.httpHeaders,
    };
    final safeHeaders = bodyUri == null
        ? mergedHeaders
        : _stripSensitiveHeadersIfCrossOrigin(
            mergedHeaders,
            from: first.effectiveUri,
            to: bodyUri,
          );
    resolved = ResolvedPlaybackSource(
      itemId: resolved.itemId,
      playSessionId: resolved.playSessionId,
      mediaSourceId: resolved.mediaSourceId,
      url: bodyLink.url.trim(),
      httpHeaders: Map<String, String>.unmodifiable(safeHeaders),
      isExternal: true,
      mediaTypeHint: _mediaTypeHintForUrl(bodyLink.url.trim()),
      fromStrm: true,
      redirectChain: List<String>.unmodifiable(
        _mergeRedirectChains(
          resolved.redirectChain,
          <String>[bodyLink.url.trim()],
        ),
      ),
      contentTypeHint: resolved.contentTypeHint,
      supportsByteRange: resolved.supportsByteRange,
      httpStatusHint: resolved.httpStatusHint,
      bitrate: resolved.bitrate,
      sizeBytes: resolved.sizeBytes,
      sourcePath: resolved.sourcePath,
    );

    final secondUri = Uri.tryParse(resolved.url);
    if (secondUri == null || !_isHttpUrl(secondUri)) {
      return resolved;
    }
    final second = await _RedirectResolver.resolve(
      secondUri,
      requestHeaders: resolved.httpHeaders,
    );
    if (second == null) return resolved;
    return _applyRedirectResult(
      resolved,
      originalUrl: bodyLink.url.trim(),
      result: second,
    );
  }

  static ResolvedPlaybackSource _applyRedirectResult(
    ResolvedPlaybackSource source, {
    required String originalUrl,
    required _RedirectResolveResult result,
  }) {
    final finalUrl = result.effectiveUri.toString().trim();
    final mediaHint = _mergeMediaTypeHint(
      source.mediaTypeHint,
      finalUrl.isEmpty ? source.url : finalUrl,
      result.contentTypeMime,
    );
    return ResolvedPlaybackSource(
      itemId: source.itemId,
      playSessionId: source.playSessionId,
      mediaSourceId: source.mediaSourceId,
      url: finalUrl.isEmpty ? source.url : finalUrl,
      httpHeaders: Map<String, String>.unmodifiable(result.effectiveRequestHeaders),
      isExternal: source.isExternal,
      mediaTypeHint: mediaHint,
      fromStrm: source.fromStrm,
      redirectChain: List<String>.unmodifiable(
        _mergeRedirectChains(
          source.redirectChain,
          _redirectChainFor(originalUrl, result),
        ),
      ),
      contentTypeHint: result.contentTypeMime ?? source.contentTypeHint,
      supportsByteRange:
          result.supportsByteRange ?? source.supportsByteRange,
      httpStatusHint:
          result.statusCode > 0 ? result.statusCode : source.httpStatusHint,
      bitrate: source.bitrate,
      sizeBytes: source.sizeBytes,
      sourcePath: source.sourcePath,
    );
  }

  static String? _resolveMediaSourceId({
    required List<Map<String, dynamic>> sources,
    required String? selectedMediaSourceId,
    required int? preferredMediaSourceIndex,
    required VideoVersionPreference preferred,
  }) {
    final selected = (selectedMediaSourceId ?? '').trim();
    if (selected.isNotEmpty &&
        sources.any((source) => (source['Id']?.toString() ?? '').trim() == selected)) {
      return selected;
    }
    final preferredIndex = preferredMediaSourceIndex;
    if (preferredIndex != null &&
        preferredIndex >= 0 &&
        preferredIndex < sources.length) {
      final indexed = (sources[preferredIndex]['Id']?.toString() ?? '').trim();
      if (indexed.isNotEmpty) return indexed;
    }
    if (sources.isEmpty) return null;

    int heightOf(Map<String, dynamic> mediaSource) {
      final videos = streamsOfType(mediaSource, 'Video');
      final video = videos.isNotEmpty ? videos.first : null;
      return asInt(video?['Height']) ?? 0;
    }

    int bitrateOf(Map<String, dynamic> mediaSource) =>
        asInt(mediaSource['Bitrate']) ?? 0;

    String videoCodecOf(Map<String, dynamic> mediaSource) {
      final mediaCodec = (mediaSource['VideoCodec'] as String?)?.trim();
      if (mediaCodec != null && mediaCodec.isNotEmpty) {
        return mediaCodec.toLowerCase();
      }
      final videos = streamsOfType(mediaSource, 'Video');
      final video = videos.isNotEmpty ? videos.first : null;
      return (video?['Codec']?.toString() ?? '').trim().toLowerCase();
    }

    bool isHevc(Map<String, dynamic> mediaSource) {
      final codec = videoCodecOf(mediaSource);
      return codec.contains('hevc') ||
          codec.contains('h265') ||
          codec.contains('h.265') ||
          codec.contains('x265');
    }

    bool isAvc(Map<String, dynamic> mediaSource) {
      final codec = videoCodecOf(mediaSource);
      return codec.contains('avc') ||
          codec.contains('h264') ||
          codec.contains('h.264') ||
          codec.contains('x264');
    }

    Map<String, dynamic>? pickBest(
      List<Map<String, dynamic>> list, {
      required int Function(Map<String, dynamic> mediaSource) primary,
      required int Function(Map<String, dynamic> mediaSource) secondary,
      required bool higherIsBetter,
    }) {
      if (list.isEmpty) return null;
      Map<String, dynamic> chosen = list.first;
      var bestPrimary = primary(chosen);
      var bestSecondary = secondary(chosen);
      for (final mediaSource in list.skip(1)) {
        final primaryValue = primary(mediaSource);
        final secondaryValue = secondary(mediaSource);
        final better = higherIsBetter
            ? (primaryValue > bestPrimary ||
                (primaryValue == bestPrimary &&
                    secondaryValue > bestSecondary))
            : (primaryValue < bestPrimary ||
                (primaryValue == bestPrimary &&
                    secondaryValue < bestSecondary));
        if (better) {
          chosen = mediaSource;
          bestPrimary = primaryValue;
          bestSecondary = secondaryValue;
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
          primary: (mediaSource) {
            final bitrate = bitrateOf(mediaSource);
            return bitrate == 0 ? 1 << 30 : bitrate;
          },
          secondary: heightOf,
          higherIsBetter: false,
        );
        break;
      case VideoVersionPreference.preferHevc:
        final hevcSources = sources.where(isHevc).toList(growable: false);
        chosen = pickBest(
          hevcSources.isNotEmpty ? hevcSources : sources,
          primary: heightOf,
          secondary: bitrateOf,
          higherIsBetter: true,
        );
        break;
      case VideoVersionPreference.preferAvc:
        final avcSources = sources.where(isAvc).toList(growable: false);
        chosen = pickBest(
          avcSources.isNotEmpty ? avcSources : sources,
          primary: heightOf,
          secondary: bitrateOf,
          higherIsBetter: true,
        );
        break;
      case VideoVersionPreference.defaultVersion:
        chosen =
            (List<Map<String, dynamic>>.from(sources)..sort(_compareByQuality))
                .first;
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
      (source) => (source['Id']?.toString() ?? '').trim() == id,
      orElse: () => sources.first,
    );
  }

  static int _compareByQuality(
    Map<String, dynamic> a,
    Map<String, dynamic> b,
  ) {
    int heightOf(Map<String, dynamic> mediaSource) {
      final videos = streamsOfType(mediaSource, 'Video');
      final video = videos.isNotEmpty ? videos.first : null;
      return asInt(video?['Height']) ?? 0;
    }

    final heightDiff = heightOf(b) - heightOf(a);
    if (heightDiff != 0) return heightDiff;
    final bitrateDiff = (asInt(b['Bitrate']) ?? 0) - (asInt(a['Bitrate']) ?? 0);
    if (bitrateDiff != 0) return bitrateDiff;
    return (asInt(b['Size']) ?? 0) - (asInt(a['Size']) ?? 0);
  }

  static int? _estimateBitrateBitsPerSecond(Map<String, dynamic>? mediaSource) {
    final bitrate = asInt(mediaSource?['Bitrate']);
    if (bitrate != null && bitrate > 0) return bitrate;

    final sizeBytes = asInt(mediaSource?['Size']);
    final runTimeTicks = asInt(mediaSource?['RunTimeTicks']);
    if (sizeBytes == null ||
        sizeBytes <= 0 ||
        runTimeTicks == null ||
        runTimeTicks <= 0) {
      return bitrate;
    }

    final seconds = runTimeTicks / 10000000.0;
    if (seconds <= 0.5) return bitrate;
    final estimated = ((sizeBytes * 8) / seconds).round();
    return estimated > 0 ? estimated : bitrate;
  }

  static ResolvedPlaybackMediaType _mergeMediaTypeHint(
    ResolvedPlaybackMediaType current,
    String url,
    String? contentTypeMime,
  ) {
    final mimeHint = _mediaTypeHintForMime(contentTypeMime);
    if (mimeHint != ResolvedPlaybackMediaType.unknown) return mimeHint;
    if (current != ResolvedPlaybackMediaType.unknown) return current;
    return _mediaTypeHintForUrl(url);
  }

  static ResolvedPlaybackMediaType _mediaTypeHintForUrl(String url) {
    final uri = Uri.tryParse(url);
    final path = (uri?.path ?? url).toLowerCase();
    if (path.endsWith('.m3u8') || path.contains('.m3u8?')) {
      return ResolvedPlaybackMediaType.hls;
    }
    if (path.endsWith('.mpd') || path.contains('.mpd?')) {
      return ResolvedPlaybackMediaType.dash;
    }
    return ResolvedPlaybackMediaType.file;
  }

  static ResolvedPlaybackMediaType _mediaTypeHintForMime(String? mime) {
    final value = (mime ?? '').trim().toLowerCase();
    if (value.isEmpty) return ResolvedPlaybackMediaType.unknown;
    if (value.contains('mpegurl') || value.contains('m3u8')) {
      return ResolvedPlaybackMediaType.hls;
    }
    if (value.contains('dash+xml')) return ResolvedPlaybackMediaType.dash;
    if (value.startsWith('video/') || value.startsWith('audio/')) {
      return ResolvedPlaybackMediaType.file;
    }
    return ResolvedPlaybackMediaType.unknown;
  }

  static bool _looksLikeStrmPathOrUrl(String raw) {
    final value = raw.trim().toLowerCase();
    if (value.isEmpty) return false;
    final uri = Uri.tryParse(value);
    final path = uri?.path ?? value;
    return path.endsWith('.strm') || path.contains('.strm?');
  }

  static bool _isHttpUrl(Uri uri) {
    final scheme = uri.scheme.toLowerCase();
    return (scheme == 'http' || scheme == 'https') && uri.host.trim().isNotEmpty;
  }

  static String _normalizeApiPrefix(String raw) {
    var value = raw.trim();
    while (value.startsWith('/')) {
      value = value.substring(1);
    }
    while (value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    return value;
  }

  static String _apiUrlWithPrefix(
    String baseUrl,
    String apiPrefix,
    String path,
  ) {
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

  static List<String> _mergeRedirectChains(
    List<String> a,
    List<String> b,
  ) {
    final merged = <String>[];
    for (final entry in <String>[...a, ...b]) {
      final trimmed = entry.trim();
      if (trimmed.isEmpty) continue;
      if (merged.isEmpty || merged.last != trimmed) {
        merged.add(trimmed);
      }
    }
    return merged;
  }

  static List<String> _redirectChainFor(
    String originalUrl,
    _RedirectResolveResult result,
  ) {
    final out = <String>[];
    final start = originalUrl.trim();
    if (start.isNotEmpty) out.add(start);
    for (final hop in result.hops) {
      final location = hop.location?.toString().trim();
      if (location != null && location.isNotEmpty) out.add(location);
    }
    final effective = result.effectiveUri.toString().trim();
    if (effective.isNotEmpty && (out.isEmpty || out.last != effective)) {
      out.add(effective);
    }
    return out;
  }

  static Map<String, String> _stripSensitiveHeadersIfCrossOrigin(
    Map<String, String> headers, {
    required Uri from,
    required Uri to,
  }) {
    if (_sameOrigin(from, to)) return headers;
    final out = <String, String>{...headers};
    _removeHeader(out, 'Cookie');
    _removeHeader(out, 'Authorization');
    return out;
  }

  static bool _sameOrigin(Uri a, Uri b) {
    int portOf(Uri uri) => uri.hasPort ? uri.port : (uri.scheme == 'https' ? 443 : 80);
    return a.scheme == b.scheme &&
        a.host == b.host &&
        portOf(a) == portOf(b);
  }

  static void _removeHeader(Map<String, String> headers, String name) {
    final lower = name.toLowerCase();
    final keys = headers.keys.toList(growable: false);
    for (final key in keys) {
      if (key.toLowerCase() == lower) {
        headers.remove(key);
      }
    }
  }
}

typedef _ParsedUrlWithHeaders = ({String url, Map<String, String> httpHeaders});

class _BodyLinkResolver {
  const _BodyLinkResolver._();

  static Future<_ParsedUrlWithHeaders?> resolve(
    Uri uri, {
    required Map<String, String> requestHeaders,
    required String? contentTypeHint,
    int maxBytes = 16 * 1024,
    Duration timeout = const Duration(seconds: 4),
  }) async {
    if (!_shouldResolveBodyLink(contentTypeHint: contentTypeHint)) return null;
    if (maxBytes <= 0) return null;

    final client = LinHttpClientFactory.createHttpClient();
    try {
      final request = await client.getUrl(uri).timeout(timeout);
      request.followRedirects = true;
      request.maxRedirects = 5;
      request.persistentConnection = false;
      request.headers.set('Accept', 'text/plain, application/json, */*');
      for (final entry in requestHeaders.entries) {
        final key = entry.key.trim();
        final value = entry.value.trim();
        if (key.isEmpty || value.isEmpty) continue;
        request.headers.set(key, value);
      }
      final response = await request.close().timeout(timeout);
      if (response.statusCode != 200) return null;

      final bytes = await _readBytesFromStream(
        response,
        limit: maxBytes,
      );
      if (bytes.isEmpty) return null;
      final text = utf8.decode(bytes, allowMalformed: true);
      return _extractFromText(text, base: uri);
    } catch (_) {
      return null;
    } finally {
      try {
        client.close(force: true);
      } catch (_) {}
    }
  }

  static bool _shouldResolveBodyLink({required String? contentTypeHint}) {
    final mime = (contentTypeHint ?? '').trim().toLowerCase();
    if (mime.isEmpty) return true;
    if (mime.contains('mpegurl') || mime.contains('m3u8')) return false;
    if (mime.contains('dash+xml')) return false;
    if (mime.startsWith('video/') || mime.startsWith('audio/')) return false;
    if (mime.startsWith('text/') || mime.contains('json')) return true;
    return mime == 'application/octet-stream';
  }

  static _ParsedUrlWithHeaders? _extractFromText(
    String raw, {
    required Uri base,
  }) {
    var text = raw;
    if (text.startsWith('\uFEFF')) {
      text = text.substring(1);
    }
    final trimmed = text.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#EXTM3U')) return null;

    if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
      try {
        final decoded = jsonDecode(trimmed);
        final found = _findUrlInJson(decoded);
        if (found != null) {
          final parsed = _parseFirstTarget(
            _resolveMaybeRelative(base, found) ?? found,
          );
          if (parsed != null) return parsed;
        }
      } catch (_) {}
    }

    final parsed = _parseFirstTarget(trimmed);
    if (parsed != null) {
      final resolved = _resolveMaybeRelative(base, parsed.url) ?? parsed.url;
      return (url: resolved, httpHeaders: parsed.httpHeaders);
    }

    final match = RegExp(r'''https?://[^\s"'<>]+''').firstMatch(trimmed);
    final url = match?.group(0)?.trim();
    if (url == null || url.isEmpty) return null;
    return (url: _resolveMaybeRelative(base, url) ?? url, httpHeaders: const {});
  }

  static String? _findUrlInJson(dynamic node) {
    if (node == null) return null;
    if (node is String) {
      final value = node.trim();
      if (value.startsWith('http://') ||
          value.startsWith('https://') ||
          value.startsWith('file://')) {
        return value;
      }
      return null;
    }
    if (node is List) {
      for (final entry in node) {
        final found = _findUrlInJson(entry);
        if (found != null) return found;
      }
      return null;
    }
    if (node is Map) {
      const keys = <String>[
        'url',
        'playUrl',
        'play_url',
        'downloadUrl',
        'download_url',
        'directUrl',
        'direct_url',
        'link',
        'href',
      ];
      for (final key in keys) {
        for (final entry in node.entries) {
          final entryKey = entry.key.toString().trim().toLowerCase();
          if (entryKey == key.toLowerCase()) {
            final found = _findUrlInJson(entry.value);
            if (found != null) return found;
          }
        }
      }
      for (final value in node.values) {
        final found = _findUrlInJson(value);
        if (found != null) return found;
      }
    }
    return null;
  }

  static _ParsedUrlWithHeaders? _parseFirstTarget(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return null;

    final pendingHeaders = <String, String>{};
    for (final line in text.split(RegExp(r'\r?\n'))) {
      var value = line.trim();
      if (value.isEmpty) continue;
      if (value.startsWith('#EXTVLCOPT:') || value.startsWith('#extvlcopt:')) {
        _parseExtVlcOpt(value, pendingHeaders);
        continue;
      }
      if (value.startsWith('#') ||
          value.startsWith(';') ||
          value.startsWith('//') ||
          value.startsWith('/*') ||
          value.startsWith('*')) {
        continue;
      }
      if ((value.startsWith('"') && value.endsWith('"')) ||
          (value.startsWith("'") && value.endsWith("'"))) {
        value = value.substring(1, value.length - 1).trim();
      }
      final split = _splitUrlAndPipeOptions(value);
      final url = split.$1.trim();
      if (url.isEmpty) continue;
      final headers = <String, String>{...pendingHeaders};
      pendingHeaders.clear();
      final pipeHeaders = _parsePipeHeaderOptions(split.$2);
      if (pipeHeaders.isNotEmpty) headers.addAll(pipeHeaders);
      return (url: url, httpHeaders: headers);
    }
    return null;
  }

  static (String, String?) _splitUrlAndPipeOptions(String input) {
    final index = input.indexOf('|');
    if (index < 0) return (input, null);
    final url = input.substring(0, index);
    final options = index + 1 < input.length ? input.substring(index + 1) : '';
    return (url, options.isEmpty ? null : options);
  }

  static void _parseExtVlcOpt(String line, Map<String, String> out) {
    final index = line.indexOf(':');
    if (index < 0 || index + 1 >= line.length) return;
    final rest = line.substring(index + 1).trim();
    final eq = rest.indexOf('=');
    if (eq <= 0) return;
    final key = rest.substring(0, eq).trim().toLowerCase();
    final value = rest.substring(eq + 1).trim();
    if (value.isEmpty) return;

    String? headerName;
    if (key == 'http-user-agent') headerName = 'User-Agent';
    if (key == 'http-referrer' || key == 'http-referer') headerName = 'Referer';
    if (key == 'http-origin') headerName = 'Origin';
    if (key == 'http-cookie') headerName = 'Cookie';

    if (headerName != null) {
      out[headerName] = value;
      return;
    }

    if (key == 'http-header') {
      final headerValue = value.trim();
      final sep = headerValue.indexOf(':');
      if (sep > 0) {
        final name = headerValue.substring(0, sep).trim();
        final headerData = headerValue.substring(sep + 1).trim();
        if (name.isNotEmpty && headerData.isNotEmpty) {
          out[_canonicalHeaderName(name)] = headerData;
        }
        return;
      }
      final eq2 = headerValue.indexOf('=');
      if (eq2 > 0) {
        final name = headerValue.substring(0, eq2).trim();
        final headerData = headerValue.substring(eq2 + 1).trim();
        if (name.isNotEmpty && headerData.isNotEmpty) {
          out[_canonicalHeaderName(name)] = headerData;
        }
      }
    }
  }

  static Map<String, String> _parsePipeHeaderOptions(String? raw) {
    final value = (raw ?? '').trim();
    if (value.isEmpty) return const <String, String>{};
    final out = <String, String>{};
    for (final part in value.split('&')) {
      final item = part.trim();
      if (item.isEmpty) continue;
      final eq = item.indexOf('=');
      if (eq <= 0) continue;
      final rawKey = item.substring(0, eq).trim();
      final rawValue = item.substring(eq + 1).trim();
      if (rawKey.isEmpty || rawValue.isEmpty) continue;
      try {
        final key = Uri.decodeQueryComponent(rawKey).trim();
        final decodedValue = Uri.decodeQueryComponent(rawValue).trim();
        if (key.isEmpty || decodedValue.isEmpty) continue;
        out[_canonicalHeaderName(key)] = decodedValue;
      } catch (_) {
        out[_canonicalHeaderName(rawKey)] = rawValue;
      }
    }
    return out;
  }

  static String _canonicalHeaderName(String key) {
    final lower = key.trim().toLowerCase();
    if (lower == 'user-agent') return 'User-Agent';
    if (lower == 'referer' || lower == 'referrer') return 'Referer';
    if (lower == 'origin') return 'Origin';
    if (lower == 'cookie') return 'Cookie';
    if (lower == 'authorization') return 'Authorization';
    if (lower == 'accept') return 'Accept';
    if (lower == 'range') return 'Range';
    return key.trim();
  }

  static String? _resolveMaybeRelative(Uri base, String raw) {
    final value = raw.trim();
    if (value.isEmpty) return null;
    final uri = Uri.tryParse(value);
    if (uri == null) return null;
    if (uri.hasScheme) return value;
    try {
      return base.resolveUri(uri).toString();
    } catch (_) {
      return null;
    }
  }

  static Future<List<int>> _readBytesFromStream(
    Stream<List<int>> stream, {
    required int limit,
  }) async {
    final builder = BytesBuilder(copy: false);
    await for (final chunk in stream) {
      if (builder.length >= limit) break;
      final remaining = limit - builder.length;
      if (chunk.length <= remaining) {
        builder.add(chunk);
      } else {
        builder.add(chunk.sublist(0, remaining));
      }
      if (builder.length >= limit) break;
    }
    return builder.takeBytes();
  }
}

class _RedirectResolver {
  const _RedirectResolver._();

  static final Map<String, _RedirectCacheEntry> _cache =
      <String, _RedirectCacheEntry>{};

  static Future<_RedirectResolveResult?> resolve(
    Uri uri, {
    required Map<String, String> requestHeaders,
    Duration timeout = const Duration(seconds: 4),
    int maxRedirects = 5,
    bool allowGetFallback = true,
    bool useCache = true,
    Duration cacheTtl = const Duration(minutes: 1),
    int cacheMaxEntries = 128,
  }) async {
    if (!_isHttpUrl(uri)) return null;

    final shouldCache =
        useCache && cacheTtl > Duration.zero && cacheMaxEntries > 0;
    final cacheKey = shouldCache ? _cacheKey(uri, requestHeaders) : null;
    if (cacheKey != null) {
      final now = DateTime.now();
      final cached = _cache[cacheKey];
      if (cached != null) {
        if (cached.expiresAt.isAfter(now)) return cached.value;
        _cache.remove(cacheKey);
      }
    }

    var current = uri;
    final visited = <String>{};
    final hops = <_RedirectHop>[];
    final cookieJar = _CookieJar();

    for (var index = 0; index <= maxRedirects; index++) {
      final visitKey = current.toString();
      if (!visited.add(visitKey)) break;

      var meta = await _requestMeta(
        current,
        method: 'HEAD',
        headers: requestHeaders,
        cookieJar: cookieJar,
        timeout: timeout,
      );
      if ((meta == null || meta.statusCode == 405) && allowGetFallback) {
        meta = await _requestMeta(
          current,
          method: 'GET',
          headers: requestHeaders,
          cookieJar: cookieJar,
          timeout: timeout,
        );
      }
      if (meta == null) return null;

      cookieJar.storeFromResponse(current, meta.cookies);
      if (_isRedirectStatus(meta.statusCode) &&
          meta.location != null &&
          index < maxRedirects) {
        final next = _resolveLocation(current, meta.location!);
        hops.add(
          _RedirectHop(
            uri: current,
            statusCode: meta.statusCode,
            location: next,
          ),
        );
        if (next == null) break;
        current = next;
        continue;
      }

      final result = _RedirectResolveResult(
        effectiveUri: current,
        statusCode: meta.statusCode,
        contentTypeMime: meta.contentTypeMime,
        supportsByteRange: _supportsByteRangeHint(meta),
        hops: List<_RedirectHop>.unmodifiable(hops),
        effectiveRequestHeaders: cookieJar.applyToHeaders(current, requestHeaders),
      );
      if (cacheKey != null) {
        final now = DateTime.now();
        _cache[cacheKey] = _RedirectCacheEntry(
          value: result,
          expiresAt: now.add(cacheTtl),
        );
        _pruneCache(maxEntries: cacheMaxEntries);
      }
      return result;
    }

    return _RedirectResolveResult(
      effectiveUri: current,
      statusCode: 0,
      contentTypeMime: null,
      supportsByteRange: null,
      hops: List<_RedirectHop>.unmodifiable(hops),
      effectiveRequestHeaders: cookieJar.applyToHeaders(current, requestHeaders),
    );
  }

  static bool? _supportsByteRangeHint(_ResponseMeta meta) {
    if (meta.statusCode == 206) return true;
    final acceptRanges = (meta.acceptRanges ?? '').trim().toLowerCase();
    if (acceptRanges.contains('bytes')) return true;
    if (acceptRanges.contains('none')) return false;
    final contentRange = (meta.contentRange ?? '').trim();
    if (contentRange.isNotEmpty) return true;
    return null;
  }

  static Future<_ResponseMeta?> _requestMeta(
    Uri uri, {
    required String method,
    required Map<String, String> headers,
    required _CookieJar cookieJar,
    required Duration timeout,
  }) async {
    final client = LinHttpClientFactory.createHttpClient();
    try {
      final Future<HttpClientRequest> open = switch (method) {
        'HEAD' => client.headUrl(uri),
        _ => client.getUrl(uri),
      };
      final request = await open.timeout(timeout);
      request.followRedirects = false;
      request.maxRedirects = 0;
      request.persistentConnection = false;

      for (final entry in headers.entries) {
        final key = entry.key.trim();
        final value = entry.value.trim();
        if (key.isEmpty || value.isEmpty) continue;
        request.headers.set(key, value);
      }
      final existingCookie =
          _getHeaderValue(headers, HttpHeaders.cookieHeader);
      final cookieHeader =
          cookieJar.cookieHeaderFor(uri, existingCookieHeader: existingCookie);
      if (cookieHeader != null && cookieHeader.isNotEmpty) {
        request.headers.set(HttpHeaders.cookieHeader, cookieHeader);
      }
      if (method == 'GET') {
        request.headers.set(HttpHeaders.rangeHeader, 'bytes=0-0');
      }

      final response = await request.close().timeout(timeout);
      return _ResponseMeta(
        statusCode: response.statusCode,
        location: response.headers.value(HttpHeaders.locationHeader)?.trim(),
        cookies: List<Cookie>.from(response.cookies),
        contentTypeMime: response.headers.contentType?.mimeType.trim(),
        acceptRanges: response.headers.value(HttpHeaders.acceptRangesHeader)?.trim(),
        contentRange:
            response.headers.value(HttpHeaders.contentRangeHeader)?.trim(),
      );
    } on Exception {
      return null;
    } finally {
      try {
        client.close(force: true);
      } catch (_) {}
    }
  }

  static Uri? _resolveLocation(Uri base, String rawLocation) {
    final location = rawLocation.trim();
    if (location.isEmpty) return null;
    final parsed = Uri.tryParse(location);
    if (parsed == null) return null;
    if (parsed.hasScheme) return parsed;
    try {
      return base.resolveUri(parsed);
    } catch (_) {
      return null;
    }
  }

  static bool _isRedirectStatus(int statusCode) {
    return statusCode == 301 ||
        statusCode == 302 ||
        statusCode == 303 ||
        statusCode == 307 ||
        statusCode == 308;
  }

  static String _cacheKey(Uri uri, Map<String, String> requestHeaders) {
    final userAgent =
        (_getHeaderValue(requestHeaders, HttpHeaders.userAgentHeader) ?? '').trim();
    final referer =
        (_getHeaderValue(requestHeaders, HttpHeaders.refererHeader) ?? '').trim();
    final origin = (_getHeaderValue(requestHeaders, 'Origin') ?? '').trim();
    final authorization =
        (_getHeaderValue(requestHeaders, HttpHeaders.authorizationHeader) ?? '')
            .trim();
    final cookie =
        (_getHeaderValue(requestHeaders, HttpHeaders.cookieHeader) ?? '').trim();
    final raw = StringBuffer()
      ..write(uri.toString())
      ..write('\nua:')
      ..write(userAgent)
      ..write('\nref:')
      ..write(referer)
      ..write('\norg:')
      ..write(origin)
      ..write('\nauth:')
      ..write(authorization)
      ..write('\nck:')
      ..write(cookie);
    return sha1.convert(utf8.encode(raw.toString())).toString();
  }

  static void _pruneCache({required int maxEntries}) {
    if (_cache.length <= maxEntries) return;
    final now = DateTime.now();
    _cache.removeWhere((_, entry) => !entry.expiresAt.isAfter(now));
    if (_cache.length <= maxEntries) return;
    _cache.clear();
  }

  static String? _getHeaderValue(Map<String, String> headers, String name) {
    final lower = name.toLowerCase();
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == lower) return entry.value;
    }
    return null;
  }
}

class _RedirectResolveResult {
  const _RedirectResolveResult({
    required this.effectiveUri,
    required this.statusCode,
    required this.contentTypeMime,
    required this.supportsByteRange,
    required this.hops,
    required this.effectiveRequestHeaders,
  });

  final Uri effectiveUri;
  final int statusCode;
  final String? contentTypeMime;
  final bool? supportsByteRange;
  final List<_RedirectHop> hops;
  final Map<String, String> effectiveRequestHeaders;
}

class _RedirectHop {
  const _RedirectHop({
    required this.uri,
    required this.statusCode,
    required this.location,
  });

  final Uri uri;
  final int statusCode;
  final Uri? location;
}

class _RedirectCacheEntry {
  const _RedirectCacheEntry({
    required this.value,
    required this.expiresAt,
  });

  final _RedirectResolveResult value;
  final DateTime expiresAt;
}

class _ResponseMeta {
  const _ResponseMeta({
    required this.statusCode,
    required this.location,
    required this.cookies,
    required this.contentTypeMime,
    required this.acceptRanges,
    required this.contentRange,
  });

  final int statusCode;
  final String? location;
  final List<Cookie> cookies;
  final String? contentTypeMime;
  final String? acceptRanges;
  final String? contentRange;
}

class _StoredCookie {
  _StoredCookie({
    required this.name,
    required this.value,
    required this.originHost,
    required this.domain,
    required this.hostOnly,
    required this.path,
    required this.secure,
    required this.expiresAt,
  });

  final String name;
  final String value;
  final String originHost;
  final String domain;
  final bool hostOnly;
  final String path;
  final bool secure;
  final DateTime? expiresAt;

  bool isExpired(DateTime now) {
    final expires = expiresAt;
    if (expires == null) return false;
    return !expires.isAfter(now);
  }
}

class _CookieJar {
  final List<_StoredCookie> _cookies = <_StoredCookie>[];

  void storeFromResponse(Uri origin, List<Cookie> cookies) {
    final host = origin.host.trim().toLowerCase();
    if (host.isEmpty || cookies.isEmpty) return;

    final now = DateTime.now().toUtc();
    for (final cookie in cookies) {
      final name = cookie.name.trim();
      if (name.isEmpty) continue;

      final rawDomain = (cookie.domain ?? '').trim().toLowerCase();
      final domain =
          rawDomain.startsWith('.') ? rawDomain.substring(1) : rawDomain;
      final hostOnly = domain.isEmpty;
      if (!hostOnly && !_hostMatchesDomain(host, domain)) {
        continue;
      }

      final rawPath = (cookie.path ?? '').trim();
      final path = rawPath.isEmpty ? '/' : rawPath;
      DateTime? expiresAt;
      final expires = cookie.expires;
      if (expires != null) {
        expiresAt = expires.isUtc ? expires : expires.toUtc();
      }
      final maxAge = cookie.maxAge;
      if (maxAge != null) {
        if (maxAge <= 0) {
          expiresAt = now.subtract(const Duration(seconds: 1));
        } else {
          expiresAt = now.add(Duration(seconds: maxAge));
        }
      }

      final stored = _StoredCookie(
        name: name,
        value: cookie.value,
        originHost: host,
        domain: hostOnly ? host : domain,
        hostOnly: hostOnly,
        path: path,
        secure: cookie.secure,
        expiresAt: expiresAt,
      );

      _cookies.removeWhere(
        (entry) =>
            entry.name == stored.name &&
            entry.domain == stored.domain &&
            entry.hostOnly == stored.hostOnly &&
            entry.path == stored.path &&
            entry.originHost == stored.originHost,
      );

      if (!stored.isExpired(now)) {
        _cookies.add(stored);
      }
    }

    _cookies.removeWhere((entry) => entry.isExpired(now));
    if (_cookies.length > 256) {
      _cookies.removeRange(0, _cookies.length - 256);
    }
  }

  Map<String, String> applyToHeaders(Uri uri, Map<String, String> headers) {
    final cookieHeader = cookieHeaderFor(
      uri,
      existingCookieHeader:
          _RedirectResolver._getHeaderValue(headers, HttpHeaders.cookieHeader),
    );
    if (cookieHeader == null || cookieHeader.trim().isEmpty) return headers;

    final out = <String, String>{...headers};
    PlaybackSourceBuilder._removeHeader(out, HttpHeaders.cookieHeader);
    out[HttpHeaders.cookieHeader] = cookieHeader;
    return out;
  }

  String? cookieHeaderFor(
    Uri uri, {
    String? existingCookieHeader,
  }) {
    final now = DateTime.now().toUtc();
    final host = uri.host.trim().toLowerCase();
    if (host.isEmpty) return existingCookieHeader;

    final path = uri.path.trim().isEmpty ? '/' : uri.path.trim();
    final existing = _parseCookieHeader(existingCookieHeader);
    final out = <String, String>{...existing};

    for (final cookie in _cookies) {
      if (cookie.isExpired(now)) continue;
      if (cookie.secure && uri.scheme.toLowerCase() != 'https') continue;

      final hostMatches = cookie.hostOnly
          ? (host == cookie.domain)
          : _hostMatchesDomain(host, cookie.domain);
      if (!hostMatches) continue;

      final cookiePath = cookie.path.isEmpty ? '/' : cookie.path;
      if (!path.startsWith(cookiePath)) continue;

      out[cookie.name] = cookie.value;
    }

    if (out.isEmpty) return null;
    final parts = <String>[];
    for (final entry in out.entries) {
      final key = entry.key.trim();
      if (key.isEmpty) continue;
      parts.add('$key=${entry.value}');
    }
    return parts.isEmpty ? null : parts.join('; ');
  }

  static Map<String, String> _parseCookieHeader(String? raw) {
    final value = (raw ?? '').trim();
    if (value.isEmpty) return const <String, String>{};
    final out = <String, String>{};
    for (final part in value.split(';')) {
      final item = part.trim();
      if (item.isEmpty) continue;
      final index = item.indexOf('=');
      if (index <= 0) continue;
      final name = item.substring(0, index).trim();
      final itemValue = item.substring(index + 1).trim();
      if (name.isEmpty) continue;
      out[name] = itemValue;
    }
    return out;
  }

  static bool _hostMatchesDomain(String host, String domain) {
    final fixedHost = host.trim().toLowerCase();
    final fixedDomain = domain.trim().toLowerCase();
    if (fixedHost.isEmpty || fixedDomain.isEmpty) return false;
    if (fixedHost == fixedDomain) return true;
    return fixedHost.endsWith('.$fixedDomain');
  }
}
