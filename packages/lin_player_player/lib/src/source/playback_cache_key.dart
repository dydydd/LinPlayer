import 'package:lin_player_server_api/services/http_stream_proxy.dart';

import 'resolved_playback_source.dart';

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
    remoteUri: uri,
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
