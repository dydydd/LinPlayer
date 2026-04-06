import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:lin_player_server_api/services/http_stream_proxy.dart';

import '../source/playback_cache_key.dart';
import '../source/resolved_playback_source.dart';

@immutable
class StreamCacheDownloadRequest {
  const StreamCacheDownloadRequest({
    required this.resolvedSource,
    this.proxyUrl,
    this.remoteUriOverride,
    this.fileName,
  });

  final ResolvedPlaybackSource resolvedSource;
  final String? proxyUrl;
  final Uri? remoteUriOverride;
  final String? fileName;

  String? get effectiveProxyUrl {
    final requestProxy = (proxyUrl ?? '').trim();
    if (requestProxy.isNotEmpty) return requestProxy;
    final sourceProxy = (resolvedSource.proxyUrl ?? '').trim();
    return sourceProxy.isEmpty ? null : sourceProxy;
  }

  Uri? get remoteUri {
    final override = remoteUriOverride;
    if (override != null) return override;
    final rawUrl = resolvedSource.url.trim();
    if (rawUrl.isEmpty) return null;
    return Uri.tryParse(rawUrl);
  }

  Map<String, String> get httpHeaders => resolvedSource.httpHeaders;

  HttpStreamCacheKey? get cacheKey => buildResolvedPlaybackCacheKey(
        resolvedSource,
        proxyUrl: effectiveProxyUrl,
      );

  String get effectiveFileName {
    final explicit = (fileName ?? '').trim();
    if (explicit.isNotEmpty) return explicit;
    final uri = remoteUri;
    if (uri != null && uri.pathSegments.isNotEmpty) {
      final last = uri.pathSegments.last.trim();
      if (last.isNotEmpty) return last;
    }
    return 'stream.bin';
  }

  StreamCacheDownloadRequest withRemoteUri(
    Uri remoteUri, {
    String? fileName,
  }) {
    return StreamCacheDownloadRequest(
      resolvedSource: resolvedSource,
      proxyUrl: effectiveProxyUrl,
      remoteUriOverride: remoteUri,
      fileName: fileName ?? this.fileName,
    );
  }
}

class StreamCacheDownloadService {
  StreamCacheDownloadService._();

  static final StreamCacheDownloadService instance =
      StreamCacheDownloadService._();

  Stream<List<HttpStreamCacheDownloadProgressSnapshot>>
      get downloadProgressStream =>
          HttpStreamProxyServer.instance.downloadProgressStream;

  List<HttpStreamCacheDownloadProgressSnapshot> currentProgressSnapshots({
    int? maxEntries,
  }) {
    return HttpStreamProxyServer.instance.currentDownloadProgressSnapshots(
      maxEntries: maxEntries,
    );
  }

  String buildActiveDownloadsText({int maxEntries = 8}) {
    return HttpStreamProxyServer.instance.buildActiveDownloadsText(
      maxEntries: maxEntries,
    );
  }

  Future<Uri?> registerStream(StreamCacheDownloadRequest request) async {
    final remoteUri = request.remoteUri;
    if (remoteUri == null) return null;
    return HttpStreamProxyServer.instance.registerStream(
      remoteUri: remoteUri,
      httpHeaders: request.httpHeaders,
      fileName: request.effectiveFileName,
      cacheKey: request.cacheKey,
    );
  }

  void beginWarmup(StreamCacheDownloadRequest request) {
    final remoteUri = request.remoteUri;
    if (remoteUri == null) return;
    HttpStreamProxyServer.instance.beginStreamWarmup(
      remoteUri: remoteUri,
      httpHeaders: request.httpHeaders,
      cacheKey: request.cacheKey,
    );
  }

  void endWarmup(StreamCacheDownloadRequest request) {
    final remoteUri = request.remoteUri;
    if (remoteUri == null) return;
    HttpStreamProxyServer.instance.endStreamWarmup(
      remoteUri: remoteUri,
      httpHeaders: request.httpHeaders,
      cacheKey: request.cacheKey,
    );
  }

  Future<HttpStreamWarmupResult?> warmRangeToCache({
    required StreamCacheDownloadRequest request,
    required int startByte,
    required int lengthBytes,
  }) async {
    final remoteUri = request.remoteUri;
    if (remoteUri == null) return null;
    return HttpStreamProxyServer.instance.warmRangeToCache(
      remoteUri: remoteUri,
      httpHeaders: request.httpHeaders,
      fileName: request.effectiveFileName,
      cacheKey: request.cacheKey,
      startByte: startByte,
      lengthBytes: lengthBytes,
    );
  }

  Future<Uri?> seedCache({
    required StreamCacheDownloadRequest request,
    required int startByte,
    required List<int> bytes,
    String? contentTypeMime,
    int? totalBytes,
    bool acceptRanges = false,
  }) async {
    final remoteUri = request.remoteUri;
    if (remoteUri == null) return null;
    return HttpStreamProxyServer.instance.seedStreamCache(
      remoteUri: remoteUri,
      httpHeaders: request.httpHeaders,
      fileName: request.effectiveFileName,
      cacheKey: request.cacheKey,
      startByte: startByte,
      bytes: bytes,
      contentTypeMime: contentTypeMime,
      totalBytes: totalBytes,
      acceptRanges: acceptRanges,
    );
  }

  Future<void> markFailure(
    StreamCacheDownloadRequest request, {
    Object? error,
  }) async {
    final remoteUri = request.remoteUri;
    if (remoteUri == null) return;
    await HttpStreamProxyServer.instance.markStreamFailure(
      remoteUri: remoteUri,
      httpHeaders: request.httpHeaders,
      cacheKey: request.cacheKey,
      error: error,
    );
  }

  Future<HttpStreamCacheSnapshot?> describe(
    StreamCacheDownloadRequest request, {
    DateTime? now,
  }) async {
    final remoteUri = request.remoteUri;
    if (remoteUri == null) return null;
    return HttpStreamProxyServer.instance.debugDescribeStream(
      remoteUri: remoteUri,
      httpHeaders: request.httpHeaders,
      cacheKey: request.cacheKey,
      now: now,
    );
  }
}
