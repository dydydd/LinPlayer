import 'dart:async';

import 'src/strm_target_parser.dart';
import 'src/strm_text_reader.dart';

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

    final parsed = StrmTargetParser.parse(read.text, maxTargets: _maxTargets);
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
    return StrmTargetParser.parseFirstTargetLine(raw);
  }

  static Future<StrmTextReadResult?> _readStrmText(
    String source, {
    List<int>? bytes,
    Stream<List<int>>? readStream,
    Map<String, String>? httpHeaders,
  }) async {
    return StrmTextReader.read(
      source,
      bytes: bytes,
      readStream: readStream,
      httpHeaders: httpHeaders,
      maxBytes: _maxStrmBytes,
    );
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
