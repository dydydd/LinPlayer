import 'dart:convert';
import 'dart:typed_data';

import 'package:lin_player_server_api/network/lin_http_client.dart';

import '../../strm/strm_resolver.dart';

typedef StreamBodyLink = ({String url, Map<String, String> httpHeaders});

class StreamBodyLinkResolver {
  const StreamBodyLinkResolver._();

  static bool _isLocalhostLikeHost(String host) {
    final h = host.trim().toLowerCase();
    return h == 'localhost' ||
        h == '127.0.0.1' ||
        h == '0.0.0.0' ||
        h == '::1';
  }

  static bool _isHttpUrl(Uri uri) {
    final scheme = uri.scheme.toLowerCase();
    return (scheme == 'http' || scheme == 'https') && uri.host.trim().isNotEmpty;
  }

  static bool _looksLikeUrl(String raw) {
    final v = raw.trim();
    if (v.isEmpty) return false;
    if (v.startsWith('http://') || v.startsWith('https://')) return true;
    if (v.startsWith('file://')) return true;
    return false;
  }

  static Future<StreamBodyLink?> resolve(
    Uri uri, {
    required Map<String, String> requestHeaders,
    required int maxBytes,
    Duration timeout = const Duration(seconds: 4),
  }) async {
    if (!_isHttpUrl(uri)) return null;
    if (maxBytes <= 0) return null;

    final bytes = await _httpGetLimited(
      uri,
      headers: requestHeaders,
      limit: maxBytes,
      timeout: timeout,
    );
    if (bytes == null || bytes.isEmpty) return null;

    final text = utf8.decode(bytes, allowMalformed: true);
    return extractFromText(text, base: uri);
  }

  static StreamBodyLink? extractFromText(
    String raw, {
    required Uri base,
  }) {
    var text = raw;
    if (text.startsWith('\uFEFF')) {
      text = text.substring(1);
    }
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;

    // HLS playlist is itself playable, do not treat it as a "link wrapper".
    if (trimmed.startsWith('#EXTM3U')) return null;

    if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
      try {
        final decoded = jsonDecode(trimmed);
        final found = _findUrlInJson(decoded);
        if (found == null || found.trim().isEmpty) return null;
        final resolved = _resolveMaybeRelative(base, found.trim());
        if (resolved == null) return null;
        final rewritten = _rewriteLocalhostToBaseHost(base, resolved);
        final parsed = StrmResolver.parseFirstTarget(rewritten);
        if (parsed != null) {
          return (url: parsed.url, httpHeaders: parsed.httpHeaders);
        }
        return (url: rewritten, httpHeaders: const <String, String>{});
      } catch (_) {
        // fallthrough: try text extraction.
      }
    }

    // Try STRM-style parsing (supports comments, quotes, pipe headers, etc.).
    final parsed = StrmResolver.parseFirstTarget(trimmed);
    if (parsed != null && parsed.url.trim().isNotEmpty) {
      final resolvedUrl =
          _resolveMaybeRelative(base, parsed.url.trim()) ?? parsed.url.trim();
      final rewritten = _rewriteLocalhostToBaseHost(base, resolvedUrl);
      return (url: rewritten, httpHeaders: parsed.httpHeaders);
    }

    // Fall back to extracting the first URL-like substring.
    final m = RegExp(r'''https?://[^\s"'<>]+''').firstMatch(trimmed);
    if (m != null) {
      final u = m.group(0);
      if (u != null && _looksLikeUrl(u)) {
        final resolved = _resolveMaybeRelative(base, u.trim());
        if (resolved != null) {
          final rewritten = _rewriteLocalhostToBaseHost(base, resolved);
          return (url: rewritten, httpHeaders: const <String, String>{});
        }
      }
    }

    return null;
  }

  static String? _resolveMaybeRelative(Uri base, String raw) {
    final v = raw.trim();
    if (v.isEmpty) return null;
    final u = Uri.tryParse(v);
    if (u == null) return null;
    if (u.hasScheme) return v;
    try {
      return base.resolveUri(u).toString();
    } catch (_) {
      return null;
    }
  }

  static String _rewriteLocalhostToBaseHost(Uri base, String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return url;
    if (!_isHttpUrl(uri)) return url;
    if (!_isLocalhostLikeHost(uri.host)) return url;
    if (base.host.trim().isEmpty || _isLocalhostLikeHost(base.host)) return url;

    final scheme = uri.scheme.isNotEmpty ? uri.scheme : base.scheme;
    if (!uri.hasPort && base.hasPort) {
      return uri.replace(
        scheme: scheme,
        host: base.host,
        port: base.port,
      ).toString();
    }
    return uri.replace(
      scheme: scheme,
      host: base.host,
    ).toString();
  }

  static String? _findUrlInJson(dynamic node) {
    if (node == null) return null;

    if (node is String) {
      final v = node.trim();
      return _looksLikeUrl(v) ? v : null;
    }

    if (node is List) {
      for (final e in node) {
        final found = _findUrlInJson(e);
        if (found != null) return found;
      }
      return null;
    }

    if (node is Map) {
      dynamic pickKey(String k) {
        for (final e in node.entries) {
          if (e.key is String &&
              (e.key as String).trim().toLowerCase() == k.toLowerCase()) {
            return e.value;
          }
        }
        return null;
      }

      // Prefer common keys.
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
      for (final k in keys) {
        final v = pickKey(k);
        final found = _findUrlInJson(v);
        if (found != null) return found;
      }

      // Then traverse all values.
      for (final v in node.values) {
        final found = _findUrlInJson(v);
        if (found != null) return found;
      }
    }

    return null;
  }

  static Future<Uint8List?> _httpGetLimited(
    Uri uri, {
    required Map<String, String> headers,
    required int limit,
    required Duration timeout,
  }) async {
    final client = LinHttpClientFactory.createHttpClient();
    try {
      final request = await client.getUrl(uri).timeout(timeout);
      request.followRedirects = false;
      request.maxRedirects = 0;
      request.persistentConnection = false;

      request.headers.set('Accept', 'text/plain, application/json, */*');
      for (final e in headers.entries) {
        final k = e.key.trim();
        final v = e.value.trim();
        if (k.isEmpty || v.isEmpty) continue;
        request.headers.set(k, v);
      }

      final response = await request.close().timeout(timeout);
      if (response.statusCode != 200) return null;
      return _readBytesFromStream(response, limit: limit);
    } catch (_) {
      return null;
    } finally {
      try {
        client.close(force: true);
      } catch (_) {}
    }
  }

  static Future<Uint8List> _readBytesFromStream(
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
