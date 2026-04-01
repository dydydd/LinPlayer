import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:lin_player_server_api/services/http_stream_proxy.dart';

import '../app_diagnostics_log.dart';
import '../stream_resolver/stream_models.dart';

class LocalHttpStreamProxy {
  const LocalHttpStreamProxy._();

  static Future<List<PlayableSource>> wrapCandidates(
    List<PlayableSource> candidates,
  ) async {
    if (kIsWeb || candidates.isEmpty) return candidates;

    final out = <PlayableSource>[];
    for (final candidate in candidates) {
      final proxied = await _wrapCandidate(candidate);
      if (proxied != null) {
        out.add(proxied);
      }
      out.add(candidate);
    }
    return List<PlayableSource>.unmodifiable(out);
  }

  static Future<PlayableSource?> _wrapCandidate(
      PlayableSource candidate) async {
    if (!_shouldProxy(candidate)) return null;
    return _wrapHttpSource(candidate);
  }

  static Future<PlayableSource?> wrapPlaybackSource(
    PlayableSource candidate,
  ) async {
    if (kIsWeb) return null;
    if (!_supportsCacheProxyMode(candidate)) return null;
    if (!_isSupportedHttpSource(candidate)) return null;
    return _wrapHttpSource(candidate);
  }

  static Future<PlayableSource?> _wrapHttpSource(
      PlayableSource candidate) async {
    if (!_isSupportedHttpSource(candidate)) return null;

    final uri = Uri.tryParse(candidate.url.trim());
    if (uri == null) return null;

    try {
      final proxyUri = await HttpStreamProxyServer.instance.registerStream(
        remoteUri: uri,
        httpHeaders: candidate.httpHeaders,
        fileName: _suggestFileName(uri),
      );
      AppDiagnosticsLogger.instance.info(
        'loopback_proxy',
        'Wrapped HTTP playback source with loopback cache proxy',
        data: <String, Object?>{
          'remote': AppDiagnosticsLogger.summarizeUrl(candidate.url),
          'proxy': AppDiagnosticsLogger.summarizeUrl(proxyUri.toString()),
          'headers':
              AppDiagnosticsLogger.summarizeHeaderKeys(candidate.httpHeaders),
          'mediaType': candidate.mediaTypeHint.name,
        },
      );
      return PlayableSource(
        url: proxyUri.toString(),
        httpHeaders: const <String, String>{},
        mediaTypeHint: candidate.mediaTypeHint,
        fromStrm: candidate.fromStrm,
        redirectChain: candidate.redirectChain,
        contentTypeHint: candidate.contentTypeHint,
        supportsByteRange: candidate.supportsByteRange,
        httpStatusHint: candidate.httpStatusHint,
      );
    } catch (_) {
      return null;
    }
  }

  static bool _shouldProxy(PlayableSource candidate) {
    if (!candidate.fromStrm) return false;
    if (candidate.mediaTypeHint == StreamMediaType.hls ||
        candidate.mediaTypeHint == StreamMediaType.dash) {
      return false;
    }

    return _isSupportedHttpSource(candidate);
  }

  static bool _isSupportedHttpSource(PlayableSource candidate) {
    final uri = Uri.tryParse(candidate.url.trim());
    if (uri == null) return false;

    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') return false;

    final host = uri.host.trim().toLowerCase();
    if (host.isEmpty) return false;
    if (host == 'localhost' || host == '127.0.0.1' || host == '::1') {
      return false;
    }

    return true;
  }

  static bool _supportsCacheProxyMode(PlayableSource candidate) {
    return candidate.mediaTypeHint == StreamMediaType.file ||
        candidate.mediaTypeHint == StreamMediaType.unknown;
  }

  static String _suggestFileName(Uri uri) {
    if (uri.pathSegments.isNotEmpty) {
      final last = uri.pathSegments.last.trim();
      if (last.isNotEmpty) return last;
    }
    return 'stream.bin';
  }
}
