import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:lin_player_server_api/network/lin_http_client.dart';

import '../../app_diagnostics_log.dart';

class StreamRedirectHop {
  const StreamRedirectHop({
    required this.uri,
    required this.statusCode,
    required this.location,
  });

  final Uri uri;
  final int statusCode;
  final Uri? location;
}

class StreamRedirectResolveResult {
  const StreamRedirectResolveResult({
    required this.effectiveUri,
    required this.statusCode,
    this.contentTypeMime,
    this.acceptRanges,
    this.contentRange,
    this.contentLength,
    required this.hops,
    required this.effectiveRequestHeaders,
  });

  final Uri effectiveUri;
  final int statusCode;
  final String? contentTypeMime;
  final String? acceptRanges;
  final String? contentRange;
  final int? contentLength;
  final List<StreamRedirectHop> hops;

  /// Headers to use for requests to [effectiveUri] (includes merged cookies).
  final Map<String, String> effectiveRequestHeaders;
}

class StreamRedirectResolver {
  const StreamRedirectResolver._();

  static final Map<String, _CacheEntry> _cache = <String, _CacheEntry>{};

  static bool _isLocalhostLikeHost(String host) {
    final h = host.trim().toLowerCase();
    return h == 'localhost' || h == '127.0.0.1' || h == '0.0.0.0' || h == '::1';
  }

  static bool _isHttpUrl(Uri uri) {
    final s = uri.scheme.toLowerCase();
    return (s == 'http' || s == 'https') && uri.host.trim().isNotEmpty;
  }

  static bool _isRedirectStatus(int statusCode) {
    return statusCode == 301 ||
        statusCode == 302 ||
        statusCode == 303 ||
        statusCode == 307 ||
        statusCode == 308;
  }

  static String? _getHeaderValue(Map<String, String> headers, String name) {
    final lower = name.toLowerCase();
    for (final e in headers.entries) {
      if (e.key.toLowerCase() == lower) return e.value;
    }
    return null;
  }

  static Map<String, String> _setHeaderValue(
    Map<String, String> headers,
    String name,
    String value,
  ) {
    final out = <String, String>{...headers};
    final lower = name.toLowerCase();
    String? existingKey;
    for (final k in out.keys) {
      if (k.toLowerCase() == lower) {
        existingKey = k;
        break;
      }
    }
    if (existingKey != null) {
      out.remove(existingKey);
    }
    out[name] = value;
    return out;
  }

  static Uri? _resolveLocation(Uri base, String rawLocation) {
    final loc = rawLocation.trim();
    if (loc.isEmpty) return null;
    final parsed = Uri.tryParse(loc);
    if (parsed == null) return null;
    if (parsed.hasScheme) return parsed;
    try {
      return base.resolveUri(parsed);
    } catch (_) {
      return null;
    }
  }

  static Uri _rewriteLocalhostToBaseHost(Uri base, Uri target) {
    if (!_isHttpUrl(target)) return target;
    if (!_isLocalhostLikeHost(target.host)) return target;
    if (base.host.trim().isEmpty || _isLocalhostLikeHost(base.host)) {
      return target;
    }

    final int? port =
        target.hasPort ? target.port : (base.hasPort ? base.port : null);
    return target.replace(
      host: base.host,
      port: port,
    );
  }

  static String _cacheKey(Uri uri, Map<String, String> requestHeaders) {
    final ua =
        (_getHeaderValue(requestHeaders, HttpHeaders.userAgentHeader) ?? '')
            .trim();
    final referer =
        (_getHeaderValue(requestHeaders, HttpHeaders.refererHeader) ?? '')
            .trim();
    final origin = (_getHeaderValue(requestHeaders, 'Origin') ?? '').trim();
    final auth =
        (_getHeaderValue(requestHeaders, HttpHeaders.authorizationHeader) ?? '')
            .trim();
    final cookie =
        (_getHeaderValue(requestHeaders, HttpHeaders.cookieHeader) ?? '')
            .trim();

    final raw = StringBuffer()
      ..write(uri.toString())
      ..write('\nua:')
      ..write(ua)
      ..write('\nref:')
      ..write(referer)
      ..write('\norg:')
      ..write(origin)
      ..write('\nauth:')
      ..write(auth)
      ..write('\nck:')
      ..write(cookie);

    return sha1.convert(utf8.encode(raw.toString())).toString();
  }

  static void _pruneCache({required int maxEntries}) {
    if (_cache.length <= maxEntries) return;
    final now = DateTime.now();
    _cache.removeWhere((_, v) => !v.expiresAt.isAfter(now));
    if (_cache.length <= maxEntries) return;
    _cache.clear();
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

      // Copy headers.
      for (final e in headers.entries) {
        final k = e.key.trim();
        final v = e.value.trim();
        if (k.isEmpty || v.isEmpty) continue;
        request.headers.set(k, v);
      }

      // Merge Cookie header with cookies captured from prior hops.
      final existingCookie = _getHeaderValue(headers, HttpHeaders.cookieHeader);
      final cookieHeader = cookieJar.cookieHeaderFor(
        uri,
        existingCookieHeader: existingCookie,
      );
      if (cookieHeader != null && cookieHeader.isNotEmpty) {
        request.headers.set(HttpHeaders.cookieHeader, cookieHeader);
      }

      // Best-effort: avoid downloading a full response body.
      if (method == 'GET') {
        request.headers.set(HttpHeaders.rangeHeader, 'bytes=0-0');
      }

      final response = await request.close().timeout(timeout);

      final location = response.headers.value(HttpHeaders.locationHeader);
      final cookies = List<Cookie>.from(response.cookies);
      final statusCode = response.statusCode;
      final contentType = response.headers.contentType?.mimeType.trim();
      final acceptRanges = response.headers.value('accept-ranges')?.trim();
      final contentRange =
          response.headers.value(HttpHeaders.contentRangeHeader)?.trim();
      final rawLen = response.contentLength;
      final contentLength = rawLen >= 0 ? rawLen : null;

      return _ResponseMeta(
        statusCode: statusCode,
        location: location?.trim().isEmpty == true ? null : location?.trim(),
        cookies: cookies,
        contentTypeMime:
            (contentType == null || contentType.isEmpty) ? null : contentType,
        acceptRanges: (acceptRanges == null || acceptRanges.isEmpty)
            ? null
            : acceptRanges,
        contentRange: (contentRange == null || contentRange.isEmpty)
            ? null
            : contentRange,
        contentLength: contentLength,
      );
    } on Exception {
      return null;
    } finally {
      try {
        client.close(force: true);
      } catch (_) {}
    }
  }

  static Future<StreamRedirectResolveResult?> resolve(
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

    final origin = uri;

    final shouldCache =
        useCache && cacheTtl > Duration.zero && cacheMaxEntries > 0;
    final cacheKey = shouldCache ? _cacheKey(uri, requestHeaders) : null;
    if (cacheKey != null) {
      final now = DateTime.now();
      final cached = _cache[cacheKey];
      if (cached != null) {
        if (cached.expiresAt.isAfter(now)) {
          return cached.value;
        }
        _cache.remove(cacheKey);
      }
    }

    var current = uri;
    final visited = <String>{};
    final hops = <StreamRedirectHop>[];
    final cookieJar = _CookieJar();

    for (var i = 0; i <= maxRedirects; i++) {
      final visitKey = current.toString();
      if (!visited.add(visitKey)) {
        break;
      }

      var meta = await _requestMeta(
        current,
        method: 'HEAD',
        headers: requestHeaders,
        cookieJar: cookieJar,
        timeout: timeout,
      );

      if ((meta == null || meta.statusCode == 405) && allowGetFallback) {
        AppDiagnosticsLogger.instance.info(
          'redirect',
          'HEAD probe unavailable, falling back to GET',
          data: <String, Object?>{
            'url': AppDiagnosticsLogger.summarizeUrl(current.toString()),
            'reason': meta == null ? 'head_failed' : 'status_405',
          },
        );
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

      final statusCode = meta.statusCode;
      final location = meta.location;

      if (_isRedirectStatus(statusCode) &&
          location != null &&
          i < maxRedirects) {
        final next0 = _resolveLocation(current, location);
        final next =
            next0 == null ? null : _rewriteLocalhostToBaseHost(origin, next0);
        hops.add(
          StreamRedirectHop(
            uri: current,
            statusCode: statusCode,
            location: next,
          ),
        );
        if (next == null) break;
        current = next;
        continue;
      }

      final mergedHeaders = cookieJar.applyToHeaders(
        current,
        requestHeaders,
      );

      final result = StreamRedirectResolveResult(
        effectiveUri: current,
        statusCode: statusCode,
        contentTypeMime: meta.contentTypeMime,
        acceptRanges: meta.acceptRanges,
        contentRange: meta.contentRange,
        contentLength: meta.contentLength,
        hops: List<StreamRedirectHop>.unmodifiable(hops),
        effectiveRequestHeaders: mergedHeaders,
      );

      if (cacheKey != null) {
        final now = DateTime.now();
        _cache[cacheKey] = _CacheEntry(
          value: result,
          expiresAt: now.add(cacheTtl),
        );
        _pruneCache(maxEntries: cacheMaxEntries);
        if (_cache.isEmpty) {
          _cache[cacheKey] = _CacheEntry(
            value: result,
            expiresAt: now.add(cacheTtl),
          );
        }
      }

      return result;
    }

    final mergedHeaders = cookieJar.applyToHeaders(
      current,
      requestHeaders,
    );
    final result = StreamRedirectResolveResult(
      effectiveUri: current,
      statusCode: 0,
      contentTypeMime: null,
      acceptRanges: null,
      contentRange: null,
      contentLength: null,
      hops: List<StreamRedirectHop>.unmodifiable(hops),
      effectiveRequestHeaders: mergedHeaders,
    );

    return result;
  }
}

class _CacheEntry {
  const _CacheEntry({
    required this.value,
    required this.expiresAt,
  });

  final StreamRedirectResolveResult value;
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
    required this.contentLength,
  });

  final int statusCode;
  final String? location;
  final List<Cookie> cookies;
  final String? contentTypeMime;
  final String? acceptRanges;
  final String? contentRange;
  final int? contentLength;
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
    final exp = expiresAt;
    if (exp == null) return false;
    return !exp.isAfter(now);
  }
}

class _CookieJar {
  final List<_StoredCookie> _cookies = <_StoredCookie>[];

  void storeFromResponse(Uri origin, List<Cookie> cookies) {
    final host = origin.host.trim().toLowerCase();
    if (host.isEmpty || cookies.isEmpty) return;

    final now = DateTime.now().toUtc();

    for (final c in cookies) {
      final name = c.name.trim();
      if (name.isEmpty) continue;

      final value = c.value;
      final rawDomain = (c.domain ?? '').trim().toLowerCase();
      final domain =
          rawDomain.startsWith('.') ? rawDomain.substring(1) : rawDomain;
      final hostOnly = domain.isEmpty;

      // Reject obviously invalid domains (avoid leaking cookies cross-site).
      if (!hostOnly && !_hostMatchesDomain(host, domain)) {
        continue;
      }

      final path = (c.path ?? '').trim();
      final fixedPath = path.isEmpty ? '/' : path;

      DateTime? expiresAt;
      final expires = c.expires;
      if (expires != null) {
        expiresAt = expires.isUtc ? expires : expires.toUtc();
      }
      final maxAge = c.maxAge;
      if (maxAge != null) {
        if (maxAge <= 0) {
          expiresAt = now.subtract(const Duration(seconds: 1));
        } else {
          expiresAt = now.add(Duration(seconds: maxAge));
        }
      }

      final stored = _StoredCookie(
        name: name,
        value: value,
        originHost: host,
        domain: hostOnly ? host : domain,
        hostOnly: hostOnly,
        path: fixedPath,
        secure: c.secure,
        expiresAt: expiresAt,
      );

      _cookies.removeWhere(
        (e) =>
            e.name == stored.name &&
            e.domain == stored.domain &&
            e.hostOnly == stored.hostOnly &&
            e.path == stored.path &&
            e.originHost == stored.originHost,
      );

      if (!stored.isExpired(now)) {
        _cookies.add(stored);
      }
    }

    // Best-effort pruning.
    _cookies.removeWhere((e) => e.isExpired(now));
    if (_cookies.length > 256) {
      _cookies.removeRange(0, _cookies.length - 256);
    }
  }

  Map<String, String> applyToHeaders(Uri uri, Map<String, String> headers) {
    final cookieHeader = cookieHeaderFor(uri,
        existingCookieHeader: StreamRedirectResolver._getHeaderValue(
            headers, HttpHeaders.cookieHeader));
    if (cookieHeader == null || cookieHeader.trim().isEmpty) return headers;
    return StreamRedirectResolver._setHeaderValue(
      headers,
      HttpHeaders.cookieHeader,
      cookieHeader,
    );
  }

  String? cookieHeaderFor(
    Uri uri, {
    String? existingCookieHeader,
  }) {
    final now = DateTime.now().toUtc();
    final host = uri.host.trim().toLowerCase();
    if (host.isEmpty) return existingCookieHeader;

    final path = (uri.path.trim().isEmpty ? '/' : uri.path.trim());
    final existing = _parseCookieHeader(existingCookieHeader);
    final out = <String, String>{...existing};

    for (final c in _cookies) {
      if (c.isExpired(now)) continue;
      if (c.secure && uri.scheme.toLowerCase() != 'https') continue;

      final hostOk =
          c.hostOnly ? (host == c.domain) : _hostMatchesDomain(host, c.domain);
      if (!hostOk) continue;

      final cookiePath = c.path.isEmpty ? '/' : c.path;
      if (!path.startsWith(cookiePath)) continue;

      out[c.name] = c.value;
    }

    if (out.isEmpty) return null;

    final parts = <String>[];
    for (final e in out.entries) {
      final k = e.key.trim();
      if (k.isEmpty) continue;
      parts.add('$k=${e.value}');
    }
    return parts.isEmpty ? null : parts.join('; ');
  }

  static Map<String, String> _parseCookieHeader(String? raw) {
    final v = (raw ?? '').trim();
    if (v.isEmpty) return const <String, String>{};

    final out = <String, String>{};
    for (final part in v.split(';')) {
      final p = part.trim();
      if (p.isEmpty) continue;
      final idx = p.indexOf('=');
      if (idx <= 0) continue;
      final name = p.substring(0, idx).trim();
      final value = p.substring(idx + 1).trim();
      if (name.isEmpty) continue;
      out[name] = value;
    }
    return out;
  }

  static bool _hostMatchesDomain(String host, String domain) {
    final h = host.trim().toLowerCase();
    final d = domain.trim().toLowerCase();
    if (h.isEmpty || d.isEmpty) return false;
    if (h == d) return true;
    return h.endsWith('.$d');
  }
}
