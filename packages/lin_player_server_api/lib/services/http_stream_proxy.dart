import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import '../network/lin_http_client.dart';

class HttpStreamProxyServer {
  HttpStreamProxyServer._();

  static final HttpStreamProxyServer instance = HttpStreamProxyServer._();

  static const int _maxEntries = 256;
  static const Duration _entryTtl = Duration(hours: 6);
  static const int _maxCachedRangesPerEntry = 4;
  static const int _maxCachedBytesPerEntry = 24 * 1024 * 1024;
  static const Duration _warmupWaitTimeout = Duration(milliseconds: 1200);
  static const Duration _warmupStateTtl = Duration(seconds: 15);

  HttpServer? _server;
  Uri? _baseUri;
  http.Client? _client;
  http.Client Function()? _httpClientFactory;
  final Map<String, _HttpStreamProxyEntry> _entries =
      <String, _HttpStreamProxyEntry>{};
  final Map<String, String> _entryIdByFingerprint = <String, String>{};
  final Map<String, _HttpStreamProxyWarmupState> _warmupStates =
      <String, _HttpStreamProxyWarmupState>{};

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
    final registered = await _ensureEntry(
      remoteUri: remoteUri,
      httpHeaders: httpHeaders,
      fileName: fileName,
    );
    return _proxyUriFor(registered.baseUri, registered.entry);
  }

  Future<Uri> seedStreamCache({
    required Uri remoteUri,
    Map<String, String>? httpHeaders,
    String? fileName,
    required int startByte,
    required List<int> bytes,
    String? contentTypeMime,
    int? totalBytes,
    bool acceptRanges = false,
  }) async {
    final registered = await _ensureEntry(
      remoteUri: remoteUri,
      httpHeaders: httpHeaders,
      fileName: fileName,
    );
    registered.entry.storeCachedRange(
      _HttpStreamProxyCachedRange(
        startByte: startByte < 0 ? 0 : startByte,
        bytes: Uint8List.fromList(bytes),
        contentTypeMime: contentTypeMime,
        totalBytes: totalBytes,
        acceptRanges: acceptRanges,
      ),
      maxRanges: _maxCachedRangesPerEntry,
      maxBytes: _maxCachedBytesPerEntry,
    );
    _notifyWarmupProgress(registered.entry.fingerprint);
    return _proxyUriFor(registered.baseUri, registered.entry);
  }

  void beginStreamWarmup({
    required Uri remoteUri,
    Map<String, String>? httpHeaders,
  }) {
    final fingerprint = _fingerprintFor(
      remoteUri,
      _sanitizeStoredHeaders(httpHeaders),
    );
    _pruneWarmupStates();
    final state = _warmupStates.putIfAbsent(
      fingerprint,
      _HttpStreamProxyWarmupState.new,
    );
    state.begin();
  }

  void endStreamWarmup({
    required Uri remoteUri,
    Map<String, String>? httpHeaders,
  }) {
    final fingerprint = _fingerprintFor(
      remoteUri,
      _sanitizeStoredHeaders(httpHeaders),
    );
    final state = _warmupStates[fingerprint];
    if (state == null) return;
    state.finish();
    if (state.canRemove) {
      _warmupStates.remove(fingerprint);
    }
  }

  Future<void> debugResetForTest() async {
    _entries.clear();
    _entryIdByFingerprint.clear();
    _warmupStates.clear();
    final server = _server;
    _server = null;
    _baseUri = null;
    _client?.close();
    _client = null;
    if (server != null) {
      await server.close(force: true);
    }
  }

  static String _randomId() {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final rnd = Random.secure();
    return List<String>.generate(22, (_) => chars[rnd.nextInt(chars.length)])
        .join();
  }

  Future<_RegisteredProxyEntry> _ensureEntry({
    required Uri remoteUri,
    Map<String, String>? httpHeaders,
    String? fileName,
  }) async {
    final base = await ensureStarted();
    _pruneEntries();

    final sanitizedHeaders = _sanitizeStoredHeaders(httpHeaders);
    final fingerprint = _fingerprintFor(remoteUri, sanitizedHeaders);
    final existingId = _entryIdByFingerprint[fingerprint];
    if (existingId != null) {
      final existing = _entries[existingId];
      if (existing != null) {
        existing.touch();
        return _RegisteredProxyEntry(baseUri: base, entry: existing);
      }
      _entryIdByFingerprint.remove(fingerprint);
    }

    final id = _randomId();
    final safeName = _safeFileName(
      fileName,
      remoteUri.pathSegments.isEmpty ? '' : remoteUri.pathSegments.last,
    );
    final entry = _HttpStreamProxyEntry(
      id: id,
      fingerprint: fingerprint,
      remoteUri: remoteUri,
      httpHeaders: sanitizedHeaders,
      localPathSegments: _localPathSegmentsFor(
        remoteUri: remoteUri,
        fallbackFileName: safeName,
      ),
    );
    _entries[id] = entry;
    _entryIdByFingerprint[fingerprint] = id;
    _pruneEntries();
    return _RegisteredProxyEntry(baseUri: base, entry: entry);
  }

  Uri _proxyUriFor(Uri base, _HttpStreamProxyEntry entry) {
    return base.replace(
      pathSegments: <String>[
        ...base.pathSegments.where((s) => s.isNotEmpty),
        'stream',
        entry.id,
        ...entry.localPathSegments,
      ],
    );
  }

  void _removeEntry(String key) {
    final removed = _entries.remove(key);
    if (removed == null) return;
    final mappedId = _entryIdByFingerprint[removed.fingerprint];
    if (mappedId == key) {
      _entryIdByFingerprint.remove(removed.fingerprint);
    }
  }

  void _pruneEntries() {
    _pruneWarmupStates();
    if (_entries.isEmpty) return;

    final now = DateTime.now();
    final expired = _entries.entries
        .where((e) => e.value.expiresAt.isBefore(now))
        .map((e) => e.key)
        .toList(growable: false);
    for (final key in expired) {
      _removeEntry(key);
    }

    if (_entries.length <= _maxEntries) return;

    final keysByLastAccess = _entries.entries.toList(growable: false)
      ..sort(
        (a, b) => a.value.lastAccessedAt.compareTo(b.value.lastAccessedAt),
      );
    final overflow = _entries.length - _maxEntries;
    for (var i = 0; i < overflow; i++) {
      _removeEntry(keysByLastAccess[i].key);
    }
  }

  void _pruneWarmupStates() {
    if (_warmupStates.isEmpty) return;
    final stale = <String>[];
    for (final entry in _warmupStates.entries) {
      final state = entry.value;
      if (state.canRemove || state.isStale(_warmupStateTtl)) {
        stale.add(entry.key);
      }
    }
    for (final key in stale) {
      _warmupStates.remove(key);
    }
  }

  void _notifyWarmupProgress(String fingerprint) {
    final state = _warmupStates[fingerprint];
    if (state == null) return;
    state.notifyProgress();
    if (state.canRemove) {
      _warmupStates.remove(fingerprint);
    }
  }

  Future<void> _awaitWarmupProgress(_HttpStreamProxyEntry entry) async {
    _pruneWarmupStates();
    final state = _warmupStates[entry.fingerprint];
    final signal = state?.waitForProgress();
    if (signal == null) return;
    try {
      await signal.timeout(_warmupWaitTimeout);
    } catch (_) {}
    _pruneWarmupStates();
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

      final cacheRange = method == 'GET'
          ? _parseCacheableRange(
              request.headers.value(HttpHeaders.rangeHeader),
            )
          : null;
      if (cacheRange != null) {
        var cached = entry.cachedRangeStartingAt(cacheRange.startByte);
        if (cached == null || cached.bytes.isEmpty) {
          await _awaitWarmupProgress(entry);
          cached = entry.cachedRangeStartingAt(cacheRange.startByte);
        }
        if (cached != null && cached.bytes.isNotEmpty) {
          final served = await _tryServeCachedRange(
            request: request,
            response: response,
            entry: entry,
            cached: cached,
            range: cacheRange,
          );
          if (served) return;
        }
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

  Future<bool> _tryServeCachedRange({
    required HttpRequest request,
    required HttpResponse response,
    required _HttpStreamProxyEntry entry,
    required _HttpStreamProxyCachedRange cached,
    required _CacheableRangeRequest range,
  }) async {
    final totalFromCache = cached.totalBytes;
    final requestedEnd = range.endByte;
    final requestedLength = requestedEnd == null
        ? null
        : requestedEnd - range.startByte + 1;
    if (requestedLength != null && requestedLength <= 0) {
      return false;
    }

    var cachedBytes = cached.bytes;
    if (requestedLength != null && cachedBytes.length > requestedLength) {
      cachedBytes = Uint8List.fromList(
        cachedBytes.sublist(0, requestedLength),
      );
    }
    if (range.hasRange &&
        totalFromCache == null &&
        requestedLength != null &&
        cachedBytes.length >= requestedLength) {
      return false;
    }

    final nextStart = range.startByte + cachedBytes.length;
    _OpenedRemote? remote;
    try {
      var totalBytes = totalFromCache;
      var contentTypeMime = cached.contentTypeMime;
      var acceptRanges = cached.acceptRanges;
      Stream<List<int>> tailStream = const Stream<List<int>>.empty();
      Map<String, String> remoteHeaders = const <String, String>{};
      final needsRemoteTail = requestedLength != null
          ? cachedBytes.length < requestedLength
          : (totalBytes == null || nextStart < totalBytes);

      if (needsRemoteTail) {
        remote = await _openRemote(
          entry,
          requestUri: request.uri,
          method: request.method.toUpperCase(),
          range: requestedEnd == null
              ? 'bytes=$nextStart-'
              : 'bytes=$nextStart-$requestedEnd',
          ifRange: request.headers.value(HttpHeaders.ifRangeHeader),
        );
        remoteHeaders = remote.response.headers;
        final remoteStatus = remote.response.statusCode;
        if (range.hasRange && remoteStatus != HttpStatus.partialContent) {
          await remote.close();
          return false;
        }

        contentTypeMime ??= _contentTypeMimeFromHeaders(remoteHeaders);
        acceptRanges = acceptRanges || _acceptsByteRanges(remoteHeaders);
        totalBytes ??=
            _inferTotalBytesFromHeaders(remoteStatus, remoteHeaders, nextStart);
        if (range.hasRange && totalBytes == null) {
          await remote.close();
          return false;
        }

        final bytesToSkip =
            (!range.hasRange && remoteStatus == HttpStatus.ok) ? nextStart : 0;
        tailStream = _skipBytes(remote.response.stream, bytesToSkip);
      }

      response.statusCode =
          range.hasRange ? HttpStatus.partialContent : HttpStatus.ok;
      _applyCachedResponseHeaders(
        response.headers,
        remoteHeaders: remoteHeaders,
        contentTypeMime: contentTypeMime,
        acceptRanges: acceptRanges,
        totalBytes: totalBytes,
        startByte: range.startByte,
        endByte: requestedEnd,
        hasRange: range.hasRange,
      );
      response.add(cachedBytes);
      await response.addStream(tailStream);
      remote = null;
      return true;
    } catch (_) {
      if (remote != null) {
        await remote.close();
      }
      return false;
    }
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

  static _CacheableRangeRequest? _parseCacheableRange(String? raw) {
    final value = raw?.trim() ?? '';
    if (value.isEmpty) {
      return const _CacheableRangeRequest(
        startByte: 0,
        endByte: null,
        hasRange: false,
      );
    }

    final match = RegExp(r'^bytes=(\d+)-(\d*)$').firstMatch(value);
    if (match == null) return null;
    final start = int.tryParse(match.group(1) ?? '');
    if (start == null || start < 0) return null;
    final endText = match.group(2)?.trim() ?? '';
    final end = endText.isEmpty ? null : int.tryParse(endText);
    if (end != null && end < start) return null;
    return _CacheableRangeRequest(
      startByte: start,
      endByte: end,
      hasRange: true,
    );
  }

  static Stream<List<int>> _skipBytes(
    Stream<List<int>> source,
    int bytesToSkip,
  ) async* {
    var remaining = bytesToSkip < 0 ? 0 : bytesToSkip;
    await for (final chunk in source) {
      if (remaining <= 0) {
        yield chunk;
        continue;
      }
      if (remaining >= chunk.length) {
        remaining -= chunk.length;
        continue;
      }
      yield chunk.sublist(remaining);
      remaining = 0;
    }
  }

  static String _fingerprintFor(Uri remoteUri, Map<String, String> headers) {
    final normalizedHeaders = headers.entries
        .map((entry) => '${entry.key.toLowerCase()}:${entry.value.trim()}')
        .toList(growable: false)
      ..sort();
    final payload = <String>[
      remoteUri.toString(),
      ...normalizedHeaders,
    ].join('|');
    return sha1.convert(utf8.encode(payload)).toString();
  }

  static String? _headerValue(Map<String, String> headers, String name) {
    final lower = name.toLowerCase();
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == lower) return entry.value;
    }
    return null;
  }

  static String? _contentTypeMimeFromHeaders(Map<String, String> headers) {
    final raw = _headerValue(headers, HttpHeaders.contentTypeHeader)?.trim();
    if (raw == null || raw.isEmpty) return null;
    return raw.split(';').first.trim();
  }

  static bool _acceptsByteRanges(Map<String, String> headers) {
    final raw = _headerValue(headers, HttpHeaders.acceptRangesHeader) ?? '';
    return raw.toLowerCase().contains('bytes');
  }

  static int? _inferTotalBytesFromHeaders(
    int statusCode,
    Map<String, String> headers,
    int rangeStart,
  ) {
    final contentRange = _headerValue(headers, HttpHeaders.contentRangeHeader);
    final fromRange = _totalBytesFromContentRange(contentRange);
    if (fromRange != null) return fromRange;

    final contentLength = int.tryParse(
      _headerValue(headers, HttpHeaders.contentLengthHeader) ?? '',
    );
    if (contentLength == null || contentLength < 0) return null;
    if (statusCode == HttpStatus.partialContent) {
      return rangeStart + contentLength;
    }
    if (statusCode == HttpStatus.ok) {
      return contentLength;
    }
    return null;
  }

  static int? _totalBytesFromContentRange(String? raw) {
    final value = raw?.trim() ?? '';
    if (value.isEmpty) return null;
    final match = RegExp(r'^bytes\s+\d+-\d+/(\d+|\*)$').firstMatch(value);
    if (match == null) return null;
    final totalText = match.group(1) ?? '';
    if (totalText == '*') return null;
    return int.tryParse(totalText);
  }

  static void _copyHeaderIfPresent(
    Map<String, String> from,
    HttpHeaders to,
    String name,
  ) {
    final value = _headerValue(from, name);
    if (value == null || value.trim().isEmpty) return;
    to.set(name, value);
  }

  static void _applyCachedResponseHeaders(
    HttpHeaders target, {
    required Map<String, String> remoteHeaders,
    required String? contentTypeMime,
    required bool acceptRanges,
    required int? totalBytes,
    required int startByte,
    required int? endByte,
    required bool hasRange,
  }) {
    if ((contentTypeMime ?? '').trim().isNotEmpty) {
      target.set(HttpHeaders.contentTypeHeader, contentTypeMime!);
    } else {
      _copyHeaderIfPresent(
        remoteHeaders,
        target,
        HttpHeaders.contentTypeHeader,
      );
    }
    if (acceptRanges) {
      target.set(HttpHeaders.acceptRangesHeader, 'bytes');
    }
    _copyHeaderIfPresent(
      remoteHeaders,
      target,
      HttpHeaders.cacheControlHeader,
    );
    _copyHeaderIfPresent(remoteHeaders, target, HttpHeaders.etagHeader);
    _copyHeaderIfPresent(remoteHeaders, target, HttpHeaders.lastModifiedHeader);
    _copyHeaderIfPresent(remoteHeaders, target, 'content-disposition');

    if (totalBytes == null) return;
    final resolvedEnd = hasRange ? (endByte ?? totalBytes - 1) : totalBytes - 1;
    final length = resolvedEnd - startByte + 1;
    if (length < 0) return;

    if (hasRange) {
      target.set(
        HttpHeaders.contentRangeHeader,
        'bytes $startByte-$resolvedEnd/$totalBytes',
      );
    }
    target.set(HttpHeaders.contentLengthHeader, '$length');
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
    required this.id,
    required this.fingerprint,
    required this.remoteUri,
    required this.httpHeaders,
    required this.localPathSegments,
  })  : lastAccessedAt = DateTime.now(),
        expiresAt = DateTime.now().add(HttpStreamProxyServer._entryTtl);

  final String id;
  final String fingerprint;
  final Uri remoteUri;
  final Map<String, String> httpHeaders;
  final List<String> localPathSegments;
  final Map<int, _HttpStreamProxyCachedRange> _cachedRanges =
      <int, _HttpStreamProxyCachedRange>{};
  DateTime lastAccessedAt;
  DateTime expiresAt;

  void touch() {
    final now = DateTime.now();
    lastAccessedAt = now;
    expiresAt = now.add(HttpStreamProxyServer._entryTtl);
  }

  void storeCachedRange(
    _HttpStreamProxyCachedRange range, {
    required int maxRanges,
    required int maxBytes,
  }) {
    touch();
    final existing = _cachedRanges[range.startByte];
    if (existing == null || range.bytes.length >= existing.bytes.length) {
      _cachedRanges[range.startByte] = range;
    } else if (existing.totalBytes == null && range.totalBytes != null) {
      _cachedRanges[range.startByte] = existing.copyWith(
        totalBytes: range.totalBytes,
        contentTypeMime: existing.contentTypeMime ?? range.contentTypeMime,
        acceptRanges: existing.acceptRanges || range.acceptRanges,
      );
    }
    _pruneCachedRanges(maxRanges: maxRanges, maxBytes: maxBytes);
  }

  _HttpStreamProxyCachedRange? cachedRangeStartingAt(int startByte) {
    touch();
    return _cachedRanges[startByte];
  }

  void _pruneCachedRanges({
    required int maxRanges,
    required int maxBytes,
  }) {
    if (_cachedRanges.isEmpty) return;

    final sorted = _cachedRanges.values.toList(growable: false)
      ..sort((a, b) => a.storedAt.compareTo(b.storedAt));
    var total = sorted.fold<int>(0, (sum, item) => sum + item.bytes.length);
    final removeKeys = <int>{};

    for (final item in sorted) {
      final overCount = _cachedRanges.length - removeKeys.length > maxRanges;
      final overBytes = total > maxBytes;
      if (!overCount && !overBytes) break;
      removeKeys.add(item.startByte);
      total -= item.bytes.length;
    }

    for (final key in removeKeys) {
      _cachedRanges.remove(key);
    }
  }
}

class _HttpStreamProxyCachedRange {
  _HttpStreamProxyCachedRange({
    required this.startByte,
    required this.bytes,
    required this.contentTypeMime,
    required this.totalBytes,
    required this.acceptRanges,
  }) : storedAt = DateTime.now();

  final int startByte;
  final Uint8List bytes;
  final String? contentTypeMime;
  final int? totalBytes;
  final bool acceptRanges;
  final DateTime storedAt;

  _HttpStreamProxyCachedRange copyWith({
    String? contentTypeMime,
    int? totalBytes,
    bool? acceptRanges,
  }) {
    return _HttpStreamProxyCachedRange(
      startByte: startByte,
      bytes: bytes,
      contentTypeMime: contentTypeMime ?? this.contentTypeMime,
      totalBytes: totalBytes ?? this.totalBytes,
      acceptRanges: acceptRanges ?? this.acceptRanges,
    );
  }
}

class _RegisteredProxyEntry {
  const _RegisteredProxyEntry({
    required this.baseUri,
    required this.entry,
  });

  final Uri baseUri;
  final _HttpStreamProxyEntry entry;
}

class _CacheableRangeRequest {
  const _CacheableRangeRequest({
    required this.startByte,
    required this.endByte,
    required this.hasRange,
  });

  final int startByte;
  final int? endByte;
  final bool hasRange;
}

class _HttpStreamProxyWarmupState {
  int _activeCount = 0;
  DateTime _updatedAt = DateTime.now();
  Completer<void>? _progress = Completer<void>();

  bool get canRemove => _activeCount <= 0 && (_progress == null || _progress!.isCompleted);

  bool isStale(Duration ttl) => DateTime.now().difference(_updatedAt) > ttl;

  void begin() {
    _activeCount += 1;
    _updatedAt = DateTime.now();
    if (_progress == null || _progress!.isCompleted) {
      _progress = Completer<void>();
    }
  }

  Future<void>? waitForProgress() {
    if (_activeCount <= 0) return null;
    _updatedAt = DateTime.now();
    _progress ??= Completer<void>();
    return _progress!.future;
  }

  void notifyProgress() {
    _updatedAt = DateTime.now();
    final current = _progress;
    if (current != null && !current.isCompleted) {
      current.complete();
    }
    _progress = _activeCount > 0 ? Completer<void>() : null;
  }

  void finish() {
    if (_activeCount > 0) {
      _activeCount -= 1;
    }
    _updatedAt = DateTime.now();
    final current = _progress;
    if (current != null && !current.isCompleted) {
      current.complete();
    }
    _progress = _activeCount > 0 ? Completer<void>() : null;
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
