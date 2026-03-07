import 'package:flutter/foundation.dart' show kIsWeb;

import '../strm/strm_resolver.dart';
export 'stream_models.dart';
import 'src/stream_redirect_resolver.dart';
import 'stream_models.dart';

class StreamResolver {
  const StreamResolver._();

  static bool _looksLikeNetworkUrl(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null) return false;
    final scheme = uri.scheme.toLowerCase();
    return (scheme == 'http' || scheme == 'https') && uri.host.isNotEmpty;
  }

  static bool _hasHeader(Map<String, String> headers, String name) {
    final lower = name.toLowerCase();
    for (final k in headers.keys) {
      if (k.toLowerCase() == lower) return true;
    }
    return false;
  }

  static String? _getHeaderValue(Map<String, String> headers, String name) {
    final lower = name.toLowerCase();
    for (final e in headers.entries) {
      if (e.key.toLowerCase() == lower) return e.value;
    }
    return null;
  }

  static StreamMediaType _mediaTypeHintForUrl(String url) {
    final uri = Uri.tryParse(url);
    final path = (uri?.path ?? url).toLowerCase();
    if (path.endsWith('.m3u8') || path.contains('.m3u8?')) {
      return StreamMediaType.hls;
    }
    if (path.endsWith('.mpd') || path.contains('.mpd?')) {
      return StreamMediaType.dash;
    }
    return StreamMediaType.file;
  }

  static StreamMediaType _mediaTypeHintForMime(String? mime) {
    final v = (mime ?? '').trim().toLowerCase();
    if (v.isEmpty) return StreamMediaType.unknown;
    if (v.contains('mpegurl') || v.contains('m3u8')) return StreamMediaType.hls;
    if (v.contains('dash+xml')) return StreamMediaType.dash;
    if (v.startsWith('video/') || v.startsWith('audio/')) {
      return StreamMediaType.file;
    }
    return StreamMediaType.unknown;
  }

  static bool? _supportsByteRangeHint(StreamRedirectResolveResult resolved) {
    if (resolved.statusCode == 206) return true;
    final ar = (resolved.acceptRanges ?? '').trim().toLowerCase();
    if (ar.contains('bytes')) return true;
    if (ar.contains('none')) return false;
    final cr = (resolved.contentRange ?? '').trim();
    if (cr.isNotEmpty) return true;
    return null;
  }

  static List<String> _redirectChainFor(
    String originalUrl,
    StreamRedirectResolveResult resolved,
  ) {
    final out = <String>[];
    final start = originalUrl.trim();
    if (start.isNotEmpty) out.add(start);
    for (final hop in resolved.hops) {
      final loc = hop.location?.toString().trim();
      if (loc != null && loc.isNotEmpty) out.add(loc);
    }
    final effective = resolved.effectiveUri.toString().trim();
    if (effective.isNotEmpty && (out.isEmpty || out.last != effective)) {
      out.add(effective);
    }

    final dedup = <String>[];
    for (final s in out) {
      if (dedup.isEmpty || dedup.last != s) dedup.add(s);
    }
    return List<String>.unmodifiable(dedup);
  }

  static Map<String, String> _mergeHeaders(
    Map<String, String>? base,
    Map<String, String>? override,
  ) {
    if ((base == null || base.isEmpty) &&
        (override == null || override.isEmpty)) {
      return const <String, String>{};
    }

    final out = <String, String>{};
    if (base != null) {
      for (final e in base.entries) {
        final k = e.key.trim();
        final v = e.value.trim();
        if (k.isEmpty || v.isEmpty) continue;
        out[k] = v;
      }
    }
    if (override != null) {
      for (final e in override.entries) {
        final k = e.key.trim();
        final v = e.value.trim();
        if (k.isEmpty || v.isEmpty) continue;
        out[k] = v;
      }
    }
    return out;
  }

  static Future<StreamResolveResult> resolve(
    StreamResolveRequest request, {
    StreamResolveOptions options = const StreamResolveOptions(),
  }) async {
    final source = request.sourcePathOrUrl.trim();
    final fileName = (request.fileName ?? '').trim();

    final looksLikeStrm = StrmResolver.looksLikeStrmFileName(fileName) ||
        StrmResolver.looksLikeStrmPathOrUrl(source);

    if (!looksLikeStrm) {
      final headers = _mergeHeaders(request.httpHeaders, null);
      return StreamResolveResult.success(
        candidates: <PlayableSource>[
          PlayableSource(
            url: source,
            httpHeaders: headers,
            mediaTypeHint: _mediaTypeHintForUrl(source),
            fromStrm: false,
          ),
        ],
        inputWasStrm: false,
        usedDirectPlayFallback: false,
      );
    }

    final strmReadHeaders = (() {
      final headers = _mergeHeaders(request.httpHeaders, null);
      final shouldApplyBrowserUa = options.preferBrowserUserAgentForStrm &&
          !kIsWeb &&
          _looksLikeNetworkUrl(source) &&
          !_hasHeader(headers, 'User-Agent');
      return shouldApplyBrowserUa
          ? <String, String>{
              ...headers,
              'User-Agent': options.browserUserAgent,
            }
          : headers;
    })();

    final strm = await StrmResolver.resolve(
      sourcePathOrUrl: source,
      fileName: fileName,
      bytes: request.bytes,
      readStream: request.readStream,
      httpHeaders: strmReadHeaders.isEmpty ? null : strmReadHeaders,
    );

    if (!strm.isSuccess) {
      if (strm.suggestDirectPlayFallback && source.isNotEmpty) {
        final headers = _mergeHeaders(request.httpHeaders, null);
        final shouldApplyBrowserUa = options.preferBrowserUserAgentForStrm &&
            !kIsWeb &&
            _looksLikeNetworkUrl(source) &&
            !_hasHeader(headers, 'User-Agent');
        final effectiveHeaders = shouldApplyBrowserUa
            ? <String, String>{
                ...headers,
                'User-Agent': options.browserUserAgent,
              }
            : headers;

        final baseCandidate = PlayableSource(
          url: source,
          httpHeaders: effectiveHeaders,
          mediaTypeHint: _mediaTypeHintForUrl(source),
          fromStrm: true,
        );

        final resolved = await (() async {
          if (!options.resolveRedirectsForStrmTargets || kIsWeb) return null;
          final uri = Uri.tryParse(source);
          if (uri == null) return null;
          final scheme = uri.scheme.toLowerCase();
          if (scheme != 'http' && scheme != 'https') return null;
          return StreamRedirectResolver.resolve(
            uri,
            requestHeaders: effectiveHeaders,
            timeout: options.redirectResolveTimeout,
            maxRedirects: options.maxRedirects,
            useCache: options.cacheRedirectResolution,
            cacheTtl: options.redirectCacheTtl,
            cacheMaxEntries: options.redirectCacheMaxEntries,
          );
        })();

        final out = <PlayableSource>[];
        final r = resolved;
        final effectiveUrl = (r?.effectiveUri.toString() ?? '').trim();

        final improved = (() {
          if (r == null) return false;
          if (effectiveUrl.isEmpty) return false;
          final urlChanged = effectiveUrl != source;
          final cookieBefore =
              (_getHeaderValue(effectiveHeaders, 'Cookie') ?? '').trim();
          final cookieAfter =
              (_getHeaderValue(r.effectiveRequestHeaders, 'Cookie') ?? '')
                  .trim();
          final cookieChanged =
              cookieAfter.isNotEmpty && cookieAfter != cookieBefore;
          return urlChanged || cookieChanged || r.hops.isNotEmpty;
        })();

        if (improved) {
          final rr = r!;
          final urlHint = _mediaTypeHintForUrl(effectiveUrl);
          final mimeHint = _mediaTypeHintForMime(rr.contentTypeMime);
          final hint = mimeHint == StreamMediaType.unknown ? urlHint : mimeHint;

          out.add(
            PlayableSource(
              url: effectiveUrl,
              httpHeaders: rr.effectiveRequestHeaders,
              mediaTypeHint: hint,
              fromStrm: true,
              redirectChain: _redirectChainFor(source, rr),
              contentTypeHint: rr.contentTypeMime,
              supportsByteRange: _supportsByteRangeHint(rr),
              httpStatusHint: rr.statusCode > 0 ? rr.statusCode : null,
            ),
          );
        }
        if (!improved || options.keepOriginalCandidateWhenRedirected) {
          out.add(baseCandidate);
        }

        return StreamResolveResult.success(
          candidates: out,
          inputWasStrm: true,
          usedDirectPlayFallback: true,
        );
      }

      final msg = (strm.error ?? 'STRM 解析失败').trim();
      final code = msg.contains('无法读取')
          ? StreamErrorCode.strmReadFailed
          : (msg.contains('未找到') ? StreamErrorCode.strmParseFailed : StreamErrorCode.unknown);
      return StreamResolveResult.failure(
        error: StreamError(code: code, message: msg),
        inputWasStrm: true,
        usedDirectPlayFallback: false,
      );
    }

    final out = <PlayableSource>[];
    for (final t in strm.targets) {
      final url = t.url.trim();
      if (url.isEmpty) continue;

      final headers = _mergeHeaders(request.httpHeaders, t.httpHeaders);

      final shouldApplyBrowserUa = options.preferBrowserUserAgentForStrm &&
          !kIsWeb &&
          _looksLikeNetworkUrl(url) &&
          !_hasHeader(headers, 'User-Agent');
      final effectiveHeaders = shouldApplyBrowserUa
          ? <String, String>{
              ...headers,
              'User-Agent': options.browserUserAgent,
            }
          : headers;

      final baseCandidate = PlayableSource(
        url: url,
        httpHeaders: effectiveHeaders,
        mediaTypeHint: _mediaTypeHintForUrl(url),
        fromStrm: true,
      );

      final resolved = await (() async {
        if (!options.resolveRedirectsForStrmTargets || kIsWeb) return null;
        final uri = Uri.tryParse(url);
        if (uri == null) return null;
        final scheme = uri.scheme.toLowerCase();
        if (scheme != 'http' && scheme != 'https') return null;
        return StreamRedirectResolver.resolve(
          uri,
          requestHeaders: effectiveHeaders,
          timeout: options.redirectResolveTimeout,
          maxRedirects: options.maxRedirects,
          useCache: options.cacheRedirectResolution,
          cacheTtl: options.redirectCacheTtl,
          cacheMaxEntries: options.redirectCacheMaxEntries,
        );
      })();

      final r = resolved;
      final effectiveUrl = (r?.effectiveUri.toString() ?? '').trim();

      final improved = (() {
        if (r == null) return false;
        if (effectiveUrl.isEmpty) return false;
        final urlChanged = effectiveUrl != url;
        final cookieBefore =
            (_getHeaderValue(effectiveHeaders, 'Cookie') ?? '').trim();
        final cookieAfter =
            (_getHeaderValue(r.effectiveRequestHeaders, 'Cookie') ?? '').trim();
        final cookieChanged = cookieAfter.isNotEmpty && cookieAfter != cookieBefore;
        return urlChanged || cookieChanged || r.hops.isNotEmpty;
      })();

      if (improved) {
        final rr = r!;
        final urlHint = _mediaTypeHintForUrl(effectiveUrl);
        final mimeHint = _mediaTypeHintForMime(rr.contentTypeMime);
        final hint = mimeHint == StreamMediaType.unknown ? urlHint : mimeHint;

        out.add(
          PlayableSource(
            url: effectiveUrl,
            httpHeaders: rr.effectiveRequestHeaders,
            mediaTypeHint: hint,
            fromStrm: true,
            redirectChain: _redirectChainFor(url, rr),
            contentTypeHint: rr.contentTypeMime,
            supportsByteRange: _supportsByteRangeHint(rr),
            httpStatusHint: rr.statusCode > 0 ? rr.statusCode : null,
          ),
        );
      }

      if (!improved || options.keepOriginalCandidateWhenRedirected) {
        out.add(baseCandidate);
      }
    }

    if (out.isEmpty) {
      return StreamResolveResult.failure(
        error: const StreamError(
          code: StreamErrorCode.noCandidates,
          message: 'STRM 内容中未找到可播放链接',
        ),
        inputWasStrm: true,
        usedDirectPlayFallback: false,
      );
    }

    return StreamResolveResult.success(
      candidates: out,
      inputWasStrm: true,
      usedDirectPlayFallback: false,
    );
  }
}
