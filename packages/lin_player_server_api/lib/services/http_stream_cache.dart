import 'dart:convert';

import 'package:crypto/crypto.dart';

enum HttpStreamCacheState {
  warming,
  playable,
  completed,
  failed,
  stale,
}

enum HttpStreamCacheDownloadKind {
  warmup,
  playbackFill,
}

class HttpStreamCacheKey {
  const HttpStreamCacheKey._({
    required this.fingerprint,
    required this.remoteUrl,
    required this.httpHeaders,
    required this.mediaSourceId,
    required this.audioStreamIndex,
    required this.subtitleStreamIndex,
    required this.proxyUrl,
  });

  factory HttpStreamCacheKey.fromNetworkSource({
    required Uri remoteUri,
    Map<String, String>? httpHeaders,
    String? mediaSourceId,
    int? audioStreamIndex,
    int? subtitleStreamIndex,
    String? proxyUrl,
  }) {
    final normalizedHeaders = normalizeHeaders(httpHeaders);
    final normalizedUrl = _normalizeRemoteUrl(remoteUri);
    final normalizedMediaSourceId = (mediaSourceId ?? '').trim();
    final normalizedProxy = _normalizeProxyUrl(proxyUrl);
    final headerPairs = normalizedHeaders.entries
        .map((entry) => '${entry.key}:${entry.value}')
        .toList(growable: false)
      ..sort();
    final payload = <String>[
      'v1',
      normalizedUrl,
      normalizedMediaSourceId,
      audioStreamIndex?.toString() ?? '',
      subtitleStreamIndex?.toString() ?? '',
      normalizedProxy ?? '',
      ...headerPairs,
    ].join('|');
    final fingerprint = sha1.convert(utf8.encode(payload)).toString();
    return HttpStreamCacheKey._(
      fingerprint: fingerprint,
      remoteUrl: normalizedUrl,
      httpHeaders: Map<String, String>.unmodifiable(normalizedHeaders),
      mediaSourceId: normalizedMediaSourceId,
      audioStreamIndex: audioStreamIndex,
      subtitleStreamIndex: subtitleStreamIndex,
      proxyUrl: normalizedProxy,
    );
  }

  final String fingerprint;
  final String remoteUrl;
  final Map<String, String> httpHeaders;
  final String mediaSourceId;
  final int? audioStreamIndex;
  final int? subtitleStreamIndex;
  final String? proxyUrl;

  bool get usesProxy => (proxyUrl ?? '').trim().isNotEmpty;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'fingerprint': fingerprint,
      'remoteUrl': remoteUrl,
      'httpHeaders': httpHeaders,
      'mediaSourceId': mediaSourceId,
      'audioStreamIndex': audioStreamIndex,
      'subtitleStreamIndex': subtitleStreamIndex,
      'proxyUrl': proxyUrl,
    };
  }

  static HttpStreamCacheKey? fromJson(
    Object? raw, {
    Uri? fallbackRemoteUri,
    Map<String, String>? fallbackHttpHeaders,
  }) {
    if (raw is! Map) {
      if (fallbackRemoteUri == null) return null;
      return HttpStreamCacheKey.fromNetworkSource(
        remoteUri: fallbackRemoteUri,
        httpHeaders: fallbackHttpHeaders,
      );
    }

    final remoteUrl = (raw['remoteUrl']?.toString() ?? '').trim();
    final fallbackUrl = fallbackRemoteUri?.toString().trim() ?? '';
    final resolvedRemoteUrl = remoteUrl.isNotEmpty ? remoteUrl : fallbackUrl;
    if (resolvedRemoteUrl.isEmpty) return null;

    final remoteUri = Uri.tryParse(resolvedRemoteUrl);
    if (remoteUri == null) return null;

    final storedHeaders = <String, String>{};
    final rawHeaders = raw['httpHeaders'];
    if (rawHeaders is Map) {
      rawHeaders.forEach((key, value) {
        final normalizedKey = key.toString().trim();
        final normalizedValue = value.toString().trim();
        if (normalizedKey.isEmpty) return;
        storedHeaders[normalizedKey] = normalizedValue;
      });
    }
    if (storedHeaders.isEmpty && fallbackHttpHeaders != null) {
      storedHeaders.addAll(fallbackHttpHeaders);
    }

    return HttpStreamCacheKey.fromNetworkSource(
      remoteUri: remoteUri,
      httpHeaders: storedHeaders,
      mediaSourceId: raw['mediaSourceId']?.toString(),
      audioStreamIndex: int.tryParse(raw['audioStreamIndex']?.toString() ?? ''),
      subtitleStreamIndex:
          int.tryParse(raw['subtitleStreamIndex']?.toString() ?? ''),
      proxyUrl: raw['proxyUrl']?.toString(),
    );
  }

  static Map<String, String> normalizeHeaders(Map<String, String>? headers) {
    if (headers == null || headers.isEmpty) {
      return const <String, String>{};
    }

    final normalized = <String, String>{};
    for (final entry in headers.entries) {
      final key = entry.key.trim().toLowerCase();
      if (key.isEmpty) continue;
      normalized[key] = entry.value.trim();
    }
    final orderedEntries = normalized.entries.toList(growable: false)
      ..sort((a, b) => a.key.compareTo(b.key));
    return Map<String, String>.fromEntries(orderedEntries);
  }

  static String? _normalizeProxyUrl(String? proxyUrl) {
    final value = (proxyUrl ?? '').trim();
    return value.isEmpty ? null : value;
  }

  static String _normalizeRemoteUrl(Uri remoteUri) {
    final buffer = StringBuffer();
    final scheme = remoteUri.scheme.toLowerCase();
    final hasAuthority = remoteUri.hasAuthority || remoteUri.host.isNotEmpty;
    if (scheme.isNotEmpty) {
      buffer
        ..write(scheme)
        ..write(':');
    }
    if (hasAuthority) {
      buffer.write('//');
      if (remoteUri.userInfo.isNotEmpty) {
        buffer
          ..write(remoteUri.userInfo)
          ..write('@');
      }
      buffer.write(remoteUri.host.toLowerCase());
      if (remoteUri.hasPort) {
        buffer
          ..write(':')
          ..write(remoteUri.port);
      }
    }
    final path =
        remoteUri.path.isEmpty ? (hasAuthority ? '/' : '') : remoteUri.path;
    buffer.write(path);

    final queryParts = <String>[];
    final entries = remoteUri.queryParametersAll.entries.toList(growable: false)
      ..sort((a, b) => a.key.compareTo(b.key));
    for (final entry in entries) {
      final values = entry.value.toList(growable: false)..sort();
      for (final value in values) {
        queryParts.add(
          '${Uri.encodeQueryComponent(entry.key)}='
          '${Uri.encodeQueryComponent(value)}',
        );
      }
    }
    if (queryParts.isNotEmpty) {
      buffer
        ..write('?')
        ..write(queryParts.join('&'));
    }
    if (remoteUri.fragment.isNotEmpty) {
      buffer
        ..write('#')
        ..write(remoteUri.fragment);
    }
    return buffer.toString().trim();
  }
}

class HttpStreamCacheRange {
  const HttpStreamCacheRange({
    required this.startByte,
    required this.lengthBytes,
  });

  final int startByte;
  final int lengthBytes;

  int get endExclusive => startByte + lengthBytes;
}

class HttpStreamCacheSnapshot {
  HttpStreamCacheSnapshot({
    required this.key,
    required this.state,
    required List<HttpStreamCacheRange> ranges,
    required this.cachedBytes,
    required this.contiguousBytesFromStart,
    required this.totalBytes,
    required this.acceptRanges,
    required this.lastUpdatedAt,
    required this.warmupInProgress,
    required this.hasObservedPlaybackRequest,
    this.lastFailureAt,
    this.lastFailureMessage,
  }) : ranges = List<HttpStreamCacheRange>.unmodifiable(ranges);

  final HttpStreamCacheKey key;
  final HttpStreamCacheState state;
  final List<HttpStreamCacheRange> ranges;
  final int cachedBytes;
  final int contiguousBytesFromStart;
  final int? totalBytes;
  final bool acceptRanges;
  final DateTime lastUpdatedAt;
  final bool warmupInProgress;
  final bool hasObservedPlaybackRequest;
  final DateTime? lastFailureAt;
  final String? lastFailureMessage;

  bool get isPlayable =>
      state == HttpStreamCacheState.playable ||
      state == HttpStreamCacheState.completed;
}

class HttpStreamCacheDownloadProgressSnapshot {
  const HttpStreamCacheDownloadProgressSnapshot({
    required this.id,
    required this.key,
    required this.kind,
    required this.remoteUrl,
    required this.startByte,
    required this.bytesWritten,
    required this.startedAt,
    required this.updatedAt,
    this.requestedBytes,
    this.totalBytes,
    this.contentTypeMime,
  });

  final String id;
  final HttpStreamCacheKey key;
  final HttpStreamCacheDownloadKind kind;
  final String remoteUrl;
  final int startByte;
  final int bytesWritten;
  final int? requestedBytes;
  final int? totalBytes;
  final String? contentTypeMime;
  final DateTime startedAt;
  final DateTime updatedAt;

  bool get isIndeterminate => requestedBytes == null || requestedBytes! <= 0;

  double? get progress {
    final requested = requestedBytes;
    if (requested == null || requested <= 0) return null;
    if (bytesWritten <= 0) return 0;
    final fraction = bytesWritten / requested;
    if (fraction < 0) return 0;
    if (fraction > 1) return 1;
    return fraction;
  }
}

class HttpStreamPlaybackObservation {
  const HttpStreamPlaybackObservation({
    required this.timestamp,
    required this.cacheFingerprint,
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
  final String cacheFingerprint;
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

  bool get reusedCachePrefix =>
      cacheStatus == 'hit' || cacheStatus == 'partial';
}
