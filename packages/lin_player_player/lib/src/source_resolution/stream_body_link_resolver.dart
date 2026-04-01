import 'dart:convert';
import 'dart:typed_data';

import 'package:lin_player_server_api/network/lin_http_client.dart';

typedef StreamBodyLink = ({String url, Map<String, String> httpHeaders});

class StreamBodyLinkResolver {
  const StreamBodyLinkResolver._();

  static bool _isLocalhostLikeHost(String host) {
    final fixed = host.trim().toLowerCase();
    return fixed == 'localhost' ||
        fixed == '127.0.0.1' ||
        fixed == '0.0.0.0' ||
        fixed == '::1';
  }

  static bool _isHttpUrl(Uri uri) {
    final scheme = uri.scheme.toLowerCase();
    return (scheme == 'http' || scheme == 'https') &&
        uri.host.trim().isNotEmpty;
  }

  static bool _looksLikeUrl(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return false;
    return value.startsWith('http://') ||
        value.startsWith('https://') ||
        value.startsWith('file://');
  }

  static Future<StreamBodyLink?> resolve(
    Uri uri, {
    required Map<String, String> requestHeaders,
    String? contentTypeHint,
    int maxBytes = 16 * 1024,
    Duration timeout = const Duration(seconds: 4),
  }) async {
    if (!_shouldResolveBodyLink(contentTypeHint: contentTypeHint)) return null;
    if (!_isHttpUrl(uri) || maxBytes <= 0) return null;

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
    if (trimmed.isEmpty || trimmed.startsWith('#EXTM3U')) return null;

    if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
      try {
        final decoded = jsonDecode(trimmed);
        final found = _findUrlInJson(decoded);
        if (found != null && found.trim().isNotEmpty) {
          final resolved = _resolveMaybeRelative(base, found.trim()) ?? found.trim();
          final rewritten = _rewriteLocalhostToBaseHost(base, resolved);
          final parsed = _parseFirstTarget(rewritten);
          if (parsed != null) {
            return (url: parsed.url, httpHeaders: parsed.httpHeaders);
          }
          return (url: rewritten, httpHeaders: const <String, String>{});
        }
      } catch (_) {}
    }

    final parsed = _parseFirstTarget(trimmed);
    if (parsed != null && parsed.url.trim().isNotEmpty) {
      final resolved = _resolveMaybeRelative(base, parsed.url.trim()) ??
          parsed.url.trim();
      final rewritten = _rewriteLocalhostToBaseHost(base, resolved);
      return (url: rewritten, httpHeaders: parsed.httpHeaders);
    }

    final match = RegExp(r'''https?://[^\s"'<>]+''').firstMatch(trimmed);
    final url = match?.group(0)?.trim();
    if (url == null || url.isEmpty || !_looksLikeUrl(url)) return null;
    final resolved = _resolveMaybeRelative(base, url) ?? url;
    return (
      url: _rewriteLocalhostToBaseHost(base, resolved),
      httpHeaders: const <String, String>{},
    );
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

  static String? _findUrlInJson(dynamic node) {
    if (node == null) return null;

    if (node is String) {
      final value = node.trim();
      return _looksLikeUrl(value) ? value : null;
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

    if (key != 'http-header') return;
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
    if (eq2 <= 0) return;
    final name = headerValue.substring(0, eq2).trim();
    final headerData = headerValue.substring(eq2 + 1).trim();
    if (name.isNotEmpty && headerData.isNotEmpty) {
      out[_canonicalHeaderName(name)] = headerData;
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

  static String _rewriteLocalhostToBaseHost(Uri base, String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || !_isHttpUrl(uri)) return url;
    if (!_isLocalhostLikeHost(uri.host)) return url;
    if (base.host.trim().isEmpty || _isLocalhostLikeHost(base.host)) return url;

    final scheme = uri.scheme.isNotEmpty ? uri.scheme : base.scheme;
    if (!uri.hasPort && base.hasPort) {
      return uri
          .replace(
            scheme: scheme,
            host: base.host,
            port: base.port,
          )
          .toString();
    }
    return uri.replace(scheme: scheme, host: base.host).toString();
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
      for (final entry in headers.entries) {
        final key = entry.key.trim();
        final value = entry.value.trim();
        if (key.isEmpty || value.isEmpty) continue;
        request.headers.set(key, value);
      }

      final response = await request.close().timeout(timeout);
      if (response.statusCode != 200) return null;
      final bytes = await _readBytesFromStream(response, limit: limit);
      return bytes;
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

typedef _ParsedUrlWithHeaders = ({String url, Map<String, String> httpHeaders});
