import 'package:lin_player_server_api/services/http_stream_proxy.dart';

import 'resolved_playback_source.dart';

const Set<String> _volatilePlaybackQueryKeys = <String>{
  'api_key',
  'deviceid',
  'playsessionid',
  'token',
  'userid',
  'x-emby-client',
  'x-emby-device-id',
  'x-emby-device-name',
  'x-emby-devicename',
  'x-emby-token',
  'x-mediabrowser-client',
  'x-mediabrowser-device-id',
  'x-mediabrowser-device-name',
  'x-mediabrowser-devicename',
  'x-mediabrowser-token',
};

HttpStreamCacheKey buildNetworkPlaybackCacheKey({
  required Uri remoteUri,
  Map<String, String>? httpHeaders,
  String? mediaSourceId,
  int? audioStreamIndex,
  int? subtitleStreamIndex,
  String? proxyUrl,
}) {
  return HttpStreamCacheKey.fromNetworkSource(
    remoteUri: remoteUri,
    httpHeaders: httpHeaders,
    mediaSourceId: mediaSourceId,
    audioStreamIndex: audioStreamIndex,
    subtitleStreamIndex: subtitleStreamIndex,
    proxyUrl: proxyUrl,
  );
}

HttpStreamCacheKey? buildResolvedPlaybackCacheKey(
  ResolvedPlaybackSource source, {
  String? proxyUrl,
}) {
  final rawUrl = source.url.trim();
  if (rawUrl.isEmpty) return null;

  final uri = Uri.tryParse(rawUrl);
  if (uri == null) return null;

  return buildNetworkPlaybackCacheKey(
    remoteUri: _cacheIdentityUri(source, uri),
    httpHeaders: source.httpHeaders,
    mediaSourceId: source.mediaSourceId,
    audioStreamIndex: _queryInt(uri, 'AudioStreamIndex'),
    subtitleStreamIndex: _queryInt(uri, 'SubtitleStreamIndex'),
    proxyUrl: (proxyUrl ?? source.proxyUrl)?.trim(),
  );
}

int? _queryInt(Uri uri, String name) {
  final raw = (uri.queryParameters[name] ?? '').trim();
  if (raw.isEmpty) return null;
  return int.tryParse(raw);
}

Uri _cacheIdentityUri(ResolvedPlaybackSource source, Uri uri) {
  final query = _normalizedCacheIdentityQuery(
    uri.queryParametersAll,
    sourcePath: source.sourcePath,
  );
  return uri.replace(
    query: query.isEmpty ? null : query,
  );
}

String _normalizedCacheIdentityQuery(
  Map<String, List<String>> queryParametersAll, {
  String? sourcePath,
}) {
  final parts = <String>[];
  final keys = queryParametersAll.keys.toList(growable: false)..sort();
  for (final key in keys) {
    if (_volatilePlaybackQueryKeys.contains(key.trim().toLowerCase())) {
      continue;
    }
    final values =
        List<String>.from(queryParametersAll[key] ?? const <String>[])..sort();
    if (values.isEmpty) {
      parts.add(Uri.encodeQueryComponent(key));
      continue;
    }
    for (final value in values) {
      parts.add(
        '${Uri.encodeQueryComponent(key)}=${Uri.encodeQueryComponent(value)}',
      );
    }
  }

  final normalizedSourcePath = (sourcePath ?? '').trim();
  if (normalizedSourcePath.isNotEmpty) {
    parts.add(
      '__lp_source_path=${Uri.encodeQueryComponent(normalizedSourcePath)}',
    );
  }
  return parts.join('&');
}
