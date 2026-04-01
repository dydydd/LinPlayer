import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:lin_player_server_api/network/lin_http_client.dart';

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
  final Map<String, String> effectiveRequestHeaders;
}

class StreamRedirectResolver {
  const StreamRedirectResolver._();

  static final Map<String, _CacheEntry> _cache = <String, _CacheEntry>{};

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

  static bool _isRedirectStatus(int statusCode) {
    return statusCode == 301 ||
        statusCode == 302 ||
        statusCode == 303 ||
        statusCode == 307 ||
        statusCode == 308;
  }

  static String? getHeaderValue(Map<String, String> headers, String name) {
    final lower = name.toLowerCase();
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == lower) return entry.value;
    }
    return null;
  }

  static Map<String, String> setHeaderValue(
    Map<String, String> headers,
    String name,
    String value,
  ) {
    final out = <String, String>{...headers};
    final lower = name.toLowerCase();
    String? existingKey;
    for (final key in out.keys) {
      if (key.toLowerCase() == lower) {
        existingKey = key;
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

  static Uri _rewriteLocalhostToBaseHost(Uri base, Uri target) {
    if (!_isHttpUrl(target)) return target;
    if (!_isLocalhostLikeHost(target.host)) return target;
    if (base.host.trim().isEmpty || _isLocalhostLikeHost(base.host)) {
      return target;
    }

    final port = target.hasPort
        ? target.port
        : (base.hasPort ? base.port : null);
    return target.replace(host: base.host, port: port);
  }

  static String _cacheKey(Uri uri, Map<String, String> requestHeaders) {
    final userAgent =
        (getHeaderValue(requestHeaders, HttpHeaders.userAgentHeader) ?? '')
            .trim();
    final referer =
        (getHeaderValue(requestHeaders, HttpHeaders.refererHeader) ?? '')
            .trim();
    final origin = (getHeaderValue(requestHeaders, 'Origin') ?? '').trim();
    final authorization = (getHeaderValue(
              requestHeaders,
              HttpHeaders.authorizationHeader,
            ) ??
            '')
        .trim();
    final cookie =
        (getHeaderValue(requestHeaders, HttpHeaders.cookieHeader) ?? '').trim();

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

      final existingCookie = getHeaderValue(headers, HttpHeaders.cookieHeader);
      final cookieHeader = cookieJar.cookieHeaderFor(
        uri,
        existingCookieHeader: existingCookie,
      );
      if (cookieHeader != null && cookieHeader.isNotEmpty) {
        request.headers.set(HttpHeaders.cookieHeader, cookieHeader);
      }

      if (method == 'GET') {
        request.headers.set(HttpHeaders.rangeHeader, 'bytes=0-0');
      }

      final response = await request.close().timeout(timeout);
      final rawLength = response.contentLength;
      return _ResponseMeta(
        statusCode: response.statusCode,
        location: response.headers.value(HttpHeaders.locationHeader)?.trim(),
        cookies: List<Cookie>.from(response.cookies),
        contentTypeMime: response.headers.contentType?.mimeType.trim(),
        acceptRanges: response.headers.value(HttpHeaders.acceptRangesHeader)?.trim(),
        contentRange:
            response.headers.value(HttpHeaders.contentRangeHeader)?.trim(),
        contentLength: rawLength >= 0 ? rawLength : null,
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
        if (cached.expiresAt.isAfter(now)) return cached.value;
        _cache.remove(cacheKey);
      }
    }

    var current = uri;
    final visited = <String>{};
    final hops = <StreamRedirectHop>[];
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
        final next0 = _resolveLocation(current, meta.location!);
        final next =
            next0 == null ? null : _rewriteLocalhostToBaseHost(origin, next0);
        hops.add(
          StreamRedirectHop(
            uri: current,
            statusCode: meta.statusCode,
            location: next,
          ),
        );
        if (next == null) break;
        current = next;
        continue;
      }

      final result = StreamRedirectResolveResult(
        effectiveUri: current,
        statusCode: meta.statusCode,
        contentTypeMime: meta.contentTypeMime,
        acceptRanges: meta.acceptRanges,
        contentRange: meta.contentRange,
        contentLength: meta.contentLength,
        hops: List<StreamRedirectHop>.unmodifiable(hops),
        effectiveRequestHeaders: cookieJar.applyToHeaders(current, requestHeaders),
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

    return StreamRedirectResolveResult(
      effectiveUri: current,
      statusCode: 0,
      contentTypeMime: null,
      acceptRanges: null,
      contentRange: null,
      contentLength: null,
      hops: List<StreamRedirectHop>.unmodifiable(hops),
      effectiveRequestHeaders: cookieJar.applyToHeaders(current, requestHeaders),
    );
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
          StreamRedirectResolver.getHeaderValue(headers, HttpHeaders.cookieHeader),
    );
    if (cookieHeader == null || cookieHeader.trim().isEmpty) return headers;
    return StreamRedirectResolver.setHeaderValue(
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
