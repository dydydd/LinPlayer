import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;

import '../network/lin_http_client.dart';
import 'http_stream_cache.dart';

export 'http_stream_cache.dart';

class HttpStreamProxyServer {
  HttpStreamProxyServer._();

  static final HttpStreamProxyServer instance = HttpStreamProxyServer._();

  static const int _maxEntries = 256;
  static const Duration _entryTtl = Duration(hours: 6);
  static const int _maxCachedRangesPerEntry = 4;
  static const int _maxCachedBytesPerEntry = 24 * 1024 * 1024;
  static const Duration _warmupWaitTimeout = Duration(milliseconds: 1200);
  static const Duration _warmupStateTtl = Duration(seconds: 15);
  static const int _maxRecentDiagnostics = 96;
  static const String _cacheRootName = 'linplayer_http_stream_proxy_v2';

  HttpServer? _server;
  Uri? _baseUri;
  http.Client? _client;
  http.Client Function()? _httpClientFactory;
  final Map<String, _HttpStreamProxyEntry> _entries =
      <String, _HttpStreamProxyEntry>{};
  final Map<String, String> _entryIdByFingerprint = <String, String>{};
  final Map<String, _HttpStreamProxyWarmupState> _warmupStates =
      <String, _HttpStreamProxyWarmupState>{};
  final Map<String, List<_HttpStreamProxyInFlightCacheWrite>>
      _inFlightCacheWrites =
      <String, List<_HttpStreamProxyInFlightCacheWrite>>{};
  final Map<String, Future<HttpStreamWarmupResult>> _inFlightWarmups =
      <String, Future<HttpStreamWarmupResult>>{};
  final List<_HttpStreamProxyDiagnosticEntry> _recentDiagnostics =
      <_HttpStreamProxyDiagnosticEntry>[];
  final StreamController<List<HttpStreamCacheDownloadProgressSnapshot>>
      _downloadProgressController =
      StreamController<List<HttpStreamCacheDownloadProgressSnapshot>>.broadcast(
    sync: true,
  );
  final Map<String, _HttpStreamProxyDownloadProgress> _activeDownloads =
      <String, _HttpStreamProxyDownloadProgress>{};
  final Map<String, _HttpStreamProxyDownloadCancellation>
      _activeDownloadCancellations =
      <String, _HttpStreamProxyDownloadCancellation>{};
  int _nextDownloadProgressId = 0;

  Stream<List<HttpStreamCacheDownloadProgressSnapshot>>
      get downloadProgressStream => _downloadProgressController.stream;

  void configureHttpClientFactory(http.Client Function()? factory) {
    _httpClientFactory = factory;
    _client = null;
  }

  List<HttpStreamCacheDownloadProgressSnapshot>
      currentDownloadProgressSnapshots({int? maxEntries}) {
    final snapshots = _activeDownloads.values
        .map((entry) => entry.snapshot())
        .toList(growable: false)
      ..sort((a, b) => a.startedAt.compareTo(b.startedAt));
    if (maxEntries == null ||
        maxEntries < 1 ||
        snapshots.length <= maxEntries) {
      return List<HttpStreamCacheDownloadProgressSnapshot>.unmodifiable(
        snapshots,
      );
    }
    return List<HttpStreamCacheDownloadProgressSnapshot>.unmodifiable(
      snapshots.sublist(snapshots.length - maxEntries),
    );
  }

  String buildActiveDownloadsText({int maxEntries = 8}) {
    final snapshots = currentDownloadProgressSnapshots(maxEntries: maxEntries);
    final buffer = StringBuffer()
      ..writeln('activeDownloads: ${_activeDownloads.length}');
    if (snapshots.isEmpty) {
      buffer.writeln('(empty)');
      return buffer.toString().trim();
    }
    for (final snapshot in snapshots) {
      final requestedText =
          snapshot.requestedBytes == null ? '?' : '${snapshot.requestedBytes}';
      final progress = snapshot.progress;
      final progressText = progress == null
          ? 'indeterminate'
          : '${(progress * 100).toStringAsFixed(progress >= 0.1 ? 0 : 1)}%';
      buffer.writeln(
        '${snapshot.kind.name} '
        'start=${snapshot.startByte} '
        'written=${snapshot.bytesWritten}/$requestedText '
        'progress=$progressText '
        'url=${_summarizeUrl(snapshot.remoteUrl)}',
      );
    }
    return buffer.toString().trim();
  }

  int cancelActivePlaybackDownloads({String? cacheFingerprint}) {
    final normalizedFingerprint = cacheFingerprint?.trim() ?? '';
    final ids = _activeDownloads.values
        .where(
          (download) =>
              download.kind == HttpStreamCacheDownloadKind.playbackFill &&
              (normalizedFingerprint.isEmpty ||
                  download.key.fingerprint == normalizedFingerprint),
        )
        .map((download) => download.id)
        .toList(growable: false);
    for (final id in ids) {
      _activeDownloadCancellations[id]?.cancel();
    }
    if (ids.isNotEmpty) {
      _emitDownloadProgressSnapshot();
    }
    return ids.length;
  }

  Future<Uri> ensureStarted() async {
    final existing = _baseUri;
    if (existing != null && _server != null) return existing;

    await _ensureCacheRootDirectory();
    await _pruneDiskCacheDirectories();

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
    HttpStreamCacheKey? cacheKey,
  }) async {
    final registered = await _ensureEntry(
      remoteUri: remoteUri,
      httpHeaders: httpHeaders,
      fileName: fileName,
      cacheKey: cacheKey,
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
    HttpStreamCacheKey? cacheKey,
  }) async {
    final registered = await _ensureEntry(
      remoteUri: remoteUri,
      httpHeaders: httpHeaders,
      fileName: fileName,
      cacheKey: cacheKey,
    );
    if (bytes.isNotEmpty) {
      await registered.entry.storeBytesRange(
        startByte: startByte < 0 ? 0 : startByte,
        bytes: bytes,
        contentTypeMime: contentTypeMime,
        totalBytes: totalBytes,
        acceptRanges: acceptRanges,
        maxRanges: _maxCachedRangesPerEntry,
        maxBytes: _maxCachedBytesPerEntry,
      );
    }
    _notifyWarmupProgress(registered.entry.fingerprint);
    return _proxyUriFor(registered.baseUri, registered.entry);
  }

  Future<HttpStreamWarmupResult> warmRangeToCache({
    required Uri remoteUri,
    Map<String, String>? httpHeaders,
    String? fileName,
    required int startByte,
    required int lengthBytes,
    HttpStreamCacheKey? cacheKey,
  }) async {
    final registered = await _ensureEntry(
      remoteUri: remoteUri,
      httpHeaders: httpHeaders,
      fileName: fileName,
      cacheKey: cacheKey,
    );
    final proxyUri = _proxyUriFor(registered.baseUri, registered.entry);
    final normalizedStart = startByte < 0 ? 0 : startByte;
    final normalizedLength = lengthBytes < 0 ? 0 : lengthBytes;
    if (normalizedLength <= 0) {
      return HttpStreamWarmupResult(
        proxyUri: proxyUri,
        effectiveRemoteUri: registered.entry.remoteUri,
        startByte: normalizedStart,
        requestedBytes: 0,
        bytesWritten: 0,
        satisfiedFromCache: true,
        contentTypeMime: null,
        totalBytes: null,
        acceptRanges: false,
      );
    }

    final dedupeKey =
        '${registered.entry.fingerprint}|$normalizedStart|$normalizedLength';
    final existing = _inFlightWarmups[dedupeKey];
    if (existing != null) {
      return existing;
    }

    final run = _warmRangeToCacheRegistered(
      registered,
      proxyUri: proxyUri,
      startByte: normalizedStart,
      lengthBytes: normalizedLength,
    );
    _inFlightWarmups[dedupeKey] = run;
    try {
      return await run;
    } finally {
      if (identical(_inFlightWarmups[dedupeKey], run)) {
        _inFlightWarmups.remove(dedupeKey);
      }
    }
  }

  void beginStreamWarmup({
    required Uri remoteUri,
    Map<String, String>? httpHeaders,
    HttpStreamCacheKey? cacheKey,
  }) {
    _pruneWarmupStates();
    final fingerprint = (cacheKey ??
            HttpStreamCacheKey.fromNetworkSource(
              remoteUri: remoteUri,
              httpHeaders: _sanitizeStoredHeaders(httpHeaders),
            ))
        .fingerprint;
    final state = _warmupStates.putIfAbsent(
      fingerprint,
      _HttpStreamProxyWarmupState.new,
    );
    state.begin();
  }

  void endStreamWarmup({
    required Uri remoteUri,
    Map<String, String>? httpHeaders,
    HttpStreamCacheKey? cacheKey,
  }) {
    final fingerprint = (cacheKey ??
            HttpStreamCacheKey.fromNetworkSource(
              remoteUri: remoteUri,
              httpHeaders: _sanitizeStoredHeaders(httpHeaders),
            ))
        .fingerprint;
    final state = _warmupStates[fingerprint];
    if (state == null) return;
    state.finish();
    if (state.canRemove) {
      _warmupStates.remove(fingerprint);
    }
  }

  String buildDiagnosticsText({int maxEntries = 40}) {
    _pruneEntries();
    _pruneWarmupStates();
    _pruneInFlightCacheWrites();
    final now = DateTime.now();
    final inFlightCacheWrites = _inFlightCacheWrites.values.fold<int>(
      0,
      (sum, states) => sum + states.length,
    );
    final stateCounts = <String, int>{};
    final snapshots = _entries.values
        .map(
          (entry) => entry.snapshot(
            now: now,
            ttl: _entryTtl,
            warmupInProgress:
                _warmupStates[entry.fingerprint]?.isActive ?? false,
          ),
        )
        .toList(growable: false);
    for (final snapshot in snapshots) {
      _bumpCounter(stateCounts, snapshot.state.name);
    }
    final buffer = StringBuffer()
      ..writeln('cacheRoot: ${_cacheRootDirectory.path}')
      ..writeln('entries: ${_entries.length}')
      ..writeln('warmups: ${_warmupStates.length}')
      ..writeln('activeDownloads: ${_activeDownloads.length}')
      ..writeln('inFlightCacheWrites: $inFlightCacheWrites')
      ..writeln('cacheStates: ${_formatCounterSummary(stateCounts)}')
      ..writeln('recent:');
    if (_recentDiagnostics.isEmpty) {
      buffer.writeln('(empty)');
      return buffer.toString().trim();
    }

    final count = maxEntries < 1 ? 1 : maxEntries;
    final startIndex = _recentDiagnostics.length > count
        ? _recentDiagnostics.length - count
        : 0;
    for (final entry in _recentDiagnostics.skip(startIndex)) {
      buffer.writeln(
        '${entry.timestamp.toIso8601String()} '
        'method=${entry.method} '
        'first=${entry.firstPlaybackRequest} '
        'status=${entry.statusCode} '
        'reuse=${entry.reuseOutcome} '
        'cache=${entry.cacheStatus} '
        'reason=${entry.reason} '
        'miss=${entry.missReason} '
        'warmupWait=${entry.waitedWarmup} '
        'cacheFillWait=${entry.waitedCacheFill} '
        'reqHeaders=${entry.requestHeadersSummary} '
        'range=${entry.rangeHeader.isEmpty ? "-" : entry.rangeHeader} '
        'cached=${entry.cachedBytes} '
        'remote=${entry.remoteBytes} '
        'request=${_summarizeUrl(entry.requestUrl)} '
        'url=${_summarizeUrl(entry.remoteUrl)}',
      );
    }
    return buffer.toString().trim();
  }

  String buildReuseSummaryText({int maxFirstRequests = 8}) {
    _pruneEntries();
    _pruneWarmupStates();
    _pruneInFlightCacheWrites();
    final now = DateTime.now();

    final playback = _recentDiagnostics
        .where((entry) => _isPlaybackMethod(entry.method))
        .toList(growable: false);
    final cacheCounts = <String, int>{};
    final missCounts = <String, int>{};
    final reuseCounts = <String, int>{};
    var waitedWarmup = 0;
    var waitedCacheFill = 0;
    for (final entry in playback) {
      _bumpCounter(cacheCounts, entry.cacheStatus);
      _bumpCounter(reuseCounts, entry.reuseOutcome);
      final miss = entry.missReason.trim();
      if (miss.isNotEmpty && miss != '-') {
        _bumpCounter(missCounts, miss);
      }
      if (entry.waitedWarmup) waitedWarmup += 1;
      if (entry.waitedCacheFill) waitedCacheFill += 1;
    }

    final reusedRequests =
        (cacheCounts['hit'] ?? 0) + (cacheCounts['partial'] ?? 0);
    final cacheStateCounts = <String, int>{};
    for (final entry in _entries.values) {
      final snapshot = entry.snapshot(
        now: now,
        ttl: _entryTtl,
        warmupInProgress: _warmupStates[entry.fingerprint]?.isActive ?? false,
      );
      _bumpCounter(cacheStateCounts, snapshot.state.name);
    }
    final buffer = StringBuffer()
      ..writeln('observedRequests: ${playback.length}')
      ..writeln('reusedRequests: $reusedRequests')
      ..writeln('warmupWaits: $waitedWarmup')
      ..writeln('cacheFillWaits: $waitedCacheFill')
      ..writeln('activeDownloads: ${_activeDownloads.length}')
      ..writeln('cacheStates: ${_formatCounterSummary(cacheStateCounts)}')
      ..writeln('reuseOutcomes: ${_formatCounterSummary(reuseCounts)}')
      ..writeln('cacheStatuses: ${_formatCounterSummary(cacheCounts)}')
      ..writeln('missReasons: ${_formatCounterSummary(missCounts)}');

    final firstRequests = playback
        .where((entry) => entry.firstPlaybackRequest)
        .toList(growable: false);
    buffer.writeln('firstPlaybackRequests: ${firstRequests.length}');
    if (firstRequests.isEmpty) {
      buffer.writeln('(empty)');
      return buffer.toString().trim();
    }

    final keep = maxFirstRequests < 1 ? 1 : maxFirstRequests;
    final startIndex =
        firstRequests.length > keep ? firstRequests.length - keep : 0;
    for (final entry in firstRequests.skip(startIndex)) {
      buffer.writeln(
        '${entry.timestamp.toIso8601String()} '
        'reuse=${entry.reuseOutcome} '
        'cache=${entry.cacheStatus} '
        'miss=${entry.missReason} '
        'range=${entry.rangeHeader.isEmpty ? "-" : entry.rangeHeader} '
        'reqHeaders=${entry.requestHeadersSummary} '
        'request=${_summarizeUrl(entry.requestUrl)} '
        'remote=${_summarizeUrl(entry.remoteUrl)}',
      );
    }
    return buffer.toString().trim();
  }

  Future<void> debugResetForTest() async {
    _entries.clear();
    _entryIdByFingerprint.clear();
    _warmupStates.clear();
    _inFlightCacheWrites.clear();
    _inFlightWarmups.clear();
    _recentDiagnostics.clear();
    _activeDownloads.clear();
    _activeDownloadCancellations.clear();
    _emitDownloadProgressSnapshot();
    final server = _server;
    _server = null;
    _baseUri = null;
    _client?.close();
    _client = null;
    if (server != null) {
      await server.close(force: true);
    }
    final root = _cacheRootDirectory;
    if (await root.exists()) {
      try {
        await root.delete(recursive: true);
      } catch (_) {}
    }
  }

  Future<void> markStreamFailure({
    required Uri remoteUri,
    Map<String, String>? httpHeaders,
    HttpStreamCacheKey? cacheKey,
    Object? error,
  }) async {
    final registered = await _ensureEntry(
      remoteUri: remoteUri,
      httpHeaders: httpHeaders,
      cacheKey: cacheKey,
      fileName: null,
      touchExisting: false,
    );
    await registered.entry.recordFailure(error);
  }

  Future<HttpStreamCacheSnapshot> debugDescribeStream({
    required Uri remoteUri,
    Map<String, String>? httpHeaders,
    HttpStreamCacheKey? cacheKey,
    DateTime? now,
  }) async {
    final registered = await _ensureEntry(
      remoteUri: remoteUri,
      httpHeaders: httpHeaders,
      cacheKey: cacheKey,
      fileName: null,
      touchExisting: false,
    );
    return registered.entry.snapshot(
      now: now ?? DateTime.now(),
      ttl: _entryTtl,
      warmupInProgress:
          _warmupStates[registered.entry.fingerprint]?.isActive ?? false,
    );
  }

  String _startDownloadProgress({
    required _HttpStreamProxyEntry entry,
    required HttpStreamCacheDownloadKind kind,
    required Uri remoteUri,
    required int startByte,
    int? requestedBytes,
    int? totalBytes,
    String? contentTypeMime,
    _HttpStreamProxyDownloadCancellation? cancellation,
  }) {
    final id = 'dl-${++_nextDownloadProgressId}';
    _activeDownloads[id] = _HttpStreamProxyDownloadProgress(
      id: id,
      key: entry.cacheKey,
      kind: kind,
      remoteUrl: remoteUri.toString(),
      startByte: startByte,
      requestedBytes: requestedBytes,
      totalBytes: totalBytes,
      contentTypeMime: contentTypeMime,
    );
    if (cancellation != null) {
      _activeDownloadCancellations[id] = cancellation;
    }
    _emitDownloadProgressSnapshot();
    return id;
  }

  void _incrementDownloadProgress(String id, int deltaBytes) {
    final current = _activeDownloads[id];
    if (current == null) return;
    current.bytesWritten += deltaBytes < 0 ? 0 : deltaBytes;
    current.updatedAt = DateTime.now();
    _emitDownloadProgressSnapshot();
  }

  void _finishDownloadProgress(String? id) {
    if (id == null) return;
    _activeDownloadCancellations.remove(id);
    if (_activeDownloads.remove(id) == null) return;
    _emitDownloadProgressSnapshot();
  }

  void _emitDownloadProgressSnapshot() {
    try {
      _downloadProgressController.add(currentDownloadProgressSnapshots());
    } catch (_) {}
  }

  Future<HttpStreamWarmupResult> _warmRangeToCacheRegistered(
    _RegisteredProxyEntry registered, {
    required Uri proxyUri,
    required int startByte,
    required int lengthBytes,
  }) async {
    final entry = registered.entry;
    final requestedEnd = startByte + lengthBytes - 1;

    var coverage = entry.cachedCoverageStartingAt(startByte);
    if (_coverageSatisfiesLength(coverage, lengthBytes)) {
      return HttpStreamWarmupResult(
        proxyUri: proxyUri,
        effectiveRemoteUri: entry.remoteUri,
        startByte: startByte,
        requestedBytes: lengthBytes,
        bytesWritten: 0,
        satisfiedFromCache: true,
        contentTypeMime: coverage?.contentTypeMime,
        totalBytes: coverage?.totalBytes,
        acceptRanges: coverage?.acceptRanges ?? false,
      );
    }

    final existingCovered = coverage?.lengthBytes ?? 0;
    final missingStart = startByte + existingCovered;
    final missingBytes = lengthBytes - existingCovered;

    if (missingBytes <= 0) {
      return HttpStreamWarmupResult(
        proxyUri: proxyUri,
        effectiveRemoteUri: entry.remoteUri,
        startByte: startByte,
        requestedBytes: lengthBytes,
        bytesWritten: 0,
        satisfiedFromCache: true,
        contentTypeMime: coverage?.contentTypeMime,
        totalBytes: coverage?.totalBytes,
        acceptRanges: coverage?.acceptRanges ?? false,
      );
    }

    final waited = await _awaitInFlightCacheWrite(
      entry,
      requestedStartByte: missingStart,
    );
    if (waited) {
      coverage = entry.cachedCoverageStartingAt(startByte);
      if (_coverageSatisfiesLength(coverage, lengthBytes)) {
        return HttpStreamWarmupResult(
          proxyUri: proxyUri,
          effectiveRemoteUri: entry.remoteUri,
          startByte: startByte,
          requestedBytes: lengthBytes,
          bytesWritten: 0,
          satisfiedFromCache: true,
          contentTypeMime: coverage?.contentTypeMime,
          totalBytes: coverage?.totalBytes,
          acceptRanges: coverage?.acceptRanges ?? false,
        );
      }
    }

    final requestRange = _CacheableRangeRequest(
      startByte: missingStart,
      endByte: requestedEnd,
      hasRange: true,
    );
    final inFlightCacheWrite = _beginInFlightCacheWrite(
      entry: entry,
      startByte: missingStart,
      plannedEndByteExclusive: requestedEnd + 1,
    );
    _OpenedRemote? remote;
    String? progressId;
    try {
      remote = await _openRemote(
        entry,
        requestUri: proxyUri,
        method: 'GET',
        range: 'bytes=$missingStart-$requestedEnd',
        ifRange: null,
      );

      final cacheStartByte = _cacheStartByteForResponse(
        requestRange: requestRange,
        remote: remote.response,
      );
      if (cacheStartByte == null) {
        throw StateError(
          'range-not-cacheable:${remote.response.statusCode}',
        );
      }

      await entry.updateRemoteUri(
        _effectiveRemoteUriFromResponse(
          remote.response,
          fallback: entry.remoteUri,
        ),
      );

      final contentTypeMime =
          _contentTypeMimeFromHeaders(remote.response.headers);
      final acceptRanges = _acceptsByteRanges(remote.response.headers) ||
          remote.response.statusCode == HttpStatus.partialContent;
      final totalBytes = _inferTotalBytesFromHeaders(
        remote.response.statusCode,
        remote.response.headers,
        cacheStartByte,
      );
      final effectiveRemoteUri = _effectiveRemoteUriFromResponse(
        remote.response,
        fallback: entry.remoteUri,
      );
      final expectedBytes = totalBytes != null && totalBytes > cacheStartByte
          ? min(missingBytes, totalBytes - cacheStartByte)
          : missingBytes;
      progressId = _startDownloadProgress(
        entry: entry,
        kind: HttpStreamCacheDownloadKind.warmup,
        remoteUri: effectiveRemoteUri,
        startByte: cacheStartByte,
        requestedBytes: expectedBytes <= 0 ? null : expectedBytes,
        totalBytes: totalBytes,
        contentTypeMime: contentTypeMime,
      );
      final cacheResult = await _cacheRemoteToEntry(
        entry: entry,
        remote: remote.response,
        cacheStartByte: cacheStartByte,
        skipBytes: 0,
        maxBytes: missingBytes,
        contentTypeMime: contentTypeMime,
        totalBytes: totalBytes,
        acceptRanges: acceptRanges,
        progressId: progressId,
      );
      await remote.close();
      remote = null;
      if (cacheResult.bytesRelayed <= 0) {
        throw StateError('range-empty');
      }
      _notifyWarmupProgress(entry.fingerprint);

      final snapshotCoverage = entry.cachedCoverageStartingAt(startByte);
      return HttpStreamWarmupResult(
        proxyUri: proxyUri,
        effectiveRemoteUri: entry.remoteUri,
        startByte: startByte,
        requestedBytes: lengthBytes,
        bytesWritten: cacheResult.bytesRelayed,
        satisfiedFromCache: false,
        contentTypeMime: snapshotCoverage?.contentTypeMime ?? contentTypeMime,
        totalBytes: snapshotCoverage?.totalBytes ?? totalBytes,
        acceptRanges: snapshotCoverage?.acceptRanges ?? acceptRanges,
      );
    } finally {
      _finishDownloadProgress(progressId);
      _finishInFlightCacheWrite(entry, inFlightCacheWrite);
      if (remote != null) {
        await remote.close();
      }
    }
  }

  Future<void> _ensureCacheRootDirectory() async {
    final root = _cacheRootDirectory;
    if (await root.exists()) return;
    await root.create(recursive: true);
  }

  Future<void> _pruneDiskCacheDirectories() async {
    final root = _cacheRootDirectory;
    if (!await root.exists()) return;

    final directories = <({Directory directory, DateTime touchedAt})>[];
    await for (final entity in root.list(followLinks: false)) {
      if (entity is! Directory) continue;
      final touchedAt = await _readCacheDirectoryTouchedAt(entity);
      if (touchedAt == null) {
        await _deleteDirectoryIfExists(entity);
        continue;
      }
      directories.add((directory: entity, touchedAt: touchedAt));
    }

    final now = DateTime.now();
    final staleCutoff = now.subtract(_entryTtl);
    final stale = directories
        .where((entry) => entry.touchedAt.isBefore(staleCutoff))
        .toList(growable: false);
    for (final entry in stale) {
      await _deleteDirectoryIfExists(entry.directory);
    }

    final active = directories
        .where((entry) => !entry.touchedAt.isBefore(staleCutoff))
        .toList(growable: false)
      ..sort((a, b) => b.touchedAt.compareTo(a.touchedAt));
    if (active.length <= _maxEntries) return;

    for (final entry in active.skip(_maxEntries)) {
      await _deleteDirectoryIfExists(entry.directory);
    }
  }

  Future<DateTime?> _readCacheDirectoryTouchedAt(Directory directory) async {
    final metadataFile = File(
      _joinPath(directory.path, _HttpStreamProxyEntry.metadataFileName),
    );
    if (await metadataFile.exists()) {
      try {
        final decoded = jsonDecode(await metadataFile.readAsString());
        if (decoded is Map) {
          final raw = decoded['lastUpdatedAt']?.toString().trim() ?? '';
          final parsed = DateTime.tryParse(raw);
          if (parsed != null) return parsed;
        }
      } catch (_) {}

      try {
        return await metadataFile.lastModified();
      } catch (_) {}
    }

    try {
      return (await directory.stat()).modified;
    } catch (_) {
      return null;
    }
  }

  Future<void> _deleteDirectoryIfExists(Directory directory) async {
    try {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    } catch (_) {}
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
    HttpStreamCacheKey? cacheKey,
    bool touchExisting = true,
  }) async {
    final base = await ensureStarted();
    _pruneEntries();

    final sanitizedHeaders = _sanitizeStoredHeaders(httpHeaders);
    final resolvedCacheKey = cacheKey ??
        HttpStreamCacheKey.fromNetworkSource(
          remoteUri: remoteUri,
          httpHeaders: sanitizedHeaders,
        );
    final fingerprint = resolvedCacheKey.fingerprint;
    final existingId = _entryIdByFingerprint[fingerprint];
    if (existingId != null) {
      final existing = _entries[existingId];
      if (existing != null) {
        if (touchExisting) {
          existing.touch();
        }
        return _RegisteredProxyEntry(baseUri: base, entry: existing);
      }
      _entryIdByFingerprint.remove(fingerprint);
    }

    final id = _randomId();
    final safeName = _safeFileName(
      fileName,
      remoteUri.pathSegments.isEmpty ? '' : remoteUri.pathSegments.last,
    );
    final entry = await _HttpStreamProxyEntry.create(
      id: id,
      fingerprint: fingerprint,
      cacheKey: resolvedCacheKey,
      remoteUri: remoteUri,
      httpHeaders: sanitizedHeaders,
      localPathSegments: _localPathSegmentsFor(
        remoteUri: remoteUri,
        fallbackFileName: safeName,
      ),
      cacheDirectory:
          Directory(_joinPath(_cacheRootDirectory.path, fingerprint)),
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
    _inFlightCacheWrites.remove(removed.fingerprint);
  }

  void _pruneEntries() {
    _pruneWarmupStates();
    _pruneInFlightCacheWrites();
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

  void _pruneInFlightCacheWrites() {
    if (_inFlightCacheWrites.isEmpty) return;
    final staleFingerprints = <String>[];
    for (final entry in _inFlightCacheWrites.entries) {
      entry.value.removeWhere(
        (state) => state.canRemove || state.isStale(_warmupStateTtl),
      );
      if (entry.value.isEmpty) {
        staleFingerprints.add(entry.key);
      }
    }
    for (final fingerprint in staleFingerprints) {
      _inFlightCacheWrites.remove(fingerprint);
    }
  }

  _HttpStreamProxyInFlightCacheWrite _beginInFlightCacheWrite({
    required _HttpStreamProxyEntry entry,
    required int startByte,
    required int? plannedEndByteExclusive,
  }) {
    _pruneInFlightCacheWrites();
    final state = _HttpStreamProxyInFlightCacheWrite(
      startByte: startByte,
      plannedEndByteExclusive: plannedEndByteExclusive,
    );
    _inFlightCacheWrites
        .putIfAbsent(
          entry.fingerprint,
          () => <_HttpStreamProxyInFlightCacheWrite>[],
        )
        .add(state);
    return state;
  }

  void _finishInFlightCacheWrite(
    _HttpStreamProxyEntry entry,
    _HttpStreamProxyInFlightCacheWrite state,
  ) {
    state.finish();
    _pruneInFlightCacheWrites();
  }

  Future<bool> _awaitInFlightCacheWrite(
    _HttpStreamProxyEntry entry, {
    required int requestedStartByte,
  }) async {
    _pruneInFlightCacheWrites();
    final states = _inFlightCacheWrites[entry.fingerprint];
    if (states == null || states.isEmpty) return false;
    final relevant = states
        .where((state) => state.mightCover(requestedStartByte))
        .toList(growable: false);
    if (relevant.isEmpty) return false;
    try {
      await Future.any<void>(
        relevant.map((state) => state.waitForCompletion()),
      ).timeout(_warmupWaitTimeout);
      _pruneInFlightCacheWrites();
      return true;
    } catch (_) {
      _pruneInFlightCacheWrites();
      return true;
    }
  }

  void _recordDiagnostic(_HttpStreamProxyDiagnosticEntry entry) {
    _recentDiagnostics.add(entry);
    if (_recentDiagnostics.length > _maxRecentDiagnostics) {
      _recentDiagnostics.removeRange(
        0,
        _recentDiagnostics.length - _maxRecentDiagnostics,
      );
    }
  }

  Future<bool> _awaitWarmupProgress(_HttpStreamProxyEntry entry) async {
    _pruneWarmupStates();
    final state = _warmupStates[entry.fingerprint];
    final signal = state?.waitForProgress();
    if (signal == null) return false;
    try {
      await signal.timeout(_warmupWaitTimeout);
      _pruneWarmupStates();
      return true;
    } catch (_) {
      _pruneWarmupStates();
      return true;
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
    _HttpStreamProxyEntry? activeEntry;
    _HttpStreamProxyInFlightCacheWrite? inFlightCacheWrite;
    final diag = _ProxyRequestTrace(
      method: request.method.toUpperCase(),
      rangeHeader:
          (request.headers.value(HttpHeaders.rangeHeader) ?? '').trim(),
    );
    try {
      _pruneEntries();

      final segments = request.uri.pathSegments;
      if (segments.length < 2 || segments[0] != 'stream') {
        response.statusCode = HttpStatus.notFound;
        diag.statusCode = response.statusCode;
        diag.cacheStatus = 'reject';
        diag.reuseOutcome = 'rejected';
        diag.reason = 'unknown-path';
        await response.close();
        return;
      }

      final entry = _entries[segments[1]];
      if (entry == null) {
        response.statusCode = HttpStatus.notFound;
        diag.statusCode = response.statusCode;
        diag.cacheStatus = 'reject';
        diag.reuseOutcome = 'rejected';
        diag.reason = 'unknown-entry';
        await response.close();
        return;
      }
      activeEntry = entry;
      entry.touch();
      diag.remoteUrl = entry.remoteUri.toString();
      diag.requestUrl =
          (_baseUri?.resolveUri(request.uri) ?? request.uri).toString();
      diag.requestHeadersSummary = _summarizeIncomingRequestHeaders(
        request.headers,
      );

      final method = request.method.toUpperCase();
      if (method != 'GET' && method != 'HEAD') {
        response.statusCode = HttpStatus.methodNotAllowed;
        response.headers.set(HttpHeaders.allowHeader, 'GET, HEAD');
        diag.statusCode = response.statusCode;
        diag.cacheStatus = 'reject';
        diag.reuseOutcome = 'rejected';
        diag.reason = 'method-not-allowed';
        await response.close();
        return;
      }
      diag.firstPlaybackRequest = entry.markObservedPlaybackRequest();

      final cacheRange = _parseCacheableRange(
        request.headers.value(HttpHeaders.rangeHeader),
      );
      if (method == 'HEAD') {
        final headRange = cacheRange ??
            const _CacheableRangeRequest(
              startByte: 0,
              endByte: null,
              hasRange: false,
            );
        final cachedHead = entry.headMetadataFor(headRange);
        if (cachedHead != null) {
          response.statusCode = cachedHead.statusCode;
          _applyCachedResponseHeaders(
            response.headers,
            remoteHeaders: const <String, String>{},
            contentTypeMime: cachedHead.contentTypeMime,
            acceptRanges: cachedHead.acceptRanges,
            totalBytes: cachedHead.totalBytes,
            startByte: headRange.startByte,
            endByte: headRange.endByte,
            hasRange: headRange.hasRange,
          );
          diag.statusCode = response.statusCode;
          diag.cacheStatus = 'hit';
          diag.reason = 'head-metadata';
          diag.reuseOutcome = 'cache-only';
          await response.close();
          return;
        }
      }

      if (method == 'GET' && cacheRange != null) {
        var coverage = entry.cachedCoverageStartingAt(cacheRange.startByte);
        if (coverage == null || coverage.lengthBytes <= 0) {
          final waited = await _awaitWarmupProgress(entry);
          diag.waitedWarmup = waited;
          coverage = entry.cachedCoverageStartingAt(cacheRange.startByte);
        }
        if (coverage == null || coverage.lengthBytes <= 0) {
          final waited = await _awaitInFlightCacheWrite(
            entry,
            requestedStartByte: cacheRange.startByte,
          );
          diag.waitedCacheFill = waited;
          coverage = entry.cachedCoverageStartingAt(cacheRange.startByte);
        }
        if (coverage != null && coverage.lengthBytes > 0) {
          final served = await _tryServeCachedRange(
            request: request,
            response: response,
            entry: entry,
            coverage: coverage,
            range: cacheRange,
          );
          if (served.served) {
            diag.statusCode = served.statusCode;
            diag.cacheStatus = served.remoteBytes > 0 ? 'partial' : 'hit';
            diag.reason = served.reason;
            diag.reuseOutcome =
                served.remoteBytes > 0 ? 'cache+remote-tail' : 'cache-only';
            diag.cachedBytes = served.cachedBytes;
            diag.remoteBytes = served.remoteBytes;
            return;
          }
          if (served.reason.isNotEmpty) {
            diag.missReason = served.reason;
          }
        } else {
          diag.missReason = _classifyCacheMiss(
            entry,
            requestedStartByte: cacheRange.startByte,
          );
        }
      }

      if (method == 'GET' && cacheRange != null) {
        inFlightCacheWrite = _beginInFlightCacheWrite(
          entry: entry,
          startByte: cacheRange.startByte,
          plannedEndByteExclusive:
              cacheRange.endByte == null ? null : cacheRange.endByte! + 1,
        );
      }

      remote = await _openRemote(
        entry,
        requestUri: request.uri,
        method: method,
        range: request.headers.value(HttpHeaders.rangeHeader),
        ifRange: request.headers.value(HttpHeaders.ifRangeHeader),
      );

      response.statusCode = remote.response.statusCode;
      diag.statusCode = response.statusCode;
      _copyHeaders(remote.response.headers, response.headers);

      if (method == 'GET') {
        final relay = await _relayRemoteDirect(
          entry: entry,
          response: response,
          requestRange: cacheRange,
          remote: remote.response,
          abortRemote: remote.close,
        );
        diag.cacheStatus = relay.cached ? 'miss' : 'remote';
        diag.reason = relay.reason;
        diag.reuseOutcome = 'direct-upstream';
        if (diag.missReason == '-' || diag.missReason.trim().isEmpty) {
          diag.missReason = relay.reason;
        }
        diag.remoteBytes = relay.bytesRelayed;
        await remote.close();
        remote = null;
      } else {
        diag.cacheStatus = 'miss';
        diag.reason = 'head-remote';
        diag.reuseOutcome = 'direct-upstream';
        if (diag.missReason == '-' || diag.missReason.trim().isEmpty) {
          diag.missReason = 'head-remote';
        }
      }
    } on _HttpStreamProxyDownloadCancelledException {
      diag.statusCode = diag.statusCode == 0 ? 499 : diag.statusCode;
      diag.cacheStatus =
          diag.cacheStatus.isEmpty ? 'cancelled' : diag.cacheStatus;
      diag.reason = 'download-cancelled';
      diag.reuseOutcome =
          diag.reuseOutcome.trim().isEmpty ? 'cancelled' : diag.reuseOutcome;
      if (diag.missReason == '-' || diag.missReason.trim().isEmpty) {
        diag.missReason = 'download-cancelled';
      }
      try {
        await response.close();
      } catch (_) {}
    } on _HttpStreamProxyClientDisconnectedException {
      diag.statusCode = diag.statusCode == 0 ? 499 : diag.statusCode;
      diag.cacheStatus =
          diag.cacheStatus.isEmpty ? 'client-disconnected' : diag.cacheStatus;
      diag.reason = 'client-disconnected';
      diag.reuseOutcome = diag.reuseOutcome.trim().isEmpty
          ? 'client-disconnected'
          : diag.reuseOutcome;
      if (diag.missReason == '-' || diag.missReason.trim().isEmpty) {
        diag.missReason = 'client-disconnected';
      }
      try {
        await response.close();
      } catch (_) {}
    } catch (_) {
      diag.statusCode =
          diag.statusCode == 0 ? HttpStatus.badGateway : diag.statusCode;
      try {
        response.statusCode = HttpStatus.badGateway;
        response.headers
            .set(HttpHeaders.contentTypeHeader, 'text/plain; charset=utf-8');
        response.write('HTTP stream proxy error');
      } catch (_) {}
      diag.cacheStatus = 'error';
      diag.reason = 'proxy-error';
      diag.reuseOutcome = 'proxy-error';
      try {
        await response.close();
      } catch (_) {}
    } finally {
      _recordDiagnostic(diag.build());
      if (activeEntry != null && inFlightCacheWrite != null) {
        _finishInFlightCacheWrite(
          activeEntry,
          inFlightCacheWrite,
        );
      }
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
    final abort = Completer<void>();
    final request = http.AbortableStreamedRequest(
      method,
      _resolveRemoteUri(entry, requestUri),
      abortTrigger: abort.future,
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
    final client = _createHttpClientForEntry(entry, dedicated: true);
    final response = await client.send(request);
    return _OpenedRemote(
      response: response,
      ownedClient: client,
      abort: abort,
    );
  }

  Future<_CachedServeResult> _tryServeCachedRange({
    required HttpRequest request,
    required HttpResponse response,
    required _HttpStreamProxyEntry entry,
    required _HttpStreamProxyCachedCoverage coverage,
    required _CacheableRangeRequest range,
  }) async {
    final totalFromCache = coverage.totalBytes;
    final requestedEnd = range.endByte;
    final requestedLength =
        requestedEnd == null ? null : requestedEnd - range.startByte + 1;
    if (requestedLength != null && requestedLength <= 0) {
      return const _CachedServeResult.notServed(
        reason: 'invalid-requested-range',
      );
    }

    var cachedBytesToServe = coverage.lengthBytes;
    if (requestedLength != null && cachedBytesToServe > requestedLength) {
      cachedBytesToServe = requestedLength;
    }
    if (range.hasRange &&
        totalFromCache == null &&
        requestedLength != null &&
        cachedBytesToServe >= requestedLength) {
      return const _CachedServeResult.notServed(
        reason: 'range-total-unknown',
      );
    }

    final nextStart = range.startByte + cachedBytesToServe;
    _OpenedRemote? remote;
    _HttpStreamProxyInFlightCacheWrite? inFlightCacheWrite;
    String? progressId;
    var responseCommitted = false;
    try {
      var totalBytes = totalFromCache;
      var contentTypeMime = coverage.contentTypeMime;
      var acceptRanges = coverage.acceptRanges;
      var remoteBytes = 0;
      final needsRemoteTail = requestedLength != null
          ? cachedBytesToServe < requestedLength
          : (totalBytes == null || nextStart < totalBytes);

      if (needsRemoteTail) {
        inFlightCacheWrite = _beginInFlightCacheWrite(
          entry: entry,
          startByte: nextStart,
          plannedEndByteExclusive:
              requestedEnd == null ? totalBytes : requestedEnd + 1,
        );
        remote = await _openRemote(
          entry,
          requestUri: request.uri,
          method: request.method.toUpperCase(),
          range: requestedEnd == null
              ? 'bytes=$nextStart-'
              : 'bytes=$nextStart-$requestedEnd',
          ifRange: request.headers.value(HttpHeaders.ifRangeHeader),
        );
        final remoteStatus = remote.response.statusCode;
        if (range.hasRange && remoteStatus != HttpStatus.partialContent) {
          await remote.close();
          return const _CachedServeResult.notServed(
            reason: 'tail-range-ignored',
          );
        }

        contentTypeMime ??=
            _contentTypeMimeFromHeaders(remote.response.headers);
        acceptRanges =
            acceptRanges || _acceptsByteRanges(remote.response.headers);
        totalBytes ??= _inferTotalBytesFromHeaders(
          remoteStatus,
          remote.response.headers,
          nextStart,
        );
        if (range.hasRange && totalBytes == null) {
          await remote.close();
          return const _CachedServeResult.notServed(
            reason: 'tail-total-unknown',
          );
        }
      }

      response.statusCode =
          range.hasRange ? HttpStatus.partialContent : HttpStatus.ok;
      _applyCachedResponseHeaders(
        response.headers,
        remoteHeaders: remote?.response.headers ?? const <String, String>{},
        contentTypeMime: contentTypeMime,
        acceptRanges: acceptRanges,
        totalBytes: totalBytes,
        startByte: range.startByte,
        endByte: requestedEnd,
        hasRange: range.hasRange,
      );

      var remainingCached = cachedBytesToServe;
      for (final segment in coverage.segments) {
        if (remainingCached <= 0) break;
        final length = remainingCached < segment.availableBytes
            ? remainingCached
            : segment.availableBytes;
        responseCommitted = true;
        await response.addStream(
          segment.range.openReadSlice(
            startOffset: segment.readOffset,
            maxBytes: length,
          ),
        );
        remainingCached -= length;
      }

      if (remote != null) {
        final cancellation = _HttpStreamProxyDownloadCancellation();
        final bytesToSkip =
            (!range.hasRange && remote.response.statusCode == HttpStatus.ok)
                ? nextStart
                : 0;
        final expectedBytes = requestedEnd == null
            ? (totalBytes != null && totalBytes > nextStart
                ? totalBytes - nextStart
                : null)
            : ((requestedEnd - nextStart + 1).clamp(0, 1 << 30));
        progressId = _startDownloadProgress(
          entry: entry,
          kind: HttpStreamCacheDownloadKind.playbackFill,
          remoteUri: _effectiveRemoteUriFromResponse(
            remote.response,
            fallback: entry.remoteUri,
          ),
          startByte: nextStart,
          requestedBytes: expectedBytes == null || expectedBytes <= 0
              ? null
              : expectedBytes,
          totalBytes: totalBytes,
          contentTypeMime: contentTypeMime ??
              _contentTypeMimeFromHeaders(remote.response.headers),
          cancellation: cancellation,
        );
        responseCommitted = true;
        final relay = await _relayRemoteToResponse(
          entry: entry,
          response: response,
          remote: remote.response,
          cacheStartByte: nextStart,
          skipBytes: bytesToSkip,
          contentTypeMime: contentTypeMime ??
              _contentTypeMimeFromHeaders(remote.response.headers),
          totalBytes: totalBytes,
          acceptRanges: acceptRanges,
          progressId: progressId,
          cancellation: cancellation,
          abortRemote: remote.close,
        );
        remoteBytes = relay.bytesRelayed;
        await remote.close();
        remote = null;
      }

      return _CachedServeResult.served(
        statusCode: response.statusCode,
        cachedBytes: cachedBytesToServe,
        remoteBytes: remoteBytes,
        reason: needsRemoteTail ? 'cached-prefix+tail' : 'cached-coverage',
      );
    } on _HttpStreamProxyDownloadCancelledException {
      if (remote != null) {
        await remote.close();
      }
      return _CachedServeResult.served(
        statusCode: response.statusCode == 0
            ? HttpStatus.partialContent
            : response.statusCode,
        cachedBytes: cachedBytesToServe,
        remoteBytes: 0,
        reason: 'download-cancelled',
      );
    } on _HttpStreamProxyClientDisconnectedException {
      if (remote != null) {
        await remote.close();
      }
      return _CachedServeResult.served(
        statusCode: response.statusCode == 0
            ? HttpStatus.partialContent
            : response.statusCode,
        cachedBytes: cachedBytesToServe,
        remoteBytes: 0,
        reason: 'client-disconnected',
      );
    } catch (_) {
      if (remote != null) {
        await remote.close();
      }
      if (responseCommitted) {
        return _CachedServeResult.served(
          statusCode: response.statusCode == 0
              ? HttpStatus.partialContent
              : response.statusCode,
          cachedBytes: cachedBytesToServe,
          remoteBytes: 0,
          reason: 'response-aborted',
        );
      }
      return const _CachedServeResult.notServed(
        reason: 'cache-serve-error',
      );
    } finally {
      _finishDownloadProgress(progressId);
      if (inFlightCacheWrite != null) {
        _finishInFlightCacheWrite(entry, inFlightCacheWrite);
      }
    }
  }

  Future<_RemoteRelayResult> _relayRemoteDirect({
    required _HttpStreamProxyEntry entry,
    required HttpResponse response,
    required _CacheableRangeRequest? requestRange,
    required http.StreamedResponse remote,
    Future<void> Function()? abortRemote,
  }) async {
    final status = remote.statusCode;
    if (requestRange == null) {
      final bytes = await _drainRemoteToResponse(response, remote.stream);
      return _RemoteRelayResult(
        bytesRelayed: bytes,
        cached: false,
        reason: 'invalid-range',
      );
    }

    if (status == HttpStatus.ok && requestRange.hasRange) {
      final bytes = await _drainRemoteToResponse(response, remote.stream);
      return _RemoteRelayResult(
        bytesRelayed: bytes,
        cached: false,
        reason: 'range-ignored-upstream',
      );
    }

    final cacheStartByte = _cacheStartByteForResponse(
      requestRange: requestRange,
      remote: remote,
    );
    if (cacheStartByte == null) {
      final bytes = await _drainRemoteToResponse(response, remote.stream);
      return _RemoteRelayResult(
        bytesRelayed: bytes,
        cached: false,
        reason: 'uncacheable-response',
      );
    }

    final totalBytes =
        _inferTotalBytesFromHeaders(status, remote.headers, cacheStartByte);
    final expectedBytes = requestRange.hasRange
        ? (requestRange.endByte == null
            ? (totalBytes != null && totalBytes > cacheStartByte
                ? totalBytes - cacheStartByte
                : null)
            : ((requestRange.endByte! - cacheStartByte + 1).clamp(0, 1 << 30)))
        : (totalBytes != null && totalBytes > cacheStartByte
            ? totalBytes - cacheStartByte
            : null);
    final cancellation = _HttpStreamProxyDownloadCancellation();
    final progressId = _startDownloadProgress(
      entry: entry,
      kind: HttpStreamCacheDownloadKind.playbackFill,
      remoteUri: _effectiveRemoteUriFromResponse(
        remote,
        fallback: entry.remoteUri,
      ),
      startByte: cacheStartByte,
      requestedBytes:
          expectedBytes == null || expectedBytes <= 0 ? null : expectedBytes,
      totalBytes: totalBytes,
      contentTypeMime: _contentTypeMimeFromHeaders(remote.headers),
      cancellation: cancellation,
    );
    try {
      final relay = await _relayRemoteToResponse(
        entry: entry,
        response: response,
        remote: remote,
        cacheStartByte: cacheStartByte,
        skipBytes: requestRange.hasRange ? 0 : requestRange.startByte,
        contentTypeMime: _contentTypeMimeFromHeaders(remote.headers),
        totalBytes: totalBytes,
        acceptRanges: _acceptsByteRanges(remote.headers) ||
            status == HttpStatus.partialContent,
        progressId: progressId,
        cancellation: cancellation,
        abortRemote: abortRemote,
      );
      return _RemoteRelayResult(
        bytesRelayed: relay.bytesRelayed,
        cached: relay.cached,
        reason: relay.cached ? 'remote-cached' : 'remote-empty',
      );
    } finally {
      _finishDownloadProgress(progressId);
    }
  }

  Future<_RemoteCacheResult> _relayRemoteToResponse({
    required _HttpStreamProxyEntry entry,
    required HttpResponse response,
    required http.StreamedResponse remote,
    required int cacheStartByte,
    required int skipBytes,
    required String? contentTypeMime,
    required int? totalBytes,
    required bool acceptRanges,
    String? progressId,
    _HttpStreamProxyDownloadCancellation? cancellation,
    Future<void> Function()? abortRemote,
  }) async {
    final pendingFile = await entry.createPendingRangeFile(cacheStartByte);
    final sink = pendingFile.openWrite();
    var bytesRelayed = 0;
    var remainingSkip = skipBytes < 0 ? 0 : skipBytes;
    var clientDisconnected = false;
    unawaited(
      response.done.then<void>(
        (_) {
          clientDisconnected = true;
        },
        onError: (_) {
          clientDisconnected = true;
        },
      ),
    );
    final remoteIterator = StreamIterator<List<int>>(remote.stream);
    try {
      while (true) {
        final chunk = await _nextRemoteChunk(
          remoteIterator,
          cancellation: cancellation,
          abortRemote: abortRemote,
        );
        if (chunk == null) break;
        if (clientDisconnected) {
          throw const _HttpStreamProxyClientDisconnectedException();
        }
        var data = chunk;
        if (remainingSkip > 0) {
          if (remainingSkip >= data.length) {
            remainingSkip -= data.length;
            continue;
          }
          data = data.sublist(remainingSkip);
          remainingSkip = 0;
        }
        if (data.isEmpty) continue;
        sink.add(data);
        try {
          response.add(data);
        } catch (_) {
          throw const _HttpStreamProxyClientDisconnectedException();
        }
        bytesRelayed += data.length;
        _incrementDownloadProgress(progressId ?? '', data.length);
      }
      await sink.flush();
      await sink.close();
      if (bytesRelayed > 0) {
        await entry.storePendingRangeFile(
          pendingFile: pendingFile,
          startByte: cacheStartByte,
          lengthBytes: bytesRelayed,
          contentTypeMime: contentTypeMime,
          totalBytes: totalBytes,
          acceptRanges: acceptRanges,
          maxRanges: _maxCachedRangesPerEntry,
          maxBytes: _maxCachedBytesPerEntry,
        );
        return _RemoteCacheResult(bytesRelayed: bytesRelayed, cached: true);
      }
      try {
        await pendingFile.delete();
      } catch (_) {}
      return const _RemoteCacheResult(bytesRelayed: 0, cached: false);
    } catch (_) {
      try {
        await remoteIterator.cancel();
      } catch (_) {}
      try {
        await sink.flush();
      } catch (_) {}
      try {
        await sink.close();
      } catch (_) {}
      try {
        await pendingFile.delete();
      } catch (_) {}
      rethrow;
    } finally {
      try {
        await remoteIterator.cancel();
      } catch (_) {}
    }
  }

  Future<List<int>?> _nextRemoteChunk(
    StreamIterator<List<int>> iterator, {
    _HttpStreamProxyDownloadCancellation? cancellation,
    Future<void> Function()? abortRemote,
  }) async {
    final cancelSignal = cancellation?.cancelled;
    if (cancelSignal == null) {
      return await iterator.moveNext() ? iterator.current : null;
    }
    final result = await Future.any<Object?>(
      <Future<Object?>>[
        iterator.moveNext().then<Object?>((hasNext) => hasNext),
        cancelSignal.then<Object?>(
          (_) => const _HttpStreamProxyRemoteReadCancelled(),
        ),
      ],
    );
    if (result is _HttpStreamProxyRemoteReadCancelled) {
      if (abortRemote != null) {
        await abortRemote();
      }
      throw const _HttpStreamProxyDownloadCancelledException();
    }
    return result == true ? iterator.current : null;
  }

  Future<_RemoteCacheResult> _cacheRemoteToEntry({
    required _HttpStreamProxyEntry entry,
    required http.StreamedResponse remote,
    required int cacheStartByte,
    required int skipBytes,
    required int? maxBytes,
    required String? contentTypeMime,
    required int? totalBytes,
    required bool acceptRanges,
    String? progressId,
  }) async {
    final pendingFile = await entry.createPendingRangeFile(cacheStartByte);
    final sink = pendingFile.openWrite();
    var bytesRelayed = 0;
    var remainingSkip = skipBytes < 0 ? 0 : skipBytes;
    var remainingMax = maxBytes != null && maxBytes >= 0 ? maxBytes : null;
    try {
      await for (final chunk in remote.stream) {
        var data = chunk;
        if (remainingSkip > 0) {
          if (remainingSkip >= data.length) {
            remainingSkip -= data.length;
            continue;
          }
          data = data.sublist(remainingSkip);
          remainingSkip = 0;
        }
        if (data.isEmpty) continue;
        if (remainingMax != null) {
          if (remainingMax <= 0) break;
          if (data.length > remainingMax) {
            data = data.sublist(0, remainingMax);
          }
        }
        if (data.isEmpty) continue;
        sink.add(data);
        bytesRelayed += data.length;
        _incrementDownloadProgress(progressId ?? '', data.length);
        if (remainingMax != null) {
          remainingMax -= data.length;
          if (remainingMax <= 0) break;
        }
      }
      await sink.flush();
      await sink.close();
      if (bytesRelayed > 0) {
        await entry.storePendingRangeFile(
          pendingFile: pendingFile,
          startByte: cacheStartByte,
          lengthBytes: bytesRelayed,
          contentTypeMime: contentTypeMime,
          totalBytes: totalBytes,
          acceptRanges: acceptRanges,
          maxRanges: _maxCachedRangesPerEntry,
          maxBytes: _maxCachedBytesPerEntry,
        );
        return _RemoteCacheResult(bytesRelayed: bytesRelayed, cached: true);
      }
      try {
        await pendingFile.delete();
      } catch (_) {}
      return const _RemoteCacheResult(bytesRelayed: 0, cached: false);
    } catch (_) {
      try {
        await sink.flush();
      } catch (_) {}
      try {
        await sink.close();
      } catch (_) {}
      try {
        await pendingFile.delete();
      } catch (_) {}
      rethrow;
    }
  }

  Future<int> _drainRemoteToResponse(
    HttpResponse response,
    Stream<List<int>> stream,
  ) async {
    var total = 0;
    await for (final chunk in stream) {
      if (chunk.isEmpty) continue;
      response.add(chunk);
      total += chunk.length;
    }
    return total;
  }

  http.Client _createHttpClientForEntry(
    _HttpStreamProxyEntry entry, {
    bool dedicated = false,
  }) {
    final proxy = (entry.cacheKey.proxyUrl ?? '').trim();
    final proxyUri = proxy.isEmpty ? null : Uri.tryParse(proxy);
    final hasProxy = proxyUri != null &&
        proxyUri.host.trim().isNotEmpty &&
        proxyUri.port > 0 &&
        proxyUri.port <= 65535;
    if (!hasProxy) {
      if (!dedicated) return _httpClient;
      return _httpClientFactory?.call() ??
          LinHttpClientFactory.createClient(
            LinHttpClientFactory.config.copyWith(userAgent: ''),
          );
    }

    return LinHttpClientFactory.createClient(
      LinHttpClientFactory.config.copyWith(
        userAgent: '',
        proxyResolver: (_) => 'PROXY ${proxyUri.host}:${proxyUri.port}',
      ),
    );
  }

  http.Client get _httpClient {
    return _client ??= (_httpClientFactory?.call() ??
        LinHttpClientFactory.createClient(
          LinHttpClientFactory.config.copyWith(userAgent: ''),
        ));
  }

  Uri _resolveRemoteUri(_HttpStreamProxyEntry entry, Uri requestUri) {
    final requestedSegments = requestUri.pathSegments.length <= 2
        ? const <String>[]
        : requestUri.pathSegments.sublist(2);
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

  static bool _coverageSatisfiesLength(
    _HttpStreamProxyCachedCoverage? coverage,
    int requiredBytes,
  ) {
    if (coverage == null) return false;
    if (requiredBytes <= 0) return true;
    return coverage.lengthBytes >= requiredBytes;
  }

  static int? _cacheStartByteForResponse({
    required _CacheableRangeRequest requestRange,
    required http.StreamedResponse remote,
  }) {
    if (remote.statusCode == HttpStatus.partialContent) {
      return _startByteFromContentRange(
            _headerValue(remote.headers, HttpHeaders.contentRangeHeader),
          ) ??
          requestRange.startByte;
    }
    if (remote.statusCode == HttpStatus.ok && !requestRange.hasRange) {
      return requestRange.startByte;
    }
    return null;
  }

  String _classifyCacheMiss(
    _HttpStreamProxyEntry entry, {
    required int requestedStartByte,
  }) {
    final hasAlternateCachedEntry = _hasAlternateCachedEntry(
      entry,
      requestedStartByte: requestedStartByte,
    );
    if (!entry.hasCachedRanges) {
      if (hasAlternateCachedEntry) return 'header-mismatch';
      return 'cache-empty';
    }
    if (!entry.coversCachedByte(requestedStartByte)) {
      if (hasAlternateCachedEntry) return 'header-mismatch';
      return 'range-not-covered';
    }
    return 'cache-unusable';
  }

  bool _hasAlternateCachedEntry(
    _HttpStreamProxyEntry entry, {
    required int requestedStartByte,
  }) {
    for (final other in _entries.values) {
      if (identical(other, entry) || other.fingerprint == entry.fingerprint) {
        continue;
      }
      if (other.remoteUri != entry.remoteUri) continue;
      if (!other.hasCachedRanges) continue;
      if (!other.coversCachedByte(requestedStartByte)) continue;
      return true;
    }
    return false;
  }

  static int? _startByteFromContentRange(String? raw) {
    final value = raw?.trim() ?? '';
    if (value.isEmpty) return null;
    final match = RegExp(r'^bytes\s+(\d+)-\d+/(\d+|\*)$').firstMatch(value);
    if (match == null) return null;
    return int.tryParse(match.group(1) ?? '');
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

  static Uri _effectiveRemoteUriFromResponse(
    http.StreamedResponse response, {
    required Uri fallback,
  }) {
    if (response is http.BaseResponseWithUrl) {
      final url = (response as http.BaseResponseWithUrl).url;
      if (url.scheme.trim().isNotEmpty && url.host.trim().isNotEmpty) {
        return url;
      }
    }
    return fallback;
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

    if (totalBytes == null || totalBytes <= 0) return;
    final maxEnd = totalBytes - 1;
    final resolvedEnd = hasRange ? min(endByte ?? maxEnd, maxEnd) : maxEnd;
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

  static Directory get _cacheRootDirectory => Directory(
        _joinPath(Directory.systemTemp.path, _cacheRootName),
      );

  static String _joinPath(String left, String right) {
    if (left.isEmpty) return right;
    if (right.isEmpty) return left;
    if (left.endsWith(Platform.pathSeparator)) {
      return '$left$right';
    }
    return '$left${Platform.pathSeparator}$right';
  }

  static String _summarizeUrl(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return '';
    final uri = Uri.tryParse(value);
    if (uri == null || uri.host.trim().isEmpty || uri.scheme.isEmpty) {
      return _summarizeInline(value);
    }
    final buffer = StringBuffer()
      ..write(uri.scheme)
      ..write('://')
      ..write(uri.host);
    if (uri.hasPort &&
        !((uri.scheme == 'http' && uri.port == 80) ||
            (uri.scheme == 'https' && uri.port == 443))) {
      buffer
        ..write(':')
        ..write(uri.port);
    }
    buffer.write(uri.path.trim().isEmpty ? '/' : uri.path.trim());
    if (uri.hasQuery) buffer.write('?...');
    return _summarizeInline(buffer.toString());
  }

  static String _summarizeInline(String raw, {int limit = 180}) {
    final text = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text.length <= limit) return text;
    return '${text.substring(0, limit - 3)}...';
  }

  static String _summarizeIncomingRequestHeaders(HttpHeaders headers) {
    final names = <String>{};
    headers.forEach((name, values) {
      final fixed = name.trim().toLowerCase();
      if (fixed.isEmpty) return;
      names.add(fixed);
    });
    if (names.isEmpty) return '-';
    final sorted = names.toList(growable: false)..sort();
    return sorted.join('|');
  }

  static bool _isPlaybackMethod(String method) {
    final fixed = method.trim().toUpperCase();
    return fixed == 'GET' || fixed == 'HEAD';
  }

  static void _bumpCounter(Map<String, int> counts, String key) {
    final fixed = key.trim();
    if (fixed.isEmpty) return;
    counts[fixed] = (counts[fixed] ?? 0) + 1;
  }

  static String _formatCounterSummary(Map<String, int> counts) {
    if (counts.isEmpty) return '(empty)';
    final entries = counts.entries.toList(growable: false)
      ..sort((a, b) {
        final countCmp = b.value.compareTo(a.value);
        if (countCmp != 0) return countCmp;
        return a.key.compareTo(b.key);
      });
    return entries.map((entry) => '${entry.key}=${entry.value}').join(', ');
  }
}

class _HttpStreamProxyEntry {
  _HttpStreamProxyEntry._({
    required this.id,
    required this.fingerprint,
    required this.cacheKey,
    required this.remoteUri,
    required this.httpHeaders,
    required this.localPathSegments,
    required this.cacheDirectory,
    required DateTime now,
  })  : lastAccessedAt = now,
        lastUpdatedAt = now,
        expiresAt = now.add(HttpStreamProxyServer._entryTtl),
        metadataFile = File(
          HttpStreamProxyServer._joinPath(
            cacheDirectory.path,
            metadataFileName,
          ),
        );

  static const String metadataFileName = 'meta.json';

  static Future<_HttpStreamProxyEntry> create({
    required String id,
    required String fingerprint,
    required HttpStreamCacheKey cacheKey,
    required Uri remoteUri,
    required Map<String, String> httpHeaders,
    required List<String> localPathSegments,
    required Directory cacheDirectory,
  }) async {
    final now = DateTime.now();
    final entry = _HttpStreamProxyEntry._(
      id: id,
      fingerprint: fingerprint,
      cacheKey: cacheKey,
      remoteUri: remoteUri,
      httpHeaders: httpHeaders,
      localPathSegments: localPathSegments,
      cacheDirectory: cacheDirectory,
      now: now,
    );
    await entry._loadFromDisk();
    return entry;
  }

  final String id;
  final String fingerprint;
  final HttpStreamCacheKey cacheKey;
  Uri remoteUri;
  final Map<String, String> httpHeaders;
  final List<String> localPathSegments;
  final Directory cacheDirectory;
  final File metadataFile;
  final Map<int, _HttpStreamProxyCachedRange> _cachedRanges =
      <int, _HttpStreamProxyCachedRange>{};
  DateTime lastAccessedAt;
  DateTime lastUpdatedAt;
  DateTime expiresAt;
  DateTime? lastFailureAt;
  String? lastFailureMessage;
  bool _hasObservedPlaybackRequest = false;

  bool get hasCachedRanges => _cachedRanges.isNotEmpty;

  void touch() {
    final now = DateTime.now();
    lastAccessedAt = now;
    lastUpdatedAt = now;
    expiresAt = now.add(HttpStreamProxyServer._entryTtl);
    unawaited(_writeMetadata());
  }

  bool coversCachedByte(int byteOffset) {
    for (final range in _cachedRanges.values) {
      if (range.coversByte(byteOffset)) return true;
    }
    return false;
  }

  bool markObservedPlaybackRequest() {
    if (_hasObservedPlaybackRequest) return false;
    _hasObservedPlaybackRequest = true;
    lastUpdatedAt = DateTime.now();
    unawaited(_writeMetadata());
    return true;
  }

  Future<void> recordFailure(Object? error) async {
    final now = DateTime.now();
    lastUpdatedAt = now;
    lastFailureAt = now;
    final message = (error ?? '').toString().trim();
    lastFailureMessage = message.isEmpty ? 'unknown' : message;
    await _writeMetadata();
  }

  Future<void> updateRemoteUri(Uri value) async {
    if (remoteUri == value) return;
    remoteUri = value;
    lastUpdatedAt = DateTime.now();
    expiresAt = lastUpdatedAt.add(HttpStreamProxyServer._entryTtl);
    await _writeMetadata();
  }

  Future<void> storeBytesRange({
    required int startByte,
    required List<int> bytes,
    required String? contentTypeMime,
    required int? totalBytes,
    required bool acceptRanges,
    required int maxRanges,
    required int maxBytes,
  }) async {
    await _ensureDirectory();
    final pending = await createPendingRangeFile(startByte);
    await pending.writeAsBytes(bytes, flush: true);
    await storePendingRangeFile(
      pendingFile: pending,
      startByte: startByte,
      lengthBytes: bytes.length,
      contentTypeMime: contentTypeMime,
      totalBytes: totalBytes,
      acceptRanges: acceptRanges,
      maxRanges: maxRanges,
      maxBytes: maxBytes,
    );
  }

  Future<File> createPendingRangeFile(int startByte) async {
    await _ensureDirectory();
    final fileName =
        'pending_${startByte}_${DateTime.now().microsecondsSinceEpoch}.bin';
    return File(HttpStreamProxyServer._joinPath(cacheDirectory.path, fileName));
  }

  Future<void> storePendingRangeFile({
    required File pendingFile,
    required int startByte,
    required int lengthBytes,
    required String? contentTypeMime,
    required int? totalBytes,
    required bool acceptRanges,
    required int maxRanges,
    required int maxBytes,
  }) async {
    touch();
    if (lengthBytes <= 0) {
      try {
        await pendingFile.delete();
      } catch (_) {}
      return;
    }

    await _ensureDirectory();
    final finalName = 'range_${startByte}_$lengthBytes.bin';
    final finalPath =
        HttpStreamProxyServer._joinPath(cacheDirectory.path, finalName);
    final finalFile = File(finalPath);
    List<int>? fallbackBytes;
    if (Platform.isWindows) {
      try {
        if (await pendingFile.exists()) {
          fallbackBytes = await pendingFile.readAsBytes();
        }
      } catch (_) {}
    }
    try {
      if (await finalFile.exists()) {
        await finalFile.delete();
      }
    } catch (_) {}

    File storedFile = pendingFile;
    try {
      if (Platform.isWindows) {
        if (await pendingFile.exists()) {
          // Windows can sporadically fail same-directory renames for freshly
          // flushed temp files, so finalize via copy + delete instead.
          await _ensureDirectory();
          storedFile = await pendingFile.copy(finalPath);
          try {
            await pendingFile.delete();
          } catch (_) {}
        } else if (fallbackBytes != null && fallbackBytes.isNotEmpty) {
          await finalFile.writeAsBytes(fallbackBytes, flush: true);
          storedFile = finalFile;
        } else {
          storedFile = await pendingFile.rename(finalPath);
        }
      } else {
        storedFile = await pendingFile.rename(finalPath);
      }
    } catch (_) {
      await _ensureDirectory();
      if (await finalFile.exists()) {
        storedFile = finalFile;
      } else if (await pendingFile.exists()) {
        await finalFile.writeAsBytes(await pendingFile.readAsBytes(),
            flush: true);
        storedFile = finalFile;
        try {
          await pendingFile.delete();
        } catch (_) {}
      } else if (fallbackBytes != null && fallbackBytes.isNotEmpty) {
        await finalFile.writeAsBytes(fallbackBytes, flush: true);
        storedFile = finalFile;
      } else {
        rethrow;
      }
    }

    final range = _HttpStreamProxyCachedRange(
      startByte: startByte,
      lengthBytes: lengthBytes,
      file: storedFile,
      contentTypeMime: contentTypeMime,
      totalBytes: totalBytes,
      acceptRanges: acceptRanges,
      storedAt: DateTime.now(),
    );
    await _storeCachedRange(
      range,
      maxRanges: maxRanges,
      maxBytes: maxBytes,
    );
  }

  _HttpStreamProxyCachedCoverage? cachedCoverageStartingAt(int startByte) {
    touch();
    if (_cachedRanges.isEmpty) return null;
    final sorted = _cachedRanges.values.toList(growable: false)
      ..sort((a, b) => a.startByte.compareTo(b.startByte));

    final segments = <_HttpStreamProxyCachedCoverageSegment>[];
    var cursor = startByte;
    while (true) {
      _HttpStreamProxyCachedRange? best;
      for (final range in sorted) {
        if (!range.coversByte(cursor) && range.startByte != cursor) continue;
        if (best == null || range.endExclusive > best.endExclusive) {
          best = range;
        }
      }
      if (best == null) break;
      final readOffset = cursor > best.startByte ? cursor - best.startByte : 0;
      final available = best.lengthBytes - readOffset;
      if (available <= 0) break;
      segments.add(
        _HttpStreamProxyCachedCoverageSegment(
          range: best,
          readOffset: readOffset,
        ),
      );
      final nextCursor = best.endExclusive;
      if (nextCursor <= cursor) break;
      cursor = nextCursor;
    }

    if (segments.isEmpty) return null;
    String? contentTypeMime;
    int? totalBytes;
    var acceptRanges = false;
    var lengthBytes = 0;
    for (final segment in segments) {
      contentTypeMime ??= segment.range.contentTypeMime;
      totalBytes ??= segment.range.totalBytes;
      acceptRanges = acceptRanges || segment.range.acceptRanges;
      lengthBytes += segment.availableBytes;
    }
    return _HttpStreamProxyCachedCoverage(
      startByte: startByte,
      segments: segments,
      lengthBytes: lengthBytes,
      contentTypeMime: contentTypeMime,
      totalBytes: totalBytes,
      acceptRanges: acceptRanges,
    );
  }

  _HttpStreamProxyHeadMetadata? headMetadataFor(_CacheableRangeRequest range) {
    touch();
    if (_cachedRanges.isEmpty) return null;
    final ranges = _cachedRanges.values.toList(growable: false)
      ..sort((a, b) => a.startByte.compareTo(b.startByte));
    _HttpStreamProxyCachedRange? metadataRange;
    for (final rangeEntry in ranges) {
      if (rangeEntry.totalBytes != null) {
        metadataRange = rangeEntry;
        break;
      }
    }
    metadataRange ??= ranges.first;
    if (metadataRange.totalBytes == null || metadataRange.totalBytes! <= 0) {
      return null;
    }
    if (range.hasRange && range.startByte >= metadataRange.totalBytes!) {
      return null;
    }
    return _HttpStreamProxyHeadMetadata(
      statusCode: range.hasRange ? HttpStatus.partialContent : HttpStatus.ok,
      contentTypeMime: metadataRange.contentTypeMime,
      totalBytes: metadataRange.totalBytes!,
      acceptRanges: metadataRange.acceptRanges,
    );
  }

  Future<void> _storeCachedRange(
    _HttpStreamProxyCachedRange range, {
    required int maxRanges,
    required int maxBytes,
  }) async {
    lastFailureAt = null;
    lastFailureMessage = null;
    final existing = _cachedRanges[range.startByte];
    if (existing == null || range.lengthBytes >= existing.lengthBytes) {
      _cachedRanges[range.startByte] = range;
      if (existing != null && existing.file.path != range.file.path) {
        await existing.deleteIfExists();
      }
    } else if (existing.totalBytes == null && range.totalBytes != null) {
      _cachedRanges[range.startByte] = existing.copyWith(
        totalBytes: range.totalBytes,
        contentTypeMime: existing.contentTypeMime ?? range.contentTypeMime,
        acceptRanges: existing.acceptRanges || range.acceptRanges,
      );
      await range.deleteIfExists();
    } else {
      await range.deleteIfExists();
    }
    await _pruneCachedRanges(maxRanges: maxRanges, maxBytes: maxBytes);
    await _writeMetadata();
  }

  Future<void> _pruneCachedRanges({
    required int maxRanges,
    required int maxBytes,
  }) async {
    if (_cachedRanges.isEmpty) return;

    final sorted = _cachedRanges.values.toList(growable: false)
      ..sort((a, b) => a.storedAt.compareTo(b.storedAt));
    var total = sorted.fold<int>(0, (sum, item) => sum + item.lengthBytes);
    final removeKeys = <int>{};

    for (final item in sorted) {
      final overCount = _cachedRanges.length - removeKeys.length > maxRanges;
      final overBytes = total > maxBytes;
      if (!overCount && !overBytes) break;
      removeKeys.add(item.startByte);
      total -= item.lengthBytes;
    }

    for (final key in removeKeys) {
      final removed = _cachedRanges.remove(key);
      if (removed != null) {
        await removed.deleteIfExists();
      }
    }
  }

  Future<void> _ensureDirectory() async {
    if (await cacheDirectory.exists()) return;
    await cacheDirectory.create(recursive: true);
  }

  HttpStreamCacheSnapshot snapshot({
    required DateTime now,
    required Duration ttl,
    required bool warmupInProgress,
  }) {
    final ranges = _cachedRanges.values.toList(growable: false)
      ..sort((a, b) => a.startByte.compareTo(b.startByte));
    final descriptors = ranges
        .map(
          (range) => HttpStreamCacheRange(
            startByte: range.startByte,
            lengthBytes: range.lengthBytes,
          ),
        )
        .toList(growable: false);
    final cachedBytes =
        ranges.fold<int>(0, (sum, range) => sum + range.lengthBytes);
    final contiguousBytesFromStart = _contiguousBytesFromStart(ranges);
    final totalBytes = _resolveKnownTotalBytes(ranges);
    final acceptRanges = ranges.any((range) => range.acceptRanges);

    var state = HttpStreamCacheState.warming;
    if (now.difference(lastUpdatedAt) > ttl) {
      state = HttpStreamCacheState.stale;
    } else if (totalBytes != null &&
        totalBytes > 0 &&
        contiguousBytesFromStart >= totalBytes) {
      state = HttpStreamCacheState.completed;
    } else if (cachedBytes > 0) {
      state = HttpStreamCacheState.playable;
    } else if (lastFailureAt != null ||
        (lastFailureMessage ?? '').trim().isNotEmpty) {
      state = HttpStreamCacheState.failed;
    } else if (warmupInProgress) {
      state = HttpStreamCacheState.warming;
    }

    return HttpStreamCacheSnapshot(
      key: cacheKey,
      state: state,
      ranges: descriptors,
      cachedBytes: cachedBytes,
      contiguousBytesFromStart: contiguousBytesFromStart,
      totalBytes: totalBytes,
      acceptRanges: acceptRanges,
      lastUpdatedAt: lastUpdatedAt,
      warmupInProgress: warmupInProgress,
      hasObservedPlaybackRequest: _hasObservedPlaybackRequest,
      lastFailureAt: lastFailureAt,
      lastFailureMessage: lastFailureMessage,
    );
  }

  Future<void> _loadFromDisk() async {
    await _ensureDirectory();
    if (!await metadataFile.exists()) {
      await _writeMetadata();
      return;
    }

    try {
      final decoded = jsonDecode(await metadataFile.readAsString());
      if (decoded is! Map) {
        await _writeMetadata();
        return;
      }

      final rawUpdatedAt = decoded['lastUpdatedAt']?.toString().trim() ?? '';
      lastUpdatedAt = DateTime.tryParse(rawUpdatedAt) ?? lastUpdatedAt;
      final rawRemoteUri = decoded['remoteUri']?.toString().trim() ?? '';
      final storedRemoteUri = Uri.tryParse(rawRemoteUri);
      if (storedRemoteUri != null &&
          storedRemoteUri.scheme.trim().isNotEmpty &&
          storedRemoteUri.host.trim().isNotEmpty) {
        remoteUri = storedRemoteUri;
      }
      lastFailureAt =
          DateTime.tryParse(decoded['lastFailureAt']?.toString() ?? '');
      final rawFailureMessage =
          decoded['lastFailureMessage']?.toString().trim() ?? '';
      lastFailureMessage = rawFailureMessage.isEmpty ? null : rawFailureMessage;
      _hasObservedPlaybackRequest =
          decoded['hasObservedPlaybackRequest'] == true;

      final ranges = decoded['ranges'];
      if (ranges is List) {
        for (final raw in ranges) {
          final range = _HttpStreamProxyCachedRange.fromJson(
            raw,
            cacheDirectory: cacheDirectory,
          );
          if (range == null) continue;
          if (!await range.file.exists()) continue;
          _cachedRanges[range.startByte] = range;
        }
      }
      await _writeMetadata();
    } catch (_) {
      _cachedRanges.clear();
      await _writeMetadata();
    }
  }

  Future<void> _writeMetadata() async {
    try {
      await _ensureDirectory();
      final ordered = _cachedRanges.values.toList(growable: false)
        ..sort((a, b) => a.startByte.compareTo(b.startByte));
      final snapshotNow = snapshot(
        now: DateTime.now(),
        ttl: HttpStreamProxyServer._entryTtl,
        warmupInProgress: false,
      );
      final payload = <String, Object?>{
        'version': 2,
        'cacheKey': cacheKey.toJson(),
        'remoteUri': remoteUri.toString(),
        'httpHeaders': httpHeaders,
        'lastUpdatedAt': lastUpdatedAt.toIso8601String(),
        'lastFailureAt': lastFailureAt?.toIso8601String(),
        'lastFailureMessage': lastFailureMessage,
        'hasObservedPlaybackRequest': _hasObservedPlaybackRequest,
        'state': snapshotNow.state.name,
        'cachedBytes': snapshotNow.cachedBytes,
        'contiguousBytesFromStart': snapshotNow.contiguousBytesFromStart,
        'totalBytes': snapshotNow.totalBytes,
        'ranges':
            ordered.map((entry) => entry.toJson()).toList(growable: false),
      };
      await metadataFile.writeAsString(jsonEncode(payload), flush: true);
    } catch (_) {}
  }

  int _contiguousBytesFromStart(List<_HttpStreamProxyCachedRange> ranges) {
    var cursor = 0;
    for (final range in ranges) {
      if (range.startByte > cursor) break;
      if (range.endExclusive > cursor) {
        cursor = range.endExclusive;
      }
    }
    return cursor;
  }

  int? _resolveKnownTotalBytes(List<_HttpStreamProxyCachedRange> ranges) {
    for (final range in ranges) {
      final total = range.totalBytes;
      if (total != null && total > 0) return total;
    }
    return null;
  }
}

class _HttpStreamProxyCachedRange {
  const _HttpStreamProxyCachedRange({
    required this.startByte,
    required this.lengthBytes,
    required this.file,
    required this.contentTypeMime,
    required this.totalBytes,
    required this.acceptRanges,
    required this.storedAt,
  });

  final int startByte;
  final int lengthBytes;
  final File file;
  final String? contentTypeMime;
  final int? totalBytes;
  final bool acceptRanges;
  final DateTime storedAt;

  int get endExclusive => startByte + lengthBytes;

  bool coversByte(int byteOffset) {
    return byteOffset >= startByte && byteOffset < endExclusive;
  }

  int availableBytesFromOffset(int readOffset) {
    final remaining = lengthBytes - readOffset;
    return remaining < 0 ? 0 : remaining;
  }

  Stream<List<int>> openReadSlice({
    required int startOffset,
    required int maxBytes,
  }) {
    final safeStart = startOffset < 0 ? 0 : startOffset;
    final safeLength = maxBytes < 0 ? 0 : maxBytes;
    return file.openRead(safeStart, safeStart + safeLength);
  }

  Future<void> deleteIfExists() async {
    try {
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }

  _HttpStreamProxyCachedRange copyWith({
    String? contentTypeMime,
    int? totalBytes,
    bool? acceptRanges,
  }) {
    return _HttpStreamProxyCachedRange(
      startByte: startByte,
      lengthBytes: lengthBytes,
      file: file,
      contentTypeMime: contentTypeMime ?? this.contentTypeMime,
      totalBytes: totalBytes ?? this.totalBytes,
      acceptRanges: acceptRanges ?? this.acceptRanges,
      storedAt: storedAt,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'startByte': startByte,
      'lengthBytes': lengthBytes,
      'fileName': file.uri.pathSegments.isEmpty
          ? file.path
          : file.uri.pathSegments.last,
      'contentTypeMime': contentTypeMime,
      'totalBytes': totalBytes,
      'acceptRanges': acceptRanges,
      'storedAt': storedAt.toIso8601String(),
    };
  }

  static _HttpStreamProxyCachedRange? fromJson(
    Object? raw, {
    required Directory cacheDirectory,
  }) {
    if (raw is! Map) return null;
    final startByte = int.tryParse(raw['startByte']?.toString() ?? '');
    final lengthBytes = int.tryParse(raw['lengthBytes']?.toString() ?? '');
    final fileName = raw['fileName']?.toString().trim() ?? '';
    if (startByte == null || startByte < 0) return null;
    if (lengthBytes == null || lengthBytes <= 0) return null;
    if (fileName.isEmpty) return null;
    return _HttpStreamProxyCachedRange(
      startByte: startByte,
      lengthBytes: lengthBytes,
      file: File(
        HttpStreamProxyServer._joinPath(cacheDirectory.path, fileName),
      ),
      contentTypeMime: raw['contentTypeMime']?.toString(),
      totalBytes: int.tryParse(raw['totalBytes']?.toString() ?? ''),
      acceptRanges: raw['acceptRanges'] == true,
      storedAt: DateTime.tryParse(raw['storedAt']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}

class HttpStreamWarmupResult {
  const HttpStreamWarmupResult({
    required this.proxyUri,
    required this.effectiveRemoteUri,
    required this.startByte,
    required this.requestedBytes,
    required this.bytesWritten,
    required this.satisfiedFromCache,
    required this.contentTypeMime,
    required this.totalBytes,
    required this.acceptRanges,
  });

  final Uri proxyUri;
  final Uri effectiveRemoteUri;
  final int startByte;
  final int requestedBytes;
  final int bytesWritten;
  final bool satisfiedFromCache;
  final String? contentTypeMime;
  final int? totalBytes;
  final bool acceptRanges;
}

class _RegisteredProxyEntry {
  const _RegisteredProxyEntry({
    required this.baseUri,
    required this.entry,
  });

  final Uri baseUri;
  final _HttpStreamProxyEntry entry;
}

class _HttpStreamProxyDownloadProgress {
  _HttpStreamProxyDownloadProgress({
    required this.id,
    required this.key,
    required this.kind,
    required this.remoteUrl,
    required this.startByte,
    required this.requestedBytes,
    required this.totalBytes,
    required this.contentTypeMime,
  })  : startedAt = DateTime.now(),
        updatedAt = DateTime.now();

  final String id;
  final HttpStreamCacheKey key;
  final HttpStreamCacheDownloadKind kind;
  String remoteUrl;
  final int startByte;
  int bytesWritten = 0;
  int? requestedBytes;
  int? totalBytes;
  String? contentTypeMime;
  final DateTime startedAt;
  DateTime updatedAt;

  void update({
    int? bytesWritten,
    int? requestedBytes,
    int? totalBytes,
    String? contentTypeMime,
    String? remoteUrl,
  }) {
    if (bytesWritten != null) this.bytesWritten = bytesWritten;
    if (requestedBytes != null) this.requestedBytes = requestedBytes;
    if (totalBytes != null) this.totalBytes = totalBytes;
    if (contentTypeMime != null) this.contentTypeMime = contentTypeMime;
    if (remoteUrl != null && remoteUrl.trim().isNotEmpty) {
      this.remoteUrl = remoteUrl;
    }
    updatedAt = DateTime.now();
  }

  HttpStreamCacheDownloadProgressSnapshot snapshot() {
    return HttpStreamCacheDownloadProgressSnapshot(
      id: id,
      key: key,
      kind: kind,
      remoteUrl: remoteUrl,
      startByte: startByte,
      bytesWritten: bytesWritten,
      requestedBytes: requestedBytes,
      totalBytes: totalBytes,
      contentTypeMime: contentTypeMime,
      startedAt: startedAt,
      updatedAt: updatedAt,
    );
  }
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

  bool get isActive => _activeCount > 0;
  bool get canRemove =>
      _activeCount <= 0 && (_progress == null || _progress!.isCompleted);

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

class _HttpStreamProxyInFlightCacheWrite {
  _HttpStreamProxyInFlightCacheWrite({
    required this.startByte,
    required this.plannedEndByteExclusive,
  });

  final int startByte;
  final int? plannedEndByteExclusive;
  final Completer<void> _completion = Completer<void>();
  DateTime _updatedAt = DateTime.now();

  bool get canRemove => _completion.isCompleted;

  bool isStale(Duration ttl) => DateTime.now().difference(_updatedAt) > ttl;

  bool mightCover(int byteOffset) {
    if (byteOffset < startByte) return false;
    final endExclusive = plannedEndByteExclusive;
    if (endExclusive == null) return true;
    return byteOffset < endExclusive;
  }

  Future<void> waitForCompletion() {
    _updatedAt = DateTime.now();
    return _completion.future;
  }

  void finish() {
    _updatedAt = DateTime.now();
    if (!_completion.isCompleted) {
      _completion.complete();
    }
  }
}

class _HttpStreamProxyDownloadCancellation {
  final Completer<void> _cancelled = Completer<void>();

  bool get isCancelled => _cancelled.isCompleted;
  Future<void> get cancelled => _cancelled.future;

  void cancel() {
    if (!_cancelled.isCompleted) {
      _cancelled.complete();
    }
  }
}

class _HttpStreamProxyRemoteReadCancelled {
  const _HttpStreamProxyRemoteReadCancelled();
}

class _HttpStreamProxyDownloadCancelledException implements Exception {
  const _HttpStreamProxyDownloadCancelledException();
}

class _HttpStreamProxyClientDisconnectedException implements Exception {
  const _HttpStreamProxyClientDisconnectedException();
}

class _OpenedRemote {
  _OpenedRemote({
    required this.response,
    this.ownedClient,
    Completer<void>? abort,
  }) : _abort = abort;

  final http.StreamedResponse response;
  final http.Client? ownedClient;
  final Completer<void>? _abort;

  Future<void> close() async {
    final abort = _abort;
    if (abort != null && !abort.isCompleted) {
      abort.complete();
    }
    try {
      await response.stream.listen(null).cancel();
    } catch (_) {}
    try {
      ownedClient?.close();
    } catch (_) {}
  }
}

class _HttpStreamProxyCachedCoverage {
  const _HttpStreamProxyCachedCoverage({
    required this.startByte,
    required this.segments,
    required this.lengthBytes,
    required this.contentTypeMime,
    required this.totalBytes,
    required this.acceptRanges,
  });

  final int startByte;
  final List<_HttpStreamProxyCachedCoverageSegment> segments;
  final int lengthBytes;
  final String? contentTypeMime;
  final int? totalBytes;
  final bool acceptRanges;
}

class _HttpStreamProxyCachedCoverageSegment {
  const _HttpStreamProxyCachedCoverageSegment({
    required this.range,
    required this.readOffset,
  });

  final _HttpStreamProxyCachedRange range;
  final int readOffset;

  int get availableBytes => range.availableBytesFromOffset(readOffset);
}

class _HttpStreamProxyHeadMetadata {
  const _HttpStreamProxyHeadMetadata({
    required this.statusCode,
    required this.contentTypeMime,
    required this.totalBytes,
    required this.acceptRanges,
  });

  final int statusCode;
  final String? contentTypeMime;
  final int totalBytes;
  final bool acceptRanges;
}

class _CachedServeResult {
  const _CachedServeResult.notServed({
    this.reason = '',
  })  : served = false,
        statusCode = 0,
        cachedBytes = 0,
        remoteBytes = 0;

  const _CachedServeResult.served({
    required this.statusCode,
    required this.cachedBytes,
    required this.remoteBytes,
    required this.reason,
  }) : served = true;

  final bool served;
  final int statusCode;
  final int cachedBytes;
  final int remoteBytes;
  final String reason;
}

class _RemoteRelayResult {
  const _RemoteRelayResult({
    required this.bytesRelayed,
    required this.cached,
    required this.reason,
  });

  final int bytesRelayed;
  final bool cached;
  final String reason;
}

class _RemoteCacheResult {
  const _RemoteCacheResult({
    required this.bytesRelayed,
    required this.cached,
  });

  final int bytesRelayed;
  final bool cached;
}

class _ProxyRequestTrace {
  _ProxyRequestTrace({
    required this.method,
    required this.rangeHeader,
  });

  final String method;
  final String rangeHeader;
  String remoteUrl = '';
  String requestUrl = '';
  String requestHeadersSummary = '-';
  bool firstPlaybackRequest = false;
  bool waitedWarmup = false;
  bool waitedCacheFill = false;
  String cacheStatus = '';
  String reuseOutcome = '';
  String reason = '';
  String missReason = '-';
  int cachedBytes = 0;
  int remoteBytes = 0;
  int statusCode = 0;

  _HttpStreamProxyDiagnosticEntry build() {
    return _HttpStreamProxyDiagnosticEntry(
      timestamp: DateTime.now(),
      method: method,
      rangeHeader: rangeHeader,
      remoteUrl: remoteUrl,
      requestUrl: requestUrl,
      requestHeadersSummary:
          requestHeadersSummary.trim().isEmpty ? '-' : requestHeadersSummary,
      firstPlaybackRequest: firstPlaybackRequest,
      waitedWarmup: waitedWarmup,
      waitedCacheFill: waitedCacheFill,
      cacheStatus: cacheStatus.isEmpty ? 'unknown' : cacheStatus,
      reuseOutcome: reuseOutcome.trim().isEmpty ? 'unknown' : reuseOutcome,
      reason: reason.isEmpty ? '-' : reason,
      missReason: missReason.trim().isEmpty ? '-' : missReason,
      cachedBytes: cachedBytes,
      remoteBytes: remoteBytes,
      statusCode: statusCode,
    );
  }
}

class _HttpStreamProxyDiagnosticEntry {
  const _HttpStreamProxyDiagnosticEntry({
    required this.timestamp,
    required this.method,
    required this.rangeHeader,
    required this.remoteUrl,
    required this.requestUrl,
    required this.requestHeadersSummary,
    required this.firstPlaybackRequest,
    required this.waitedWarmup,
    required this.waitedCacheFill,
    required this.cacheStatus,
    required this.reuseOutcome,
    required this.reason,
    required this.missReason,
    required this.cachedBytes,
    required this.remoteBytes,
    required this.statusCode,
  });

  final DateTime timestamp;
  final String method;
  final String rangeHeader;
  final String remoteUrl;
  final String requestUrl;
  final String requestHeadersSummary;
  final bool firstPlaybackRequest;
  final bool waitedWarmup;
  final bool waitedCacheFill;
  final String cacheStatus;
  final String reuseOutcome;
  final String reason;
  final String missReason;
  final int cachedBytes;
  final int remoteBytes;
  final int statusCode;
}
