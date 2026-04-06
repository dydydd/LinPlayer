import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:lin_player_prefs/lin_player_prefs.dart';
import 'package:lin_player_server_adapters/lin_player_server_adapters.dart';
import 'package:lin_player_server_api/services/http_stream_proxy.dart';

import '../source/playback_cache_key.dart';
import '../source/playback_source_builder.dart';
import '../source/resolved_playback_source.dart';
import 'preload_request.dart';
import 'stream_cache_download_service.dart';

enum StreamPreloadStatus {
  skippedDisabled,
  skippedAlreadyDone,
  cancelled,
  success,
  failed,
  failedDisabled,
}

@immutable
class StreamPreloadResult {
  const StreamPreloadResult(this.status, {this.error});

  final StreamPreloadStatus status;
  final Object? error;

  bool get disabledNow => status == StreamPreloadStatus.failedDisabled;
}

@immutable
class StreamPreloadDiagnosticEntry {
  const StreamPreloadDiagnosticEntry({
    required this.timestamp,
    required this.triggerSource,
    required this.ownerKey,
    required this.scopeKey,
    required this.itemId,
    required this.mediaSourceId,
    required this.startPosition,
    required this.mediaType,
    required this.isExternal,
    required this.usesProxy,
    required this.url,
    required this.status,
    this.error,
  });

  final DateTime timestamp;
  final String triggerSource;
  final String ownerKey;
  final String scopeKey;
  final String itemId;
  final String mediaSourceId;
  final Duration startPosition;
  final ResolvedPlaybackMediaType mediaType;
  final bool isExternal;
  final bool usesProxy;
  final String url;
  final StreamPreloadStatus status;
  final Object? error;
}

class StreamPreloadService {
  StreamPreloadService._();

  static final StreamPreloadService instance = StreamPreloadService._();

  static const String preloadUserAgent = 'preload-linplayer';
  static const Duration preloadDuration = PreloadRequest.defaultPreloadDuration;
  static const int maxAttempts = 3;

  static const int _minBytes = 256 * 1024;
  static const int _maxBytes = 24 * 1024 * 1024;
  static const int _maxLoopbackSeedBytes = 16 * 1024 * 1024;
  static const Duration _failureWindow = Duration(minutes: 2);
  static const Duration _recoverableDisableDuration = Duration(minutes: 2);
  static const Duration _nonRecoverableDisableDuration = Duration(minutes: 10);
  static const int _recoverableFailuresBeforeOpen = 2;
  static const int _nonRecoverableFailuresBeforeOpen = 1;

  bool get permanentlyDisabled {
    final now = _clock();
    _pruneCircuitStates(now: now);
    return _circuitStates.values.any((state) => state.isOpen(now));
  }

  final Set<String> _doneKeys = <String>{};
  final Map<String, _InFlightPreloadTask> _inFlight =
      <String, _InFlightPreloadTask>{};
  final List<StreamPreloadDiagnosticEntry> _recentEntries =
      <StreamPreloadDiagnosticEntry>[];
  final Map<String, _PreloadCircuitState> _circuitStates =
      <String, _PreloadCircuitState>{};
  int _activeCurrentPreloads = 0;
  Completer<void>? _currentPreloadsDrained;

  static const int _maxRecentEntries = 48;
  DateTime Function() _clock = DateTime.now;

  String _keyFor(PreloadRequest request) {
    final source = request.resolvedSource;
    final startSec = request.startPosition <= Duration.zero
        ? 0
        : request.startPosition.inSeconds;
    final cacheFingerprint = _cacheKeyForRequest(request)?.fingerprint ??
        sha1.convert(utf8.encode(source.url.trim())).toString();
    final requestFingerprint = _fingerprintText(request.dedupeFingerprint);
    return [
      source.itemId.trim(),
      source.mediaSourceId.trim(),
      '$startSec',
      requestFingerprint,
      cacheFingerprint,
    ].join('|');
  }

  String _fingerprintText(String? raw) {
    final value = (raw ?? '').trim();
    if (value.isEmpty) return '';
    return sha1.convert(utf8.encode(value)).toString();
  }

  String? _effectiveProxyUrlFor(PreloadRequest request) {
    final requestProxy = (request.httpProxyUrl ?? '').trim();
    if (requestProxy.isNotEmpty) return requestProxy;
    final sourceProxy = (request.resolvedSource.proxyUrl ?? '').trim();
    if (sourceProxy.isNotEmpty) return sourceProxy;
    return null;
  }

  StreamCacheDownloadRequest _cacheDownloadRequestForRequest(
    PreloadRequest request,
  ) {
    return StreamCacheDownloadRequest(
      resolvedSource: request.resolvedSource,
      proxyUrl: _effectiveProxyUrlFor(request),
    );
  }

  HttpStreamCacheKey? _cacheKeyForRequest(PreloadRequest request) {
    return _cacheDownloadRequestForRequest(request).cacheKey;
  }

  String _scopeKeyFor(PreloadRequest request) {
    final source = request.resolvedSource;
    final uri = Uri.tryParse(source.url);
    final scope = _originScopeForUri(uri, raw: source.url);
    final proxyFingerprint = _fingerprintText(_effectiveProxyUrlFor(request));
    final kind = source.isExternal ? 'external' : 'server';
    return '$kind|$scope|proxy=$proxyFingerprint';
  }

  String _originScopeForUri(Uri? uri, {required String raw}) {
    if (uri == null) {
      return 'inline:${_fingerprintText(raw)}';
    }
    final scheme = uri.scheme.trim().toLowerCase();
    if (scheme.isEmpty) {
      return 'inline:${_fingerprintText(raw)}';
    }
    if (uri.host.trim().isNotEmpty) {
      final port = uri.hasPort ? uri.port : (scheme == 'https' ? 443 : 80);
      return '$scheme://${uri.host.toLowerCase()}:$port';
    }
    final path = uri.path.trim();
    if (path.isNotEmpty) return '$scheme:$path';
    return '$scheme:unknown';
  }

  String buildDiagnosticsText({int maxEntries = 20}) {
    final now = _clock();
    _pruneCircuitStates(now: now);
    final openCircuits = _circuitStates.values
        .where((state) => state.isOpen(now))
        .toList(growable: false)
      ..sort((a, b) => a.scopeKey.compareTo(b.scopeKey));
    final buffer = StringBuffer()
      ..writeln('permanentlyDisabled: ${openCircuits.isNotEmpty}')
      ..writeln('activeCircuits: ${openCircuits.length}')
      ..writeln('doneKeys: ${_doneKeys.length}')
      ..writeln('inFlight: ${_inFlight.length}');
    if (openCircuits.isNotEmpty) {
      buffer.writeln('circuits:');
      for (final state in openCircuits.take(6)) {
        final remaining = state.openUntil == null
            ? 0
            : state.openUntil!.difference(now).inSeconds.clamp(0, 1 << 30);
        final reason = state.lastFailure?.category.name ??
            _PreloadFailureCategory.unknown.name;
        buffer.writeln(
          'scope=${state.scopeKey} '
          'failures=${state.consecutiveFailures} '
          'reason=$reason '
          'retryIn=${remaining}s',
        );
      }
    }
    final count = maxEntries < 1 ? 1 : maxEntries;
    final startIndex =
        _recentEntries.length > count ? _recentEntries.length - count : 0;
    if (_recentEntries.isEmpty) {
      buffer.writeln('recent: (empty)');
      return buffer.toString().trim();
    }
    buffer.writeln('recent:');
    for (final entry in _recentEntries.skip(startIndex)) {
      final errorText =
          entry.error == null ? '' : ' error=${_summarizeInline(entry.error)}';
      final ownerText = entry.ownerKey.isEmpty
          ? ''
          : ' owner=${_summarizeInline(entry.ownerKey)}';
      final scopeText = entry.scopeKey.isEmpty
          ? ''
          : ' scope=${_summarizeInline(entry.scopeKey)}';
      buffer.writeln(
        '${entry.timestamp.toIso8601String()} '
        'trigger=${entry.triggerSource} '
        'status=${entry.status.name} '
        '$ownerText'
        '$scopeText '
        'item=${entry.itemId} '
        'mediaSource=${entry.mediaSourceId} '
        'start=${entry.startPosition.inSeconds}s '
        'media=${entry.mediaType.name} '
        'external=${entry.isExternal} '
        'proxy=${entry.usesProxy} '
        'url=${_summarizeUrl(entry.url)}'
        '$errorText',
      );
    }
    return buffer.toString().trim();
  }

  String buildStatusSummaryText() {
    final now = _clock();
    _pruneCircuitStates(now: now);
    final counts = <StreamPreloadStatus, int>{};
    var proxyRequests = 0;
    var externalSources = 0;
    for (final entry in _recentEntries) {
      counts[entry.status] = (counts[entry.status] ?? 0) + 1;
      if (entry.usesProxy) proxyRequests += 1;
      if (entry.isExternal) externalSources += 1;
    }

    final orderedStatuses = StreamPreloadStatus.values
        .where((status) => (counts[status] ?? 0) > 0)
        .map((status) => '${status.name}=${counts[status]}')
        .join(', ');
    final activeCircuits =
        _circuitStates.values.where((state) => state.isOpen(now)).length;
    final activeCacheDownloads =
        StreamCacheDownloadService.instance.currentProgressSnapshots().length;

    final latest = _recentEntries.isEmpty ? null : _recentEntries.last;
    final buffer = StringBuffer()
      ..writeln('observedAttempts: ${_recentEntries.length}')
      ..writeln(
        'statusCounts: ${orderedStatuses.isEmpty ? "(empty)" : orderedStatuses}',
      )
      ..writeln('activeCircuits: $activeCircuits')
      ..writeln('activeCacheDownloads: $activeCacheDownloads')
      ..writeln('proxyAttempts: $proxyRequests')
      ..writeln('externalSourceAttempts: $externalSources');
    if (latest != null) {
      buffer
        ..writeln('latestTrigger: ${latest.triggerSource}')
        ..writeln('latestStatus: ${latest.status.name}')
        ..writeln('latestUrl: ${_summarizeUrl(latest.url)}');
      if (latest.ownerKey.isNotEmpty) {
        buffer.writeln('latestOwner: ${latest.ownerKey}');
      }
      if (latest.scopeKey.isNotEmpty) {
        buffer.writeln('latestScope: ${latest.scopeKey}');
      }
    }
    return buffer.toString().trim();
  }

  Map<String, String> _buildRequestHeaders(Map<String, String> upstream) {
    final headers = <String, String>{...upstream};
    if (!_hasHeader(headers, HttpHeaders.userAgentHeader)) {
      headers['User-Agent'] = preloadUserAgent;
    }
    return headers;
  }

  bool _hasHeader(Map<String, String> headers, String name) {
    final lower = name.toLowerCase();
    for (final key in headers.keys) {
      if (key.toLowerCase() == lower) return true;
    }
    return false;
  }

  void _recordResult({
    required PreloadRequest request,
    required StreamPreloadResult result,
  }) {
    final ownerKey = _normalizeLifecycleKey(request.ownerKey);
    final scopeKey = _normalizeLifecycleKey(request.scopeKey);
    _recentEntries.add(
      StreamPreloadDiagnosticEntry(
        timestamp: _clock(),
        triggerSource: request.triggerSource.trim().isEmpty
            ? 'unknown'
            : request.triggerSource.trim(),
        ownerKey: ownerKey,
        scopeKey: scopeKey,
        itemId: request.resolvedSource.itemId,
        mediaSourceId: request.resolvedSource.mediaSourceId,
        startPosition: request.startPosition,
        mediaType: request.resolvedSource.mediaTypeHint,
        isExternal: request.resolvedSource.isExternal,
        usesProxy: (_effectiveProxyUrlFor(request) ?? '').isNotEmpty,
        url: request.resolvedSource.url,
        status: result.status,
        error: result.error,
      ),
    );
    if (_recentEntries.length > _maxRecentEntries) {
      _recentEntries.removeRange(0, _recentEntries.length - _maxRecentEntries);
    }
  }

  String _summarizeUrl(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return '';
    final uri = Uri.tryParse(value);
    if (uri == null || uri.scheme.isEmpty || uri.host.trim().isEmpty) {
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

  String _summarizeInline(Object? value, {int limit = 180}) {
    final text =
        (value ?? '').toString().replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text.length <= limit) return text;
    return '${text.substring(0, limit - 3)}...';
  }

  String _normalizeLifecycleKey(String? raw) {
    final value = (raw ?? '').trim();
    if (value.isEmpty) return '';
    return value.replaceAll(RegExp(r'\s+'), '_');
  }

  @visibleForTesting
  void debugResetForTest({DateTime Function()? nowProvider}) {
    _doneKeys.clear();
    _inFlight.clear();
    _recentEntries.clear();
    _circuitStates.clear();
    _activeCurrentPreloads = 0;
    _currentPreloadsDrained = null;
    _clock = nowProvider ?? DateTime.now;
  }

  void cancelOwner(String ownerKey) {
    final normalizedOwner = _normalizeLifecycleKey(ownerKey);
    if (normalizedOwner.isEmpty) return;
    for (final task in _inFlight.values.toList(growable: false)) {
      task.detachOwner(normalizedOwner);
    }
  }

  void cancelOwnerScope({
    required String ownerKey,
    required String scopeKey,
  }) {
    final normalizedOwner = _normalizeLifecycleKey(ownerKey);
    final normalizedScope = _normalizeLifecycleKey(scopeKey);
    if (normalizedOwner.isEmpty || normalizedScope.isEmpty) return;
    for (final task in _inFlight.values.toList(growable: false)) {
      task.detachOwnerScope(
        ownerKey: normalizedOwner,
        scopeKey: normalizedScope,
      );
    }
  }

  Future<StreamPreloadResult> preloadFirst3Seconds({
    required MediaServerAdapter adapter,
    required ServerAuthSession auth,
    required String itemId,
    Duration startPosition = Duration.zero,
    bool exoPlayer = false,
    String? selectedMediaSourceId,
    int? audioStreamIndex,
    int? subtitleStreamIndex,
    VideoVersionPreference preferredVideoVersion =
        VideoVersionPreference.defaultVersion,
    String? httpProxyUrl,
  }) async {
    try {
      final buildResult = await PlaybackSourceBuilder.build(
        PlaybackSourceBuildRequest(
          adapter: adapter,
          auth: auth,
          itemId: itemId,
          playerCore: exoPlayer
              ? PlaybackSourcePlayerCoreKind.exo
              : PlaybackSourcePlayerCoreKind.mpv,
          selectedMediaSourceId: selectedMediaSourceId,
          audioStreamIndex: audioStreamIndex,
          subtitleStreamIndex: subtitleStreamIndex,
          preferredVideoVersion: preferredVideoVersion,
        ),
      );
      return preloadResolvedSource(
        PreloadRequest(
          resolvedSource: buildResult.resolvedSource,
          triggerSource: 'legacy',
          startPosition: startPosition,
          httpProxyUrl: httpProxyUrl,
        ),
      );
    } catch (error) {
      final result = StreamPreloadResult(
        StreamPreloadStatus.failed,
        error: error,
      );
      _recordResult(
        request: PreloadRequest(
          resolvedSource: ResolvedPlaybackSource(
            itemId: itemId,
            playSessionId: '',
            mediaSourceId: selectedMediaSourceId ?? '',
            url: auth.baseUrl,
            httpHeaders: const <String, String>{},
            isExternal: false,
            mediaTypeHint: ResolvedPlaybackMediaType.unknown,
            fromStrm: false,
            redirectChain: const <String>[],
          ),
          triggerSource: 'legacy',
          startPosition: startPosition,
          httpProxyUrl: httpProxyUrl,
        ),
        result: result,
      );
      return result;
    }
  }

  Future<StreamPreloadResult> preloadResolvedSource(
      PreloadRequest request) async {
    final safeStartPosition = request.startPosition < Duration.zero
        ? Duration.zero
        : request.startPosition;
    final effectiveProxyUrl = _effectiveProxyUrlFor(request);
    final normalizedOwnerKey = _normalizeLifecycleKey(request.ownerKey);
    final normalizedScopeKey = _normalizeLifecycleKey(request.scopeKey);
    final normalizedRequest = PreloadRequest(
      resolvedSource: request.resolvedSource.copyWith(
        proxyUrl: effectiveProxyUrl,
      ),
      triggerSource: request.triggerSource,
      startPosition: safeStartPosition,
      preloadDuration: request.preloadDuration <= Duration.zero
          ? PreloadRequest.defaultPreloadDuration
          : request.preloadDuration,
      dedupeFingerprint: request.dedupeFingerprint,
      httpProxyUrl: effectiveProxyUrl,
      ownerKey: normalizedOwnerKey,
      scopeKey: normalizedScopeKey,
    );
    final scopeKey = _scopeKeyFor(normalizedRequest);
    final now = _clock();
    _pruneCircuitStates(now: now);
    final key = _keyFor(normalizedRequest);
    if (_doneKeys.contains(key)) {
      final result =
          const StreamPreloadResult(StreamPreloadStatus.skippedAlreadyDone);
      _recordResult(request: normalizedRequest, result: result);
      return result;
    }
    final openCircuit = _circuitStates[scopeKey];
    if (openCircuit != null && openCircuit.isOpen(now)) {
      final result = StreamPreloadResult(
        StreamPreloadStatus.skippedDisabled,
        error: _PreloadFailureInfo(
          category: openCircuit.lastFailure?.category ??
              _PreloadFailureCategory.unknown,
          statusCode: openCircuit.lastFailure?.statusCode,
          url: normalizedRequest.resolvedSource.url,
          message:
              'circuit-open:${openCircuit.openUntil!.difference(now).inSeconds}s',
        ),
      );
      _recordResult(request: normalizedRequest, result: result);
      return result;
    }

    final existingTask = _inFlight[key];
    if (existingTask != null && !existingTask.cancellation.isCancelled) {
      existingTask.attach(normalizedRequest);
      return existingTask.future;
    }

    final priority = _priorityFor(normalizedRequest);
    final cancellation = _PreloadCancellation();
    final task = _InFlightPreloadTask(cancellation: cancellation)
      ..attach(normalizedRequest);

    if (priority == _PreloadPriority.next) {
      await _waitForCurrentPreloadsToDrain(cancellation);
      if (_doneKeys.contains(key)) {
        final result =
            const StreamPreloadResult(StreamPreloadStatus.skippedAlreadyDone);
        _recordResult(request: normalizedRequest, result: result);
        return result;
      }
      final refreshedOpenCircuit = _circuitStates[scopeKey];
      if (refreshedOpenCircuit != null && refreshedOpenCircuit.isOpen(_clock())) {
        final result = StreamPreloadResult(
          StreamPreloadStatus.skippedDisabled,
          error: _PreloadFailureInfo(
            category: refreshedOpenCircuit.lastFailure?.category ??
                _PreloadFailureCategory.unknown,
            statusCode: refreshedOpenCircuit.lastFailure?.statusCode,
            url: normalizedRequest.resolvedSource.url,
            message:
                'circuit-open:${refreshedOpenCircuit.openUntil!.difference(_clock()).inSeconds}s',
          ),
        );
        _recordResult(request: normalizedRequest, result: result);
        return result;
      }
      final refreshedTask = _inFlight[key];
      if (refreshedTask != null && !refreshedTask.cancellation.isCancelled) {
        refreshedTask.attach(normalizedRequest);
        return refreshedTask.future;
      }
    }

    if (priority == _PreloadPriority.current) {
      _beginCurrentPreload();
    }

    final run = () async {
      _PreloadFailureInfo? lastFailure;
      final source = normalizedRequest.resolvedSource;
      final cacheDownloadRequest =
          _cacheDownloadRequestForRequest(normalizedRequest);
      StreamCacheDownloadService.instance.beginWarmup(cacheDownloadRequest);
      try {
        for (var attempt = 0; attempt < maxAttempts; attempt++) {
          _throwIfCancelled(
            cancellation,
            url: source.url,
            message: 'owner-cancelled',
          );
          final headers = _buildRequestHeaders(source.httpHeaders);
          final bytesToFetch = _estimateBytesToFetch(
            source.bitrate,
            preloadDuration: normalizedRequest.preloadDuration,
          );
          final outcome = await _prefetch(
            url: source.url,
            mediaTypeHint: source.mediaTypeHint,
            supportsByteRange: source.supportsByteRange,
            headers: headers,
            cacheHeaders: source.httpHeaders,
            bytesToFetch: bytesToFetch,
            startPosition: safeStartPosition,
            preloadDuration: normalizedRequest.preloadDuration,
            bitrateBitsPerSecond: source.bitrate,
            sizeBytes: source.sizeBytes,
            httpProxyUrl: normalizedRequest.httpProxyUrl,
            cacheDownloadRequest: cacheDownloadRequest,
            cancellation: cancellation,
          );
          if (outcome.success) {
            _doneKeys.add(key);
            _circuitStates.remove(scopeKey);
            final result =
                const StreamPreloadResult(StreamPreloadStatus.success);
            _recordResult(request: normalizedRequest, result: result);
            return result;
          }
          lastFailure = outcome.failure;
          if (lastFailure?.category == _PreloadFailureCategory.cancelled) {
            final result = StreamPreloadResult(
              StreamPreloadStatus.cancelled,
              error: lastFailure,
            );
            _recordResult(request: normalizedRequest, result: result);
            return result;
          }

          if (attempt < maxAttempts - 1 &&
              lastFailure != null &&
              lastFailure.isRecoverable) {
            await Future<void>.delayed(
              Duration(milliseconds: attempt == 0 ? 180 : 320),
            );
          }
        }

        final failure = lastFailure ??
            _PreloadFailureInfo(
              category: _PreloadFailureCategory.unknown,
              url: normalizedRequest.resolvedSource.url,
              message: 'prefetch-failed',
            );
        if (failure.category == _PreloadFailureCategory.cancelled) {
          final result = StreamPreloadResult(
            StreamPreloadStatus.cancelled,
            error: failure,
          );
          _recordResult(request: normalizedRequest, result: result);
          return result;
        }
        final disabledNow = _recordFailure(scopeKey, failure);
        final result = StreamPreloadResult(
          disabledNow
              ? StreamPreloadStatus.failedDisabled
              : StreamPreloadStatus.failed,
          error: failure,
        );
        await StreamCacheDownloadService.instance.markFailure(
          cacheDownloadRequest,
          error: failure,
        );
        _recordResult(request: normalizedRequest, result: result);
        return result;
      } on _PreloadCancelledException catch (error) {
        final failure = _classifyException(error, url: source.url);
        final result = StreamPreloadResult(
          StreamPreloadStatus.cancelled,
          error: failure,
        );
        _recordResult(request: normalizedRequest, result: result);
        return result;
      } finally {
        StreamCacheDownloadService.instance.endWarmup(cacheDownloadRequest);
        if (priority == _PreloadPriority.current) {
          _endCurrentPreload();
        }
      }
    }();

    task.future = run;
    _inFlight[key] = task;
    try {
      return await task.future;
    } finally {
      if (identical(_inFlight[key], task)) {
        _inFlight.remove(key);
      }
    }
  }

  int _estimateBytesToFetch(
    int? bitrateBitsPerSecond, {
    required Duration preloadDuration,
  }) {
    final bps = bitrateBitsPerSecond ?? 0;
    if (bps <= 0) return _minBytes;
    final bytesPerSecond = bps / 8.0;
    final seconds = preloadDuration.inMilliseconds / 1000.0;
    final estimated = (bytesPerSecond * seconds).round();
    return estimated.clamp(_minBytes, _maxBytes);
  }

  _PreloadPriority _priorityFor(PreloadRequest request) {
    final scope = (request.scopeKey ?? '').trim().toLowerCase();
    final fingerprint = (request.dedupeFingerprint ?? '').trim().toLowerCase();
    if (scope.contains('current') || fingerprint == 'target:current') {
      return _PreloadPriority.current;
    }
    if (scope.contains('next') || fingerprint == 'target:next') {
      return _PreloadPriority.next;
    }
    return _PreloadPriority.normal;
  }

  void _beginCurrentPreload() {
    if (_activeCurrentPreloads == 0) {
      _currentPreloadsDrained = Completer<void>();
    }
    _activeCurrentPreloads += 1;
  }

  void _endCurrentPreload() {
    if (_activeCurrentPreloads <= 0) return;
    _activeCurrentPreloads -= 1;
    if (_activeCurrentPreloads == 0) {
      final drained = _currentPreloadsDrained;
      _currentPreloadsDrained = null;
      if (drained != null && !drained.isCompleted) {
        drained.complete();
      }
    }
  }

  Future<void> _waitForCurrentPreloadsToDrain(
    _PreloadCancellation cancellation,
  ) async {
    while (_activeCurrentPreloads > 0) {
      final waiter = _currentPreloadsDrained?.future;
      if (waiter == null) return;
      await Future.any<void>(<Future<void>>[
        waiter,
        cancellation.cancelled,
      ]);
      _throwIfCancelled(cancellation, url: 'preload://scheduler');
    }
  }

  bool _recordFailure(String scopeKey, _PreloadFailureInfo failure) {
    final now = _clock();
    final state = _circuitStates.putIfAbsent(
      scopeKey,
      () => _PreloadCircuitState(scopeKey: scopeKey),
    );
    if (state.lastFailureAt == null ||
        now.difference(state.lastFailureAt!) > _failureWindow ||
        state.lastFailure?.category != failure.category) {
      state.consecutiveFailures = 0;
    }
    state.consecutiveFailures += 1;
    state.lastFailureAt = now;
    state.lastFailure = failure;

    final threshold = failure.isRecoverable
        ? _recoverableFailuresBeforeOpen
        : _nonRecoverableFailuresBeforeOpen;
    if (state.consecutiveFailures < threshold) return false;

    state.openUntil = now.add(
      failure.isRecoverable
          ? _recoverableDisableDuration
          : _nonRecoverableDisableDuration,
    );
    return true;
  }

  void _pruneCircuitStates({required DateTime now}) {
    final staleKeys = <String>[];
    for (final entry in _circuitStates.entries) {
      final state = entry.value;
      if (state.isOpen(now)) continue;
      if (state.openUntil != null && !state.isOpen(now)) {
        staleKeys.add(entry.key);
        continue;
      }
      final lastFailureAt = state.lastFailureAt;
      if (lastFailureAt == null ||
          now.difference(lastFailureAt) > _failureWindow) {
        staleKeys.add(entry.key);
      }
    }
    for (final key in staleKeys) {
      _circuitStates.remove(key);
    }
  }

  Future<_PreloadAttemptResult> _prefetch({
    required String url,
    required ResolvedPlaybackMediaType mediaTypeHint,
    required bool? supportsByteRange,
    required Map<String, String> headers,
    required Map<String, String> cacheHeaders,
    required int bytesToFetch,
    required Duration startPosition,
    required Duration preloadDuration,
    required int? bitrateBitsPerSecond,
    required int? sizeBytes,
    String? httpProxyUrl,
    required StreamCacheDownloadRequest cacheDownloadRequest,
    required _PreloadCancellation cancellation,
  }) async {
    _throwIfCancelled(cancellation, url: url);
    if (kIsWeb) {
      return _PreloadAttemptResult.failure(
        _PreloadFailureInfo(
          category: _PreloadFailureCategory.unsupported,
          url: url,
          message: 'web-not-supported',
        ),
      );
    }
    final uri = Uri.tryParse(url);
    if (uri == null) {
      return _PreloadAttemptResult.failure(
        _PreloadFailureInfo(
          category: _PreloadFailureCategory.unsupported,
          url: url,
          message: 'invalid-url',
        ),
      );
    }

    final client = LinHttpClientFactory.createHttpClient(
      _overrideConfig(httpProxyUrl),
    );
    cancellation.addListener(() {
      try {
        client.close(force: true);
      } catch (_) {}
    });
    try {
      return await _prefetchUri(
        client: client,
        uri: uri,
        mediaTypeHint: mediaTypeHint,
        supportsByteRange: supportsByteRange,
        headers: headers,
        cacheHeaders: cacheHeaders,
        bytesToFetch: bytesToFetch,
        startPosition: startPosition,
        preloadDuration: preloadDuration,
        bitrateBitsPerSecond: bitrateBitsPerSecond,
        sizeBytes: sizeBytes,
        cacheDownloadRequest: cacheDownloadRequest,
        cancellation: cancellation,
      );
    } catch (error) {
      return _PreloadAttemptResult.failure(
        _classifyException(error, url: url),
      );
    } finally {
      try {
        client.close(force: true);
      } catch (_) {}
    }
  }

  LinHttpClientConfig _overrideConfig(String? httpProxyUrl) {
    final base = LinHttpClientFactory.config;
    final proxy = (httpProxyUrl ?? '').trim();
    final proxyUri = proxy.isEmpty ? null : Uri.tryParse(proxy);
    final hasProxy = proxyUri != null &&
        proxyUri.host.trim().isNotEmpty &&
        proxyUri.port > 0 &&
        proxyUri.port <= 65535;

    LinProxyResolver? proxyResolver;
    if (hasProxy) {
      final host = proxyUri.host;
      final port = proxyUri.port;
      proxyResolver = (_) => 'PROXY $host:$port';
    }

    return base.copyWith(
      userAgent: preloadUserAgent,
      connectionTimeout: const Duration(seconds: 8),
      idleTimeout: const Duration(seconds: 8),
      maxConnectionsPerHost: 4,
      proxyResolver: proxyResolver,
    );
  }

  Future<_PreloadAttemptResult> _prefetchUri({
    required HttpClient client,
    required Uri uri,
    required ResolvedPlaybackMediaType mediaTypeHint,
    required bool? supportsByteRange,
    required Map<String, String> headers,
    required Map<String, String> cacheHeaders,
    required int bytesToFetch,
    required Duration startPosition,
    required Duration preloadDuration,
    required int? bitrateBitsPerSecond,
    required int? sizeBytes,
    required StreamCacheDownloadRequest cacheDownloadRequest,
    required _PreloadCancellation cancellation,
  }) async {
    _throwIfCancelled(cancellation, url: uri.toString());
    if (mediaTypeHint == ResolvedPlaybackMediaType.file) {
      return _prefetchDirectFile(
        uri: uri,
        bytesToFetch: bytesToFetch,
        startPosition: startPosition,
        bitrateBitsPerSecond: bitrateBitsPerSecond,
        sizeBytes: sizeBytes,
        supportsByteRange: supportsByteRange,
        cacheDownloadRequest: cacheDownloadRequest,
        cancellation: cancellation,
      );
    }

    final useOffset = startPosition > Duration.zero;
    final sniffBytes = useOffset ? 512 * 1024 : bytesToFetch;
    final firstCaptureLimit = useOffset
        ? sniffBytes
        : sniffBytes.clamp(0, _maxLoopbackSeedBytes).toInt();
    final first = await _get(
      client: client,
      uri: uri,
      headers: headers,
      rangeStartBytes: 0,
      rangeBytes: sniffBytes,
      captureLimitBytes: firstCaptureLimit,
      cancellation: cancellation,
    );
    if (!first.ok) {
      return _failureFromGetResult(
        first,
        fallbackUri: uri,
        message: 'initial-fetch-failed',
      );
    }

    final playlistText = _asHlsPlaylistText(first);
    if (playlistText == null) {
      _throwIfCancelled(cancellation, url: first.effectiveUri.toString());
      if (!useOffset) {
        await _seedLoopbackProxyCache(
          startByte: 0,
          result: first,
          cacheDownloadRequest: cacheDownloadRequest,
        );
        return first.bytesRead > 0
            ? const _PreloadAttemptResult.success()
            : _PreloadAttemptResult.failure(
                _PreloadFailureInfo(
                  category: _PreloadFailureCategory.emptyResponse,
                  url: first.effectiveUri.toString(),
                  message: 'empty-initial-response',
                ),
              );
      }

      final startByte = _estimateRangeStartBytes(
        startPosition: startPosition,
        bytesToFetch: bytesToFetch,
        bitrateBitsPerSecond: bitrateBitsPerSecond,
        sizeBytes: sizeBytes,
      );
      if (startByte <= 0) {
        await _seedLoopbackProxyCache(
          startByte: 0,
          result: first,
          cacheDownloadRequest: cacheDownloadRequest,
        );
        return first.bytesRead > 0
            ? const _PreloadAttemptResult.success()
            : _PreloadAttemptResult.failure(
                _PreloadFailureInfo(
                  category: _PreloadFailureCategory.emptyResponse,
                  url: first.effectiveUri.toString(),
                  message: 'empty-sniff-response',
                ),
              );
      }

      final second = await _get(
        client: client,
        uri: first.effectiveUri,
        headers: headers,
        rangeStartBytes: startByte,
        rangeBytes: bytesToFetch,
        captureLimitBytes: bytesToFetch.clamp(0, _maxLoopbackSeedBytes).toInt(),
        cancellation: cancellation,
      );
      if (!second.ok || second.bytesRead <= 0) {
        return _failureFromGetResult(
          second,
          fallbackUri: first.effectiveUri,
          message: second.bytesRead <= 0
              ? 'empty-offset-response'
              : 'offset-fetch-failed',
        );
      }
      await _seedLoopbackProxyCache(
        startByte: 0,
        result: first,
        cacheDownloadRequest: cacheDownloadRequest,
      );
      await _seedLoopbackProxyCache(
        startByte: startByte,
        result: second,
        cacheDownloadRequest: cacheDownloadRequest,
      );
      return const _PreloadAttemptResult.success();
    }

    final playlistUri = first.effectiveUri;
    return _prefetchHls(
      client: client,
      playlistUri: playlistUri,
      playlistText: playlistText,
      headers: headers,
      startPosition: startPosition,
      preloadDuration: preloadDuration,
      cacheDownloadRequest: cacheDownloadRequest,
      cancellation: cancellation,
    );
  }

  Future<_PreloadAttemptResult> _prefetchDirectFile({
    required Uri uri,
    required int bytesToFetch,
    required Duration startPosition,
    required int? bitrateBitsPerSecond,
    required int? sizeBytes,
    required bool? supportsByteRange,
    required StreamCacheDownloadRequest cacheDownloadRequest,
    required _PreloadCancellation cancellation,
  }) async {
    final prefixBytes =
        startPosition > Duration.zero ? 512 * 1024 : bytesToFetch;
    try {
      _throwIfCancelled(cancellation, url: uri.toString());
      await StreamCacheDownloadService.instance.warmRangeToCache(
        request: cacheDownloadRequest.withRemoteUri(uri),
        startByte: 0,
        lengthBytes: prefixBytes,
      );
      _throwIfCancelled(cancellation, url: uri.toString());
    } catch (error) {
      return _PreloadAttemptResult.failure(
        _classifyException(error, url: uri.toString()),
      );
    }

    if (startPosition <= Duration.zero || supportsByteRange == false) {
      return const _PreloadAttemptResult.success();
    }

    _throwIfCancelled(cancellation, url: uri.toString());
    final startByte = _estimateRangeStartBytes(
      startPosition: startPosition,
      bytesToFetch: bytesToFetch,
      bitrateBitsPerSecond: bitrateBitsPerSecond,
      sizeBytes: sizeBytes,
    );
    if (startByte <= 0) {
      return const _PreloadAttemptResult.success();
    }

    try {
      _throwIfCancelled(cancellation, url: uri.toString());
      await StreamCacheDownloadService.instance.warmRangeToCache(
        request: cacheDownloadRequest.withRemoteUri(uri),
        startByte: startByte,
        lengthBytes: bytesToFetch,
      );
      _throwIfCancelled(cancellation, url: uri.toString());
      return const _PreloadAttemptResult.success();
    } catch (error) {
      return _PreloadAttemptResult.failure(
        _classifyException(error, url: uri.toString()),
      );
    }
  }

  int _estimateRangeStartBytes({
    required Duration startPosition,
    required int bytesToFetch,
    required int? bitrateBitsPerSecond,
    required int? sizeBytes,
  }) {
    if (startPosition <= Duration.zero) return 0;
    final bps = bitrateBitsPerSecond ?? 0;
    if (bps <= 0) return 0;

    final seconds = startPosition.inMilliseconds / 1000.0;
    if (seconds <= 0) return 0;

    final bytesPerSecond = bps / 8.0;
    var start = (bytesPerSecond * seconds).round();
    if (start < 0) start = 0;

    final size = sizeBytes ?? 0;
    if (size > 0 && bytesToFetch > 0) {
      final maxStart = (size - bytesToFetch).clamp(0, size);
      if (start > maxStart) start = maxStart;
    }

    return start;
  }

  bool _shouldSeedLoopbackCache(Uri uri) {
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') return false;
    final host = uri.host.trim().toLowerCase();
    if (host.isEmpty) return false;
    if (host == 'localhost' || host == '127.0.0.1' || host == '::1') {
      return false;
    }
    return true;
  }

  Future<void> _seedLoopbackProxyCache({
    required int startByte,
    required StreamPreloadGetResult result,
    required StreamCacheDownloadRequest cacheDownloadRequest,
  }) async {
    if (kIsWeb) return;
    final seedUri = result.effectiveUri;
    if (!_shouldSeedLoopbackCache(seedUri)) return;
    if (result.capturedBytes.isEmpty) return;

    try {
      await StreamCacheDownloadService.instance.seedCache(
        // Keep the cache key bound to the original playback semantics, but let
        // the proxy reuse the redirect-final transport URL for later cache
        // fills so playback does not need to repeat the redirect hop.
        request: cacheDownloadRequest.withRemoteUri(seedUri),
        startByte: startByte,
        bytes: result.capturedBytes,
        contentTypeMime: result.contentTypeMime,
        totalBytes: result.totalBytes,
        acceptRanges: result.acceptsByteRanges,
      );
    } catch (_) {
      // Best-effort warmup only.
    }
  }

  Future<_PreloadAttemptResult> _prefetchHls({
    required HttpClient client,
    required Uri playlistUri,
    required String playlistText,
    required Map<String, String> headers,
    required Duration startPosition,
    required Duration preloadDuration,
    required StreamCacheDownloadRequest cacheDownloadRequest,
    required _PreloadCancellation cancellation,
  }) async {
    _throwIfCancelled(cancellation, url: playlistUri.toString());
    var parsed = _parseHls(
      playlistText,
      base: playlistUri,
      preferredBitrateBitsPerSecond:
          cacheDownloadRequest.resolvedSource.bitrate,
    );
    if (parsed == null) {
      return _PreloadAttemptResult.failure(
        _PreloadFailureInfo(
          category: _PreloadFailureCategory.unsupported,
          url: playlistUri.toString(),
          message: 'invalid-hls-playlist',
        ),
      );
    }

    if (parsed.variantPlaylistUri != null) {
      final variant = await _get(
        client: client,
        uri: parsed.variantPlaylistUri!,
        headers: headers,
        rangeStartBytes: 0,
        rangeBytes: 512 * 1024,
        captureLimitBytes: 1024 * 1024,
        cancellation: cancellation,
      );
      if (!variant.ok) {
        return _failureFromGetResult(
          variant,
          fallbackUri: parsed.variantPlaylistUri!,
          message: 'variant-fetch-failed',
        );
      }
      final text = _asHlsPlaylistText(variant);
      if (text == null) {
        return _PreloadAttemptResult.failure(
          _PreloadFailureInfo(
            category: _PreloadFailureCategory.unsupported,
            url: variant.effectiveUri.toString(),
            message: 'variant-not-playlist',
          ),
        );
      }
      parsed = _parseHls(
        text,
        base: variant.effectiveUri,
        preferredBitrateBitsPerSecond:
            cacheDownloadRequest.resolvedSource.bitrate,
      );
      if (parsed == null) {
        return _PreloadAttemptResult.failure(
          _PreloadFailureInfo(
            category: _PreloadFailureCategory.unsupported,
            url: variant.effectiveUri.toString(),
            message: 'invalid-variant-playlist',
          ),
        );
      }
    }

    if (parsed.initSegmentUri != null) {
      final init = await _get(
        client: client,
        uri: parsed.initSegmentUri!,
        headers: headers,
        rangeStartBytes: null,
        rangeBytes: null,
        captureLimitBytes: _maxLoopbackSeedBytes,
        cancellation: cancellation,
      );
      if (!init.ok) {
        return _failureFromGetResult(
          init,
          fallbackUri: parsed.initSegmentUri!,
          message: 'init-segment-failed',
        );
      }
      await _seedHlsAssetCache(
        assetUri: parsed.initSegmentUri!,
        cacheHeaders: cacheDownloadRequest.resolvedSource.httpHeaders,
        result: init,
        cacheDownloadRequest: cacheDownloadRequest,
      );
    }

    var remainingMs = preloadDuration.inMilliseconds;
    var fetchedAny = false;
    var segmentCount = 0;
    final segs = parsed.segments;
    var startIndex = 0;
    if (startPosition > Duration.zero && segs.isNotEmpty) {
      var remainingStartMs = startPosition.inMilliseconds;
      for (var i = 0; i < segs.length; i++) {
        final segDurMs = segs[i].durationMs > 0
            ? segs[i].durationMs
            : preloadDuration.inMilliseconds;
        if (remainingStartMs < segDurMs) {
          startIndex = i;
          break;
        }
        remainingStartMs -= segDurMs;
        startIndex = i + 1;
      }
      if (startIndex >= segs.length) startIndex = segs.length - 1;
    }

    for (final seg in segs.skip(startIndex)) {
      if (remainingMs <= 0) break;
      if (segmentCount >= _kMaxHlsPreloadSegments) break;
      _throwIfCancelled(cancellation, url: seg.uri.toString());

      final r = await _get(
        client: client,
        uri: seg.uri,
        headers: headers,
        rangeStartBytes: null,
        rangeBytes: null,
        captureLimitBytes: _maxLoopbackSeedBytes,
        cancellation: cancellation,
      );
      if (!r.ok) {
        return _failureFromGetResult(
          r,
          fallbackUri: seg.uri,
          message: 'segment-fetch-failed',
        );
      }
      await _seedHlsAssetCache(
        assetUri: seg.uri,
        cacheHeaders: cacheDownloadRequest.resolvedSource.httpHeaders,
        result: r,
        cacheDownloadRequest: cacheDownloadRequest,
      );
      fetchedAny = true;
      segmentCount++;

      final durMs =
          seg.durationMs > 0 ? seg.durationMs : preloadDuration.inMilliseconds;
      remainingMs -= durMs;
    }

    if (!fetchedAny) {
      return _PreloadAttemptResult.failure(
        _PreloadFailureInfo(
          category: _PreloadFailureCategory.emptyResponse,
          url: playlistUri.toString(),
          message: 'no-hls-segments-fetched',
        ),
      );
    }
    return const _PreloadAttemptResult.success();
  }

  Future<void> _seedHlsAssetCache({
    required Uri assetUri,
    required Map<String, String> cacheHeaders,
    required StreamPreloadGetResult result,
    required StreamCacheDownloadRequest cacheDownloadRequest,
  }) async {
    if (kIsWeb) return;
    if (result.capturedBytes.isEmpty) return;

    final rootCacheKey = cacheDownloadRequest.cacheKey;
    final assetCacheKey = buildNetworkPlaybackCacheKey(
      remoteUri: assetUri,
      httpHeaders: cacheHeaders,
      mediaSourceId: rootCacheKey?.mediaSourceId,
      proxyUrl: rootCacheKey?.proxyUrl,
    );

    try {
      await HttpStreamProxyServer.instance.seedStreamCache(
        remoteUri: result.effectiveUri,
        httpHeaders: cacheHeaders,
        fileName: _suggestProxyFileName(result.effectiveUri),
        cacheKey: assetCacheKey,
        startByte: 0,
        bytes: result.capturedBytes,
        contentTypeMime: result.contentTypeMime,
        totalBytes: result.totalBytes,
        acceptRanges: result.acceptsByteRanges,
      );
    } catch (_) {
      // Best-effort warmup only.
    }
  }

  String _suggestProxyFileName(Uri uri) {
    if (uri.pathSegments.isNotEmpty) {
      final last = uri.pathSegments.last.trim();
      if (last.isNotEmpty) return last;
    }
    return 'stream.bin';
  }

  String? _asHlsPlaylistText(StreamPreloadGetResult result) {
    final mime = (result.contentTypeMime ?? '').toLowerCase();
    final looksLikeMime = mime.contains('mpegurl') || mime.contains('m3u8');
    final text = utf8.decode(result.capturedBytes, allowMalformed: true);
    final prefix = text.trimLeft();
    final looksLikeText = prefix.startsWith('#EXTM3U');
    if (!looksLikeMime && !looksLikeText) return null;
    return text;
  }

  Future<StreamPreloadGetResult> _get({
    required HttpClient client,
    required Uri uri,
    required Map<String, String> headers,
    required int? rangeStartBytes,
    required int? rangeBytes,
    required int captureLimitBytes,
    required _PreloadCancellation cancellation,
  }) async {
    _throwIfCancelled(cancellation, url: uri.toString());
    final request =
        await client.getUrl(uri).timeout(const Duration(seconds: 8));
    request.followRedirects = true;
    request.maxRedirects = 5;
    headers.forEach((k, v) {
      request.headers.set(k, v);
    });
    if (rangeBytes != null && rangeBytes > 0) {
      final rawStart = rangeStartBytes ?? 0;
      final start = rawStart < 0 ? 0 : rawStart;
      final end = start + rangeBytes - 1;
      request.headers.set(HttpHeaders.rangeHeader, 'bytes=$start-$end');
    }

    final response = await request.close().timeout(const Duration(seconds: 10));
    final status = response.statusCode;
    final ok = status == 200 || status == 206;
    final mime = response.headers.contentType?.mimeType;
    final acceptsByteRanges =
        (response.headers.value(HttpHeaders.acceptRangesHeader) ?? '')
            .toLowerCase()
            .contains('bytes');
    var totalBytes = _inferTotalBytes(
      response: response,
      rangeStartBytes: rangeStartBytes,
    );

    var bytesRead = 0;
    final captured = <int>[];

    try {
      await for (final chunk in response.timeout(const Duration(seconds: 10))) {
        _throwIfCancelled(cancellation, url: uri.toString());
        bytesRead += chunk.length;
        if (captureLimitBytes > 0 && captured.length < captureLimitBytes) {
          final take =
              (captureLimitBytes - captured.length).clamp(0, chunk.length);
          if (take > 0) {
            captured.addAll(chunk.take(take));
          }
        }
        if (rangeBytes != null &&
            rangeBytes > 0 &&
            status != 206 &&
            bytesRead >= rangeBytes) {
          break;
        }
      }
    } catch (_) {
      // best-effort
    }

    _throwIfCancelled(cancellation, url: uri.toString());

    if (totalBytes == null &&
        response.statusCode == HttpStatus.ok &&
        bytesRead > 0) {
      totalBytes = bytesRead;
    }

    var effective = uri;
    try {
      for (final r in response.redirects) {
        effective = effective.resolveUri(r.location);
      }
    } catch (_) {}

    return StreamPreloadGetResult(
      ok: ok,
      statusCode: status,
      bytesRead: bytesRead,
      capturedBytes: captured,
      contentTypeMime: mime,
      effectiveUri: effective,
      totalBytes: totalBytes,
      acceptsByteRanges: acceptsByteRanges,
    );
  }

  int? _inferTotalBytes({
    required HttpClientResponse response,
    required int? rangeStartBytes,
  }) {
    final contentRange = response.headers.value(HttpHeaders.contentRangeHeader);
    if (contentRange != null) {
      final match = RegExp(r'^bytes\s+\d+-\d+/(\d+|\*)$').firstMatch(
        contentRange.trim(),
      );
      if (match != null) {
        final totalText = match.group(1) ?? '';
        if (totalText != '*') {
          final total = int.tryParse(totalText);
          if (total != null && total >= 0) return total;
        }
      }
    }

    final contentLength = response.contentLength;
    if (contentLength < 0) return null;
    if (response.statusCode == HttpStatus.partialContent) {
      final start = rangeStartBytes ?? 0;
      return start + contentLength;
    }
    if (response.statusCode == HttpStatus.ok) {
      return contentLength;
    }
    return null;
  }

  void _throwIfCancelled(
    _PreloadCancellation cancellation, {
    required String url,
    String message = 'cancelled',
  }) {
    if (!cancellation.isCancelled) return;
    throw _PreloadCancelledException(
      url: url,
      message: cancellation.reason ?? message,
    );
  }

  _PreloadAttemptResult _failureFromGetResult(
    StreamPreloadGetResult result, {
    required Uri fallbackUri,
    required String message,
  }) {
    final statusCode = result.statusCode;
    final url = result.effectiveUri.toString().trim().isEmpty
        ? fallbackUri.toString()
        : result.effectiveUri.toString();
    if (statusCode == 401 || statusCode == 403) {
      return _PreloadAttemptResult.failure(
        _PreloadFailureInfo(
          category: _PreloadFailureCategory.client,
          statusCode: statusCode,
          url: url,
          message: message,
        ),
      );
    }
    if (statusCode == 404 || statusCode == 410) {
      return _PreloadAttemptResult.failure(
        _PreloadFailureInfo(
          category: _PreloadFailureCategory.client,
          statusCode: statusCode,
          url: url,
          message: message,
        ),
      );
    }
    if (statusCode == 408 || statusCode == 425 || statusCode == 429) {
      return _PreloadAttemptResult.failure(
        _PreloadFailureInfo(
          category: _PreloadFailureCategory.rateLimited,
          statusCode: statusCode,
          url: url,
          message: message,
        ),
      );
    }
    if (statusCode >= 500) {
      return _PreloadAttemptResult.failure(
        _PreloadFailureInfo(
          category: _PreloadFailureCategory.server,
          statusCode: statusCode,
          url: url,
          message: message,
        ),
      );
    }
    if (result.bytesRead <= 0) {
      return _PreloadAttemptResult.failure(
        _PreloadFailureInfo(
          category: _PreloadFailureCategory.emptyResponse,
          statusCode: statusCode == 0 ? null : statusCode,
          url: url,
          message: message,
        ),
      );
    }
    return _PreloadAttemptResult.failure(
      _PreloadFailureInfo(
        category: _PreloadFailureCategory.unknown,
        statusCode: statusCode == 0 ? null : statusCode,
        url: url,
        message: message,
      ),
    );
  }

  _PreloadFailureInfo _classifyException(Object error, {required String url}) {
    if (error is _PreloadCancelledException) {
      return _PreloadFailureInfo(
        category: _PreloadFailureCategory.cancelled,
        url: error.url,
        message: error.message,
      );
    }
    if (error is TimeoutException) {
      return _PreloadFailureInfo(
        category: _PreloadFailureCategory.network,
        url: url,
        message: 'timeout',
      );
    }
    if (error is SocketException || error is HandshakeException) {
      return _PreloadFailureInfo(
        category: _PreloadFailureCategory.network,
        url: url,
        message: error.runtimeType.toString(),
      );
    }
    if (error is HttpException) {
      return _PreloadFailureInfo(
        category: _PreloadFailureCategory.network,
        url: url,
        message: error.message,
      );
    }
    return _PreloadFailureInfo(
      category: _PreloadFailureCategory.unknown,
      url: url,
      message: error.toString(),
    );
  }
}

enum _PreloadFailureCategory {
  cancelled,
  network,
  server,
  rateLimited,
  client,
  unsupported,
  emptyResponse,
  unknown,
}

@immutable
class _PreloadFailureInfo {
  const _PreloadFailureInfo({
    required this.category,
    this.statusCode,
    this.url,
    this.message,
  });

  final _PreloadFailureCategory category;
  final int? statusCode;
  final String? url;
  final String? message;

  bool get isRecoverable {
    switch (category) {
      case _PreloadFailureCategory.network:
      case _PreloadFailureCategory.server:
      case _PreloadFailureCategory.rateLimited:
      case _PreloadFailureCategory.emptyResponse:
      case _PreloadFailureCategory.unknown:
        return true;
      case _PreloadFailureCategory.cancelled:
      case _PreloadFailureCategory.client:
      case _PreloadFailureCategory.unsupported:
        return false;
    }
  }

  @override
  String toString() {
    final pieces = <String>[category.name];
    if (statusCode != null) pieces.add('status=$statusCode');
    final msg = (message ?? '').trim();
    if (msg.isNotEmpty) pieces.add(msg);
    final target = (url ?? '').trim();
    if (target.isNotEmpty) pieces.add(target);
    return pieces.join(' ');
  }
}

class _PreloadCircuitState {
  _PreloadCircuitState({required this.scopeKey});

  final String scopeKey;
  int consecutiveFailures = 0;
  DateTime? lastFailureAt;
  DateTime? openUntil;
  _PreloadFailureInfo? lastFailure;

  bool isOpen(DateTime now) {
    final until = openUntil;
    return until != null && now.isBefore(until);
  }
}

@immutable
class _PreloadAttemptResult {
  const _PreloadAttemptResult.success()
      : success = true,
        failure = null;

  const _PreloadAttemptResult.failure(this.failure) : success = false;

  final bool success;
  final _PreloadFailureInfo? failure;
}

class _PreloadCancelledException implements Exception {
  const _PreloadCancelledException({
    required this.url,
    required this.message,
  });

  final String url;
  final String message;
}

enum _PreloadPriority {
  normal,
  current,
  next,
}

class _PreloadCancellation {
  String? _reason;
  final List<VoidCallback> _listeners = <VoidCallback>[];
  final Completer<void> _cancelled = Completer<void>();

  bool get isCancelled => (_reason ?? '').trim().isNotEmpty;
  String? get reason => _reason;
  Future<void> get cancelled => _cancelled.future;

  void addListener(VoidCallback listener) {
    if (isCancelled) {
      listener();
      return;
    }
    _listeners.add(listener);
  }

  void cancel([String reason = 'cancelled']) {
    if (isCancelled) return;
    _reason = reason.trim().isEmpty ? 'cancelled' : reason.trim();
    if (!_cancelled.isCompleted) {
      _cancelled.complete();
    }
    final listeners = List<VoidCallback>.from(_listeners);
    _listeners.clear();
    for (final listener in listeners) {
      try {
        listener();
      } catch (_) {}
    }
  }
}

@immutable
class _PreloadInterest {
  const _PreloadInterest({
    required this.ownerKey,
    required this.scopeKey,
  });

  final String ownerKey;
  final String scopeKey;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is _PreloadInterest &&
        other.ownerKey == ownerKey &&
        other.scopeKey == scopeKey;
  }

  @override
  int get hashCode => Object.hash(ownerKey, scopeKey);
}

class _InFlightPreloadTask {
  _InFlightPreloadTask({required this.cancellation});

  final _PreloadCancellation cancellation;
  final Set<_PreloadInterest> _ownedInterests = <_PreloadInterest>{};
  var _hasUnownedInterest = false;
  late Future<StreamPreloadResult> future;

  void attach(PreloadRequest request) {
    final ownerKey = (request.ownerKey ?? '').trim();
    if (ownerKey.isEmpty) {
      _hasUnownedInterest = true;
      return;
    }
    _ownedInterests.add(
      _PreloadInterest(
        ownerKey: ownerKey,
        scopeKey: (request.scopeKey ?? '').trim(),
      ),
    );
  }

  void detachOwner(String ownerKey) {
    if (ownerKey.trim().isEmpty) return;
    _ownedInterests.removeWhere((interest) => interest.ownerKey == ownerKey);
    _cancelIfOrphaned(reason: 'owner-cancelled:$ownerKey');
  }

  void detachOwnerScope({
    required String ownerKey,
    required String scopeKey,
  }) {
    if (ownerKey.trim().isEmpty || scopeKey.trim().isEmpty) return;
    _ownedInterests.removeWhere(
      (interest) =>
          interest.ownerKey == ownerKey && interest.scopeKey == scopeKey,
    );
    _cancelIfOrphaned(reason: 'scope-cancelled:$ownerKey/$scopeKey');
  }

  void _cancelIfOrphaned({required String reason}) {
    if (_hasUnownedInterest || _ownedInterests.isNotEmpty) return;
    cancellation.cancel(reason);
  }
}

@immutable
class StreamPreloadGetResult {
  const StreamPreloadGetResult({
    required this.ok,
    required this.statusCode,
    required this.bytesRead,
    required this.capturedBytes,
    required this.contentTypeMime,
    required this.effectiveUri,
    required this.totalBytes,
    required this.acceptsByteRanges,
  });

  final bool ok;
  final int statusCode;
  final int bytesRead;
  final List<int> capturedBytes;
  final String? contentTypeMime;
  final Uri effectiveUri;
  final int? totalBytes;
  final bool acceptsByteRanges;
}

@immutable
class _HlsSegment {
  const _HlsSegment({
    required this.uri,
    required this.durationMs,
  });

  final Uri uri;
  final int durationMs;
}

@immutable
class _HlsParseResult {
  const _HlsParseResult({
    required this.variantPlaylistUri,
    required this.initSegmentUri,
    required this.segments,
  });

  final Uri? variantPlaylistUri;
  final Uri? initSegmentUri;
  final List<_HlsSegment> segments;
}

_HlsParseResult? _parseHls(
  String text, {
  required Uri base,
  int? preferredBitrateBitsPerSecond,
  _HlsVariantSelectionStrategy variantSelectionStrategy =
      _kHlsVariantSelectionStrategy,
}) {
  final normalized = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  final lines = normalized.split('\n');
  if (lines.isEmpty) return null;

  Uri? initUri;
  final variants = <({Uri uri, int bandwidth})>[];
  final segments = <_HlsSegment>[];

  var expectingVariantUri = false;
  var variantBandwidth = 0;
  double? pendingDurationSeconds;

  for (final raw in lines) {
    final line = raw.trim();
    if (line.isEmpty) continue;

    if (expectingVariantUri) {
      if (!line.startsWith('#')) {
        variants.add((
          uri: base.resolve(line),
          bandwidth: variantBandwidth,
        ));
        expectingVariantUri = false;
        variantBandwidth = 0;
        continue;
      }
      expectingVariantUri = false;
      variantBandwidth = 0;
    }

    if (line.startsWith('#EXT-X-STREAM-INF')) {
      expectingVariantUri = true;
      final m = RegExp(r'BANDWIDTH=(\d+)').firstMatch(line);
      variantBandwidth = int.tryParse(m?.group(1) ?? '') ?? 0;
      continue;
    }

    if (line.startsWith('#EXT-X-MAP')) {
      final m = RegExp(r'URI=\"([^\"]+)\"').firstMatch(line);
      final uri = (m?.group(1) ?? '').trim();
      if (uri.isNotEmpty) {
        initUri = base.resolve(uri);
      }
      continue;
    }

    if (line.startsWith('#EXTINF')) {
      final m = RegExp(r'#EXTINF:([0-9.]+)').firstMatch(line);
      pendingDurationSeconds = double.tryParse(m?.group(1) ?? '');
      continue;
    }

    if (line.startsWith('#')) continue;

    final segUri = base.resolve(line);
    final durMs =
        ((pendingDurationSeconds ?? 0) * 1000).round().clamp(0, 1 << 30);
    segments.add(_HlsSegment(uri: segUri, durationMs: durMs));
    pendingDurationSeconds = null;
  }

  final variantUri = _pickVariantUri(
    variants,
    preferredBitrateBitsPerSecond: preferredBitrateBitsPerSecond,
    strategy: variantSelectionStrategy,
  );

  return _HlsParseResult(
    variantPlaylistUri: variantUri,
    initSegmentUri: initUri,
    segments: segments,
  );
}

Uri? _pickVariantUri(
  List<({Uri uri, int bandwidth})> variants, {
  int? preferredBitrateBitsPerSecond,
  required _HlsVariantSelectionStrategy strategy,
}) {
  if (variants.isEmpty) return null;
  switch (strategy) {
    case _HlsVariantSelectionStrategy.closestToPreferredBitrate:
      final preferred = preferredBitrateBitsPerSecond ?? 0;
      if (preferred > 0) {
        variants.sort((a, b) {
          final aDistance = (a.bandwidth - preferred).abs();
          final bDistance = (b.bandwidth - preferred).abs();
          if (aDistance != bDistance) return aDistance.compareTo(bDistance);
          if (a.bandwidth != b.bandwidth) {
            return a.bandwidth.compareTo(b.bandwidth);
          }
          return 0;
        });
        return variants.first.uri;
      }
      variants.sort((a, b) => b.bandwidth.compareTo(a.bandwidth));
      return variants.first.uri;
    case _HlsVariantSelectionStrategy.highestBandwidth:
      variants.sort((a, b) => b.bandwidth.compareTo(a.bandwidth));
      return variants.first.uri;
  }
}

const int _kMaxHlsPreloadSegments = 3;

enum _HlsVariantSelectionStrategy {
  closestToPreferredBitrate,
  highestBandwidth,
}

const _HlsVariantSelectionStrategy _kHlsVariantSelectionStrategy =
    _HlsVariantSelectionStrategy.closestToPreferredBitrate;
