import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

class StrmTarget {
  StrmTarget({
    required String url,
    Map<String, String>? httpHeaders,
  })  : url = url.trim(),
        httpHeaders = Map.unmodifiable(
          (httpHeaders ?? const <String, String>{})
              .map((k, v) => MapEntry(k.trim(), v)),
        );

  final String url;
  final Map<String, String> httpHeaders;
}

class StrmResolution {
  const StrmResolution._({
    required this.targets,
    this.error,
    this.suggestDirectPlayFallback = false,
  });

  factory StrmResolution.success(List<StrmTarget> targets) {
    return StrmResolution._(targets: List<StrmTarget>.unmodifiable(targets));
  }

  factory StrmResolution.failure(
    String error, {
    bool suggestDirectPlayFallback = false,
  }) {
    return StrmResolution._(
      targets: const <StrmTarget>[],
      error: error.trim().isEmpty ? 'STRM 解析失败' : error.trim(),
      suggestDirectPlayFallback: suggestDirectPlayFallback,
    );
  }

  final List<StrmTarget> targets;
  final String? error;

  /// If true, callers may try to play the original `.strm` URL/path directly.
  /// This is useful when the source looks like a direct media resource even if
  /// it has a `.strm` suffix (misnamed, server-side rewrite, etc.).
  final bool suggestDirectPlayFallback;

  bool get isSuccess => targets.isNotEmpty;
}

class StrmResolver {
  const StrmResolver._();

  static const int _maxStrmBytes = 64 * 1024;
  static const int _maxTargets = 20;
  static const int _maxCacheEntries = 128;

  static final Map<String, StrmResolution> _cache = <String, StrmResolution>{};

  static bool looksLikeStrmPathOrUrl(String raw) {
    final v = raw.trim();
    if (v.isEmpty) return false;

    final uri = Uri.tryParse(v);
    if (uri != null && uri.path.isNotEmpty) {
      final name = uri.pathSegments.isNotEmpty ? uri.pathSegments.last : uri.path;
      return name.toLowerCase().endsWith('.strm');
    }

    final cleaned = _stripQueryAndFragment(v);
    return cleaned.toLowerCase().endsWith('.strm');
  }

  static bool looksLikeStrmFileName(String raw) {
    final v = raw.trim().toLowerCase();
    return v.endsWith('.strm');
  }

  static Future<StrmResolution> resolve({
    required String sourcePathOrUrl,
    String? fileName,
    List<int>? bytes,
    Stream<List<int>>? readStream,
    Map<String, String>? httpHeaders,
  }) async {
    final source = sourcePathOrUrl.trim();
    final hasBytes = bytes != null && bytes.isNotEmpty;
    final hasStream = readStream != null;
    if (source.isEmpty && !hasBytes && !hasStream) {
      return StrmResolution.failure('STRM 源为空');
    }

    final canCache = !hasBytes &&
        !hasStream &&
        source.isNotEmpty &&
        (httpHeaders == null || httpHeaders.isEmpty);
    final cacheKey = canCache ? 'src:$source' : null;
    if (cacheKey != null) {
      final cached = _cache[cacheKey];
      if (cached != null && cached.isSuccess) return cached;
    }

    final read = await _readStrmText(
      source,
      bytes: bytes,
      readStream: readStream,
      httpHeaders: httpHeaders,
    );
    if (read == null) {
      final uri = Uri.tryParse(source);
      final isHttpUrl = uri != null &&
          (uri.scheme == 'http' || uri.scheme == 'https') &&
          uri.host.isNotEmpty;
      return StrmResolution.failure(
        uri != null && uri.scheme == 'content'
            ? '无法读取 STRM：content:// URI 需要 readStream'
            : '无法读取 STRM 内容',
        suggestDirectPlayFallback: isHttpUrl,
      );
    }

    final parsed = _parseTargets(read.text);
    if (parsed.isEmpty) {
      final uri = Uri.tryParse(source);
      final isHttpUrl = uri != null &&
          (uri.scheme == 'http' || uri.scheme == 'https') &&
          uri.host.isNotEmpty;
      return StrmResolution.failure(
        'STRM 内容中未找到可播放链接',
        suggestDirectPlayFallback: isHttpUrl || read.truncated,
      );
    }

    final targets = <StrmTarget>[];
    for (final t in parsed) {
      final ref = t.url.trim();
      if (ref.isEmpty) continue;

      final resolved = source.isEmpty ? ref : (_resolveReference(source, ref));
      final url = (resolved ?? ref).trim();
      if (url.isEmpty) continue;
      targets.add(StrmTarget(url: url, httpHeaders: t.httpHeaders));
      if (targets.length >= _maxTargets) break;
    }
    if (targets.isEmpty) {
      final uri = Uri.tryParse(source);
      final isHttpUrl = uri != null &&
          (uri.scheme == 'http' || uri.scheme == 'https') &&
          uri.host.isNotEmpty;
      return StrmResolution.failure(
        'STRM 链接解析失败',
        suggestDirectPlayFallback: isHttpUrl || read.truncated,
      );
    }

    final result = StrmResolution.success(targets);

    if (cacheKey != null) {
      _cache[cacheKey] = result;
      if (_cache.length > _maxCacheEntries) {
        // Keep it simple: bounded best-effort cache.
        _cache.clear();
        _cache[cacheKey] = result;
      }
    }
    return result;
  }

  static Future<String?> resolveTarget({
    required String sourcePathOrUrl,
    String? fileName,
    List<int>? bytes,
    Stream<List<int>>? readStream,
    Map<String, String>? httpHeaders,
  }) async {
    final r = await resolve(
      sourcePathOrUrl: sourcePathOrUrl,
      fileName: fileName,
      bytes: bytes,
      readStream: readStream,
      httpHeaders: httpHeaders,
    );
    return r.targets.isEmpty ? null : r.targets.first.url;
  }

  static String? parseFirstTargetLine(String raw) {
    final targets = _parseTargets(raw);
    if (targets.isEmpty) return null;
    final first = targets.first.url.trim();
    return first.isEmpty ? null : first;
  }

  static List<_StrmParsedTarget> _parseTargets(String raw) {
    var text = raw;
    if (text.startsWith('\uFEFF')) {
      text = text.substring(1);
    }

    final out = <_StrmParsedTarget>[];
    final pendingHeaders = <String, String>{};

    for (final line in text.split(RegExp(r'\r?\n'))) {
      var v = line.trim();
      if (v.isEmpty) continue;

      if (v.startsWith('\uFEFF')) v = v.substring(1).trim();

      if (v.startsWith('#EXTVLCOPT:') || v.startsWith('#extvlcopt:')) {
        _parseExtVlcOpt(v, pendingHeaders);
        continue;
      }

      if (v.startsWith('#')) continue;
      if (v.startsWith(';')) continue;
      if (v.startsWith('//')) continue;
      if (v.startsWith('/*') || v.startsWith('*')) continue;

      // Strip optional quotes.
      if ((v.startsWith('"') && v.endsWith('"')) ||
          (v.startsWith("'") && v.endsWith("'"))) {
        v = v.substring(1, v.length - 1).trim();
      }

      if (v.startsWith('\uFEFF')) v = v.substring(1).trim();

      final split = _splitUrlAndPipeOptions(v);
      final url = split.$1.trim();
      if (url.isEmpty) continue;

      final headers = <String, String>{};
      if (pendingHeaders.isNotEmpty) {
        headers.addAll(pendingHeaders);
        pendingHeaders.clear();
      }
      final pipeHeaders = _parsePipeHeaderOptions(split.$2);
      if (pipeHeaders.isNotEmpty) headers.addAll(pipeHeaders);

      out.add(_StrmParsedTarget(url: url, httpHeaders: headers));
      if (out.length >= _maxTargets) break;
    }

    return out;
  }

  static (String, String?) _splitUrlAndPipeOptions(String input) {
    final idx = input.indexOf('|');
    if (idx < 0) return (input, null);
    final url = input.substring(0, idx);
    final opts = idx + 1 < input.length ? input.substring(idx + 1) : '';
    return (url, opts.isEmpty ? null : opts);
  }

  static void _parseExtVlcOpt(String line, Map<String, String> out) {
    final idx = line.indexOf(':');
    if (idx < 0 || idx + 1 >= line.length) return;
    final rest = line.substring(idx + 1).trim();
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
      final hv = value.trim();
      final sep = hv.indexOf(':');
      if (sep > 0) {
        final name = hv.substring(0, sep).trim();
        final v = hv.substring(sep + 1).trim();
        if (name.isNotEmpty && v.isNotEmpty) {
          out[_canonicalHeaderName(name)] = v;
        }
        return;
      }
      final eq2 = hv.indexOf('=');
      if (eq2 > 0) {
        final name = hv.substring(0, eq2).trim();
        final v = hv.substring(eq2 + 1).trim();
        if (name.isNotEmpty && v.isNotEmpty) {
          out[_canonicalHeaderName(name)] = v;
        }
      }
    }
  }

  static Map<String, String> _parsePipeHeaderOptions(String? raw) {
    final input = (raw ?? '').trim();
    if (input.isEmpty) return const <String, String>{};

    final out = <String, String>{};
    for (final part in input.split('&')) {
      final p = part.trim();
      if (p.isEmpty) continue;
      final eq = p.indexOf('=');
      if (eq <= 0) continue;
      final rawKey = p.substring(0, eq).trim();
      final rawVal = p.substring(eq + 1).trim();
      if (rawKey.isEmpty || rawVal.isEmpty) continue;
      try {
        final key = Uri.decodeQueryComponent(rawKey).trim();
        final value = Uri.decodeQueryComponent(rawVal).trim();
        if (key.isEmpty || value.isEmpty) continue;
        out[_canonicalHeaderName(key)] = value;
      } catch (_) {
        out[_canonicalHeaderName(rawKey)] = rawVal;
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

  static Future<_StrmReadResult?> _readStrmText(
    String source, {
    List<int>? bytes,
    Stream<List<int>>? readStream,
    Map<String, String>? httpHeaders,
  }) async {
    final limit = _maxStrmBytes + 1;

    if (bytes != null) {
      final truncated = bytes.length > _maxStrmBytes;
      final slice = bytes.length > _maxStrmBytes ? bytes.sublist(0, _maxStrmBytes) : bytes;
      return _StrmReadResult(
        text: utf8.decode(slice, allowMalformed: true),
        truncated: truncated,
      );
    }

    if (readStream != null) {
      try {
        final r = await _readBytesFromStream(readStream, limit: limit);
        final truncated = r.length > _maxStrmBytes;
        final slice =
            truncated ? r.sublist(0, _maxStrmBytes) : r;
        return _StrmReadResult(
          text: utf8.decode(slice, allowMalformed: true),
          truncated: truncated,
        );
      } catch (_) {
        return null;
      }
    }

    final uri = Uri.tryParse(source);
    final isHttpUrl = uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;

    if (isHttpUrl) {
      try {
        final resp = await _httpGetLimited(uri, limit: limit, headers: httpHeaders);
        if (resp == null) return null;
        final truncated = resp.bytes.length > _maxStrmBytes;
        final slice =
            truncated ? resp.bytes.sublist(0, _maxStrmBytes) : resp.bytes;
        return _StrmReadResult(
          text: utf8.decode(slice, allowMalformed: true),
          truncated: truncated,
        );
      } catch (_) {
        return null;
      }
    }

    if (kIsWeb) return null;

    try {
      final filePath = (uri != null && uri.scheme.toLowerCase() == 'file')
          ? (() {
              try {
                return uri.toFilePath();
              } catch (_) {
                return source;
              }
            })()
          : source;
      final file = File(filePath);
      if (!await file.exists()) return null;
      final stream = file.openRead(0, limit);
      final data = await _readBytesFromStream(stream, limit: limit);
      final truncated = data.length > _maxStrmBytes;
      final slice =
          truncated ? data.sublist(0, _maxStrmBytes) : data;
      return _StrmReadResult(
        text: utf8.decode(slice, allowMalformed: true),
        truncated: truncated,
      );
    } catch (_) {
      return null;
    }
  }

  static Future<Uint8List> _readBytesFromStream(
    Stream<List<int>> stream, {
    required int limit,
  }) async {
    final builder = BytesBuilder(copy: false);
    late StreamSubscription<List<int>> sub;
    final completer = Completer<Uint8List>();

    void finish() {
      if (completer.isCompleted) return;
      completer.complete(builder.takeBytes());
    }

    sub = stream.listen(
      (chunk) {
        if (builder.length >= limit) {
          // Already reached limit; stop.
          // ignore: unawaited_futures
          sub.cancel();
          finish();
          return;
        }
        final remaining = limit - builder.length;
        if (chunk.length <= remaining) {
          builder.add(chunk);
        } else {
          builder.add(chunk.sublist(0, remaining));
        }
        if (builder.length >= limit) {
          // ignore: unawaited_futures
          sub.cancel();
          finish();
        }
      },
      onError: (_) {
        if (!completer.isCompleted) {
          completer.completeError(StateError('read error'));
        }
      },
      onDone: finish,
      cancelOnError: true,
    );

    return completer.future;
  }

  static Future<_HttpLimitedResponse?> _httpGetLimited(
    Uri uri, {
    required int limit,
    Map<String, String>? headers,
  }) async {
    final client = http.Client();
    try {
      final req = http.Request('GET', uri);
      req.followRedirects = true;
      req.maxRedirects = 5;
      req.headers['Accept'] = 'text/plain, */*';
      if (headers != null && headers.isNotEmpty) {
        req.headers.addAll(headers);
      }
      final resp = await client.send(req);
      if (resp.statusCode != 200) return null;
      final data = await _readBytesFromStream(resp.stream, limit: limit);
      return _HttpLimitedResponse(bytes: data);
    } finally {
      client.close();
    }
  }

  static String _stripQueryAndFragment(String input) {
    final q = input.indexOf('?');
    final f = input.indexOf('#');
    final cut = (q >= 0 && f >= 0) ? (q < f ? q : f) : (q >= 0 ? q : f);
    return cut >= 0 ? input.substring(0, cut) : input;
  }

  static String? _resolveReference(String baseSource, String ref) {
    final v = ref.trim();
    if (v.isEmpty) return null;

    final base = baseSource.trim();
    final baseLooksLikeWindowsPath =
        RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(base) || base.startsWith('\\\\');
    if (baseLooksLikeWindowsPath) {
      try {
        final resolved = Uri.file(base).resolve(v);
        return resolved.toFilePath();
      } catch (_) {
        return v;
      }
    }

    // Windows absolute paths like C:\ or C:/.
    if (RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(v)) {
      return v;
    }
    // UNC path like \\server\share\file.
    if (v.startsWith('\\\\')) return v;

    final uri = Uri.tryParse(v);
    if (uri != null && uri.scheme.isNotEmpty) {
      if (uri.scheme.toLowerCase() == 'file') {
        try {
          return uri.toFilePath();
        } catch (_) {
          return v;
        }
      }
      return v;
    }

    // Relative reference.
    final baseUri = Uri.tryParse(baseSource);
    if (baseUri != null && baseUri.scheme.isNotEmpty) {
      // URL base.
      try {
        return baseUri.resolve(v).toString();
      } catch (_) {
        return v;
      }
    }

    // Local file base.
    try {
      final resolved = Uri.file(baseSource).resolve(v);
      return resolved.toFilePath();
    } catch (_) {
      return v;
    }
  }
}

class _StrmParsedTarget {
  final String url;
  final Map<String, String> httpHeaders;
  const _StrmParsedTarget({required this.url, required this.httpHeaders});
}

class _StrmReadResult {
  final String text;
  final bool truncated;
  const _StrmReadResult({required this.text, required this.truncated});
}

class _HttpLimitedResponse {
  final Uint8List bytes;
  const _HttpLimitedResponse({required this.bytes});
}
