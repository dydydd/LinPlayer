import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

class StrmResolver {
  const StrmResolver._();

  static const int _maxStrmBytes = 64 * 1024;
  static const int _maxCacheEntries = 128;

  static final Map<String, String> _cache = <String, String>{};

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

  static Future<String?> resolveTarget({
    required String sourcePathOrUrl,
    String? fileName,
    List<int>? bytes,
    Map<String, String>? httpHeaders,
  }) async {
    final source = sourcePathOrUrl.trim();
    final hasBytes = bytes != null && bytes.isNotEmpty;
    if (source.isEmpty && !hasBytes) return null;

    final cacheKey = source.isEmpty ? null : 'src:$source';
    if (cacheKey != null) {
      final cached = _cache[cacheKey];
      if (cached != null && cached.isNotEmpty) return cached;
    }

    final text = await _readStrmText(
      source,
      bytes: bytes,
      httpHeaders: httpHeaders,
    );
    if (text == null) return null;

    final first = parseFirstTargetLine(text);
    if (first == null || first.isEmpty) return null;

    final resolved = source.isEmpty ? first : _resolveReference(source, first);
    if (resolved == null || resolved.isEmpty) return null;

    if (cacheKey != null) {
      _cache[cacheKey] = resolved;
      if (_cache.length > _maxCacheEntries) {
        // Keep it simple: bounded best-effort cache.
        _cache.clear();
        _cache[cacheKey] = resolved;
      }
    }
    return resolved;
  }

  static String? parseFirstTargetLine(String raw) {
    var text = raw;
    if (text.startsWith('\uFEFF')) {
      text = text.substring(1);
    }

    for (final line in text.split(RegExp(r'\r?\n'))) {
      var v = line.trim();
      if (v.isEmpty) continue;
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
      return v;
    }

    return null;
  }

  static Future<String?> _readStrmText(
    String source, {
    List<int>? bytes,
    Map<String, String>? httpHeaders,
  }) async {
    if (bytes != null) {
      if (bytes.length > _maxStrmBytes) return null;
      return utf8.decode(bytes, allowMalformed: true);
    }

    final uri = Uri.tryParse(source);
    final isHttpUrl = uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;

    if (isHttpUrl) {
      try {
        final resp = await http.get(uri, headers: httpHeaders);
        if (resp.statusCode != 200) return null;
        if (resp.bodyBytes.length > _maxStrmBytes) return null;
        return utf8.decode(resp.bodyBytes, allowMalformed: true);
      } catch (_) {
        return null;
      }
    }

    if (kIsWeb) return null;

    try {
      final file = File(source);
      if (!await file.exists()) return null;
      final data = await file.readAsBytes();
      if (data.length > _maxStrmBytes) return null;
      return utf8.decode(data, allowMalformed: true);
    } catch (_) {
      return null;
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
