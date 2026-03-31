import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;

import '../network/lin_http_client.dart';

class HttpStreamProxyServer {
  HttpStreamProxyServer._();

  static final HttpStreamProxyServer instance = HttpStreamProxyServer._();

  static const int _maxEntries = 256;
  static const Duration _entryTtl = Duration(hours: 6);

  HttpServer? _server;
  Uri? _baseUri;
  http.Client? _client;
  http.Client Function()? _httpClientFactory;
  final Map<String, _HttpStreamProxyEntry> _entries =
      <String, _HttpStreamProxyEntry>{};

  void configureHttpClientFactory(http.Client Function()? factory) {
    _httpClientFactory = factory;
    _client = null;
  }

  Future<Uri> ensureStarted() async {
    final existing = _baseUri;
    if (existing != null && _server != null) return existing;

    final server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
      shared: true,
    );
    _server = server;
    _baseUri = Uri.parse('http://${server.address.address}:${server.port}/');
    unawaited(_serve(server));
    return _baseUri!;
  }

  Future<Uri> registerStream({
    required Uri remoteUri,
    Map<String, String>? httpHeaders,
    String? fileName,
  }) async {
    final base = await ensureStarted();
    _pruneEntries();

    final id = _randomId();
    final safeName = _safeFileName(
      fileName,
      remoteUri.pathSegments.isEmpty ? '' : remoteUri.pathSegments.last,
    );
    _entries[id] = _HttpStreamProxyEntry(
      remoteUri: remoteUri,
      httpHeaders: _sanitizeStoredHeaders(httpHeaders),
      localPathSegments: _localPathSegmentsFor(
        remoteUri: remoteUri,
        fallbackFileName: safeName,
      ),
    );
    _pruneEntries();
    return base.replace(
      pathSegments: <String>[
        ...base.pathSegments.where((s) => s.isNotEmpty),
        'stream',
        id,
        ..._entries[id]!.localPathSegments,
      ],
    );
  }

  static String _randomId() {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final rnd = Random.secure();
    return List<String>.generate(22, (_) => chars[rnd.nextInt(chars.length)])
        .join();
  }

  void _pruneEntries() {
    if (_entries.isEmpty) return;

    final now = DateTime.now();
    final expired = _entries.entries
        .where((e) => e.value.expiresAt.isBefore(now))
        .map((e) => e.key)
        .toList(growable: false);
    for (final key in expired) {
      _entries.remove(key);
    }

    if (_entries.length <= _maxEntries) return;

    final keysByLastAccess = _entries.entries.toList(growable: false)
      ..sort(
        (a, b) => a.value.lastAccessedAt.compareTo(b.value.lastAccessedAt),
      );
    final overflow = _entries.length - _maxEntries;
    for (var i = 0; i < overflow; i++) {
      _entries.remove(keysByLastAccess[i].key);
    }
  }

  Future<void> _serve(HttpServer server) async {
    await for (final request in server) {
      // Best-effort isolation per request.
      unawaited(_handle(request));
    }
  }

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    _OpenedRemote? remote;
    try {
      _pruneEntries();

      final segments = request.uri.pathSegments;
      if (segments.length < 2 || segments[0] != 'stream') {
        response.statusCode = HttpStatus.notFound;
        await response.close();
        return;
      }

      final entry = _entries[segments[1]];
      if (entry == null) {
        response.statusCode = HttpStatus.notFound;
        await response.close();
        return;
      }
      entry.touch();

      final method = request.method.toUpperCase();
      if (method != 'GET' && method != 'HEAD') {
        response.statusCode = HttpStatus.methodNotAllowed;
        response.headers.set(HttpHeaders.allowHeader, 'GET, HEAD');
        await response.close();
        return;
      }

      remote = await _openRemote(
        entry,
        requestUri: request.uri,
        method: method,
        range: request.headers.value(HttpHeaders.rangeHeader),
        ifRange: request.headers.value(HttpHeaders.ifRangeHeader),
      );

      response.statusCode = remote.response.statusCode;
      _copyHeaders(remote.response.headers, response.headers);

      if (method == 'GET') {
        await response.addStream(remote.response.stream);
        remote = null;
      }
    } catch (_) {
      response.statusCode = HttpStatus.badGateway;
      response.headers
          .set(HttpHeaders.contentTypeHeader, 'text/plain; charset=utf-8');
      response.write('HTTP stream proxy error');
    } finally {
      if (remote != null) {
        await remote.close();
      }
      try {
        await response.close();
      } catch (_) {}
    }
  }

  Future<_OpenedRemote> _openRemote(
    _HttpStreamProxyEntry entry, {
    required Uri requestUri,
    required String method,
    String? range,
    String? ifRange,
  }) async {
    if (method == 'HEAD') {
      try {
        final opened = await _openRemoteOnce(
          entry,
          requestUri: requestUri,
          method: 'HEAD',
          range: range,
          ifRange: ifRange,
        );
        if (opened.response.statusCode != HttpStatus.methodNotAllowed) {
          return opened;
        }
        await opened.close();
      } catch (_) {
        // Some cloud-disk download endpoints simply terminate HEAD.
      }

      final fallbackRange = (range != null && range.trim().isNotEmpty)
          ? range.trim()
          : 'bytes=0-0';
      return _openRemoteOnce(
        entry,
        requestUri: requestUri,
        method: 'GET',
        range: fallbackRange,
        ifRange: ifRange,
      );
    }

    return _openRemoteOnce(
      entry,
      requestUri: requestUri,
      method: method,
      range: range,
      ifRange: ifRange,
    );
  }

  Future<_OpenedRemote> _openRemoteOnce(
    _HttpStreamProxyEntry entry, {
    required Uri requestUri,
    required String method,
    String? range,
    String? ifRange,
  }) async {
    final request = http.StreamedRequest(
      method,
      _resolveRemoteUri(entry, requestUri),
    )
      ..followRedirects = true
      ..maxRedirects = 5
      ..persistentConnection = false;
    request.headers[HttpHeaders.acceptHeader] = '*/*';

    for (final e in entry.httpHeaders.entries) {
      request.headers[e.key] = e.value;
    }

    final fixedRange = range?.trim();
    if (fixedRange != null && fixedRange.isNotEmpty) {
      request.headers[HttpHeaders.rangeHeader] = fixedRange;
    }

    final fixedIfRange = ifRange?.trim();
    if (fixedIfRange != null && fixedIfRange.isNotEmpty) {
      request.headers[HttpHeaders.ifRangeHeader] = fixedIfRange;
    }

    unawaited(request.sink.close());
    final response = await _httpClient.send(request);
    return _OpenedRemote(response: response);
  }

  http.Client get _httpClient {
    return _client ??=
        (_httpClientFactory?.call() ??
            LinHttpClientFactory.createClient(
              LinHttpClientFactory.config.copyWith(userAgent: ''),
            ));
  }

  Uri _resolveRemoteUri(_HttpStreamProxyEntry entry, Uri requestUri) {
    final requestedSegments =
        requestUri.pathSegments.length <= 2 ? const <String>[] : requestUri.pathSegments.sublist(2);
    final isTopLevel = _samePathSegments(
      requestedSegments,
      entry.localPathSegments,
    );
    if (isTopLevel && !requestUri.hasQuery) {
      return entry.remoteUri;
    }
    return entry.remoteUri.replace(
      pathSegments: requestedSegments,
      query: requestUri.hasQuery ? requestUri.query : null,
    );
  }

  static Map<String, String> _sanitizeStoredHeaders(
    Map<String, String>? headers,
  ) {
    if (headers == null || headers.isEmpty) return const <String, String>{};

    const blocked = <String>{
      'accept-encoding',
      'connection',
      'content-length',
      'host',
      'if-range',
      'range',
      'transfer-encoding',
    };

    final out = <String, String>{};
    for (final e in headers.entries) {
      final key = e.key.trim();
      final value = e.value.trim();
      if (key.isEmpty || value.isEmpty) continue;
      if (blocked.contains(key.toLowerCase())) continue;
      out[key] = value;
    }
    return out;
  }

  static String _safeFileName(String? preferred, String fallback) {
    final raw =
        (preferred ?? '').trim().isNotEmpty ? preferred!.trim() : fallback;
    final sanitized =
        raw.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_').trim();
    return sanitized.isEmpty ? 'stream.bin' : sanitized;
  }

  static void _copyHeaders(Map<String, String> from, HttpHeaders to) {
    const allow = <String>{
      HttpHeaders.acceptRangesHeader,
      HttpHeaders.cacheControlHeader,
      HttpHeaders.contentLengthHeader,
      HttpHeaders.contentRangeHeader,
      HttpHeaders.contentTypeHeader,
      HttpHeaders.etagHeader,
      HttpHeaders.lastModifiedHeader,
      'content-disposition',
    };

    for (final entry in from.entries) {
      final lower = entry.key.toLowerCase();
      if (!allow.contains(lower)) continue;
      to.set(lower, entry.value);
    }
  }

  static List<String> _localPathSegmentsFor({
    required Uri remoteUri,
    required String fallbackFileName,
  }) {
    final out = <String>[
      for (final segment in remoteUri.pathSegments)
        if (segment.trim().isNotEmpty) segment,
    ];
    if (out.isEmpty) {
      out.add(fallbackFileName);
    }
    return List<String>.unmodifiable(out);
  }

  static bool _samePathSegments(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

class _HttpStreamProxyEntry {
  _HttpStreamProxyEntry({
    required this.remoteUri,
    required this.httpHeaders,
    required this.localPathSegments,
  })  : lastAccessedAt = DateTime.now(),
        expiresAt = DateTime.now().add(HttpStreamProxyServer._entryTtl);

  final Uri remoteUri;
  final Map<String, String> httpHeaders;
  final List<String> localPathSegments;
  DateTime lastAccessedAt;
  DateTime expiresAt;

  void touch() {
    final now = DateTime.now();
    lastAccessedAt = now;
    expiresAt = now.add(HttpStreamProxyServer._entryTtl);
  }
}

class _OpenedRemote {
  _OpenedRemote({
    required this.response,
  });

  final http.StreamedResponse response;

  Future<void> close() async {
    try {
      await response.stream.drain<void>();
    } catch (_) {}
  }
}
