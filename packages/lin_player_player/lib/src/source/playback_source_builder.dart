import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:lin_player_prefs/lin_player_prefs.dart';
import 'package:lin_player_server_adapters/lin_player_server_adapters.dart';

import '../source_resolution/stream_body_link_resolver.dart';
import '../source_resolution/stream_redirect_resolver.dart';
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
      profile: playbackInfoProfileKindForPlaybackSourceCore(request.playerCore),
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
    final selectedMediaSource =
        _findMediaSource(sources, selectedMediaSourceId);
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

    String normalizedMediaSourceField(String key) {
      return (mediaSource?[key]?.toString() ?? '').trim().toLowerCase();
    }

    String normalizedVideoCodec() {
      final mediaSourceCodec = normalizedMediaSourceField('VideoCodec');
      if (mediaSourceCodec.isNotEmpty) return mediaSourceCodec;
      final videos =
          streamsOfType(mediaSource ?? const <String, dynamic>{}, 'Video');
      final first = videos.isNotEmpty ? videos.first : null;
      return (first?['Codec']?.toString() ?? '').trim().toLowerCase();
    }

    bool isAvPlayerSafeDirectVideoCodec(String codec) {
      if (codec.isEmpty) return false;
      return codec.contains('h264') ||
          codec.contains('avc') ||
          codec.contains('h265') ||
          codec.contains('h.265') ||
          codec.contains('hevc') ||
          codec.contains('hev1') ||
          codec.contains('hvc1') ||
          codec.contains('x265') ||
          codec.contains('av1');
    }

    final directStreamUrl =
        (mediaSource?['DirectStreamUrl'] as String?)?.trim();
    final transcodingUrl = (mediaSource?['TranscodingUrl'] as String?)?.trim();
    final shouldPreferAvPlayerTranscoding =
        request.playerCore == PlaybackSourcePlayerCoreKind.avplayer &&
            request.allowTranscoding &&
            transcodingUrl != null &&
            transcodingUrl.isNotEmpty &&
            (() {
              final container = normalizedMediaSourceField('Container');
              if (container.isNotEmpty &&
                  container != 'mov' &&
                  container != 'mp4' &&
                  container != 'm4v') {
                return true;
              }
              return !isAvPlayerSafeDirectVideoCodec(normalizedVideoCodec());
            })();
    final preferredAvPlayerTranscodingUrl =
        shouldPreferAvPlayerTranscoding ? transcodingUrl : null;

    String url;
    if (preferredAvPlayerTranscodingUrl != null) {
      url = resolve(preferredAvPlayerTranscodingUrl);
    } else if (directStreamUrl != null && directStreamUrl.isNotEmpty) {
      url = resolve(directStreamUrl);
    } else if (request.allowTranscoding &&
        transcodingUrl != null &&
        transcodingUrl.isNotEmpty) {
      url = resolve(transcodingUrl);
    } else {
      final pathUri = (sourcePath == null || sourcePath.isEmpty)
          ? null
          : Uri.tryParse(sourcePath);
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
    final headers = isExternal
        ? const <String, String>{}
        : request.adapter.buildStreamHeaders(auth);
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
      playbackPipeline: playbackPipelineForPlaybackSourceCore(
        request.playerCore,
      ),
    );
  }

  static Future<ResolvedPlaybackSource> _maybeResolveExternalSource(
    ResolvedPlaybackSource source,
  ) async {
    if (kIsWeb) return source;
    final uri = Uri.tryParse(source.url);
    if (uri == null || !_isHttpUrl(uri)) return source;
    if (!source.isExternal && !source.fromStrm) return source;

    var resolved = source;
    final first = await StreamRedirectResolver.resolve(
      uri,
      requestHeaders: source.httpHeaders,
    );
    if (first == null) return resolved;

    resolved = _applyRedirectResult(
      resolved,
      originalUrl: source.url,
      result: first,
    );

    final bodyLink = await StreamBodyLinkResolver.resolve(
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
      proxyUrl: resolved.proxyUrl,
      playbackPipeline: resolved.playbackPipeline,
    );

    final secondUri = Uri.tryParse(resolved.url);
    if (secondUri == null || !_isHttpUrl(secondUri)) {
      return resolved;
    }
    final second = await StreamRedirectResolver.resolve(
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
    required StreamRedirectResolveResult result,
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
      httpHeaders:
          Map<String, String>.unmodifiable(result.effectiveRequestHeaders),
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
          _supportsByteRangeHint(result) ?? source.supportsByteRange,
      httpStatusHint:
          result.statusCode > 0 ? result.statusCode : source.httpStatusHint,
      bitrate: source.bitrate,
      sizeBytes: source.sizeBytes,
      sourcePath: source.sourcePath,
      proxyUrl: source.proxyUrl,
      playbackPipeline: source.playbackPipeline,
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
        sources.any(
            (source) => (source['Id']?.toString() ?? '').trim() == selected)) {
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
                (primaryValue == bestPrimary && secondaryValue > bestSecondary))
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
        chosen = (List<Map<String, dynamic>>.from(sources)
              ..sort(_compareByQuality))
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
    final sizeBytes = asInt(mediaSource?['Size']);
    final runTimeTicks = asInt(mediaSource?['RunTimeTicks']);
    if (sizeBytes == null ||
        sizeBytes <= 0 ||
        runTimeTicks == null ||
        runTimeTicks <= 0) {
      return bitrate != null && bitrate > 0 ? bitrate : null;
    }

    final seconds = runTimeTicks / 10000000.0;
    if (seconds <= 0.5) return bitrate != null && bitrate > 0 ? bitrate : null;
    final estimated = ((sizeBytes * 8) / seconds).round();
    return estimated > 0
        ? estimated
        : bitrate != null && bitrate > 0
            ? bitrate
            : null;
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

  static bool? _supportsByteRangeHint(StreamRedirectResolveResult resolved) {
    if (resolved.statusCode == 206) return true;
    final acceptRanges = (resolved.acceptRanges ?? '').trim().toLowerCase();
    if (acceptRanges.contains('bytes')) return true;
    if (acceptRanges.contains('none')) return false;
    final contentRange = (resolved.contentRange ?? '').trim();
    if (contentRange.isNotEmpty) return true;
    return null;
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
    StreamRedirectResolveResult result,
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
    int portOf(Uri uri) =>
        uri.hasPort ? uri.port : (uri.scheme == 'https' ? 443 : 80);
    return a.scheme == b.scheme && a.host == b.host && portOf(a) == portOf(b);
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
